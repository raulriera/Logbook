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
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount
    }

    func write(_ text: String) {
        guard !disabled, let data = text.data(using: .utf8) else { return }

        if handle == nil { openCurrentFile() }
        if bytesWritten + data.count > maxFileSize { rotate() }

        do {
            try handle?.write(contentsOf: data)
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
        // mark is sticky.
        let created = !manager.fileExists(atPath: directory.path)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
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
