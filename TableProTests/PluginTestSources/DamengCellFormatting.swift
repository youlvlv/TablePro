//
//  DamengCellFormatting.swift
//  TableProTests
//
//  Copy of plugin helper for unit testing.
//

import Foundation

enum DamengCellFormatting {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func formatTimestamp(_ date: Date) -> String {
        isoTimestampFormatter.string(from: date)
    }

    static func hexEncodedString(_ data: Data, maxBytes: Int = 4096) -> String {
        let prefix = data.prefix(maxBytes)
        return prefix.map { String(format: "%02x", $0) }.joined()
    }
}
