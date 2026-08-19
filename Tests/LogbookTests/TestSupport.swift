import Foundation
import Testing
@testable import Logbook

extension Tag {
    @Tag static var core: Self
    @Tag static var middleware: Self
    @Tag static var sinks: Self
}

/// Creates a directory that is removed when `body` returns, so no test ever
/// writes outside its own temporary corner.
func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}

extension LogEntry {
    /// A concrete entry with every field fixed and any of them overridable.
    /// The timestamp renders as `2026-03-26 10:32:15Z`.
    static func stub(
        timestamp: Date = Date(timeIntervalSince1970: 1_774_521_135),
        level: LogLevel = .info,
        message: String = "Test",
        metadata: [String: String] = [:],
        category: String = "Test",
        file: String = "Test.swift",
        function: String = "test()",
        line: UInt = 1
    ) -> LogEntry {
        LogEntry(
            timestamp: timestamp,
            level: level,
            message: message,
            metadata: metadata,
            category: category,
            file: file,
            function: function,
            line: line
        )
    }
}
