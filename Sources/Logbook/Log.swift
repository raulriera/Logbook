/// A named entry point for logging. The name becomes the unified log's
/// category, so `Log("Networking")` is filterable as such in Console.
///
/// Keep `message` a constant and put every variable in `metadata`: middleware
/// only scrubs metadata, so a value interpolated into the message reaches every
/// sink exactly as written.
public struct Log: Sendable {
    private let category: String

    /// Creates a log whose name becomes the unified log's category.
    public init(_ category: String) {
        self.category = category
    }

    /// Records the finest-grained step, for following control flow through a
    /// problem. Off in release builds.
    public func trace(
        _ message: String,
        metadata: @autoclosure () -> [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(.trace, message, metadata, file, function, line)
    }

    /// Records a step worth seeing while working on this code, and not after.
    public func debug(
        _ message: String,
        metadata: @autoclosure () -> [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(.debug, message, metadata, file, function, line)
    }

    /// Records something worth knowing when reading a normal session back.
    public func info(
        _ message: String,
        metadata: @autoclosure () -> [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(.info, message, metadata, file, function, line)
    }

    /// Records something out of the ordinary that is not yet wrong.
    public func notice(
        _ message: String,
        metadata: @autoclosure () -> [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(.notice, message, metadata, file, function, line)
    }

    /// Records something wrong that the app absorbed and carried on from.
    public func warning(
        _ message: String,
        metadata: @autoclosure () -> [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(.warning, message, metadata, file, function, line)
    }

    /// Records a failure the user can feel, whether or not a screen says so.
    public func error(
        _ message: String,
        metadata: @autoclosure () -> [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(.error, message, metadata, file, function, line)
    }

    /// Records a failure the app cannot carry on past.
    public func critical(
        _ message: String,
        metadata: @autoclosure () -> [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(.critical, message, metadata, file, function, line)
    }

    private func emit(
        _ level: LogLevel,
        _ message: String,
        _ metadata: () -> [String: String],
        _ file: String,
        _ function: String,
        _ line: UInt
    ) {
        Logbook.record(
            level: level,
            message: message,
            category: category,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
    }
}
