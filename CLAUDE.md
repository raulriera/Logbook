# Logbook — binding rules

A small logging package with no dependencies. That is a feature: adding one
needs a reason strong enough to put in this file.

## Invariants

- **Middleware is the single place values are scrubbed.** Messages are
  constants; every variable travels in `metadata`, which is all middleware
  sees. This is why every sink records text as `.public` — marking it private
  in Console while the exported file carried it in full would be a lie, and
  interpolating a value into a message bypasses scrubbing entirely.
- **A `Log` resolves the installation as it records, not as it is built.**
  A `Log` held in a `static let` must keep working regardless of ordering
  against `bootstrap`. Never cache installation state inside `Log`.
- **Before `bootstrap`, metadata is dropped, not risked.** No middleware
  exists yet to scrub it; only the message reaches the unified log.
- **A sink must never take down the thing it observes.** File I/O failure
  disables file logging for the rest of the process; it never throws into the
  caller and never retries into a crash loop.
- **Timestamps are UTC with fixed locale and calendar**, so an exported log
  reads identically on any device setting.

## Platforms

iOS 18 / macOS 15 is the floor because `Synchronization.Mutex` is the one
lock used everywhere. Do not lower it; raise it only with the API that earns
it named in the diff.

## Testing

Swift Testing only; sentence-case raw-identifier test names; concrete
literals, no tautologies. Tests set `files: nil` or point `directory` at a
temporary one — a test must never write into the real `Caches/Logs`.
`swift test` runs the full suite on the host; it is the gate for every
commit.

## Comments

Comments state what the code cannot: a constraint, an invariant, a
non-obvious why. Present tense, no history, no narratives to a reviewer.

## Releases

Tags are semver (`1.0.0`, no `v` prefix). Consumers pin `from:`; anything
that breaks a public signature or observable behavior is a major.
