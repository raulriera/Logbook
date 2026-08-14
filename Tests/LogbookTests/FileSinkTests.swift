import Foundation
import Testing
@testable import Logbook

/// Creates a directory that is removed when `body` returns.
private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}

@Suite("File writer", .tags(.sinks))
struct FileWriterTests {
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
