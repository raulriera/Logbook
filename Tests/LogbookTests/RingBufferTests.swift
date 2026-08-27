import Testing
@testable import Logbook

@Suite("Ring buffer", .tags(.sinks))
struct RingBufferTests {
    @Test func `entries come back oldest first`() {
        let buffer = RingBuffer(capacity: 5)
        for i in 0..<5 { buffer.append(.stub(message: "msg-\(i)")) }

        #expect(buffer.entries().map(\.message) == ["msg-0", "msg-1", "msg-2", "msg-3", "msg-4"])
    }

    @Test func `appending past capacity evicts the oldest entries`() {
        let buffer = RingBuffer(capacity: 3)
        for i in 0..<5 { buffer.append(.stub(message: "msg-\(i)")) }

        #expect(buffer.entries().map(\.message) == ["msg-2", "msg-3", "msg-4"])
    }

    @Test func `asking for the last few returns the newest of them`() {
        let buffer = RingBuffer(capacity: 10)
        for i in 0..<10 { buffer.append(.stub(message: "msg-\(i)")) }

        #expect(buffer.entries(last: 3).map(\.message) == ["msg-7", "msg-8", "msg-9"])
    }

    @Test func `asking for more than exists returns everything held`() {
        let buffer = RingBuffer(capacity: 5)
        for i in 0..<3 { buffer.append(.stub(message: "msg-\(i)")) }

        #expect(buffer.entries(last: 10).map(\.message) == ["msg-0", "msg-1", "msg-2"])
    }

    @Test func `an untouched buffer holds nothing`() {
        #expect(RingBuffer(capacity: 5).entries().isEmpty)
    }
}
