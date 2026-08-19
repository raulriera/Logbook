import Foundation
import Testing
@testable import Logbook

@Suite("Log entry", .tags(.core))
struct LogEntryTests {
    /// 2026-03-26 10:32:15 UTC.
    private static let timestamp = Date(timeIntervalSince1970: 1_774_521_135)

    @Test func `an entry without metadata formats as level, timestamp, category, message`() {
        let entry = LogEntry(
            timestamp: Self.timestamp,
            level: .info,
            message: "Rate fetched",
            metadata: [:],
            category: "Rates",
            file: "Rates.swift",
            function: "fetch()",
            line: 42
        )

        #expect(entry.formatted() == "[INFO] 2026-03-26 10:32:15Z Rates Rate fetched (Rates.swift:42)")
    }

    @Test func `metadata renders as key=value pairs sorted by key`() {
        let entry = LogEntry(
            timestamp: Self.timestamp,
            level: .warning,
            message: "Stale rate",
            metadata: ["currency": "USD", "age": "120"],
            category: "Rates",
            file: "Rates.swift",
            function: "fetch()",
            line: 42
        )

        #expect(entry.formatted() == "[WARNING] 2026-03-26 10:32:15Z Rates Stale rate age=120 currency=USD (Rates.swift:42)")
    }

    @Test func `console text drops what the unified log records for itself`() {
        let entry = LogEntry(
            timestamp: Self.timestamp,
            level: .warning,
            message: "Stale rate",
            metadata: ["currency": "USD", "age": "120"],
            category: "Rates",
            file: "Rates.swift",
            function: "fetch()",
            line: 42
        )

        // The unified log stamps its own time, level and category on an entry,
        // and a reader shows those beside the message.
        #expect(entry.consoleText == "Stale rate age=120 currency=USD")
    }

    @Test func `console text is the bare message when there is no metadata`() {
        let entry = LogEntry(
            timestamp: Self.timestamp,
            level: .info,
            message: "Rate fetched",
            metadata: [:],
            category: "Rates",
            file: "Rates.swift",
            function: "fetch()",
            line: 42
        )

        #expect(entry.consoleText == "Rate fetched")
    }
}
