import os

/// Severity of a log entry, ordered from `trace` through `critical`.
public enum LogLevel: String, Sendable, CaseIterable, Comparable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.severity < rhs.severity
    }

    private var severity: Int {
        switch self {
        case .trace: 0
        case .debug: 1
        case .info: 2
        case .notice: 3
        case .warning: 4
        case .error: 5
        case .critical: 6
        }
    }

    /// The unified-log type this level records as. The unified log offers five
    /// types, so `trace`/`debug` and `notice`/`warning` each share one.
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: .debug
        case .info: .info
        case .notice, .warning: .default
        case .error: .error
        case .critical: .fault
        }
    }
}
