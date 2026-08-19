import Synchronization

/// Collects formatted lines and hands them to `FileWriter` in batches, so a
/// burst of logging costs one write rather than one per line.
final class FileWriteBuffer: Sendable {
    private let writer: FileWriter
    private let flushThreshold: Int

    private struct State {
        var lines: [String] = []
        /// Every batch awaits the one before it, so lines reach disk in the
        /// order they were appended rather than in whichever order tasks get
        /// scheduled. Draining and chaining share one critical section: two
        /// racing appends could otherwise chain their batches out of order.
        var pending: Task<Void, Never>?
    }

    private let state = Mutex(State())

    init(writer: FileWriter, flushThreshold: Int) {
        precondition(flushThreshold > 0, "A batch needs at least one line")
        self.writer = writer
        self.flushThreshold = flushThreshold
    }

    func append(_ line: String) {
        state.withLock { state in
            state.lines.append(line)
            guard state.lines.count >= flushThreshold else { return }
            drainAndChain(&state)
        }
    }

    /// Writes whatever is buffered and waits for it, along with any batch still in flight.
    func flush() async {
        let last = state.withLock { state -> Task<Void, Never>? in
            if !state.lines.isEmpty { drainAndChain(&state) }
            return state.pending
        }
        await last?.value
    }

    private func drainAndChain(_ state: inout State) {
        let batch = state.lines.joined()
        state.lines.removeAll(keepingCapacity: true)

        let previous = state.pending
        let writer = self.writer
        // Detached from the caller's isolation: a log call from the main actor
        // must not drag file I/O onto it. Creating the task under the lock is
        // safe — it only schedules, never runs.
        state.pending = Task { @concurrent in
            await previous?.value
            await writer.write(batch)
        }
    }
}
