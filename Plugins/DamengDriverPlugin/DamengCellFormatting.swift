//
//  DamengCellFormatting.swift
//  TablePro
//
//  Helpers for rendering Dameng cell values as strings.
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

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
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

    static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    static func hexEncodedString(_ data: Data, maxBytes: Int = 4096) -> String {
        let prefix = data.prefix(maxBytes)
        return prefix.map { String(format: "%02x", $0) }.joined()
    }

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsers: [DateFormatter] = [
            isoTimestampFormatter,
            timestampFormatter,
            dateFormatter
        ]
        for parser in parsers {
            if let date = parser.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}
