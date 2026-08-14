# Logbook

A small logging package with no dependencies. Every entry fans out to three
sinks — the unified log, an in-memory ring buffer, and a rotating file — after
passing through a middleware chain that can rewrite or drop it.

iOS 18 / macOS 15 and up.

## Using it

Install the pipeline once, as early in launch as you can:

```swift
Logbook.bootstrap(
    subsystem: "com.example.MyApp",
    configuration: .init(middleware: [SensitiveKeyRedactor()])
)
```

Then hold a `Log` wherever you need one. Its name becomes the unified log's
category, so `Log("Networking")` is filterable as such in Console:

```swift
private static let log = Log("Networking")

Self.log.warning("Request failed", metadata: ["status": "\(response.statusCode)"])
```

A `Log` resolves the installation as it records, not as it is built, so one held
in a `static let` needs no particular ordering against `bootstrap`.

## Keep the message constant

**Put every variable in `metadata`, never in the message.** Middleware only sees
`metadata`, so a value interpolated into the message reaches the unified log and
the exported file exactly as written:

```swift
// Leaks the address to every sink
log.info("Resolved owner \(account.address)")

// Redactable, and greppable by key
log.info("Resolved owner", metadata: ["address": "\(account.address)"])
```

Metadata is built lazily, so an entry filtered out by `minimumLevel` costs
nothing beyond the level comparison.

## Redaction

`SensitiveKeyRedactor` matches on the *key* — anything containing `token`,
`key`, `secret`, `password`, `credential`, `seed`, `mnemonic`, `phone`, or
`email` has its value replaced. Pass `keywords:` to substitute your own list.

`PatternRedactor` matches on the *value's shape*: emails become `u..@host.com`
and phone numbers `***-***-1234`. A bare run of digits is left alone so amounts
and IDs stay readable. `.base58(minLength:)` is available but off by default,
since it only makes sense where cryptographic addresses are logged.

Anything else is a `LogMiddleware`:

```swift
struct DropNoisyCategory: LogMiddleware {
    func process(_ entry: inout LogEntry) -> Bool { entry.category != "Chatty" }
}
```

## Getting logs out

`Logbook.recentEntries(last:)` returns formatted lines from the ring buffer
synchronously, so a crash reporter can attach recent history from a context that
cannot await.

`Logbook.exportLogs()` gathers every log file into one file and returns its URL,
ready for a `ShareLink`. It throws `LogExportError.noLogsAvailable` when nothing
has been written or file logging is off.

## Notes

- Timestamps are UTC, so an exported log reads the same wherever it is opened.
- Formatted lines are recorded to the unified log as `.public`. Middleware is the
  single place values are scrubbed; marking them private here would hide them in
  Console while the exported file still carried them in full.
- Before `bootstrap`, only the message reaches the unified log — metadata is
  dropped rather than risked, since no middleware exists yet to scrub it.
- `subsystem` defaults to the main bundle identifier. Pass the host app's
  identifier from an app extension, where that default names the extension.
- Set `files` to `nil` to keep logging in memory and the unified log only. Tests
  should do this, or point `directory` at a temporary one.
