import SwiftUI

/// When something on screen can change, and no more often: every second only while seconds are shown,
/// otherwise on the minute – plus any moments where something switches mid-minute (a zman or sunset not
/// rounded to the minute).
struct Ticks: TimelineSchedule {
    /// Seconds are shown.
    var everySecond = false
    /// Moments when the display changes even though no seconds are shown.
    var changes: [Date] = []

    func next(after date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let nextSecond = Date(timeIntervalSinceReferenceDate: t.rounded(.down) + 1)
        if everySecond { return nextSecond }
        var next = Date(timeIntervalSinceReferenceDate: (t / 60).rounded(.down) * 60 + 60)
        for c in changes where c > date { next = min(next, c) }
        return next
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        // When the system asks for low frequency (e.g. the view isn't visible), the minute is enough.
        let schedule = mode == .lowFrequency ? Ticks() : self
        var current = startDate
        var first = true
        return AnyIterator {
            if first { first = false; return current }
            current = schedule.next(after: current)
            return current
        }
    }
}
