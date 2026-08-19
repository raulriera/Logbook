import Testing
import os
@testable import Logbook

@Suite("Log level", .tags(.core))
struct LogLevelTests {
    @Test func `levels order by severity`() {
        #expect(LogLevel.trace < LogLevel.debug)
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.notice)
        #expect(LogLevel.notice < LogLevel.warning)
        #expect(LogLevel.warning < LogLevel.error)
        #expect(LogLevel.error < LogLevel.critical)
    }

    @Test func `the seven levels collapse onto five os log types`() {
        #expect(LogLevel.trace.osLogType == .debug)
        #expect(LogLevel.debug.osLogType == .debug)
        #expect(LogLevel.info.osLogType == .info)
        #expect(LogLevel.notice.osLogType == .default)
        #expect(LogLevel.warning.osLogType == .default)
        #expect(LogLevel.error.osLogType == .error)
        #expect(LogLevel.critical.osLogType == .fault)
    }
}
