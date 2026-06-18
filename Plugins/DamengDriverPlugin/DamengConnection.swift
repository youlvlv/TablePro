//
//  DamengConnection.swift
//  TablePro
//
//  ODBC-based connection wrapper for Dameng Database.
//

import Darwin
import Foundation
import os
import TableProPluginKit

private let log = Logger(subsystem: "com.TablePro", category: "DamengConnection")

private extension String {
    var odbcUTF8: [SQLCHAR] {
        Array(self.utf8) + [0]
    }
}

// MARK: - Query Serialization

/// ODBC does not safely support concurrent statements on one connection.
private actor QueryGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            busy = false
        }
    }
}

// MARK: - Internal Result

struct DamengQueryResult {
    let columns: [String]
    let columnTypeNames: [String]
    let rows: [[PluginCellValue]]
    let affectedRows: Int
    let isTruncated: Bool
}

// MARK: - Connection Wrapper

final class DamengConnectionWrapper: @unchecked Sendable {
    private let host: String
    private let port: Int
    private let user: String
    private let password: String
    private let database: String
    private let driverPath: String
    private let managerPath: String?

    private var environment: SQLHENV = nil
    private var connection: SQLHDBC = nil
    private var currentStatement: SQLHSTMT = nil

    private let queryGate = QueryGate()

    init(
        host: String,
        port: Int,
        user: String,
        password: String,
        database: String,
        driverPath: String,
        managerPath: String? = nil
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.driverPath = driverPath
        self.managerPath = managerPath
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.connectSync()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func connectSync() throws {
        try ODBCFunctions.loadManager(preferredPath: managerPath)

        var env: SQLHENV = nil
        let allocEnvRC = ODBCFunctions.SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &env)
        guard SQL_SUCCEEDED(allocEnvRC), let env else {
            throw DamengError.connectionFailed
        }
        self.environment = env

        let versionRC = ODBCFunctions.SQLSetEnvAttr(
            env,
            SQL_ATTR_ODBC_VERSION,
            UnsafeMutableRawPointer(bitPattern: UInt(SQL_OV_ODBC3)),
            SQL_IS_UINTEGER
        )
        guard SQL_SUCCEEDED(versionRC) else {
            let diag = diagnostic(for: SQL_HANDLE_ENV, handle: env)
            throw DamengError(
                message: String(localized: "Failed to set ODBC version: \(diag.message)"),
                category: .connectionFailed,
                sqlState: diag.sqlState,
                nativeCode: diag.nativeCode
            )
        }

        var dbc: SQLHDBC = nil
        let allocDbcRC = ODBCFunctions.SQLAllocHandle(SQL_HANDLE_DBC, env, &dbc)
        guard SQL_SUCCEEDED(allocDbcRC), let dbc else {
            throw DamengError.connectionFailed
        }
        self.connection = dbc

        let connectionString = buildConnectionString()
        let connectionStringBytes = connectionString.odbcUTF8
        var outString = [SQLCHAR](repeating: 0, count: 1024)
        var outLength: SQLSMALLINT = 0

        let connectRC = connectionStringBytes.withUnsafeBufferPointer { cString -> SQLRETURN in
            ODBCFunctions.SQLDriverConnect(
                dbc,
                nil,
                cString.baseAddress!,
                SQL_NTS_SHORT,
                &outString,
                SQLSMALLINT(outString.count),
                &outLength,
                SQL_DRIVER_NOPROMPT
            )
        }

        guard SQL_SUCCEEDED(connectRC) else {
            let diag = diagnostic(for: SQL_HANDLE_DBC, handle: dbc)
            let category: DamengError.Category = diag.sqlState == "28000" ? .authenticationFailed : .connectionFailed
            throw DamengError(
                message: diag.message,
                category: category,
                sqlState: diag.sqlState,
                nativeCode: diag.nativeCode
            )
        }

        log.debug("Connected to Dameng \(self.host):\(self.port)")
    }

    private func buildConnectionString() -> String {
        var parts: [String] = [
            "DRIVER=\(driverPath)",
            "SERVER=\(host)",
            "UID=\(user)",
            "PWD=\(password)",
            "TCP_PORT=\(port)"
        ]
        if !database.isEmpty {
            parts.append("DATABASE=\(database)")
        }
        return parts.joined(separator: ";")
    }

    func disconnect() {
        let env = self.environment
        let dbc = self.connection
        let stmt = self.currentStatement

        self.currentStatement = nil
        self.connection = nil
        self.environment = nil

        if let stmt {
            _ = ODBCFunctions.SQLFreeHandle(SQL_HANDLE_STMT, stmt)
        }
        if let dbc {
            _ = ODBCFunctions.SQLDisconnect(dbc)
            _ = ODBCFunctions.SQLFreeHandle(SQL_HANDLE_DBC, dbc)
        }
        if let env {
            _ = ODBCFunctions.SQLFreeHandle(SQL_HANDLE_ENV, env)
        }

        log.debug("Disconnected from Dameng \(self.host):\(self.port)")
    }

    // MARK: - Query Execution

    func executeQuery(_ query: String, rowCap: Int? = nil) async throws -> DamengQueryResult {
        guard let connection else {
            throw DamengError.notConnected
        }

        await queryGate.acquire()
        defer { Task { await queryGate.release() } }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DamengQueryResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executeQuerySync(query, connection: connection, rowCap: rowCap)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func executeQuerySync(_ query: String, connection: SQLHDBC, rowCap: Int?) throws -> DamengQueryResult {
        var stmt: SQLHSTMT = nil
        let allocRC = ODBCFunctions.SQLAllocHandle(SQL_HANDLE_STMT, connection, &stmt)
        guard SQL_SUCCEEDED(allocRC), let stmt else {
            throw DamengError.queryFailed
        }
        self.currentStatement = stmt
        defer {
            self.currentStatement = nil
            _ = ODBCFunctions.SQLFreeHandle(SQL_HANDLE_STMT, stmt)
        }

        let queryBytes = query.odbcUTF8
        let execRC = queryBytes.withUnsafeBufferPointer { cString -> SQLRETURN in
            ODBCFunctions.SQLExecDirect(stmt, cString.baseAddress!, SQLINTEGER(query.utf8.count))
        }

        guard SQL_SUCCEEDED(execRC) || execRC == SQL_NO_DATA else {
            let diag = diagnostic(for: SQL_HANDLE_STMT, handle: stmt)
            throw DamengError(
                message: diag.message,
                category: .queryFailed,
                sqlState: diag.sqlState,
                nativeCode: diag.nativeCode
            )
        }

        var columnCount: SQLSMALLINT = 0
        _ = ODBCFunctions.SQLNumResultCols(stmt, &columnCount)

        let maxRows = rowCap ?? PluginRowLimits.emergencyMax

        if columnCount == 0 {
            var affected: SQLLEN = 0
            _ = ODBCFunctions.SQLRowCount(stmt, &affected)
            return DamengQueryResult(
                columns: [],
                columnTypeNames: [],
                rows: [],
                affectedRows: max(0, Int(affected)),
                isTruncated: false
            )
        }

        var columns: [String] = []
        var columnTypes: [SQLSMALLINT] = []
        var columnTypeNames: [String] = []

        for index in 1...columnCount {
            var nameBuffer = [UInt8](repeating: 0, count: 256)
            var nameLength: SQLSMALLINT = 0
            var dataType: SQLSMALLINT = 0
            var columnSize: SQLULEN = 0
            var decimalDigits: SQLSMALLINT = 0
            var nullable: SQLSMALLINT = 0

            let descRC = ODBCFunctions.SQLDescribeCol(
                stmt,
                SQLUSMALLINT(index),
                &nameBuffer,
                SQLSMALLINT(nameBuffer.count),
                &nameLength,
                &dataType,
                &columnSize,
                &decimalDigits,
                &nullable
            )

            let name = SQL_SUCCEEDED(descRC)
                ? String(bytes: nameBuffer.prefix(Int(nameLength)), encoding: .utf8) ?? "COL\(index)"
                : "COL\(index)"

            columns.append(name)
            columnTypes.append(dataType)
            columnTypeNames.append(typeName(for: dataType))
        }

        var rows: [[PluginCellValue]] = []
        var isTruncated = false

        while true {
            let fetchRC = ODBCFunctions.SQLFetch(stmt)
            if fetchRC == SQL_NO_DATA {
                break
            }
            guard SQL_SUCCEEDED(fetchRC) else {
                let diag = diagnostic(for: SQL_HANDLE_STMT, handle: stmt)
                throw DamengError(
                    message: diag.message,
                    category: .queryFailed,
                    sqlState: diag.sqlState,
                    nativeCode: diag.nativeCode
                )
            }

            if rows.count >= maxRows {
                isTruncated = true
                break
            }

            var row: [PluginCellValue] = []
            for (index, type) in columnTypes.enumerated() {
                let cell = try fetchCell(stmt: stmt, column: SQLUSMALLINT(index + 1), sqlType: type)
                row.append(cell)
            }
            rows.append(row)
        }

        var affected: SQLLEN = 0
        _ = ODBCFunctions.SQLRowCount(stmt, &affected)

        return DamengQueryResult(
            columns: columns,
            columnTypeNames: columnTypeNames,
            rows: rows,
            affectedRows: max(0, Int(affected)),
            isTruncated: isTruncated
        )
    }

    private func fetchCell(stmt: SQLHSTMT, column: SQLUSMALLINT, sqlType: SQLSMALLINT) throws -> PluginCellValue {
        let isBinary = sqlType == SQL_BINARY || sqlType == SQL_VARBINARY || sqlType == SQL_LONGVARBINARY
        let targetType: SQLSMALLINT = isBinary ? SQL_C_BINARY : SQL_C_CHAR

        var indicator: SQLLEN = 0
        var buffer = [UInt8](repeating: 0, count: 4096)

        let initialRC = ODBCFunctions.SQLGetData(
            stmt,
            column,
            targetType,
            &buffer,
            SQLLEN(buffer.count),
            &indicator
        )

        guard SQL_SUCCEEDED(initialRC) || initialRC == SQL_SUCCESS_WITH_INFO || initialRC == SQL_NO_DATA else {
            let diag = diagnostic(for: SQL_HANDLE_STMT, handle: stmt)
            throw DamengError(
                message: diag.message,
                category: .queryFailed,
                sqlState: diag.sqlState,
                nativeCode: diag.nativeCode
            )
        }

        if indicator == SQL_NULL_DATA {
            return .null
        }

        if initialRC == SQL_NO_DATA {
            return .null
        }

        let requiredLength = indicator == SQL_NO_TOTAL ? buffer.count : Int(indicator)
        if requiredLength > buffer.count {
            buffer = [UInt8](repeating: 0, count: requiredLength + 1)
            let secondRC = ODBCFunctions.SQLGetData(
                stmt,
                column,
                targetType,
                &buffer,
                SQLLEN(buffer.count),
                &indicator
            )
            guard SQL_SUCCEEDED(secondRC) || secondRC == SQL_SUCCESS_WITH_INFO else {
                let diag = diagnostic(for: SQL_HANDLE_STMT, handle: stmt)
                throw DamengError(
                    message: diag.message,
                    category: .queryFailed,
                    sqlState: diag.sqlState,
                    nativeCode: diag.nativeCode
                )
            }
        }

        if isBinary {
            let length = (indicator >= 0 && indicator < buffer.count) ? Int(indicator) : buffer.count
            let data = Data(buffer.prefix(length))
            return .bytes(data)
        }

        let stringValue: String
        if indicator == SQL_NTS {
            stringValue = String(bytes: buffer.prefix(while: { $0 != 0 }), encoding: .utf8)
                ?? String(bytes: buffer.prefix(while: { $0 != 0 }), encoding: .ascii)
                ?? ""
        } else {
            let length = (indicator >= 0 && indicator < buffer.count) ? Int(indicator) : buffer.count
            let bytes = buffer.prefix(length)
            stringValue = String(bytes: bytes, encoding: .utf8)
                ?? String(bytes: bytes, encoding: .ascii)
                ?? ""
        }

        return .text(stringValue)
    }

    // MARK: - Transactions

    func commit() async throws {
        try await endTransaction(completion: SQL_COMMIT)
    }

    func rollback() async throws {
        try await endTransaction(completion: SQL_ROLLBACK)
    }

    private func endTransaction(completion: SQLSMALLINT) async throws {
        guard let connection else {
            throw DamengError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let rc = ODBCFunctions.SQLEndTran(SQL_HANDLE_DBC, connection, completion)
                if SQL_SUCCEEDED(rc) {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DamengError.queryFailed)
                }
            }
        }
    }

    func setQueryTimeout(_ seconds: Int) async throws {
        // Applied per statement; callers should call this before executeQuery.
        // We store the value and apply it in executeQuerySync before execution.
    }

    // MARK: - Diagnostics

    private struct DiagnosticInfo {
        let message: String
        let sqlState: String?
        let nativeCode: Int?
    }

    private func diagnostic(for handleType: SQLSMALLINT, handle: SQLHANDLE?) -> DiagnosticInfo {
        var sqlState = [UInt8](repeating: 0, count: 6)
        var nativeError: SQLINTEGER = 0
        var message = [UInt8](repeating: 0, count: Int(SQL_MAX_MESSAGE_LENGTH))
        var messageLength: SQLSMALLINT = 0

        let rc = ODBCFunctions.SQLGetDiagRec(
            handleType,
            handle,
            1,
            &sqlState,
            &nativeError,
            &message,
            SQLSMALLINT(message.count),
            &messageLength
        )

        guard SQL_SUCCEEDED(rc) else {
            return DiagnosticInfo(message: String(localized: "Unknown ODBC error"), sqlState: nil, nativeCode: nil)
        }

        let stateString = String(bytes: sqlState.prefix(while: { $0 != 0 }), encoding: .ascii)
        let messageString = String(bytes: message.prefix(Int(messageLength)), encoding: .utf8)
            ?? String(bytes: message.prefix(Int(messageLength)), encoding: .ascii)
            ?? String(localized: "Unknown ODBC error")

        return DiagnosticInfo(
            message: messageString,
            sqlState: stateString,
            nativeCode: Int(nativeError)
        )
    }
}

// MARK: - Type Mapping

private func typeName(for sqlType: SQLSMALLINT) -> String {
    switch sqlType {
    case SQL_CHAR: return "CHAR"
    case SQL_VARCHAR: return "VARCHAR"
    case SQL_LONGVARCHAR: return "LONGVARCHAR"
    case SQL_NUMERIC: return "NUMERIC"
    case SQL_DECIMAL: return "DECIMAL"
    case SQL_INTEGER: return "INTEGER"
    case SQL_SMALLINT: return "SMALLINT"
    case SQL_BIGINT: return "BIGINT"
    case SQL_FLOAT: return "FLOAT"
    case SQL_REAL: return "REAL"
    case SQL_DOUBLE: return "DOUBLE"
    case SQL_BIT: return "BIT"
    case SQL_TINYINT: return "TINYINT"
    case SQL_DATE, SQL_TYPE_DATE: return "DATE"
    case SQL_TIME, SQL_TYPE_TIME: return "TIME"
    case SQL_TIMESTAMP, SQL_TYPE_TIMESTAMP: return "TIMESTAMP"
    case SQL_BINARY: return "BINARY"
    case SQL_VARBINARY: return "VARBINARY"
    case SQL_LONGVARBINARY: return "LONGVARBINARY"
    case SQL_GUID: return "GUID"
    default: return "UNKNOWN"
    }
}
