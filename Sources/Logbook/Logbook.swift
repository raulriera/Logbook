import Foundation
import Synchronization
import os

/// The process-wide logging installation every `Log` records through.
public enum Logbook {
    private static let installed = Mutex<Installation?>(nil)

    /// Installs the pipeline, replacing any previous one.
    ///
    /// A `Log` resolves the installation as it records rather than as it is
    /// built, so one held in a `static let` needs no particular ordering against
    /// this call.
    ///
    /// `subsystem` defaults to the main bundle identifier. Pass the host app's
    /// identifier from an app extension, where that default names the extension.
    public static func bootstrap(
        subsystem: String? = nil,
        configuration: Configuration = Configuration()
    ) {
        let resolved = subsystem ?? Bundle.main.bundleIdentifier ?? "Logbook"
        let installation = Installation(subsystem: resolved, configuration: configuration)
        installed.withLock { $0 = installation }
    }

    /// The most recent entries, oldest first, already formatted.
    ///
    /// Synchronous, so a crash reporter or diagnostic payload can attach recent
    /// history from a context that cannot await.
    public static func recentEntries(last: Int = 100) -> [String] {
        current?.recentEntries(last: last) ?? []
    }

    /// Writes whatever is still buffered and waits for it to land.
    ///
    /// Lines batch before reaching disk, so a process that ends with a batch
    /// part-filled takes those lines with it. Call this as the app leaves the
    /// foreground — the last moment it is reliably alive to write.
    public static func flush() async {
        await current?.flush()
    }

    /// Every log file gathered into one file for sharing.
    ///
    /// Throws `LogExportError.noLogsAvailable` when nothing has been written or
    /// file logging is switched off.
    public static func exportLogs() async throws -> URL {
        guard let current else { throw LogExportError.noLogsAvailable }
        return try await current.exportLogs()
    }

    static var current: Installation? {
        installed.withLock { $0 }
    }

    static func record(
        level: LogLevel,
        message: String,
        category: String,
        metadata: () -> [String: String],
        file: String,
        function: String,
        line: UInt
    ) {
        guard let current else {
            recordBeforeBootstrap(level: level, message: message, category: category)
            return
        }

        current.record(
            level: level,
            message: message,
            category: category,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
    }

    /// Without an installation there is no middleware to scrub values, so only
    /// the message reaches the unified log; metadata is dropped rather than
    /// risked. Launch-time logging stays visible without becoming a leak.
    private static func recordBeforeBootstrap(level: LogLevel, message: String, category: String) {
        guard level >= .buildDefault else { return }

        os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Logbook", category: category)
            .log(level: level.osLogType, "\(message, privacy: .public)")
    }
}
