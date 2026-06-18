//
//  DamengCellFormattingTests.swift
//  TableProTests
//

import Foundation
import Testing
@testable import TablePro

@Suite("DamengCellFormatting")
struct DamengCellFormattingTests {
    @Test("formats dates as yyyy-MM-dd")
    func dateFormatting() {
        var components = DateComponents()
        components.year = 2024
        components.month = 12
        components.day = 25
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let date = Calendar.current.date(from: components)!

        #expect(DamengCellFormatting.formatDate(date) == "2024-12-25")
    }

    @Test("formats timestamps as ISO-8601 UTC")
    func timestampFormatting() {
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 16
        components.hour = 13
        components.minute = 30
        components.second = 45
        components.nanosecond = 123_000_000
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let date = Calendar.current.date(from: components)!

        #expect(DamengCellFormatting.formatTimestamp(date) == "2024-06-16T13:30:45.123Z")
    }

    @Test("hex encodes binary data")
    func hexEncoding() {
        let data = Data([0x00, 0x0F, 0xAB, 0xCD])
        #expect(DamengCellFormatting.hexEncodedString(data) == "000fabcd")
    }
}
