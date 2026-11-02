import Foundation
import UserNotifications

/// Schedules local notifications for the user's zman reminders, a week ahead.
/// Rescheduled whenever settings change and when the day rolls over.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    // Notifications need an app bundle; a bare `swift run` binary has none.
    private lazy var center = UNUserNotificationCenter.current()
    private let available = Bundle.main.bundleIdentifier != nil
    private let daysAhead = 7

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func reschedule(_ settings: AppSettings) {
        guard available else { return }
        let active = settings.reminders.filter(\.enabled)
        center.removeAllPendingNotificationRequests()
        guard !active.isEmpty else { return }

        Task {
            guard await requestAuthorization() else { return }
            let cal = ZmanEngine.gregorian(settings.location.timeZone)
            let now = Date()
            for offset in 0..<daysAhead {
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let zmanim = ZmanEngine.zmanim(on: day, settings: settings)
                for r in active {
                    guard let z = zmanim.first(where: { $0.id == r.zmanID }), let t = z.time else { continue }
                    let fire = t.addingTimeInterval(-Double(r.minutesBefore * 60))
                    guard fire > now else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = z.item.name
                    let at = ZmanFormat(settings).time(t)
                    content.body = r.minutesBefore == 0
                        ? "הגיע הזמן (\(at)) – \(settings.location.displayName)"
                        : "בעוד \(r.minutesBefore) דקות (\(at)) – \(settings.location.displayName)"
                    content.sound = .default

                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let id = "\(r.id.uuidString)-\(offset)"
                    try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
    }
}
