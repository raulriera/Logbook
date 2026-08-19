import Foundation

/// Gathers every log file into one file for sharing, streaming so a large
/// history never lands in memory at once.
struct LogExporter: Sendable {
    private let writer: FileWriter
    private let buffer: FileWriteBuffer
    /// The last component of the subsystem, so an exported file is recognisable
    /// as belonging to this app rather than to a reverse-DNS string.
    private let name: String

    init(subsystem: String, writer: FileWriter, buffer: FileWriteBuffer) {
        self.writer = writer
        self.buffer = buffer
        self.name = subsystem.split(separator: ".").last.map(String.init) ?? subsystem
    }

    func export() async throws -> URL {
        await buffer.flush()

        let sources = await writer.fileURLs()
        guard !sources.isEmpty else { throw LogExportError.noLogsAvailable }

        // Its own directory, so the name can stay the friendly thing a person
        // sees on the share sheet: the stamp is only good to the second, and two
        // exports that close together would otherwise be one file.
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let destination = home.appending(path: "\(name)-logs-\(Self.stamp.format(Date())).log")
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

    private static let chunkSize = 64 * 1024

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
