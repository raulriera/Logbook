/// Replaces a metadata value whenever its key names something sensitive.
///
/// Keys are matched case-insensitively, as substrings, so `apiToken` and
/// `AccessToken` both match `token`.
public struct SensitiveKeyRedactor: LogMiddleware {
    /// The words a key is checked against when no others are supplied.
    public static let defaultKeywords = [
        "token", "key", "secret", "password", "credential", "seed", "mnemonic", "phone", "email",
    ]

    private let keywords: [String]

    /// Supplying `keywords` replaces the defaults rather than adding to them.
    public init(keywords: [String] = defaultKeywords) {
        self.keywords = keywords.map { $0.lowercased() }
    }

    public func process(_ entry: inout LogEntry) -> Bool {
        for (key, _) in entry.metadata where isSensitive(key) {
            entry.metadata[key] = "[REDACTED]"
        }
        return true
    }

    private func isSensitive(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return keywords.contains { lowered.contains($0) }
    }
}
