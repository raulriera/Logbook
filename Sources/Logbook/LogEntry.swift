import Foundation

/// A single log record: what was logged, at what severity, and from where.
///
/// `message` and `metadata` are mutable so middleware can rewrite them in place.
public struct LogEntry: Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public var message: String
    public var metadata: [String: String]
    public let category: String
    /// Where the call was made, captured at the call site.
    public let file: String
    public let function: String
    public let line: UInt

    public init(
        timestamp: Date,
        level: LogLevel,
        message: String,
        metadata: [String: String],
        category: String,
        file: String,
        function: String,
        line: UInt
    ) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.metadata = metadata
        self.category = category
        self.file = file
        self.function = function
        self.line = line
    }

    /// Renders the entry as one line for the file sink, which has no metadata
    /// of its own and so carries everything.
    public func formatted() -> String {
        "[\(level.rawValue.uppercased())] \(Self.timestampStyle.format(timestamp))Z \(category) \(consoleText)"
    }

    /// The message and its metadata, sorted by key so repeated runs of the same
    /// code produce diffable output.
    ///
    /// Without the time, level and category: the unified log records those for
    /// itself, and a reader shows them beside the message.
    public var consoleText: String {
        guard !metadata.isEmpty else { return message }

        let pairs = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(message) \(pairs)"
    }

    /// UTC, so an exported log reads the same wherever it is opened. Fixed
    /// locale and calendar keep the digits stable under any device setting.
    private static let timestampStyle = Date.VerbatimFormatStyle(
        format: """
            \(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\
            \(minute: .twoDigits):\(second: .twoDigits)
            """,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
}
