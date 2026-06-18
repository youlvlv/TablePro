//
//  DamengError.swift
//  TablePro
//
//  Error type for the Dameng ODBC driver plugin.
//

import Foundation
import TableProPluginKit

struct DamengError: Error {
    enum Category: Sendable, Equatable {
        case generic
        case notConnected
        case connectionFailed
        case queryFailed
        case driverManagerNotFound
        case driverNotFound
        case authenticationFailed
    }

    let message: String
    let category: Category
    let sqlState: String?
    let nativeCode: Int?

    init(
        message: String,
        category: Category = .generic,
        sqlState: String? = nil,
        nativeCode: Int? = nil
    ) {
        self.message = message
        self.category = category
        self.sqlState = sqlState
        self.nativeCode = nativeCode
    }

    static let notConnected = DamengError(
        message: String(localized: "Not connected to database"),
        category: .notConnected
    )

    static let connectionFailed = DamengError(
        message: String(localized: "Failed to establish connection"),
        category: .connectionFailed
    )

    static let queryFailed = DamengError(
        message: String(localized: "Query execution failed"),
        category: .queryFailed
    )
}

extension DamengError: PluginDriverError {
    var pluginErrorMessage: String { message }
    var pluginErrorCode: Int? { nativeCode }
    var pluginSqlState: String? { sqlState }
}
