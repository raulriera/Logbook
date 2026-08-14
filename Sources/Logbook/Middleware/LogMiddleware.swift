/// Inspects and rewrites entries on their way from a `Log` call to the sinks.
public protocol LogMiddleware: Sendable {
    /// Rewrites the entry in place. Returning `false` drops it before any sink sees it.
    func process(_ entry: inout LogEntry) -> Bool
}
