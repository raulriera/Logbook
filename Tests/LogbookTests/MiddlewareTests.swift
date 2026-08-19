import Testing
@testable import Logbook

@Suite("Sensitive key redactor", .tags(.middleware))
struct SensitiveKeyRedactorTests {
    @Test func `keys containing a sensitive word lose their value`() {
        var entry = LogEntry.stub(metadata: [
            "apiToken": "abc123",
            "ownerKey": "5xJ2k",
            "userEmail": "test@example.com",
            "currency": "USD",
            "amount": "100",
        ])

        #expect(SensitiveKeyRedactor().process(&entry))
        #expect(entry.metadata["apiToken"] == "[REDACTED]")
        #expect(entry.metadata["ownerKey"] == "[REDACTED]")
        #expect(entry.metadata["userEmail"] == "[REDACTED]")
        #expect(entry.metadata["currency"] == "USD")
        #expect(entry.metadata["amount"] == "100")
    }

    @Test func `keyword matching ignores case`() {
        var entry = LogEntry.stub(metadata: ["AccessToken": "xyz", "SECRET_VALUE": "hidden"])

        _ = SensitiveKeyRedactor().process(&entry)

        #expect(entry.metadata["AccessToken"] == "[REDACTED]")
        #expect(entry.metadata["SECRET_VALUE"] == "[REDACTED]")
    }

    @Test func `custom keywords replace the defaults rather than extending them`() {
        var entry = LogEntry.stub(metadata: ["mintAddress": "abc", "apiToken": "xyz"])

        _ = SensitiveKeyRedactor(keywords: ["mint"]).process(&entry)

        #expect(entry.metadata["mintAddress"] == "[REDACTED]")
        #expect(entry.metadata["apiToken"] == "xyz")
    }

    @Test func `an entry without metadata passes through untouched`() {
        var entry = LogEntry.stub(metadata: [:])

        #expect(SensitiveKeyRedactor().process(&entry))
        #expect(entry.metadata.isEmpty)
    }
}

@Suite("Pattern redactor", .tags(.middleware))
struct PatternRedactorTests {
    @Test func `an email keeps its first character and domain`() {
        var entry = LogEntry.stub(metadata: [
            "contact": "user@example.com",
            "shortLocal": "a@b.com",
            "status": "active",
        ])

        _ = PatternRedactor().process(&entry)

        #expect(entry.metadata["contact"] == "u..@example.com")
        #expect(entry.metadata["shortLocal"] == "a..@b.com")
        #expect(entry.metadata["status"] == "active")
    }

    @Test func `a phone number keeps only its last four digits`() {
        var entry = LogEntry.stub(metadata: [
            "withParens": "(415) 555-4321",
            "withCountry": "+1-415-555-1234",
        ])

        _ = PatternRedactor().process(&entry)

        #expect(entry.metadata["withParens"] == "***-***-4321")
        #expect(entry.metadata["withCountry"] == "***-***-1234")
    }

    @Test func `an all digit string survives, so counts and amounts stay readable`() {
        var entry = LogEntry.stub(metadata: ["quarks": "4155551234", "count": "42"])

        _ = PatternRedactor().process(&entry)

        #expect(entry.metadata["quarks"] == "4155551234")
        #expect(entry.metadata["count"] == "42")
    }

    @Test func `a date survives, so it is not mistaken for a phone number`() {
        var entry = LogEntry.stub(metadata: ["day": "2026-03-26"])

        _ = PatternRedactor().process(&entry)

        #expect(entry.metadata["day"] == "2026-03-26")
    }

    @Test func `base58 stays intact unless the rule is enabled`() {
        let address = "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
        var byDefault = LogEntry.stub(metadata: ["mint": address])
        var enabled = LogEntry.stub(metadata: ["mint": address])

        _ = PatternRedactor().process(&byDefault)
        _ = PatternRedactor(rules: [.base58(minLength: 32)]).process(&enabled)

        #expect(byDefault.metadata["mint"] == address)
        #expect(enabled.metadata["mint"] == "5eyk...2N9d")
    }

    @Test func `short words are left alone`() {
        var entry = LogEntry.stub(metadata: ["code": "USD", "name": "Rosemary"])

        _ = PatternRedactor(rules: [.email, .phone, .base58(minLength: 32)]).process(&entry)

        #expect(entry.metadata["code"] == "USD")
        #expect(entry.metadata["name"] == "Rosemary")
    }
}
