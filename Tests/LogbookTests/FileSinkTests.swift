import Foundation
import Testing
@testable import Logbook

@Suite("File writer", .tags(.sinks))
struct FileWriterTests {
    // Exit tests are unavailable on iOS; the preconditions they exercise are not.
    #if os(macOS)
    /// Bad configuration fails at bootstrap, like the other sinks — never as a
    /// modulo trap in the middle of a log write.
    @Test func `a zero file count is rejected when the writer is built`() async {
        await #expect(processExitsWith: .failure) {
            _ = FileWriter(
                directory: FileManager.default.temporaryDirectory,
                maxFileSize: 100,
                maxFileCount: 0
            )
        }
    }

    @Test func `a zero file size is rejected when the writer is built`() async {
        await #expect(processExitsWith: .failure) {
            _ = FileWriter(
                directory: FileManager.default.temporaryDirectory,
                maxFileSize: 0,
                maxFileCount: 3
            )
        }
    }
    #endif

    @Test func `writes land in a single file while they fit`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] one\n")
            await writer.write("[INFO] two\n")

            let files = await writer.fileURLs()
            #expect(files.count == 1)

            let contents = try String(contentsOf: #require(files.first), encoding: .utf8)
            #expect(contents == "[INFO] one\n[INFO] two\n")
        }
    }

    @Test func `exceeding the size limit rotates onto the next file`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 40, maxFileCount: 3)
            for i in 0..<10 { await writer.write("[INFO] message number \(i) padding\n") }

            let files = await writer.fileURLs()
            #expect(files.count > 1)
            #expect(files.count <= 3)
        }
    }

    @Test func `rotation never keeps more files than the limit allows`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 30, maxFileCount: 2)
            for i in 0..<40 { await writer.write("[INFO] line \(i) with padding text\n") }

            #expect(await writer.fileURLs().count == 2)
        }
    }

    /// Generation one of a two-launch fixture: a 30-byte line in `app-0`, an
    /// 80-byte line rotated onto `app-1` (30 + 80 > 100) with room left for
    /// one more short line, and `app-0` stamped older — the state a relaunch
    /// resumes into.
    private func seedResumedPair(in directory: URL) async throws {
        let first = FileWriter(directory: directory, maxFileSize: 100, maxFileCount: 3)
        await first.write(String(repeating: "a", count: 29) + "\n")
        await first.write(String(repeating: "b", count: 79) + "\n")
        try setModificationDate(Date(timeIntervalSince1970: 5_000), for: directory.appending(path: "app-0.log"))
        try setModificationDate(Date(timeIntervalSince1970: 5_001), for: directory.appending(path: "app-1.log"))
    }

    /// A relaunch resumes on the newest file. Restarting at the first instead
    /// would put new lines under the oldest history — and let the first
    /// rotation truncate the newest.
    @Test func `a new writer resumes on the most recently written file`() async throws {
        try await withTemporaryDirectory { directory in
            try await seedResumedPair(in: directory)

            let second = FileWriter(directory: directory, maxFileSize: 100, maxFileCount: 3)
            await second.write("[INFO] two\n")

            let zero = try String(contentsOf: directory.appending(path: "app-0.log"), encoding: .utf8)
            let one = try String(contentsOf: directory.appending(path: "app-1.log"), encoding: .utf8)
            #expect(zero == String(repeating: "a", count: 29) + "\n")
            #expect(one == String(repeating: "b", count: 79) + "\n[INFO] two\n")
        }
    }

    /// Only the writer's own `app-N.log` names count for resumption: a foreign
    /// log file in a shared directory must not reset the cycle onto the oldest
    /// history.
    @Test func `resumption ignores log files that are not the writer's own`() async throws {
        try await withTemporaryDirectory { directory in
            try await seedResumedPair(in: directory)
            let foreign = directory.appending(path: "app-events.log")
            try Data("foreign\n".utf8).write(to: foreign)
            try setModificationDate(Date(timeIntervalSince1970: 5_002), for: foreign)

            let second = FileWriter(directory: directory, maxFileSize: 100, maxFileCount: 3)
            await second.write("[INFO] two\n")

            let zero = try String(contentsOf: directory.appending(path: "app-0.log"), encoding: .utf8)
            let one = try String(contentsOf: directory.appending(path: "app-1.log"), encoding: .utf8)
            #expect(zero == String(repeating: "a", count: 29) + "\n")
            #expect(one == String(repeating: "b", count: 79) + "\n[INFO] two\n")
        }
    }

    /// Shrinking `maxFileCount` must not destroy the newest history: a file
    /// beyond the new bound survives — and keeps riding exports — until every
    /// in-range file has outlived it.
    @Test func `a file beyond the rotation survives while it holds the newest history`() async throws {
        try await withTemporaryDirectory { directory in
            for index in 0..<5 {
                let url = directory.appending(path: "app-\(index).log")
                try Data("old-\(index)\n".utf8).write(to: url)
                try setModificationDate(Date(timeIntervalSince1970: 1_000 + TimeInterval(index)), for: url)
            }

            let writer = FileWriter(directory: directory, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] fresh\n")

            let listed = await writer.fileURLs().map(\.lastPathComponent)
            #expect(listed.contains("app-3.log"))
            #expect(listed.contains("app-4.log"))
        }
    }

    /// Once the rotation has lapped a stranded file, it is reaped — even in a
    /// process that only reads: an export must not carry it forever.
    @Test func `a file the rotation has lapped is reaped before listing`() async throws {
        try await withTemporaryDirectory { directory in
            for index in 0..<3 {
                let url = directory.appending(path: "app-\(index).log")
                try Data("current-\(index)\n".utf8).write(to: url)
                try setModificationDate(Date(timeIntervalSince1970: 2_000 + TimeInterval(index)), for: url)
            }
            let lapped = directory.appending(path: "app-4.log")
            try Data("lapped\n".utf8).write(to: lapped)
            try setModificationDate(Date(timeIntervalSince1970: 1_000), for: lapped)

            let writer = FileWriter(directory: directory, maxFileSize: 1024, maxFileCount: 3)

            #expect(await writer.fileURLs().map(\.lastPathComponent) == ["app-0.log", "app-1.log", "app-2.log"])
            #expect(!FileManager.default.fileExists(atPath: lapped.path))
        }
    }

    /// `fileURLs()` feeds the export; a foreign log file in a shared directory
    /// is not ours to share.
    @Test func `a foreign log file is not listed for export`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] ours\n")
            try Data("not ours\n".utf8).write(to: directory.appending(path: "events.log"))

            #expect(await writer.fileURLs().map(\.lastPathComponent) == ["app-0.log"])
        }
    }

    /// `app-01.log` parses as index 1 but is not the file the writer would
    /// create for index 1; treating it as ours would resume onto the wrong
    /// content.
    @Test func `a non-canonical name is not treated as the writer's own`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] ours\n")
            try Data("imposter\n".utf8).write(to: directory.appending(path: "app-01.log"))

            #expect(await writer.fileURLs().map(\.lastPathComponent) == ["app-0.log"])
        }
    }

    /// The system may purge a Caches directory while the process runs;
    /// rotation recreates it and keeps logging instead of going dark for good.
    @Test func `rotation survives the directory being purged mid-run`() async throws {
        try await withTemporaryDirectory { directory in
            let logs = directory.appending(path: "Logs", directoryHint: .isDirectory)
            let writer = FileWriter(directory: logs, maxFileSize: 40, maxFileCount: 3)
            await writer.write(String(repeating: "x", count: 39) + "\n")

            try FileManager.default.removeItem(at: logs)
            await writer.write("[INFO] after purge\n")

            let contents = try await writer.fileURLs().map { try String(contentsOf: $0, encoding: .utf8) }
            #expect(contents.contains { $0.contains("after purge") })
        }
    }

    /// Two files stamped in the same instant (a backup restore can do this)
    /// must still resume deterministically: the higher index wins the tie.
    @Test func `equal modification dates resume on the higher index`() async throws {
        try await withTemporaryDirectory { directory in
            let tie = Date(timeIntervalSince1970: 3_000)
            for index in 0..<2 {
                let url = directory.appending(path: "app-\(index).log")
                try Data("tied-\(index)\n".utf8).write(to: url)
                try setModificationDate(tie, for: url)
            }

            let writer = FileWriter(directory: directory, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] resumed\n")

            let one = try String(contentsOf: directory.appending(path: "app-1.log"), encoding: .utf8)
            #expect(one == "tied-1\n[INFO] resumed\n")
        }
    }

    /// Resuming a file that is already at the limit must roll before writing,
    /// exactly as if the process had never restarted.
    @Test func `a resumed file that is already full rotates before the next line`() async throws {
        try await withTemporaryDirectory { directory in
            let first = FileWriter(directory: directory, maxFileSize: 40, maxFileCount: 3)
            await first.write(String(repeating: "x", count: 39) + "\n")

            let second = FileWriter(directory: directory, maxFileSize: 40, maxFileCount: 3)
            await second.write("[INFO] next\n")

            let zero = try String(contentsOf: directory.appending(path: "app-0.log"), encoding: .utf8)
            let one = try String(contentsOf: directory.appending(path: "app-1.log"), encoding: .utf8)
            #expect(zero == String(repeating: "x", count: 39) + "\n")
            #expect(one == "[INFO] next\n")
        }
    }

    /// The invariant behind every sink: I/O failure disables file logging for
    /// the rest of the process instead of reaching the caller. The blocker is
    /// removed before the second write, so a writer that merely retried —
    /// rather than staying disabled — would create the directory and fail this.
    @Test func `a writer that cannot create its directory stays quiet for the rest of the process`() async throws {
        try await withTemporaryDirectory { directory in
            let blocked = directory.appending(path: "Logs", directoryHint: .isDirectory)
            try Data().write(to: blocked)

            let writer = FileWriter(directory: blocked, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] lost\n")

            try FileManager.default.removeItem(at: blocked)
            await writer.write("[INFO] still lost\n")

            #expect(!FileManager.default.fileExists(atPath: blocked.path))
            #expect(await writer.fileURLs().isEmpty)
        }
    }

    /// Logs are regenerable diagnostics: a directory the writer itself creates
    /// never rides into iCloud or local backups.
    @Test func `the directory the writer creates is excluded from backups`() async throws {
        try await withTemporaryDirectory { directory in
            let logs = directory.appending(path: "Logs", directoryHint: .isDirectory)
            let writer = FileWriter(directory: logs, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] line\n")

            #expect(backupExclusion(of: logs) == true)
        }
    }

    /// A directory the host already owns is left as found: stamping it would
    /// silently pull the host's co-located files out of backups too.
    @Test func `a pre-existing directory is not marked excluded from backups`() async throws {
        try await withTemporaryDirectory { directory in
            let owned = directory.appending(path: "Logs", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)

            let writer = FileWriter(directory: owned, maxFileSize: 1024, maxFileCount: 3)
            await writer.write("[INFO] line\n")

            #expect(backupExclusion(of: owned) != true)
        }
    }

    @Test func `a rotated file is truncated rather than appended to`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 30, maxFileCount: 2)
            for i in 0..<12 { await writer.write("[INFO] line \(i) padding here\n") }

            let contents = try await writer.fileURLs().map {
                try String(contentsOf: $0, encoding: .utf8)
            }
            // Each file holds at most one line's worth beyond the limit; stale
            // content from an earlier pass would push it well past that.
            #expect(contents.allSatisfy { $0.count <= 60 })
        }
    }
}

@Suite("File write buffer", .tags(.sinks))
struct FileWriteBufferTests {
    @Test func `lines below the threshold reach disk only once flushed`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 10_000, maxFileCount: 3)
            let buffer = FileWriteBuffer(writer: writer, flushThreshold: 10)

            buffer.append("one\n")
            buffer.append("two\n")
            #expect(await writer.fileURLs().isEmpty)

            await buffer.flush()
            let files = await writer.fileURLs()
            let contents = try String(contentsOf: #require(files.first), encoding: .utf8)
            #expect(contents == "one\ntwo\n")
        }
    }

    /// No flush is ever called here: the write must come from the threshold
    /// alone. The poll is bounded because the batch lands on its own schedule.
    @Test func `a full batch reaches disk without any flush call`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 10_000, maxFileCount: 3)
            let buffer = FileWriteBuffer(writer: writer, flushThreshold: 2)

            buffer.append("one\n")
            buffer.append("two\n")

            var attempts = 0
            while await writer.fileURLs().isEmpty, attempts < 100 {
                attempts += 1
                try await Task.sleep(for: .milliseconds(10))
            }

            let files = await writer.fileURLs()
            let contents = try String(contentsOf: #require(files.first), encoding: .utf8)
            #expect(contents == "one\ntwo\n")
        }
    }

    /// A flush with nothing newly buffered still waits for the batch the
    /// threshold already sent on its way.
    @Test func `flush waits for a batch already in flight`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 10_000, maxFileCount: 3)
            let buffer = FileWriteBuffer(writer: writer, flushThreshold: 2)

            buffer.append("one\n")
            buffer.append("two\n")

            await buffer.flush()

            let files = await writer.fileURLs()
            let contents = try String(contentsOf: #require(files.first), encoding: .utf8)
            #expect(contents == "one\ntwo\n")
        }
    }

    @Test func `batches land in the order they were appended`() async throws {
        try await withTemporaryDirectory { directory in
            let writer = FileWriter(directory: directory, maxFileSize: 10_000, maxFileCount: 3)
            let buffer = FileWriteBuffer(writer: writer, flushThreshold: 2)

            for i in 0..<7 { buffer.append("line-\(i)\n") }
            await buffer.flush()

            let files = await writer.fileURLs()
            let contents = try String(contentsOf: #require(files.first), encoding: .utf8)
            #expect(contents == (0..<7).map { "line-\($0)\n" }.joined())
        }
    }
}
