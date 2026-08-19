import Synchronization

/// Collects formatted lines and hands them to `FileWriter` in batches, so a
/// burst of logging costs one write rather than one per line.
final class FileWriteBuffer: Sendable {
    private let writer: FileWriter
    private let flushThreshold: Int
    private let lines = Mutex<[String]>([])

    /// Every batch awaits the one before it, so lines reach disk in the order
    /// they were appended rather than in whichever order tasks get scheduled.
    private let pending = Mutex<Task<Void, Never>?>(nil)

    init(writer: FileWriter, flushThreshold: Int) {
        precondition(flushThreshold > 0, "A batch needs at least one line")
        self.writer = writer
        self.flushThreshold = flushThreshold
    }

    func append(_ line: String) {
        let batch = lines.withLock { lines -> String? in
            lines.append(line)
            guard lines.count >= flushThreshold else { return nil }
            defer { lines.removeAll(keepingCapacity: true) }
            return lines.joined()
        }

        if let batch { enqueue(batch) }
    }

    /// Writes whatever is buffered and waits for it, along with any batch still in flight.
    func flush() async {
        let remaining = lines.withLock { lines -> String in
            defer { lines.removeAll(keepingCapacity: true) }
            return lines.joined()
        }

        let inFlight: Task<Void, Never>? = pending.withLock { $0 }
        let last = remaining.isEmpty ? inFlight : enqueue(remaining)
        await last?.value
    }

    @discardableResult
    private func enqueue(_ batch: String) -> Task<Void, Never> {
        pending.withLock { pending in
            let previous = pending
            let writer = self.writer
            // Detached from the caller's isolation: a log call from the main actor
            // must not drag file I/O onto it.
            let task = Task { @concurrent in
                await previous?.value
                await writer.write(batch)
            }
            pending = task
            return task
        }
    }
}
