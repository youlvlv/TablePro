//
//  DamengPlugin.swift
//  TablePro
//
//  Dameng Database driver plugin for TablePro.
//

import Foundation
import os
import TableProPluginKit

final class DamengPlugin: NSObject, TableProPlugin, DriverPlugin, PluginDiagnosticProvider {
    static let pluginName = "Dameng Driver"
    static let pluginVersion = "1.0.0"
    static let pluginDescription = "Dameng Database support via Go DM8 driver"
    static let capabilities: [PluginCapability] = [.databaseDriver]

    static let databaseTypeId = "Dameng"
    static let databaseDisplayName = "Dameng"
    static let iconName = "dameng-icon"
    static let defaultPort = 5236
    static let additionalConnectionFields: [ConnectionField] = [
        ConnectionField(
            id: "damengSchema",
            label: "Default Schema",
            placeholder: "",
            section: .advanced
        )
    ]
    static let additionalDatabaseTypeIds: [String] = []

    // MARK: - UI/Capability Metadata

    static let isDownloadable = true
    static let pathFieldRole: PathFieldRole = .database
    static let supportsForeignKeyDisable = false
    static let supportsSchemaSwitching = true
    static let postConnectActions: [PostConnectAction] = [.selectSchemaFromLastSession]
    static let brandColorHex = "#E60012"
    static let systemDatabaseNames: [String] = ["SYS", "SYSDBA", "SYSSSO", "SYSAUDITOR"]
    static let databaseGroupingStrategy: GroupingStrategy = .bySchema
    static let supportsSSL = false

    static let columnTypesByCategory: [String: [String]] = [
        "Integer": ["INTEGER", "INT", "SMALLINT", "BIGINT", "TINYINT"],
        "Float": ["FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "REAL", "NUMBER"],
        "String": ["VARCHAR", "CHAR", "VARCHAR2", "NCHAR", "NVARCHAR", "NVARCHAR2", "CLOB", "NCLOB", "TEXT", "LONGVARCHAR"],
        "Date": ["DATE", "TIME", "TIMESTAMP", "DATETIME", "SMALLDATETIME"],
        "Binary": ["BLOB", "BINARY", "VARBINARY", "LONGVARBINARY", "RAW", "LONG RAW"],
        "Boolean": ["BIT", "BOOLEAN"],
        "Other": ["INTERVAL", "GUID", "ROWID"]
    ]

    static let sqlDialect: SQLDialectDescriptor? = SQLDialectDescriptor(
        identifierQuote: "\"",
        keywords: [
            "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "CROSS", "FULL",
            "ON", "USING", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "AS",
            "ORDER", "BY", "GROUP", "HAVING", "FETCH", "FIRST", "ROWS", "ONLY", "OFFSET",
            "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "MERGE",
            "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW", "DATABASE", "SCHEMA",
            "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "CONSTRAINT",
            "ADD", "MODIFY", "COLUMN", "RENAME",
            "NULL", "IS", "ASC", "DESC", "DISTINCT", "ALL", "ANY", "SOME",
            "SEQUENCE", "SYNONYM", "GRANT", "REVOKE", "TRIGGER", "PROCEDURE",
            "CASE", "WHEN", "THEN", "ELSE", "END", "COALESCE", "NULLIF", "DECODE",
            "UNION", "INTERSECT", "MINUS",
            "DECLARE", "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT",
            "EXECUTE", "IMMEDIATE",
            "OVER", "PARTITION", "ROW_NUMBER", "RANK", "DENSE_RANK",
            "CONNECT", "LEVEL", "START", "WITH", "PRIOR",
            "ROWNUM", "ROWID", "DUAL", "SYSDATE", "SYSTIMESTAMP"
        ],
        functions: [
            "COUNT", "SUM", "AVG", "MAX", "MIN", "LISTAGG",
            "CONCAT", "SUBSTR", "INSTR", "LENGTH", "LOWER", "UPPER",
            "TRIM", "LTRIM", "RTRIM", "REPLACE", "LPAD", "RPAD",
            "INITCAP", "TRANSLATE",
            "SYSDATE", "SYSTIMESTAMP", "CURRENT_DATE", "CURRENT_TIMESTAMP",
            "ADD_MONTHS", "MONTHS_BETWEEN", "LAST_DAY", "NEXT_DAY",
            "EXTRACT", "TO_DATE", "TO_CHAR", "TO_NUMBER", "TO_TIMESTAMP",
            "TRUNC", "ROUND",
            "CEIL", "FLOOR", "ABS", "POWER", "SQRT", "MOD", "SIGN",
            "NVL", "NVL2", "DECODE", "COALESCE", "NULLIF",
            "GREATEST", "LEAST", "CAST",
            "USER", "SYS_CONTEXT"
        ],
        dataTypes: [
            "NUMBER", "INTEGER", "SMALLINT", "BIGINT", "TINYINT",
            "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "REAL",
            "CHAR", "VARCHAR", "VARCHAR2", "NCHAR", "NVARCHAR", "NVARCHAR2",
            "CLOB", "NCLOB", "TEXT", "LONG", "LONGVARCHAR",
            "BLOB", "BINARY", "VARBINARY", "RAW", "LONG RAW", "LONGVARBINARY",
            "DATE", "TIME", "TIMESTAMP", "DATETIME", "SMALLDATETIME",
            "BIT", "BOOLEAN", "INTERVAL", "ROWID", "GUID"
        ],
        tableOptions: [
            "TABLESPACE", "PCTFREE", "INITRANS"
        ],
        regexSyntax: .regexpLike,
        booleanLiteralStyle: .numeric,
        likeEscapeStyle: .explicit,
        paginationStyle: .offsetFetch,
        offsetFetchOrderBy: "ORDER BY 1",
        autoLimitStyle: .fetchFirst
    )

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        DamengPluginDriver(config: config)
    }

    func diagnose(error: Error) -> PluginDiagnostic? {
        guard let damengError = error as? DamengError else { return nil }
        let issuesURL = URL(string: "https://github.com/TableProApp/TablePro/issues")

        switch damengError.category {
        case .authenticationFailed:
            return PluginDiagnostic(
                title: String(localized: "Authentication Failed"),
                message: damengError.message,
                suggestedActions: [
                    String(localized: "Check the username and password."),
                    String(localized: "Verify the account is not locked and the database is reachable.")
                ],
                supportURL: issuesURL
            )
        case .connectionFailed:
            return PluginDiagnostic(
                title: String(localized: "Could Not Connect to Dameng"),
                message: damengError.message,
                suggestedActions: [
                    String(localized: "Confirm the host and port (default 5236) are correct."),
                    String(localized: "Check that the Dameng service is running and the network path is open.")
                ],
                supportURL: issuesURL
            )
        case .queryFailed:
            return PluginDiagnostic(
                title: String(localized: "Query Failed"),
                message: damengError.message,
                suggestedActions: [
                    String(localized: "Review the SQL syntax for Dameng compatibility."),
                    String(localized: "Check that the current schema owns or can access the referenced objects.")
                ],
                supportURL: issuesURL
            )
        case .notConnected, .generic:
            return nil
        }
    }
}

// MARK: - Driver

final class DamengPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    private let config: DriverConnectionConfig
    private var damengConn: DamengConnectionWrapper?
    private var _currentSchema: String?
    private var _serverVersion: String?
    private var _queryTimeout: Int = 0

    private static let logger = Logger(subsystem: "com.TablePro", category: "DamengPluginDriver")

    var currentSchema: String? { _currentSchema }
    var serverVersion: String? { _serverVersion }
    var supportsSchemas: Bool { true }
    var supportsTransactions: Bool { true }

    var capabilities: PluginCapabilities {
        [
            .transactions,
            .alterTableDDL,
            .multiSchema,
        ]
    }

    init(config: DriverConnectionConfig) {
        self.config = config
    }

    // MARK: - View Templates

    func createViewTemplate() -> String? {
        "CREATE OR REPLACE VIEW view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
    }

    func editViewFallbackTemplate(viewName: String) -> String? {
        let quoted = quoteIdentifier(viewName)
        return "CREATE OR REPLACE VIEW \(quoted) AS\nSELECT * FROM table_name;"
    }

    // MARK: - Connection

    func connect() async throws {
        let conn = DamengConnectionWrapper(
            host: config.host,
            port: config.port,
            user: config.username,
            password: config.password,
            database: config.database
        )
        try await conn.connect()
        self.damengConn = conn

        let defaultSchema = config.additionalFields["damengSchema"]
        if let schema = defaultSchema, !schema.isEmpty {
            try? await switchSchema(to: schema)
        }

        if let current = conn.fetchCurrentSchema() {
            _currentSchema = current
        } else {
            _currentSchema = config.username.uppercased()
        }

        if let version = conn.fetchVersion() {
            _serverVersion = String(version.prefix(60))
        }
    }

    func disconnect() {
        damengConn?.disconnect()
        damengConn = nil
    }

    func ping() async throws {
        _ = try await execute(query: "SELECT 1")
    }

    // MARK: - Transaction Management

    func beginTransaction() async throws {
        try await damengConn?.beginTransaction()
    }

    func commitTransaction() async throws {
        try await damengConn?.commit()
    }

    func rollbackTransaction() async throws {
        try await damengConn?.rollback()
    }

    // MARK: - Query Execution

    func execute(query: String) async throws -> PluginQueryResult {
        guard let conn = damengConn else {
            throw DamengError.notConnected
        }
        let startTime = Date()
        let result = try await conn.executeQuery(query, rowCap: nil)
        let executionTime = Date().timeIntervalSince(startTime)

        return PluginQueryResult(
            columns: result.columns,
            columnTypeNames: result.columnTypeNames,
            rows: result.rows,
            rowsAffected: result.affectedRows,
            executionTime: executionTime,
            isTruncated: result.isTruncated
        )
    }

    func cancelQuery() throws {
        // Best-effort cancellation is not exposed by the wrapper in this version.
    }

    func applyQueryTimeout(_ seconds: Int) async throws {
        _queryTimeout = seconds
    }

    // MARK: - Streaming

    func streamRows(query: String) -> AsyncThrowingStream<PluginStreamElement, Error> {
        guard damengConn != nil else {
            return AsyncThrowingStream { $0.finish(throwing: DamengError.notConnected) }
        }

        return AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    let result = try await self.execute(query: query)
                    let header = PluginStreamHeader(
                        columns: result.columns,
                        columnTypeNames: result.columnTypeNames
                    )
                    continuation.yield(.header(header))
                    if !result.rows.isEmpty {
                        continuation.yield(.rows(result.rows))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Schema Operations

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] {
        let escaped = effectiveSchemaEscaped(schema)
        let sql = """
            SELECT table_name, 'BASE TABLE' AS table_type FROM all_tables WHERE owner = '\(escaped)'
            UNION ALL
            SELECT view_name, 'VIEW' FROM all_views WHERE owner = '\(escaped)'
            ORDER BY 1
            """
        let result = try await execute(query: sql)
        return result.rows.compactMap { row -> PluginTableInfo? in
            guard let name = row[safe: 0]?.asText else { return nil }
            let rawType = row[safe: 1]?.asText
            let tableType = (rawType == "VIEW") ? "VIEW" : "TABLE"
            return PluginTableInfo(name: name, type: tableType, schema: schema)
        }
    }

    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let escaped = effectiveSchemaEscaped(schema)
        let sql = """
            SELECT
                c.COLUMN_NAME,
                c.DATA_TYPE,
                c.DATA_LENGTH,
                c.DATA_PRECISION,
                c.DATA_SCALE,
                c.NULLABLE,
                CASE WHEN cc.COLUMN_NAME IS NOT NULL THEN 'Y' ELSE 'N' END AS IS_PK
            FROM ALL_TAB_COLUMNS c
            LEFT JOIN (
                SELECT acc.COLUMN_NAME
                FROM ALL_CONS_COLUMNS acc
                JOIN ALL_CONSTRAINTS ac ON acc.CONSTRAINT_NAME = ac.CONSTRAINT_NAME
                    AND acc.OWNER = ac.OWNER
                WHERE ac.CONSTRAINT_TYPE = 'P'
                    AND ac.OWNER = '\(escaped)'
                    AND ac.TABLE_NAME = '\(escapedTable)'
            ) cc ON c.COLUMN_NAME = cc.COLUMN_NAME
            WHERE c.OWNER = '\(escaped)'
              AND c.TABLE_NAME = '\(escapedTable)'
            ORDER BY c.COLUMN_ID
            """
        let result = try await execute(query: sql)
        return result.rows.compactMap { row -> PluginColumnInfo? in
            guard let name = row[safe: 0]?.asText else { return nil }
            let dataType = (row[safe: 1]?.asText)?.lowercased() ?? "varchar"
            let dataLength = row[safe: 2]?.asText
            let precision = row[safe: 3]?.asText
            let scale = row[safe: 4]?.asText
            let isNullable = (row[safe: 5]?.asText) == "Y"
            let isPk = (row[safe: 6]?.asText) == "Y"

            let fullType = Self.buildFullType(
                dataType: dataType,
                dataLength: dataLength,
                precision: precision,
                scale: scale
            )

            return PluginColumnInfo(
                name: name,
                dataType: fullType,
                isNullable: isNullable,
                isPrimaryKey: isPk,
                defaultValue: nil
            )
        }
    }

    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let escaped = effectiveSchemaEscaped(schema)
        let sql = """
            SELECT i.INDEX_NAME, i.UNIQUENESS, ic.COLUMN_NAME,
                   CASE WHEN c.CONSTRAINT_TYPE = 'P' THEN 'Y' ELSE 'N' END AS IS_PK
            FROM ALL_INDEXES i
            JOIN ALL_IND_COLUMNS ic ON i.INDEX_NAME = ic.INDEX_NAME AND i.OWNER = ic.INDEX_OWNER
            LEFT JOIN ALL_CONSTRAINTS c ON i.INDEX_NAME = c.INDEX_NAME AND i.OWNER = c.OWNER
                AND c.CONSTRAINT_TYPE = 'P'
            WHERE i.TABLE_NAME = '\(escapedTable)'
              AND i.OWNER = '\(escaped)'
            ORDER BY i.INDEX_NAME, ic.COLUMN_POSITION
            """
        let result = try await execute(query: sql)
        var indexMap: [String: (unique: Bool, primary: Bool, columns: [String])] = [:]
        for row in result.rows {
            guard let idxName = row[safe: 0]?.asText,
                  let colName = row[safe: 2]?.asText else { continue }
            let isUnique = (row[safe: 1]?.asText) == "UNIQUE"
            let isPrimary = (row[safe: 3]?.asText) == "Y"
            if indexMap[idxName] == nil {
                indexMap[idxName] = (unique: isUnique, primary: isPrimary, columns: [])
            }
            indexMap[idxName]?.columns.append(colName)
        }
        return indexMap.map { name, info in
            PluginIndexInfo(
                name: name,
                columns: info.columns,
                isUnique: info.unique,
                isPrimary: info.primary,
                type: "BTREE"
            )
        }.sorted { $0.name < $1.name }
    }

    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let escaped = effectiveSchemaEscaped(schema)
        let sql = """
            SELECT
                ac.CONSTRAINT_NAME,
                acc.COLUMN_NAME,
                rc.TABLE_NAME AS REF_TABLE,
                rcc.COLUMN_NAME AS REF_COLUMN,
                ac.DELETE_RULE
            FROM ALL_CONSTRAINTS ac
            JOIN ALL_CONS_COLUMNS acc ON ac.CONSTRAINT_NAME = acc.CONSTRAINT_NAME
                AND ac.OWNER = acc.OWNER
            JOIN ALL_CONSTRAINTS rc ON ac.R_CONSTRAINT_NAME = rc.CONSTRAINT_NAME
                AND ac.R_OWNER = rc.OWNER
            JOIN ALL_CONS_COLUMNS rcc ON rc.CONSTRAINT_NAME = rcc.CONSTRAINT_NAME
                AND rc.OWNER = rcc.OWNER AND acc.POSITION = rcc.POSITION
            WHERE ac.CONSTRAINT_TYPE = 'R'
              AND ac.TABLE_NAME = '\(escapedTable)'
              AND ac.OWNER = '\(escaped)'
            ORDER BY ac.CONSTRAINT_NAME, acc.POSITION
            """
        let result = try await execute(query: sql)
        return result.rows.compactMap { row -> PluginForeignKeyInfo? in
            guard let constraintName = row[safe: 0]?.asText,
                  let columnName = row[safe: 1]?.asText,
                  let refTable = row[safe: 2]?.asText,
                  let refColumn = row[safe: 3]?.asText else { return nil }
            let deleteRule = (row[safe: 4]?.asText) ?? "NO ACTION"
            return PluginForeignKeyInfo(
                name: constraintName,
                column: columnName,
                referencedTable: refTable,
                referencedColumn: refColumn,
                onDelete: deleteRule,
                onUpdate: "NO ACTION"
            )
        }
    }

    func fetchAllColumns(schema: String?) async throws -> [String: [PluginColumnInfo]] {
        let escaped = effectiveSchemaEscaped(schema)
        let sql = """
            SELECT
                c.TABLE_NAME,
                c.COLUMN_NAME,
                c.DATA_TYPE,
                c.DATA_LENGTH,
                c.DATA_PRECISION,
                c.DATA_SCALE,
                c.NULLABLE,
                CASE WHEN cc.COLUMN_NAME IS NOT NULL THEN 'Y' ELSE 'N' END AS IS_PK
            FROM ALL_TAB_COLUMNS c
            LEFT JOIN (
                SELECT acc.TABLE_NAME, acc.COLUMN_NAME
                FROM ALL_CONS_COLUMNS acc
                JOIN ALL_CONSTRAINTS ac ON acc.CONSTRAINT_NAME = ac.CONSTRAINT_NAME
                    AND acc.OWNER = ac.OWNER
                WHERE ac.CONSTRAINT_TYPE = 'P' AND ac.OWNER = '\(escaped)'
            ) cc ON c.TABLE_NAME = cc.TABLE_NAME AND c.COLUMN_NAME = cc.COLUMN_NAME
            WHERE c.OWNER = '\(escaped)'
            ORDER BY c.TABLE_NAME, c.COLUMN_ID
            """
        let result = try await execute(query: sql)
        var columnsByTable: [String: [PluginColumnInfo]] = [:]
        for row in result.rows {
            guard let tableName = row[safe: 0]?.asText,
                  let name = row[safe: 1]?.asText else { continue }
            let dataType = (row[safe: 2]?.asText)?.lowercased() ?? "varchar"
            let dataLength = row[safe: 3]?.asText
            let precision = row[safe: 4]?.asText
            let scale = row[safe: 5]?.asText
            let isNullable = (row[safe: 6]?.asText) == "Y"
            let isPk = (row[safe: 7]?.asText) == "Y"

            let fullType = Self.buildFullType(
                dataType: dataType,
                dataLength: dataLength,
                precision: precision,
                scale: scale
            )

            let col = PluginColumnInfo(
                name: name,
                dataType: fullType,
                isNullable: isNullable,
                isPrimaryKey: isPk,
                defaultValue: nil
            )
            columnsByTable[tableName, default: []].append(col)
        }
        return columnsByTable
    }

    func fetchAllForeignKeys(schema: String?) async throws -> [String: [PluginForeignKeyInfo]] {
        let escaped = effectiveSchemaEscaped(schema)
        let sql = """
            SELECT
                ac.TABLE_NAME,
                ac.CONSTRAINT_NAME,
                acc.COLUMN_NAME,
                rc.TABLE_NAME AS REF_TABLE,
                rcc.COLUMN_NAME AS REF_COLUMN,
                ac.DELETE_RULE
            FROM ALL_CONSTRAINTS ac
            JOIN ALL_CONS_COLUMNS acc ON ac.CONSTRAINT_NAME = acc.CONSTRAINT_NAME
                AND ac.OWNER = acc.OWNER
            JOIN ALL_CONSTRAINTS rc ON ac.R_CONSTRAINT_NAME = rc.CONSTRAINT_NAME
                AND ac.R_OWNER = rc.OWNER
            JOIN ALL_CONS_COLUMNS rcc ON rc.CONSTRAINT_NAME = rcc.CONSTRAINT_NAME
                AND rc.OWNER = rcc.OWNER AND acc.POSITION = rcc.POSITION
            WHERE ac.CONSTRAINT_TYPE = 'R' AND ac.OWNER = '\(escaped)'
            ORDER BY ac.TABLE_NAME, ac.CONSTRAINT_NAME, acc.POSITION
            """
        let result = try await execute(query: sql)
        var fksByTable: [String: [PluginForeignKeyInfo]] = [:]
        for row in result.rows {
            guard let tableName = row[safe: 0]?.asText,
                  let constraintName = row[safe: 1]?.asText,
                  let columnName = row[safe: 2]?.asText,
                  let refTable = row[safe: 3]?.asText,
                  let refColumn = row[safe: 4]?.asText else { continue }
            let deleteRule = (row[safe: 5]?.asText) ?? "NO ACTION"
            let fk = PluginForeignKeyInfo(
                name: constraintName,
                column: columnName,
                referencedTable: refTable,
                referencedColumn: refColumn,
                onDelete: deleteRule,
                onUpdate: "NO ACTION"
            )
            fksByTable[tableName, default: []].append(fk)
        }
        return fksByTable
    }

    func fetchTableDDL(table: String, schema: String?) async throws -> String {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let escaped = effectiveSchemaEscaped(schema)
        let cols = try await fetchColumns(table: table, schema: schema)
        var ddl = "CREATE TABLE \"\(escaped)\".\"\(escapedTable)\" (\n"
        let colDefs = cols.map { col -> String in
            var def = "    \"\(col.name)\" \(col.dataType.uppercased())"
            if !col.isNullable { def += " NOT NULL" }
            if let d = col.defaultValue, !d.isEmpty { def += " DEFAULT \(d)" }
            return def
        }
        ddl += colDefs.joined(separator: ",\n")
        ddl += "\n);"
        return ddl
    }

    func fetchViewDefinition(view: String, schema: String?) async throws -> String {
        let escapedView = view.replacingOccurrences(of: "'", with: "''")
        let escaped = effectiveSchemaEscaped(schema)
        let sql = "SELECT TEXT FROM ALL_VIEWS WHERE VIEW_NAME = '\(escapedView)' AND OWNER = '\(escaped)'"
        let result = try await execute(query: sql)
        return result.rows.first?.first?.asText ?? ""
    }

    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let escaped = effectiveSchemaEscaped(schema)
        let sql = """
            SELECT
                t.NUM_ROWS,
                tc.COMMENTS
            FROM ALL_TABLES t
            LEFT JOIN ALL_TAB_COMMENTS tc ON t.TABLE_NAME = tc.TABLE_NAME AND t.OWNER = tc.OWNER
            WHERE t.TABLE_NAME = '\(escapedTable)' AND t.OWNER = '\(escaped)'
            """
        let result = try await execute(query: sql)
        if let row = result.rows.first {
            let rowCount = (row[safe: 0]?.asText).flatMap { Int64($0) }
            let comment = row[safe: 1]?.asText
            return PluginTableMetadata(
                tableName: table,
                dataSize: 0,
                totalSize: 0,
                rowCount: rowCount,
                comment: comment
            )
        }

        let viewSQL = """
            SELECT tc.COMMENTS
            FROM ALL_TAB_COMMENTS tc
            WHERE tc.TABLE_NAME = '\(escapedTable)' AND tc.OWNER = '\(escaped)'
            """
        let viewResult = try await execute(query: viewSQL)
        if let row = viewResult.rows.first {
            let comment = row[safe: 0]?.asText
            return PluginTableMetadata(tableName: table, comment: comment)
        }

        return PluginTableMetadata(tableName: table)
    }

    func fetchDatabases() async throws -> [String] {
        let sql = "SELECT USERNAME FROM ALL_USERS ORDER BY USERNAME"
        let result = try await execute(query: sql)
        return result.rows.compactMap { $0.first?.asText }
    }

    func fetchSchemas() async throws -> [String] {
        try await fetchDatabases()
    }

    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        let escapedDb = database.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT COUNT(*) FROM ALL_TABLES WHERE OWNER = '\(escapedDb)'"
        do {
            let result = try await execute(query: sql)
            let tableCount = result.rows.first?.first?.asText.flatMap { Int($0) } ?? 0
            return PluginDatabaseMetadata(name: database, tableCount: tableCount)
        } catch {
            Self.logger.debug("Failed to fetch database metadata: \(error.localizedDescription)")
        }
        return PluginDatabaseMetadata(name: database)
    }

    func switchSchema(to schema: String) async throws {
        let escaped = schema.replacingOccurrences(of: "\"", with: "\"\"")
        _ = try await execute(query: "SET SCHEMA \"\(escaped)\"")
        _currentSchema = schema
    }

    func switchDatabase(to database: String) async throws {
        try await switchSchema(to: database)
    }

    // MARK: - DML Statement Generation

    func generateStatements(
        table: String,
        columns: [String],
        primaryKeyColumns: [String],
        changes: [PluginRowChange],
        insertedRowData: [Int: [PluginCellValue]],
        deletedRowIndices: Set<Int>,
        insertedRowIndices: Set<Int>
    ) -> [(statement: String, parameters: [PluginCellValue])]? {
        var statements: [(statement: String, parameters: [PluginCellValue])] = []

        for change in changes {
            switch change.type {
            case .insert:
                guard insertedRowIndices.contains(change.rowIndex) else { continue }
                if let values = insertedRowData[change.rowIndex] {
                    if let stmt = generateInsert(table: table, columns: columns, values: values) {
                        statements.append(stmt)
                    }
                }
            case .update:
                if let stmt = generateUpdate(table: table, columns: columns, change: change) {
                    statements.append(stmt)
                }
            case .delete:
                guard deletedRowIndices.contains(change.rowIndex) else { continue }
                if let stmt = generateDelete(table: table, columns: columns, change: change) {
                    statements.append(stmt)
                }
            }
        }

        return statements.isEmpty ? nil : statements
    }

    private func generateInsert(
        table: String,
        columns: [String],
        values: [PluginCellValue]
    ) -> (statement: String, parameters: [PluginCellValue])? {
        var insertColumns: [String] = []
        var valuesSQL: [String] = []
        var parameters: [PluginCellValue] = []

        for (index, value) in values.enumerated() {
            guard index < columns.count else { continue }
            insertColumns.append(quoteIdentifier(columns[index]))
            if value.asText == "__DEFAULT__" {
                valuesSQL.append("DEFAULT")
            } else {
                valuesSQL.append("?")
                parameters.append(value)
            }
        }

        guard !insertColumns.isEmpty else { return nil }

        let columnList = insertColumns.joined(separator: ", ")
        let valueList = valuesSQL.joined(separator: ", ")
        let sql = "INSERT INTO \(quoteIdentifier(table)) (\(columnList)) VALUES (\(valueList))"
        return (statement: sql, parameters: parameters)
    }

    private func generateUpdate(
        table: String,
        columns: [String],
        change: PluginRowChange
    ) -> (statement: String, parameters: [PluginCellValue])? {
        guard !change.cellChanges.isEmpty, let originalRow = change.originalRow else { return nil }

        let escapedTable = quoteIdentifier(table)
        var parameters: [PluginCellValue] = []

        let setClauses = change.cellChanges.map { cellChange -> String in
            let col = quoteIdentifier(cellChange.columnName)
            parameters.append(cellChange.newValue)
            return "\(col) = ?"
        }.joined(separator: ", ")

        var conditions: [String] = []
        for (index, columnName) in columns.enumerated() {
            guard index < originalRow.count else { continue }
            let col = quoteIdentifier(columnName)
            let value = originalRow[index]
            if value.isNull {
                conditions.append("\(col) IS NULL")
            } else {
                parameters.append(value)
                conditions.append("\(col) = ?")
            }
        }

        guard !conditions.isEmpty else { return nil }

        let whereClause = conditions.joined(separator: " AND ")
        let sql = "UPDATE \(escapedTable) SET \(setClauses) WHERE \(whereClause) AND ROWNUM = 1"
        return (statement: sql, parameters: parameters)
    }

    private func generateDelete(
        table: String,
        columns: [String],
        change: PluginRowChange
    ) -> (statement: String, parameters: [PluginCellValue])? {
        guard let originalRow = change.originalRow else { return nil }

        let escapedTable = quoteIdentifier(table)
        var parameters: [PluginCellValue] = []
        var conditions: [String] = []

        for (index, columnName) in columns.enumerated() {
            guard index < originalRow.count else { continue }
            let col = quoteIdentifier(columnName)
            let value = originalRow[index]
            if value.isNull {
                conditions.append("\(col) IS NULL")
            } else {
                parameters.append(value)
                conditions.append("\(col) = ?")
            }
        }

        guard !conditions.isEmpty else { return nil }

        let whereClause = conditions.joined(separator: " AND ")
        let sql = "DELETE FROM \(escapedTable) WHERE \(whereClause) AND ROWNUM = 1"
        return (statement: sql, parameters: parameters)
    }

    // MARK: - Create Table DDL

    func generateCreateTableSQL(definition: PluginCreateTableDefinition) -> String? {
        guard !definition.columns.isEmpty else { return nil }

        let qualifiedTable = damengQualifiedTable(definition.tableName)
        let pkColumns = definition.columns.filter { $0.isPrimaryKey }
        let inlinePK = pkColumns.count == 1
        var parts: [String] = definition.columns.map { damengColumnDefinition($0, inlinePK: inlinePK) }

        if pkColumns.count > 1 {
            let pkCols = pkColumns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
            parts.append("PRIMARY KEY (\(pkCols))")
        }

        for fk in definition.foreignKeys {
            parts.append(damengForeignKeyConstraint(fk))
        }

        var sql = "CREATE TABLE \(qualifiedTable) (\n  " +
            parts.joined(separator: ",\n  ") +
            "\n);"

        var indexStatements: [String] = []
        for index in definition.indexes {
            indexStatements.append(damengIndexDefinition(index, qualifiedTable: qualifiedTable))
        }
        if !indexStatements.isEmpty {
            sql += "\n\n" + indexStatements.joined(separator: ";\n") + ";"
        }

        return sql
    }

    // MARK: - Definition SQL (clipboard copy)

    func generateColumnDefinitionSQL(column: PluginColumnDefinition) -> String? {
        damengColumnDefinition(column, inlinePK: false)
    }

    func generateIndexDefinitionSQL(index: PluginIndexDefinition, tableName: String?) -> String? {
        let qualifiedTable = tableName.map { damengQualifiedTable($0) } ?? "\"table\""
        return damengIndexDefinition(index, qualifiedTable: qualifiedTable)
    }

    func generateForeignKeyDefinitionSQL(fk: PluginForeignKeyDefinition) -> String? {
        damengForeignKeyConstraint(fk)
    }

    // MARK: - ALTER TABLE DDL

    func generateAddColumnSQL(table: String, column: PluginColumnDefinition) -> String? {
        let qt = damengQualifiedTable(table)
        let colDef = damengColumnDefinition(column, inlinePK: false)
        return "ALTER TABLE \(qt) ADD (\(colDef))"
    }

    func generateModifyColumnSQL(table: String, oldColumn: PluginColumnDefinition, newColumn: PluginColumnDefinition) -> String? {
        let qt = damengQualifiedTable(table)
        var stmts: [String] = []

        if oldColumn.name != newColumn.name {
            stmts.append("ALTER TABLE \(qt) RENAME COLUMN \(quoteIdentifier(oldColumn.name)) TO \(quoteIdentifier(newColumn.name))")
        }

        var modifyParts: [String] = []
        let colName = quoteIdentifier(newColumn.name)

        let typeChanged = oldColumn.dataType.uppercased() != newColumn.dataType.uppercased()
        let nullabilityChanged = oldColumn.isNullable != newColumn.isNullable
        let defaultChanged = oldColumn.defaultValue != newColumn.defaultValue

        if typeChanged || nullabilityChanged || defaultChanged {
            var def = "\(colName) \(newColumn.dataType.uppercased())"
            if let defaultValue = newColumn.defaultValue {
                def += " DEFAULT \(damengDefaultValue(defaultValue))"
            } else if defaultChanged {
                def += " DEFAULT NULL"
            }
            if !newColumn.isNullable {
                def += " NOT NULL"
            } else if nullabilityChanged {
                def += " NULL"
            }
            modifyParts.append(def)
        }

        if !modifyParts.isEmpty {
            stmts.append("ALTER TABLE \(qt) MODIFY (\(modifyParts.joined(separator: ", ")))")
        }

        return stmts.isEmpty ? nil : stmts.joined(separator: ";\n")
    }

    func generateDropColumnSQL(table: String, columnName: String) -> String? {
        "ALTER TABLE \(damengQualifiedTable(table)) DROP COLUMN \(quoteIdentifier(columnName))"
    }

    func generateAddIndexSQL(table: String, index: PluginIndexDefinition) -> String? {
        damengIndexDefinition(index, qualifiedTable: damengQualifiedTable(table))
    }

    func generateDropIndexSQL(table: String, indexName: String) -> String? {
        "DROP INDEX \(quoteIdentifier(indexName))"
    }

    func generateAddForeignKeySQL(table: String, fk: PluginForeignKeyDefinition) -> String? {
        "ALTER TABLE \(damengQualifiedTable(table)) ADD \(damengForeignKeyConstraint(fk))"
    }

    func generateDropForeignKeySQL(table: String, constraintName: String) -> String? {
        "ALTER TABLE \(damengQualifiedTable(table)) DROP CONSTRAINT \(quoteIdentifier(constraintName))"
    }

    // MARK: - DDL Helpers

    private func damengQualifiedTable(_ table: String) -> String {
        let schema = _currentSchema ?? config.username.uppercased()
        return "\(quoteIdentifier(schema)).\(quoteIdentifier(table))"
    }

    private func damengColumnDefinition(_ col: PluginColumnDefinition, inlinePK: Bool) -> String {
        var def = "\(quoteIdentifier(col.name)) \(col.dataType.uppercased())"
        if let defaultValue = col.defaultValue {
            def += " DEFAULT \(damengDefaultValue(defaultValue))"
        }
        if !col.isNullable {
            def += " NOT NULL"
        }
        if inlinePK && col.isPrimaryKey {
            def += " PRIMARY KEY"
        }
        return def
    }

    private func damengDefaultValue(_ value: String) -> String {
        let upper = value.uppercased()
        if upper == "NULL" || upper == "SYSDATE" || upper == "SYSTIMESTAMP"
            || value.hasPrefix("'") || Int64(value) != nil || Double(value) != nil {
            return value
        }
        return "'\(escapeStringLiteral(value))'"
    }

    private func damengIndexDefinition(_ index: PluginIndexDefinition, qualifiedTable: String) -> String {
        let cols = index.columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        let unique = index.isUnique ? "UNIQUE " : ""
        return "CREATE \(unique)INDEX \(quoteIdentifier(index.name)) ON \(qualifiedTable) (\(cols))"
    }

    private func damengForeignKeyConstraint(_ fk: PluginForeignKeyDefinition) -> String {
        let cols = fk.columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        let refCols = fk.referencedColumns.map { quoteIdentifier($0) }.joined(separator: ", ")
        let refTable: String
        if let schema = fk.referencedSchema, !schema.isEmpty {
            refTable = "\(quoteIdentifier(schema)).\(quoteIdentifier(fk.referencedTable))"
        } else {
            refTable = quoteIdentifier(fk.referencedTable)
        }
        var def = "CONSTRAINT \(quoteIdentifier(fk.name)) FOREIGN KEY (\(cols)) REFERENCES \(refTable) (\(refCols))"
        if fk.onDelete != "NO ACTION" {
            def += " ON DELETE \(fk.onDelete)"
        }
        return def
    }

    // MARK: - Query Building

    func buildBrowseQuery(
        table: String,
        sortColumns: [(columnIndex: Int, ascending: Bool)],
        columns: [String],
        limit: Int,
        offset: Int
    ) -> String? {
        let quotedTable = damengQualifiedTable(table)
        var query = "SELECT * FROM \(quotedTable)"
        let orderBy = PluginSQLFilter.buildOrderByClause(
            sortColumns: sortColumns, columns: columns, quoteIdentifier: quoteIdentifier
        ) ?? "ORDER BY 1"
        query += " \(orderBy) OFFSET \(offset) ROWS FETCH NEXT \(limit) ROWS ONLY"
        return query
    }

    func buildFilteredQuery(
        table: String,
        filters: [(column: String, op: String, value: String)],
        logicMode: String,
        sortColumns: [(columnIndex: Int, ascending: Bool)],
        columns: [String],
        limit: Int,
        offset: Int
    ) -> String? {
        let quotedTable = damengQualifiedTable(table)
        var query = "SELECT * FROM \(quotedTable)"
        let whereClause = PluginSQLFilter.buildWhereClause(
            filters: filters,
            logicMode: logicMode,
            quoteIdentifier: quoteIdentifier,
            escapeValue: damengEscapeValue,
            regexCondition: { quoted, value in
                "REGEXP_LIKE(\(quoted), '\(value.replacingOccurrences(of: "'", with: "''"))')"
            }
        )
        if !whereClause.isEmpty {
            query += " WHERE \(whereClause)"
        }
        let orderBy = PluginSQLFilter.buildOrderByClause(
            sortColumns: sortColumns, columns: columns, quoteIdentifier: quoteIdentifier
        ) ?? "ORDER BY 1"
        query += " \(orderBy) OFFSET \(offset) ROWS FETCH NEXT \(limit) ROWS ONLY"
        return query
    }

    private func damengEscapeValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.caseInsensitiveCompare("NULL") == .orderedSame { return "NULL" }
        if Int(trimmed) != nil || Double(trimmed) != nil { return trimmed }
        return "'\(trimmed.replacingOccurrences(of: "'", with: "''"))'"
    }

    // MARK: - All Tables Metadata

    func allTablesMetadataSQL(schema: String?) -> String? {
        let s = schema ?? currentSchema ?? config.username.uppercased()
        return """
        SELECT
            OWNER as schema_name,
            TABLE_NAME as name,
            'TABLE' as kind,
            NUM_ROWS as estimated_rows
        FROM ALL_TABLES
        WHERE OWNER = '\(s)'
        ORDER BY TABLE_NAME
        """
    }

    // MARK: - Default Export Query

    func defaultExportQuery(table: String) -> String? {
        "SELECT * FROM \(damengQualifiedTable(table))"
    }

    func defaultExportQuery(table: String, schema: String?) -> String? {
        defaultExportQuery(table: table)
    }

    // MARK: - Identifier Quoting / Escaping

    func quoteIdentifier(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func escapeStringLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''").replacingOccurrences(of: "\0", with: "")
    }

    func castColumnToText(_ column: String) -> String {
        "CAST(\(column) AS VARCHAR)"
    }

    // MARK: - Private Helpers

    private func effectiveSchemaEscaped(_ schema: String?) -> String {
        let raw = schema ?? _currentSchema ?? config.username.uppercased()
        return raw.replacingOccurrences(of: "'", with: "''")
    }

    private static func buildFullType(
        dataType: String,
        dataLength: String?,
        precision: String?,
        scale: String?
    ) -> String {
        let fixedTypes: Set<String> = [
            "date", "time", "timestamp", "datetime", "smalldatetime",
            "clob", "nclob", "blob", "text", "long", "long raw",
            "rowid", "binary", "varbinary", "longvarbinary", "guid"
        ]
        var fullType = dataType
        if fixedTypes.contains(dataType) {
            // No suffix needed
        } else if dataType == "number" || dataType == "numeric" || dataType == "decimal" {
            if let p = precision, let pInt = Int(p) {
                if let s = scale, let sInt = Int(s), sInt > 0 {
                    fullType = "\(dataType)(\(pInt),\(sInt))"
                } else {
                    fullType = "\(dataType)(\(pInt))"
                }
            }
        } else if let len = dataLength, let lenInt = Int(len), lenInt > 0 {
            fullType = "\(dataType)(\(lenInt))"
        }
        return fullType
    }
}
