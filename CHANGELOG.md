# Changelog

## 1.1.0

- Every file-sink and `recentEntries` line now ends with the call site, as
  `(file:line)`. Anything parsing the 1.0.0 line shape must be updated.
- `FileOptions` with a zero `maxFileSize` or `maxFileCount` now fails at
  `bootstrap` with a precondition instead of misbehaving at the first write.
- File logging resumes on the most recently written file across launches,
  survives a mid-run purge of its directory, and exports only the writer's
  own `app-N.log` files. Shrinking `maxFileCount` strands files beyond it
  only until the new cycle outlives them; the newest history is never
  discarded.
- A log directory the writer itself creates is excluded from backups; a
  pre-existing one is left as found.

## 1.0.0

- Initial release.
