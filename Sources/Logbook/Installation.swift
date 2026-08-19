import Foundation
import Synchronization
import os

/// One configured pipeline: the level filter, the middleware chain, and the
/// three sinks an entry fans out to.
final class Installation: Sendable {
    private let subsystem: String
    private let minimumLevel: LogLevel
    private let middleware: [any LogMiddleware]
    private let ringBuffer: RingBuffer
    private let fileBuffer: FileWriteBuffer?
    private let exporter: LogExporter?
    private let loggers = Mutex<[String: os.Logger]>([:])

    init(subsystem: String, configuration: Logbook.Configuration) {
        self.subsystem = subsystem
        self.minimumLevel = configuration.minimumLevel
        self.middleware = configuration.middleware
        self.ringBuffer = RingBuffer(capacity: configuration.ringBufferCapacity)

        if let files = configuration.files {
            let writer = FileWriter(
                directory: files.directory ?? Self.defaultDirectory,
                maxFileSize: files.maxFileSize,
                maxFileCount: files.maxFileCount
            )
            let buffer = FileWriteBuffer(writer: writer, flushThreshold: files.flushThreshold)
            self.fileBuffer = buffer
            self.exporter = LogExporter(subsystem: subsystem, writer: writer, buffer: buffer)
        } else {
            self.fileBuffer = nil
            self.exporter = nil
        }
    }

    func record(
        level: LogLevel,
        message: String,
        category: String,
        metadata: () -> [String: String],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        guard level >= minimumLevel else { return }

        var entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            metadata: metadata(),
            category: category,
            file: file,
            function: function,
            line: line
        )

        for step in middleware {
            guard step.process(&entry) else { return }
        }

        // Middleware is the one place values are scrubbed, so the text is already
        // safe to record publicly. Marking it private here would hide it in
        // Console while the exported file still carried it in full.
        logger(for: category).log(level: level.osLogType, "\(entry.consoleText, privacy: .public)")
        ringBuffer.append(entry)
        fileBuffer?.append(entry.formatted() + "\n")
    }

    /// The most recent entries, oldest first, already formatted.
    func recentEntries(last: Int = 100) -> [String] {
        ringBuffer.entries(last: last).map { $0.formatted() }
    }

    /// Writes whatever is still buffered and waits for it to land.
    func flush() async {
        await fileBuffer?.flush()
    }

    /// Every log file gathered into one shareable file in the temporary directory.
    func exportLogs() async throws -> URL {
        guard let exporter else { throw LogExportError.noLogsAvailable }
        return try await exporter.export()
    }

    // MARK: - Private

    private static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Logs", isDirectory: true)
    }

    private func logger(for category: String) -> os.Logger {
        loggers.withLock { loggers in
            if let existing = loggers[category] { return existing }
            let created = os.Logger(subsystem: subsystem, category: category)
            loggers[category] = created
            return created
        }
    }
}
