import Foundation
import Testing
@testable import Logbook

/// Serialized because these exercise the process-wide installation.
@Suite("Bootstrap", .serialized, .tags(.core))
struct BootstrapTests {
    private func bootstrapInMemory() {
        Logbook.bootstrap(
            subsystem: "com.example.Bootstrap",
            configuration: Logbook.Configuration(minimumLevel: .trace, ringBufferCapacity: 10, files: nil)
        )
    }

    @Test func `a Log built before bootstrap records once bootstrap has run`() {
        let log = Log("Early")
        bootstrapInMemory()

        log.info("after bootstrap")

        #expect(Logbook.recentEntries().contains { $0.contains("after bootstrap") })
    }

    @Test func `the name a Log is built with becomes the entry category`() {
        bootstrapInMemory()

        Log("Networking").warning("Request failed", metadata: ["error": "boom"])

        let recorded = Logbook.recentEntries().last
        #expect(recorded?.contains(" Networking Request failed error=boom") == true)
        #expect(recorded?.hasPrefix("[WARNING] ") == true)
    }

    @Test func `bootstrapping again replaces the previous installation`() {
        bootstrapInMemory()
        Log("First").info("before")

        bootstrapInMemory()

        #expect(Logbook.recentEntries().isEmpty)
    }

    /// A batch only reaches disk once it fills, so without this a launch that
    /// says little writes nothing — and loses it when the process ends.
    @Test func `flushing writes lines that have not filled a batch`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Logbook.bootstrap(
            subsystem: "com.example.Bootstrap",
            configuration: Logbook.Configuration(
                minimumLevel: .trace,
                files: .init(directory: directory, flushThreshold: 100))
        )
        Log("Quiet").error("one lonely line")

        await Logbook.flush()

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let contents = try String(contentsOf: #require(files.first), encoding: .utf8)
        #expect(contents.contains("one lonely line"))
    }
}
