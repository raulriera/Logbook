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
    private let fileWriter: FileWriter?
    private let fileBuffer: FileWriteBuffer?
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
            self.fileWriter = writer
            self.fileBuffer = FileWriteBuffer(writer: writer, flushThreshold: files.flushThreshold)
        } else {
            self.fileWriter = nil
            self.fileBuffer = nil
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

    /// Concatenates every log file into one file in the temporary directory and
    /// returns it, streaming so a large history never lands in memory at once.
    func exportLogs() async throws -> URL {
        guard let fileBuffer, let fileWriter else { throw LogExportError.noLogsAvailable }

        await fileBuffer.flush()

        let sources = await fileWriter.fileURLs()
        guard !sources.isEmpty else { throw LogExportError.noLogsAvailable }

        // Its own directory, so the name can stay the friendly thing a person
        // sees on the share sheet: the stamp is only good to the second, and two
        // exports that close together would otherwise be one file.
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let destination = home.appending(
            path: "\(exportName)-logs-\(Self.stamp.format(Date())).log")
        FileManager.default.createFile(atPath: destination.path, contents: nil)

        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        for source in sources {
            guard let input = try? FileHandle(forReadingFrom: source) else { continue }
            defer { try? input.close() }

            while let chunk = try input.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
        }

        return destination
    }

    // MARK: - Private

    private static let chunkSize = 64 * 1024

    /// The last component of the subsystem, so an exported file is recognisable
    /// as belonging to this app rather than to a reverse-DNS string.
    private var exportName: String {
        subsystem.split(separator: ".").last.map(String.init) ?? subsystem
    }

    private static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Logs", isDirectory: true)
    }

    private static let stamp = Date.VerbatimFormatStyle(
        format: """
            \(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\
            \(minute: .twoDigits)\(second: .twoDigits)
            """,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )

    private func logger(for category: String) -> os.Logger {
        loggers.withLock { loggers in
            if let existing = loggers[category] { return existing }
            let created = os.Logger(subsystem: subsystem, category: category)
            loggers[category] = created
            return created
        }
    }
}

/// Why a log export could not be produced.
public enum LogExportError: Error, Equatable, LocalizedError {
    /// Nothing has been written to disk, or file logging is switched off.
    case noLogsAvailable

    public var errorDescription: String? {
        switch self {
        case .noLogsAvailable: "There are no logs to share yet."
        }
    }
}
