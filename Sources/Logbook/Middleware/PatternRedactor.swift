import Foundation

/// Replaces a metadata value whose *shape* gives it away as personal data,
/// keeping just enough of each to stay useful when reading a log.
///
/// Every rule matches the whole value, because a value is expected to *be* the
/// sensitive thing rather than to contain one.
public struct PatternRedactor: LogMiddleware {
    /// A shape the redactor recognises.
    public enum Rule: Sendable, Equatable {
        /// `user@example.com` becomes `u..@example.com`.
        case email
        /// `+1-415-555-1234` becomes `***-***-1234`.
        case phone
        /// A base58 string of `minLength` or more becomes its first and last four characters.
        case base58(minLength: Int)
    }

    /// The rules applied when none are supplied. `base58` is absent because it
    /// only makes sense where cryptographic addresses are logged.
    public static let defaultRules: [Rule] = [.email, .phone]

    private let rules: [Rule]

    /// Supplying `rules` replaces the defaults rather than adding to them.
    public init(rules: [Rule] = defaultRules) {
        self.rules = rules
    }

    public func process(_ entry: inout LogEntry) -> Bool {
        for (key, value) in entry.metadata {
            if let redacted = redact(value) {
                entry.metadata[key] = redacted
            }
        }
        return true
    }

    /// Returns the redacted value, or `nil` when no rule recognises it.
    private func redact(_ value: String) -> String? {
        for rule in rules {
            switch rule {
            case .email:
                if value.contains("@"), let match = value.wholeMatch(of: Self.emailPattern) {
                    return "\(match.output.1)..\(match.output.3)"
                }

            case .phone:
                // A bare run of digits is far more often an amount, a count, or an
                // ID, so a separator or `+` has to be present before one is read as
                // a phone number. Seven digits is the shortest real number.
                if value.count >= 7,
                   value.contains(where: { !$0.isNumber }),
                   let match = value.wholeMatch(of: Self.phonePattern) {
                    return "***-***-\(match.output.1)"
                }

            case .base58(let minLength):
                if value.count >= minLength,
                   value.unicodeScalars.allSatisfy(Self.base58Characters.contains) {
                    return "\(value.prefix(4))...\(value.suffix(4))"
                }
            }
        }

        return nil
    }

    // Matching never mutates a pattern, so one compiled instance is safe to share
    // across threads; `Regex` simply has no `Sendable` conformance to say so.
    // Remove `nonisolated(unsafe)` when the standard library marks `Regex` `Sendable`.

    /// Captures the first character of the local part, the rest of it, and the domain.
    nonisolated(unsafe) private static let emailPattern =
        #/([a-zA-Z0-9._%+-])([a-zA-Z0-9._%+-]*)(@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/#

    /// Captures the last four digits of `+1234567890`, `(123) 456-7890`, or `123-456-7890`.
    nonisolated(unsafe) private static let phonePattern =
        #/(?:\+\d{1,3}[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)?\d{3}[\s.-]?(\d{4})/#

    /// The Bitcoin base58 alphabet, which omits `0`, `O`, `I`, and `l`.
    private static let base58Characters = CharacterSet(
        charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    )
}
