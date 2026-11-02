import Foundation
import UserNotifications

/// Schedules local notifications for the user's reminders over the next two weeks.
/// Rescheduled whenever settings change and when the day rolls over, so the window keeps moving
/// (notifications already scheduled fire even while the app isn't running).
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    // Notifications need an app bundle; a bare `swift run` binary has none.
    private lazy var center = UNUserNotificationCenter.current()
    private let available = Bundle.main.bundleIdentifier != nil
    private let daysAhead = 14
    /// macOS keeps at most 64 pending notifications per app.
    private let maxPending = 60
    private var generation = 0

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    struct Planned {
        let reminder: Reminder
        let fire: Date
        let title: String
        let body: String
    }

    /// The upcoming notifications for the given settings (also used by Settings to preview "next alerts").
    static func plan(_ settings: AppSettings, from now: Date = Date(), days: Int = 14) -> [Planned] {
        let active = settings.reminders.filter(\.enabled)
        guard !active.isEmpty else { return [] }
        let cal = ZmanEngine.gregorian(settings.location.timeZone)
        let fmt = ZmanFormat(settings)
        var result: [Planned] = []
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            for r in active where r.applies(on: day, calendar: cal) {
                guard let fire = r.fireDate(on: day, settings: settings), fire > now else { continue }
                var body: String
                switch r.kind {
                case .zman:
                    let at = fmt.time(fire.addingTimeInterval(Double(r.minutesBefore * 60)))
                    let name = settings.zmanim.first { $0.id == r.zmanID }?.name ?? ""
                    body = r.minutesBefore == 0 ? "\(name) – עכשיו (\(at))" : "\(name) בעוד \(r.minutesBefore) דקות (\(at))"
                case .time:
                    body = fmt.time(fire)
                }
                body += " · \(settings.location.displayName)"
                result.append(Planned(reminder: r, fire: fire, title: r.title(in: settings), body: body))
            }
        }
        return result.sorted { $0.fire < $1.fire }
    }

    func reschedule(_ settings: AppSettings) {
        guard available else { return }
        generation += 1
        let gen = generation
        center.removeAllPendingNotificationRequests()
        let planned = Self.plan(settings, days: daysAhead).prefix(maxPending)
        guard !planned.isEmpty else { return }

        Task {
            guard await requestAuthorization(), gen == generation else { return }
            for p in planned {
                let content = UNMutableNotificationContent()
                content.title = p.title
                content.body = p.body
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: p.fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "\(p.reminder.id.uuidString)-\(Int(p.fire.timeIntervalSince1970))"
                guard gen == generation else { return }  // a newer reschedule started
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }
}
