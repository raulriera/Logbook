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
    /// The call site, captured where the `Log` method was invoked. `file` and
    /// `line` end each file-sink line; `function` is carried for middleware
    /// that filters or annotates by origin.
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

    /// Renders the entry as one line for the file sink and `recentEntries`,
    /// which have no metadata of their own and so carry everything — including
    /// the call site the unified log cannot record for us.
    public func formatted() -> String {
        "[\(level.rawValue.uppercased())] \(UTCFormat.line.format(timestamp))Z \(category) \(consoleText) (\(file):\(line))"
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
}
