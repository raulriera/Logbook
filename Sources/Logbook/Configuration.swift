import Foundation

extension LogLevel {
    /// `debug` where the build is a debug build, `info` otherwise.
    public static let buildDefault: LogLevel = {
        #if DEBUG
        .debug
        #else
        .info
        #endif
    }()
}

extension Logbook {
    /// How an installation behaves: what it keeps, where it writes, and what
    /// rewrites entries on the way to the sinks.
    public struct Configuration: Sendable {
        /// Where log files live and how much of them is kept.
        public struct FileOptions: Sendable {
            /// `nil` places them under `Caches/Logs`, which the system may
            /// reclaim when space runs short. A directory the writer creates
            /// itself is excluded from backups; one that already exists is
            /// left as found — but files named `app-N.log` inside it belong
            /// to the writer's rotation, which empties and reaps them.
            public var directory: URL?
            /// Bytes a file may reach before the writer rolls onto the next.
            public var maxFileSize: Int
            /// How many files the rotation cycles through. The oldest is
            /// emptied and written over, which is what bounds total log size.
            /// Shrinking the count strands files beyond it only until the new
            /// cycle outlives them; the newest history is never discarded.
            public var maxFileCount: Int
            /// Lines held in memory before a batch is written.
            public var flushThreshold: Int

            public init(
                directory: URL? = nil,
                maxFileSize: Int = 500_000,
                maxFileCount: Int = 3,
                flushThreshold: Int = 10
            ) {
                self.directory = directory
                self.maxFileSize = maxFileSize
                self.maxFileCount = maxFileCount
                self.flushThreshold = flushThreshold
            }

            /// Three 500 KB files under `Caches/Logs`, batched ten lines at a time.
            public static let `default` = FileOptions()
        }

        /// Entries below this level are discarded before their metadata is built.
        public var minimumLevel: LogLevel
        /// How many entries `Logbook.recentEntries(last:)` can reach back over.
        public var ringBufferCapacity: Int
        /// `nil` keeps logging to memory and the unified log only, writing no files.
        public var files: FileOptions?
        /// Applied in order; the first to return `false` drops the entry.
        public var middleware: [any LogMiddleware]

        public init(
            minimumLevel: LogLevel = .buildDefault,
            ringBufferCapacity: Int = 100,
            files: FileOptions? = .default,
            middleware: [any LogMiddleware] = []
        ) {
            self.minimumLevel = minimumLevel
            self.ringBufferCapacity = ringBufferCapacity
            self.files = files
            self.middleware = middleware
        }
    }
}

extension Logbook.Configuration.FileOptions {
    /// The directory the writer uses — the one seam `Installation` wires
    /// through, so the `Caches/Logs` fallback stays testable without touching
    /// the real location.
    var resolvedDirectory: URL {
        directory ?? Installation.defaultDirectory
    }
}
