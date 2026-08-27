import Foundation

/// The one place the timestamp invariant lives: UTC with fixed locale and
/// calendar, so a recorded or exported log reads identically on any device
/// setting.
enum UTCFormat {
    /// `2026-03-26 10:32:15` — the head of every recorded line.
    static let line = utc("""
        \(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \
        \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\
        \(minute: .twoDigits):\(second: .twoDigits)
        """)

    /// `2026-03-26-103215` — safe inside a file name.
    static let stamp = utc("""
        \(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\
        \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\
        \(minute: .twoDigits)\(second: .twoDigits)
        """)

    private static func utc(_ format: Date.FormatString) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: format,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .gmt,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}
