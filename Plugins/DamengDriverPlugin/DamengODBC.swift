//
//  DamengODBC.swift
//  TablePro
//
//  Dynamic loader for the ODBC driver manager. This avoids a build-time
//  dependency on a specific ODBC implementation (iODBC vs unixODBC).
//

import Darwin
import Foundation

// MARK: - ODBC Type Aliases

typealias SQLHANDLE = UnsafeMutableRawPointer
typealias SQLHENV = SQLHANDLE?
typealias SQLHDBC = SQLHANDLE?
typealias SQLHSTMT = SQLHANDLE?
typealias SQLSMALLINT = Int16
typealias SQLUSMALLINT = UInt16
typealias SQLINTEGER = Int32
typealias SQLUINTEGER = UInt32
typealias SQLLEN = Int
typealias SQLULEN = UInt
typealias SQLRETURN = SQLSMALLINT
typealias SQLPOINTER = UnsafeMutableRawPointer?
typealias SQLCHAR = UInt8

// MARK: - Constants

let SQL_MAX_MESSAGE_LENGTH: SQLSMALLINT = 512

let SQL_HANDLE_ENV: SQLSMALLINT = 1
let SQL_HANDLE_DBC: SQLSMALLINT = 2
let SQL_HANDLE_STMT: SQLSMALLINT = 3
let SQL_HANDLE_DESC: SQLSMALLINT = 4

let SQL_SUCCESS: SQLRETURN = 0
let SQL_SUCCESS_WITH_INFO: SQLRETURN = 1
let SQL_STILL_EXECUTING: SQLRETURN = 2
let SQL_ERROR: SQLRETURN = -1
let SQL_INVALID_HANDLE: SQLRETURN = -2
let SQL_NO_DATA: SQLRETURN = 100

let SQL_NULL_HANDLE: SQLHANDLE? = nil
let SQL_NULL_HENV: SQLHENV = nil
let SQL_NULL_HDBC: SQLHDBC = nil
let SQL_NULL_HSTMT: SQLHSTMT = nil

let SQL_NULL_DATA: SQLLEN = -1
let SQL_NTS: SQLLEN = -3
let SQL_NTS_SHORT: SQLSMALLINT = -3

let SQL_TRUE: SQLULEN = 1
let SQL_FALSE: SQLULEN = 0

let SQL_ATTR_ODBC_VERSION: SQLINTEGER = 200
let SQL_OV_ODBC3: SQLUINTEGER = 3

let SQL_ATTR_AUTOCOMMIT: SQLINTEGER = 102
let SQL_AUTOCOMMIT_ON: SQLULEN = 1
let SQL_AUTOCOMMIT_OFF: SQLULEN = 0

let SQL_ATTR_QUERY_TIMEOUT: SQLINTEGER = 0
let SQL_QUERY_TIMEOUT_DEFAULT: SQLULEN = 0

let SQL_IS_POINTER: SQLINTEGER = -4
let SQL_IS_UINTEGER: SQLINTEGER = -5
let SQL_IS_INTEGER: SQLINTEGER = -6

let SQL_NO_TOTAL: SQLLEN = -4

let SQL_DRIVER_NOPROMPT: SQLUSMALLINT = 0

let SQL_CLOSE: SQLUSMALLINT = 0
let SQL_UNBIND: SQLUSMALLINT = 2
let SQL_RESET_PARAMS: SQLUSMALLINT = 3

let SQL_COMMIT: SQLSMALLINT = 0
let SQL_ROLLBACK: SQLSMALLINT = 1

// SQL types
let SQL_UNKNOWN_TYPE: SQLSMALLINT = 0
let SQL_CHAR: SQLSMALLINT = 1
let SQL_NUMERIC: SQLSMALLINT = 2
let SQL_DECIMAL: SQLSMALLINT = 3
let SQL_INTEGER: SQLSMALLINT = 4
let SQL_SMALLINT: SQLSMALLINT = 5
let SQL_FLOAT: SQLSMALLINT = 6
let SQL_REAL: SQLSMALLINT = 7
let SQL_DOUBLE: SQLSMALLINT = 8
let SQL_DATETIME: SQLSMALLINT = 9
let SQL_VARCHAR: SQLSMALLINT = 12

let SQL_DATE: SQLSMALLINT = 9
let SQL_TIME: SQLSMALLINT = 10
let SQL_TIMESTAMP: SQLSMALLINT = 11
let SQL_INTERVAL: SQLSMALLINT = 10
let SQL_LONGVARCHAR: SQLSMALLINT = -1
let SQL_BINARY: SQLSMALLINT = -2
let SQL_VARBINARY: SQLSMALLINT = -3
let SQL_LONGVARBINARY: SQLSMALLINT = -4
let SQL_BIGINT: SQLSMALLINT = -5
let SQL_TINYINT: SQLSMALLINT = -6
let SQL_BIT: SQLSMALLINT = -7
let SQL_WCHAR: SQLSMALLINT = -8
let SQL_WVARCHAR: SQLSMALLINT = -9
let SQL_WLONGVARCHAR: SQLSMALLINT = -10
let SQL_GUID: SQLSMALLINT = -11

let SQL_TYPE_DATE: SQLSMALLINT = 91
let SQL_TYPE_TIME: SQLSMALLINT = 92
let SQL_TYPE_TIMESTAMP: SQLSMALLINT = 93

let SQL_SIGNED_OFFSET: SQLSMALLINT = -20
let SQL_UNSIGNED_OFFSET: SQLSMALLINT = -22

// C types
let SQL_C_CHAR: SQLSMALLINT = SQL_CHAR
let SQL_C_LONG: SQLSMALLINT = SQL_INTEGER
let SQL_C_SLONG: SQLSMALLINT = SQL_C_LONG + SQL_SIGNED_OFFSET
let SQL_C_SSHORT: SQLSMALLINT = SQL_SMALLINT + SQL_SIGNED_OFFSET
let SQL_C_FLOAT: SQLSMALLINT = SQL_REAL
let SQL_C_DOUBLE: SQLSMALLINT = SQL_DOUBLE
let SQL_C_BINARY: SQLSMALLINT = SQL_BINARY
let SQL_C_DEFAULT: SQLSMALLINT = 99
let SQL_C_WCHAR: SQLSMALLINT = SQL_WCHAR

let SQL_NO_NULLS: SQLSMALLINT = 0
let SQL_NULLABLE: SQLSMALLINT = 1
let SQL_NULLABLE_UNKNOWN: SQLSMALLINT = 2

let SQL_DIAG_RETURNCODE: SQLSMALLINT = 1
let SQL_DIAG_NUMBER: SQLSMALLINT = 2
let SQL_DIAG_ROW_COUNT: SQLSMALLINT = 3
let SQL_DIAG_SQLSTATE: SQLSMALLINT = 4
let SQL_DIAG_NATIVE: SQLSMALLINT = 5
let SQL_DIAG_MESSAGE_TEXT: SQLSMALLINT = 6

// MARK: - Function Pointer Types

typealias SQLAllocHandle_fn = @convention(c) (
    SQLSMALLINT, SQLHANDLE?, UnsafeMutablePointer<SQLHANDLE?>
) -> SQLRETURN

typealias SQLFreeHandle_fn = @convention(c) (
    SQLSMALLINT, SQLHANDLE?
) -> SQLRETURN

typealias SQLSetEnvAttr_fn = @convention(c) (
    SQLHENV, SQLINTEGER, SQLPOINTER, SQLINTEGER
) -> SQLRETURN

typealias SQLSetConnectAttr_fn = @convention(c) (
    SQLHDBC, SQLINTEGER, SQLPOINTER, SQLINTEGER
) -> SQLRETURN

typealias SQLSetStmtAttr_fn = @convention(c) (
    SQLHSTMT, SQLINTEGER, SQLPOINTER, SQLINTEGER
) -> SQLRETURN

typealias SQLDriverConnect_fn = @convention(c) (
    SQLHDBC,
    SQLPOINTER,
    UnsafePointer<SQLCHAR>,
    SQLSMALLINT,
    UnsafeMutablePointer<SQLCHAR>,
    SQLSMALLINT,
    UnsafeMutablePointer<SQLSMALLINT>,
    SQLUSMALLINT
) -> SQLRETURN

typealias SQLDisconnect_fn = @convention(c) (
    SQLHDBC
) -> SQLRETURN

typealias SQLEndTran_fn = @convention(c) (
    SQLSMALLINT, SQLHANDLE?, SQLSMALLINT
) -> SQLRETURN

typealias SQLExecDirect_fn = @convention(c) (
    SQLHSTMT, UnsafePointer<SQLCHAR>, SQLINTEGER
) -> SQLRETURN

typealias SQLFreeStmt_fn = @convention(c) (
    SQLHSTMT, SQLUSMALLINT
) -> SQLRETURN

typealias SQLNumResultCols_fn = @convention(c) (
    SQLHSTMT, UnsafeMutablePointer<SQLSMALLINT>
) -> SQLRETURN

typealias SQLRowCount_fn = @convention(c) (
    SQLHSTMT, UnsafeMutablePointer<SQLLEN>
) -> SQLRETURN

typealias SQLDescribeCol_fn = @convention(c) (
    SQLHSTMT,
    SQLUSMALLINT,
    UnsafeMutablePointer<SQLCHAR>,
    SQLSMALLINT,
    UnsafeMutablePointer<SQLSMALLINT>,
    UnsafeMutablePointer<SQLSMALLINT>,
    UnsafeMutablePointer<SQLULEN>,
    UnsafeMutablePointer<SQLSMALLINT>,
    UnsafeMutablePointer<SQLSMALLINT>
) -> SQLRETURN

typealias SQLFetch_fn = @convention(c) (
    SQLHSTMT
) -> SQLRETURN

typealias SQLGetData_fn = @convention(c) (
    SQLHSTMT,
    SQLUSMALLINT,
    SQLSMALLINT,
    SQLPOINTER,
    SQLLEN,
    UnsafeMutablePointer<SQLLEN>
) -> SQLRETURN

typealias SQLGetDiagRec_fn = @convention(c) (
    SQLSMALLINT,
    SQLHANDLE?,
    SQLSMALLINT,
    UnsafeMutablePointer<SQLCHAR>,
    UnsafeMutablePointer<SQLINTEGER>,
    UnsafeMutablePointer<SQLCHAR>,
    SQLSMALLINT,
    UnsafeMutablePointer<SQLSMALLINT>
) -> SQLRETURN

typealias SQLCancel_fn = @convention(c) (
    SQLHSTMT
) -> SQLRETURN

// MARK: - Loaded Function Pointers

enum ODBCFunctions {
    static var SQLAllocHandle: SQLAllocHandle_fn!
    static var SQLFreeHandle: SQLFreeHandle_fn!
    static var SQLSetEnvAttr: SQLSetEnvAttr_fn!
    static var SQLSetConnectAttr: SQLSetConnectAttr_fn!
    static var SQLSetStmtAttr: SQLSetStmtAttr_fn!
    static var SQLDriverConnect: SQLDriverConnect_fn!
    static var SQLDisconnect: SQLDisconnect_fn!
    static var SQLEndTran: SQLEndTran_fn!
    static var SQLExecDirect: SQLExecDirect_fn!
    static var SQLFreeStmt: SQLFreeStmt_fn!
    static var SQLNumResultCols: SQLNumResultCols_fn!
    static var SQLRowCount: SQLRowCount_fn!
    static var SQLDescribeCol: SQLDescribeCol_fn!
    static var SQLFetch: SQLFetch_fn!
    static var SQLGetData: SQLGetData_fn!
    static var SQLGetDiagRec: SQLGetDiagRec_fn!
    static var SQLCancel: SQLCancel_fn!

    static let managerSearchPaths: [String] = [
        "/opt/homebrew/lib/libodbc.dylib",
        "/opt/homebrew/lib/libiodbc.dylib",
        "/usr/local/lib/libodbc.dylib",
        "/usr/local/lib/libiodbc.dylib",
        "/usr/lib/libodbc.dylib",
        "/usr/lib/libiodbc.dylib",
        "/Library/Frameworks/iODBC.framework/iODBC",
        "/Library/Frameworks/iODBC.framework/Versions/Current/iODBC"
    ]

    static func loadManager(preferredPath: String?) throws {
        if let preferredPath, !preferredPath.isEmpty {
            if load(from: preferredPath) { return }
            throw DamengError(
                message: String(localized: "Could not load ODBC driver manager at \(preferredPath). Please install unixODBC or iODBC."),
                category: .driverManagerNotFound
            )
        }

        for path in managerSearchPaths {
            if load(from: path) { return }
        }

        throw DamengError(
            message: String(localized: "No ODBC driver manager found. Install with: brew install unixodbc"),
            category: .driverManagerNotFound
        )
    }

    @discardableResult
    private static func load(from path: String) -> Bool {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) else {
            return false
        }

        func sym(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(handle, name)
        }

        guard let allocHandle = sym("SQLAllocHandle"),
              let freeHandle = sym("SQLFreeHandle"),
              let setEnvAttr = sym("SQLSetEnvAttr"),
              let setConnectAttr = sym("SQLSetConnectAttr"),
              let setStmtAttr = sym("SQLSetStmtAttr"),
              let driverConnect = sym("SQLDriverConnect"),
              let disconnect = sym("SQLDisconnect"),
              let endTran = sym("SQLEndTran"),
              let execDirect = sym("SQLExecDirect"),
              let freeStmt = sym("SQLFreeStmt"),
              let numResultCols = sym("SQLNumResultCols"),
              let rowCount = sym("SQLRowCount"),
              let describeCol = sym("SQLDescribeCol"),
              let fetch = sym("SQLFetch"),
              let getData = sym("SQLGetData"),
              let getDiagRec = sym("SQLGetDiagRec"),
              let cancel = sym("SQLCancel") else {
            dlclose(handle)
            return false
        }

        SQLAllocHandle = unsafeBitCast(allocHandle, to: SQLAllocHandle_fn.self)
        SQLFreeHandle = unsafeBitCast(freeHandle, to: SQLFreeHandle_fn.self)
        SQLSetEnvAttr = unsafeBitCast(setEnvAttr, to: SQLSetEnvAttr_fn.self)
        SQLSetConnectAttr = unsafeBitCast(setConnectAttr, to: SQLSetConnectAttr_fn.self)
        SQLSetStmtAttr = unsafeBitCast(setStmtAttr, to: SQLSetStmtAttr_fn.self)
        SQLDriverConnect = unsafeBitCast(driverConnect, to: SQLDriverConnect_fn.self)
        SQLDisconnect = unsafeBitCast(disconnect, to: SQLDisconnect_fn.self)
        SQLEndTran = unsafeBitCast(endTran, to: SQLEndTran_fn.self)
        SQLExecDirect = unsafeBitCast(execDirect, to: SQLExecDirect_fn.self)
        SQLFreeStmt = unsafeBitCast(freeStmt, to: SQLFreeStmt_fn.self)
        SQLNumResultCols = unsafeBitCast(numResultCols, to: SQLNumResultCols_fn.self)
        SQLRowCount = unsafeBitCast(rowCount, to: SQLRowCount_fn.self)
        SQLDescribeCol = unsafeBitCast(describeCol, to: SQLDescribeCol_fn.self)
        SQLFetch = unsafeBitCast(fetch, to: SQLFetch_fn.self)
        SQLGetData = unsafeBitCast(getData, to: SQLGetData_fn.self)
        SQLGetDiagRec = unsafeBitCast(getDiagRec, to: SQLGetDiagRec_fn.self)
        SQLCancel = unsafeBitCast(cancel, to: SQLCancel_fn.self)

        return true
    }
}

// MARK: - Helpers

func SQL_SUCCEEDED(_ rc: SQLRETURN) -> Bool {
    (rc & (~1)) == 0
}

func SQL_NO_DATA_FOUND(_ rc: SQLRETURN) -> Bool {
    rc == SQL_NO_DATA
}
