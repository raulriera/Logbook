import Synchronization

/// Holds the most recent entries, overwriting the oldest once full.
///
/// Reads are synchronous, so a crash reporter or diagnostic payload can pull
/// recent history from a context that cannot await.
final class RingBuffer: Sendable {
    private struct State {
        var slots: [LogEntry?]
        var writeIndex = 0
        var count = 0
    }

    private let capacity: Int
    private let state: Mutex<State>

    init(capacity: Int) {
        precondition(capacity > 0, "A ring buffer needs room for at least one entry")
        self.capacity = capacity
        self.state = Mutex(State(slots: Array(repeating: nil, count: capacity)))
    }

    func append(_ entry: LogEntry) {
        state.withLock { state in
            state.slots[state.writeIndex] = entry
            state.writeIndex = (state.writeIndex + 1) % capacity
            state.count = min(state.count + 1, capacity)
        }
    }

    /// Entries oldest first, narrowed to the newest `last` of them when given.
    func entries(last: Int? = nil) -> [LogEntry] {
        state.withLock { state in
            let wanted = min(last ?? state.count, state.count)
            guard wanted > 0 else { return [] }

            let oldest = (state.writeIndex - state.count + capacity) % capacity
            return ((state.count - wanted)..<state.count).compactMap {
                state.slots[(oldest + $0) % capacity]
            }
        }
    }
}
