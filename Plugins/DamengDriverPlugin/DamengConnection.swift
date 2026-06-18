import CDamengGo
import Darwin
import Foundation
import os
import TableProPluginKit

private let log = Logger(subsystem: "com.TablePro", category: "DamengConnection")

// MARK: - Query Serialization

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
    private let schema: String?

    private var connHandle: UnsafeMutableRawPointer?
    private var txHandle: UnsafeMutableRawPointer?
    private let queryGate = QueryGate()

    init(
        host: String,
        port: Int,
        user: String,
        password: String,
        database: String,
        schema: String? = nil
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.schema = schema
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
        let dsn = buildDSN()
        var cDSN = dsn.cString(using: .utf8) ?? []

        let result = cDSN.withUnsafeMutableBufferPointer { buf -> (UnsafeMutableRawPointer?, String?) in
            let ret = DamengOpen(buf.baseAddress)
            if let err = ret.r1 {
                let msg = String(cString: err)
                DamengFreeString(err)
                return (nil, msg)
            }
            return (ret.r0, nil)
        }

        if let error = result.1 {
            throw DamengError(message: error, category: .connectionFailed)
        }

        guard let handle = result.0 else {
            throw DamengError.connectionFailed
        }
        self.connHandle = handle

        log.debug("Connected to Dameng \(self.host):\(self.port)")
    }

    private func buildDSN() -> String {
        var dsn = "dm://\(user):\(password)@\(host):\(port)"
        if !database.isEmpty {
            dsn += "/\(database)"
        }
        var params: [String] = []
        if let schema, !schema.isEmpty {
            params.append("schema=\(schema)")
        }
        if !params.isEmpty {
            dsn += "?" + params.joined(separator: "&")
        }
        return dsn
    }

    func disconnect() {
        guard let handle = connHandle else { return }
        DamengClose(handle)
        connHandle = nil
        log.debug("Disconnected from Dameng \(self.host):\(self.port)")
    }

    // MARK: - Query Execution

    func executeQuery(_ query: String, rowCap: Int? = nil) async throws -> DamengQueryResult {
        guard let handle = connHandle else {
            throw DamengError.notConnected
        }

        await queryGate.acquire()
        defer { Task { await queryGate.release() } }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DamengQueryResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.executeQuerySync(query, handle: handle, rowCap: rowCap)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func executeQuerySync(_ query: String, handle: UnsafeMutableRawPointer, rowCap: Int?) throws -> DamengQueryResult {
        var cQuery = query.cString(using: .utf8) ?? []

        let rowsResult = cQuery.withUnsafeMutableBufferPointer { buf -> (UnsafeMutableRawPointer?, String?) in
            let ret = DamengQuery(handle, buf.baseAddress)
            if let err = ret.r1 {
                let msg = String(cString: err)
                DamengFreeString(err)
                return (nil, msg)
            }
            return (ret.r0, nil)
        }

        if let error = rowsResult.1 {
            throw DamengError(message: error, category: .queryFailed)
        }

        guard let rowsHandle = rowsResult.0 else {
            throw DamengError.queryFailed
        }

        defer { DamengRowsClose(rowsHandle) }

        let maxRows = rowCap ?? PluginRowLimits.emergencyMax
        let columnCount = Int(DamengRowsColumnCount(rowsHandle))

        if columnCount == 0 {
            return DamengQueryResult(
                columns: [],
                columnTypeNames: [],
                rows: [],
                affectedRows: 0,
                isTruncated: false
            )
        }

        var columns: [String] = []
        var columnTypeNames: [String] = []

        if let namesPtr = DamengRowsColumnNames(rowsHandle) {
            let nameSlice = UnsafeBufferPointer<UnsafeMutablePointer<CChar>?>(start: namesPtr, count: columnCount)
            for i in 0..<columnCount {
                if let ptr = nameSlice[i] {
                    columns.append(String(cString: ptr))
                } else {
                    columns.append("COL\(i + 1)")
                }
            }
            DamengFreeStringArray(namesPtr, CInt(columnCount))
        }

        if let typesPtr = DamengRowsColumnTypeNames(rowsHandle) {
            let typeSlice = UnsafeBufferPointer<UnsafeMutablePointer<CChar>?>(start: typesPtr, count: columnCount)
            for i in 0..<columnCount {
                if let ptr = typeSlice[i] {
                    columnTypeNames.append(String(cString: ptr))
                } else {
                    columnTypeNames.append("UNKNOWN")
                }
            }
            DamengFreeStringArray(typesPtr, CInt(columnCount))
        }

        var rows: [[PluginCellValue]] = []
        var isTruncated = false

        while true {
            let nextResult = DamengRowsNext(rowsHandle)
            if nextResult == 0 { break }
            if nextResult < 0 {
                throw DamengError.queryFailed
            }

            if rows.count >= maxRows {
                isTruncated = true
                break
            }

            guard let valuesPtr = DamengRowsScanText(rowsHandle) else {
                throw DamengError.queryFailed
            }

            var row: [PluginCellValue] = []
            let valSlice = UnsafeBufferPointer<UnsafeMutablePointer<CChar>?>(start: valuesPtr, count: columnCount)
            for i in 0..<columnCount {
                if let ptr = valSlice[i] {
                    row.append(.text(String(cString: ptr)))
                } else {
                    row.append(.null)
                }
            }
            DamengFreeStringArray(valuesPtr, CInt(columnCount))
            rows.append(row)
        }

        return DamengQueryResult(
            columns: columns,
            columnTypeNames: columnTypeNames,
            rows: rows,
            affectedRows: 0,
            isTruncated: isTruncated
        )
    }

    // MARK: - Exec (no result set)

    func executeStatement(_ sql: String) async throws -> Int {
        guard let handle = connHandle else {
            throw DamengError.notConnected
        }

        await queryGate.acquire()
        defer { Task { await queryGate.release() } }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var cSQL = sql.cString(using: .utf8) ?? []
                let result = cSQL.withUnsafeMutableBufferPointer { buf -> (Int64, String?) in
                    let ret = DamengExec(handle, buf.baseAddress)
                    if let err = ret.r1 {
                        let msg = String(cString: err)
                        DamengFreeString(err)
                        return (-1, msg)
                    }
                    return (Int64(ret.r0), nil)
                }

                if let error = result.1 {
                    continuation.resume(throwing: DamengError(message: error, category: .queryFailed))
                } else {
                    continuation.resume(returning: Int(result.0))
                }
            }
        }
    }

    // MARK: - Transactions

    func beginTransaction() async throws {
        guard let handle = connHandle else {
            throw DamengError.notConnected
        }

        let result = DamengBeginTx(handle)
        if let err = result.r1 {
            let msg = String(cString: err)
            DamengFreeString(err)
            throw DamengError(message: msg, category: .queryFailed)
        }
        txHandle = result.r0
    }

    func commit() async throws {
        guard let tx = txHandle else {
            throw DamengError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if let err = DamengCommitTx(tx) {
                    let msg = String(cString: err)
                    DamengFreeString(err)
                    continuation.resume(throwing: DamengError(message: msg, category: .queryFailed))
                } else {
                    continuation.resume()
                }
            }
        }
        txHandle = nil
    }

    func rollback() async throws {
        guard let tx = txHandle else {
            throw DamengError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if let err = DamengRollbackTx(tx) {
                    let msg = String(cString: err)
                    DamengFreeString(err)
                    continuation.resume(throwing: DamengError(message: msg, category: .queryFailed))
                } else {
                    continuation.resume()
                }
            }
        }
        txHandle = nil
    }

    // MARK: - Metadata

    func fetchVersion() -> String? {
        guard let handle = connHandle else { return nil }
        if let cStr = DamengFetchVersion(handle) {
            let version = String(cString: cStr)
            DamengFreeString(cStr)
            return version
        }
        return nil
    }

    func fetchCurrentSchema() -> String? {
        guard let handle = connHandle else { return nil }
        if let cStr = DamengFetchCurrentSchema(handle) {
            let schema = String(cString: cStr)
            DamengFreeString(cStr)
            return schema
        }
        return nil
    }

    func setSchema(_ schema: String) throws {
        guard let handle = connHandle else {
            throw DamengError.notConnected
        }
        var cSchema = schema.cString(using: .utf8) ?? []
        cSchema.withUnsafeMutableBufferPointer { buf in
            if let err = DamengSetSchema(handle, buf.baseAddress) {
                let msg = String(cString: err)
                DamengFreeString(err)
                log.debug("Set schema error: \(msg)")
            }
        }
    }
}
