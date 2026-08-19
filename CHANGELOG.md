# Changelog

## 1.1.0

- Every file-sink and `recentEntries` line now ends with the call site, as
  `(file:line)`. Anything parsing the 1.0.0 line shape must be updated.
- `FileOptions` with a zero `maxFileSize` or `maxFileCount` now fails at
  `bootstrap` with a precondition instead of misbehaving at the first write.
- File logging resumes across launches on the most recently written file of
  its rotation, recreates a purged directory at the next rotation, and
  exports only the writer's own `app-N.log` files. Shrinking `maxFileCount`
  strands files beyond it only until the cycle outlives them (exports may
  read interleaved for that one cycle); the newest history is never
  discarded.
- A log directory the writer itself creates is excluded from backups; a
  pre-existing one is left as found.

## 1.0.0

- Initial release.
