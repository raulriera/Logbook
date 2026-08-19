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
            fileIndex = resumeIndex()
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

    /// Existing log files, oldest first, which is the order an export reads them in.
    func fileURLs() -> [URL] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "log" }
            .sorted { modificationDate(of: $0) < modificationDate(of: $1) }
    }

    // MARK: - Private

    private func fileURL(index: Int) -> URL {
        directory.appending(path: "app-\(index).log")
    }

    /// The index of the most recently modified `app-N.log` within the current
    /// rotation, or the first index where none exists. Only the writer's own
    /// names count: a foreign log file in a shared directory must not reset
    /// the cycle onto the oldest history.
    ///
    /// Files a larger rotation left beyond `maxFileCount` are deleted here —
    /// nothing would ever empty them again, and they would ride along in every
    /// export.
    private func resumeIndex() -> Int {
        let candidates = fileURLs().compactMap { file -> (index: Int, url: URL)? in
            let name = file.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("app-"), let index = Int(name.dropFirst(4)) else { return nil }
            return (index, file)
        }

        for candidate in candidates where candidate.index >= maxFileCount {
            try? FileManager.default.removeItem(at: candidate.url)
        }

        return candidates.last { (0..<maxFileCount).contains($0.index) }?.index ?? 0
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func openCurrentFile() {
        let url = fileURL(index: fileIndex)
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
        // failing to do so would append today's lines onto a stale pass.
        do {
            try Data().write(to: fileURL(index: fileIndex), options: .atomic)
        } catch {
            disabled = true
            return
        }

        openCurrentFile()
    }
}
