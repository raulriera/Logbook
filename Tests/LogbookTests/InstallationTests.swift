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
    @Test func `an entry below the minimum level is not recorded`() throws {
        let installation = makeInstallation(minimumLevel: .warning)

        installation.record(level: .info, message: "quiet", category: "Test", metadata: { [:] })
        installation.record(level: .error, message: "loud", category: "Test", metadata: { [:] })

        let entries = installation.recentEntries()
        #expect(entries.count == 1)
        #expect(try #require(entries.first).contains("loud"))
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

    @Test func `middleware runs in array order, each seeing the previous rewrite`() throws {
        let installation = makeInstallation(middleware: [Mark(name: "a"), Mark(name: "b")])

        installation.record(level: .info, message: "walk", category: "Test", metadata: { [:] })

        let recorded = try #require(installation.recentEntries().first)
        #expect(recorded.contains("trail=ab"))
    }

    @Test func `a middleware returning false stops the steps after it`() {
        let after = ProcessCounter()
        let installation = makeInstallation(middleware: [DropEverything(), after])

        installation.record(level: .error, message: "gone", category: "Test", metadata: { [:] })

        #expect(installation.recentEntries().isEmpty)
        #expect(after.count == 0)
    }

    @Test func `a middleware rewrite reaches the recorded entry`() throws {
        let installation = makeInstallation(middleware: [SensitiveKeyRedactor()])

        installation.record(level: .info, message: "Signed in", category: "Auth", metadata: {
            ["apiToken": "abc123", "user": "raul"]
        })

        let recorded = try #require(installation.recentEntries().first)
        #expect(recorded.contains("apiToken=[REDACTED]"))
        #expect(recorded.contains("user=raul"))
        #expect(!recorded.contains("abc123"))
    }

    @Test func `recent entries come back newest last and already formatted`() throws {
        let installation = makeInstallation()

        for i in 0..<3 {
            installation.record(level: .info, message: "step-\(i)", category: "Test", metadata: { [:] })
        }

        let entries = installation.recentEntries()
        try #require(entries.count == 3)
        #expect(entries[0].hasPrefix("[INFO] "))
        #expect(entries[2].contains("step-2"))
    }

    @Test func `recent entries can be narrowed to the newest few`() throws {
        let installation = makeInstallation()

        for i in 0..<5 {
            installation.record(level: .info, message: "step-\(i)", category: "Test", metadata: { [:] })
        }

        let entries = installation.recentEntries(last: 2)
        try #require(entries.count == 2)
        #expect(entries[0].contains("step-3"))
        #expect(entries[1].contains("step-4"))
    }

    @Test func `recording with file logging off still reaches the ring buffer`() {
        let installation = makeInstallation(files: nil)

        installation.record(level: .info, message: "memory only", category: "Test", metadata: { [:] })

        #expect(installation.recentEntries().count == 1)
    }
}

@Suite("Log export", .tags(.sinks), .timeLimit(.minutes(1)))
struct LogExportTests {
    @Test func `an export gathers everything written so far`() async throws {
        try await withTemporaryDirectory { directory in
            let installation = makeInstallation(files: .init(directory: directory, flushThreshold: 100))

            installation.record(level: .info, message: "first", category: "Test", metadata: { [:] })
            installation.record(level: .error, message: "second", category: "Test", metadata: { [:] })

            let exported = try await installation.exportLogs()
            defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }

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

    /// One continuous history, oldest first — through a full wraparound, where
    /// the reused `app-0` is the *newest* file and a name-ordered read would
    /// put it first.
    @Test func `an export spans rotated files oldest first`() async throws {
        try await withTemporaryDirectory { directory in
            let installation = makeInstallation(
                files: .init(directory: directory, maxFileSize: 120, maxFileCount: 3, flushThreshold: 1))

            for message in ["first", "second", "third", "fourth"] {
                installation.record(level: .info, message: message, category: "Test", metadata: { [:] })
                await installation.flush()
            }

            let written = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "log" }
            #expect(written.count == 3)

            // Ordering rests on modification dates; state them rather than
            // sleep for the clock to move between writes.
            for url in written {
                let body = try String(contentsOf: url, encoding: .utf8)
                let age: TimeInterval = body.contains("second") ? 1 : body.contains("third") ? 2 : 3
                try setModificationDate(Date(timeIntervalSince1970: 6_000 + age), for: url)
            }

            let exported = try await installation.exportLogs()
            defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }

            // The wraparound truncated the oldest line; the rest read in order.
            let contents = try String(contentsOf: exported, encoding: .utf8)
            #expect(!contents.contains("first"))
            let second = try #require(contents.range(of: "second"))
            let third = try #require(contents.range(of: "third"))
            let fourth = try #require(contents.range(of: "fourth"))
            #expect(second.lowerBound < third.lowerBound)
            #expect(third.lowerBound < fourth.lowerBound)
        }
    }

    /// The stamp in an export's name is only good to the second, so two exports
    /// close together land on one name — and must still be two files.
    @Test func `two exports in the same second are two files`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 10_000, maxFileCount: 3)
            let buffer = FileWriteBuffer(writer: writer, flushThreshold: 100)
            buffer.append("[INFO] shared\n")
            let exporter = LogExporter(
                subsystem: "com.example.Test",
                writer: writer,
                buffer: buffer,
                now: { Date(timeIntervalSince1970: 1_774_521_135) }
            )

            let first = try await exporter.export()
            let second = try await exporter.export()
            defer {
                try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
                try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
            }

            try #require(first.lastPathComponent == second.lastPathComponent)
            #expect(first != second)
            #expect(FileManager.default.fileExists(atPath: first.path))
            #expect(FileManager.default.fileExists(atPath: second.path))
        }
    }

    /// The seam `Installation` wires the writer through: `nil` falls back to
    /// the default, anything else is taken as given.
    @Test func `file options resolve a nil directory to the default`() {
        let custom = URL(fileURLWithPath: "/tmp/custom", isDirectory: true)

        #expect(Logbook.Configuration.FileOptions().resolvedDirectory == Installation.defaultDirectory)
        #expect(Logbook.Configuration.FileOptions(directory: custom).resolvedDirectory == custom)
    }

    /// Only the URL is asserted: the write path is covered by the temporary-
    /// directory tests, and a test must never touch the real `Caches/Logs`.
    @Test func `the default directory is Logs inside the user caches`() throws {
        let caches = try #require(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)

        let directory = Installation.defaultDirectory

        #expect(directory.lastPathComponent == "Logs")
        #expect(directory.deletingLastPathComponent().path == caches.path)
        #expect(directory.hasDirectoryPath)
    }
}
