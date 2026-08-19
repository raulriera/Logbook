import Foundation
import Synchronization
import Testing
@testable import Logbook

private func makeInstallation(
    minimumLevel: LogLevel = .trace,
    middleware: [any LogMiddleware] = [],
    files: Logbook.Configuration.FileOptions? = nil
) -> Installation {
    Installation(
        subsystem: "com.example.Test",
        configuration: Logbook.Configuration(
            minimumLevel: minimumLevel,
            ringBufferCapacity: 10,
            files: files,
            middleware: middleware
        )
    )
}

/// Drops every entry it sees.
private struct DropEverything: LogMiddleware {
    func process(_ entry: inout LogEntry) -> Bool { false }
}

/// Appends its name to the entry's trail, so the order steps ran in is
/// readable off the recorded entry.
private struct Mark: LogMiddleware {
    let name: String
    func process(_ entry: inout LogEntry) -> Bool {
        entry.metadata["trail", default: ""] += name
        return true
    }
}

/// Counts how many times it runs, observable even when the entry is dropped.
private final class ProcessCounter: LogMiddleware {
    private let hits = Mutex(0)
    var count: Int { hits.withLock { $0 } }

    func process(_ entry: inout LogEntry) -> Bool {
        hits.withLock { $0 += 1 }
        return true
    }
}

@Suite("Log pipeline", .tags(.core))
struct InstallationTests {
    @Test func `an entry below the minimum level is not recorded`() {
        let installation = makeInstallation(minimumLevel: .warning)

        installation.record(level: .info, message: "quiet", category: "Test", metadata: { [:] })
        installation.record(level: .error, message: "loud", category: "Test", metadata: { [:] })

        #expect(installation.recentEntries().count == 1)
        #expect(installation.recentEntries()[0].contains("loud"))
    }

    @Test func `metadata is never built for an entry that will be dropped`() {
        let installation = makeInstallation(minimumLevel: .warning)
        let builds = Mutex(0)

        installation.record(level: .info, message: "quiet", category: "Test", metadata: {
            builds.withLock { $0 += 1 }
            return [:]
        })

        #expect(builds.withLock { $0 } == 0)
    }

    @Test func `middleware returning false drops the entry`() {
        let installation = makeInstallation(middleware: [DropEverything()])

        installation.record(level: .error, message: "gone", category: "Test", metadata: { [:] })

        #expect(installation.recentEntries().isEmpty)
    }

    @Test func `middleware runs in array order, each seeing the previous rewrite`() {
        let installation = makeInstallation(middleware: [Mark(name: "a"), Mark(name: "b")])

        installation.record(level: .info, message: "walk", category: "Test", metadata: { [:] })

        #expect(installation.recentEntries()[0].contains("trail=ab"))
    }

    @Test func `a middleware returning false stops the steps after it`() {
        let after = ProcessCounter()
        let installation = makeInstallation(middleware: [DropEverything(), after])

        installation.record(level: .error, message: "gone", category: "Test", metadata: { [:] })

        #expect(installation.recentEntries().isEmpty)
        #expect(after.count == 0)
    }

    @Test func `a middleware rewrite reaches the recorded entry`() {
        let installation = makeInstallation(middleware: [SensitiveKeyRedactor()])

        installation.record(level: .info, message: "Signed in", category: "Auth", metadata: {
            ["apiToken": "abc123", "user": "raul"]
        })

        let recorded = installation.recentEntries()[0]
        #expect(recorded.contains("apiToken=[REDACTED]"))
        #expect(recorded.contains("user=raul"))
        #expect(!recorded.contains("abc123"))
    }

    @Test func `recent entries come back newest last and already formatted`() {
        let installation = makeInstallation()

        for i in 0..<3 {
            installation.record(level: .info, message: "step-\(i)", category: "Test", metadata: { [:] })
        }

        let entries = installation.recentEntries()
        #expect(entries.count == 3)
        #expect(entries[0].hasPrefix("[INFO] "))
        #expect(entries[2].contains("step-2"))
    }

    @Test func `recent entries can be narrowed to the newest few`() {
        let installation = makeInstallation()

        for i in 0..<5 {
            installation.record(level: .info, message: "step-\(i)", category: "Test", metadata: { [:] })
        }

        let entries = installation.recentEntries(last: 2)
        #expect(entries.count == 2)
        #expect(entries[0].contains("step-3"))
        #expect(entries[1].contains("step-4"))
    }

    @Test func `turning file logging off leaves no directory behind`() async throws {
        try await withTemporaryDirectory { directory in
            let unused = directory.appending(path: "Logs", directoryHint: .isDirectory)
            let installation = makeInstallation(files: nil)

            installation.record(level: .info, message: "memory only", category: "Test", metadata: { [:] })

            #expect(!FileManager.default.fileExists(atPath: unused.path))
            #expect(installation.recentEntries().count == 1)
        }
    }
}

@Suite("Log export", .tags(.sinks))
struct LogExportTests {
    @Test func `an export gathers everything written so far`() async throws {
        try await withTemporaryDirectory { directory in
            let installation = makeInstallation(files: .init(directory: directory, flushThreshold: 100))

            installation.record(level: .info, message: "first", category: "Test", metadata: { [:] })
            installation.record(level: .error, message: "second", category: "Test", metadata: { [:] })

            let exported = try await installation.exportLogs()
            defer { try? FileManager.default.removeItem(at: exported) }

            let contents = try String(contentsOf: exported, encoding: .utf8)
            #expect(contents.contains("first"))
            #expect(contents.contains("second"))
            #expect(exported.lastPathComponent.hasPrefix("Test-logs-"))
            #expect(exported.pathExtension == "log")
        }
    }

    @Test func `exporting before anything is logged reports that there is nothing to send`() async throws {
        try await withTemporaryDirectory { directory in
            let installation = makeInstallation(files: .init(directory: directory))

            await #expect(throws: LogExportError.noLogsAvailable) {
                try await installation.exportLogs()
            }
        }
    }

    @Test func `exporting with file logging off reports that there is nothing to send`() async throws {
        let installation = makeInstallation(files: nil)
        installation.record(level: .info, message: "memory only", category: "Test", metadata: { [:] })

        await #expect(throws: LogExportError.noLogsAvailable) {
            try await installation.exportLogs()
        }
    }

    /// One continuous history: an export reads rotated files oldest first.
    @Test func `an export spans rotated files oldest first`() async throws {
        try await withTemporaryDirectory { directory in
            let installation = makeInstallation(
                files: .init(directory: directory, maxFileSize: 120, maxFileCount: 4, flushThreshold: 1))

            for message in ["first", "second", "third"] {
                installation.record(level: .info, message: message, category: "Test", metadata: { [:] })
                await installation.flush()
                // Ordering rests on modification dates; space them out.
                try await Task.sleep(for: .milliseconds(20))
            }

            let written = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "log" }
            #expect(written.count == 3)

            let exported = try await installation.exportLogs()
            defer { try? FileManager.default.removeItem(at: exported) }

            let contents = try String(contentsOf: exported, encoding: .utf8)
            let first = try #require(contents.range(of: "first"))
            let second = try #require(contents.range(of: "second"))
            let third = try #require(contents.range(of: "third"))
            #expect(first.lowerBound < second.lowerBound)
            #expect(second.lowerBound < third.lowerBound)
        }
    }

    /// The stamp in an export's name is only good to the second, so two exports
    /// close together would otherwise land on one path and the first would go.
    @Test func `two exports in the same second are two files`() async throws {
        try await withTemporaryDirectory { directory in
            let installation = makeInstallation(files: .init(directory: directory, flushThreshold: 100))
            installation.record(level: .info, message: "shared", category: "Test", metadata: { [:] })

            let first = try await installation.exportLogs()
            let second = try await installation.exportLogs()
            defer {
                try? FileManager.default.removeItem(at: first)
                try? FileManager.default.removeItem(at: second)
            }

            #expect(first != second)
            #expect(first.lastPathComponent == second.lastPathComponent)
            #expect(FileManager.default.fileExists(atPath: first.path))
            #expect(FileManager.default.fileExists(atPath: second.path))
        }
    }

    /// The default directory is the one every real app gets, and the only part
    /// of the file sink a temporary directory cannot exercise.
    @Test func `the default directory is created and written to`() async throws {
        let caches = try #require(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let logs = caches.appending(path: "Logs", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: logs)
        defer { try? FileManager.default.removeItem(at: logs) }

        let installation = makeInstallation(files: .init(flushThreshold: 100))
        installation.record(level: .error, message: "into the default home", category: "Test", metadata: { [:] })

        let exported = try await installation.exportLogs()
        defer { try? FileManager.default.removeItem(at: exported) }

        #expect(FileManager.default.fileExists(atPath: logs.path))
        let contents = try String(contentsOf: exported, encoding: .utf8)
        #expect(contents.contains("into the default home"))
    }
}
