import Foundation

/// Appends text to `app-0.log`, rolling onto the next file once the current one
/// would pass `maxFileSize` and reusing the earliest file once `maxFileCount`
/// exist.
///
/// I/O failure disables file logging for the rest of the process instead of
/// propagating: a log sink must never take down the thing it observes.
actor FileWriter {
    private let directory: URL
    private let maxFileSize: Int
    private let maxFileCount: Int

    private var fileIndex = 0
    private var handle: FileHandle?
    private var bytesWritten = 0
    private var disabled = false
    private var prepared = false

    init(directory: URL, maxFileSize: Int, maxFileCount: Int) {
        precondition(maxFileSize > 0, "A log file needs room for at least one byte")
        precondition(maxFileCount > 0, "Rotation needs at least one file")
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount
    }

    func write(_ text: String) {
        guard !disabled else { return }
        let data = Data(text.utf8)

        // The handle is only nil before the first write of the process; a
        // rotation reopens on its own. So this is where a relaunch resumes on
        // the file the previous run stopped in, rather than putting new lines
        // under the oldest history and truncating the newest at first rotation.
        if handle == nil {
            prepareIfNeeded()
            openCurrentFile()
        }
        guard !disabled else { return }

        if bytesWritten + data.count > maxFileSize { rotate() }
        guard let handle else { return }

        do {
            try handle.write(contentsOf: data)
            bytesWritten += data.count
        } catch {
            disabled = true
        }
    }

    /// The writer's own log files, oldest first — the order an export reads
    /// them in. Only canonical `app-N.log` names count: a shared directory may
    /// hold logs that are not ours to rotate, and not ours to share.
    func fileURLs() -> [URL] {
        prepareIfNeeded()
        return ownFiles().map(\.url)
    }

    // MARK: - Private

    private struct Candidate {
        let index: Int
        let url: URL
        /// `nil` when the date cannot be read. A file that cannot be dated is
        /// never reaped and never resumed onto.
        let modified: Date?
    }

    private static let prefix = "app-"

    private static func fileName(index: Int) -> String { "\(prefix)\(index).log" }

    private func fileURL(index: Int) -> URL {
        directory.appending(path: Self.fileName(index: index))
    }

    /// Canonical own files, oldest first. The round-trip through
    /// `fileName(index:)` rejects imposters like `app-01.log`, which parse to
    /// an index whose real file is a different URL. Equal dates order by
    /// index, so resumption stays deterministic when a restore flattens
    /// timestamps.
    private func ownFiles() -> [Candidate] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        return files
            .compactMap { url -> Candidate? in
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix(Self.prefix),
                      let index = Int(name.dropFirst(Self.prefix.count)), index >= 0,
                      url.lastPathComponent == Self.fileName(index: index)
                else { return nil }

                let modified = try? url
                    .resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                return Candidate(index: index, url: url, modified: modified)
            }
            .sorted {
                let first = $0.modified ?? .distantPast
                let second = $1.modified ?? .distantPast
                return first != second ? first < second : $0.index < $1.index
            }
    }

    /// Once per process, before the first read or write of the directory:
    /// reap what the rotation has already outlived, then adopt the file the
    /// previous run stopped in.
    private func prepareIfNeeded() {
        guard !prepared else { return }
        prepared = true

        let files = reapLapped()
        let inRange = files.filter { (0..<maxFileCount).contains($0.index) }
        fileIndex = inRange.last?.index ?? 0
    }

    /// Deletes files a larger rotation stranded beyond `maxFileCount`, but
    /// only those every in-range file has verifiably outlived: a stranded file
    /// holding the newest history survives until the cycle laps it, and an
    /// unreadable date never justifies a deletion. Returns the survivors.
    @discardableResult
    private func reapLapped() -> [Candidate] {
        let files = ownFiles()
        let oldestInRange = files
            .filter { (0..<maxFileCount).contains($0.index) }
            .compactMap(\.modified)
            .min()
        guard let oldestInRange else { return files }

        var kept: [Candidate] = []
        for candidate in files {
            if candidate.index >= maxFileCount,
               let modified = candidate.modified, modified < oldestInRange {
                try? FileManager.default.removeItem(at: candidate.url)
            } else {
                kept.append(candidate)
            }
        }
        return kept
    }

    /// Re-run before every open and rotation, not once: the system may purge a
    /// Caches directory while the process runs, and logging must survive the
    /// loss.
    private func prepareDirectory() {
        let manager = FileManager.default

        // Logs are regenerable diagnostics, so a directory the writer itself
        // creates is kept out of iCloud and local backups. One the host already
        // owns is left as found: it may hold more than logs, and the exclusion
        // mark is sticky. Creating the leaf with intermediates off makes "ours
        // to stamp" atomic — an existing directory fails the create rather
        // than racing an exists check.
        try? manager.createDirectory(
            at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let created =
            (try? manager.createDirectory(at: directory, withIntermediateDirectories: false)) != nil
        if created {
            var excluded = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
        }
    }

    private func openCurrentFile() {
        let url = fileURL(index: fileIndex)
        let manager = FileManager.default

        prepareDirectory()
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }

        guard let opened = try? FileHandle(forWritingTo: url) else {
            disabled = true
            return
        }
        handle = opened
        bytesWritten = Int((try? opened.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        fileIndex = (fileIndex + 1) % maxFileCount
        bytesWritten = 0

        // Emptying the file we are about to reuse is what bounds total log size;
        // failing to do so would append today's lines onto a stale pass. The
        // directory is re-provisioned first so a mid-run purge costs one
        // rotation, not the rest of the process.
        prepareDirectory()
        do {
            try Data().write(to: fileURL(index: fileIndex), options: .atomic)
        } catch {
            disabled = true
            return
        }

        openCurrentFile()

        // The cycle just moved on, so a stranded file it has now outlived is
        // reaped here too — a long-resident process must not carry one in
        // every export until its next launch.
        reapLapped()
    }
}
