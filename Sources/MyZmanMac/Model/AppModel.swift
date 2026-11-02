import Foundation
import Combine
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            invalidate()
            WidgetCenter.shared.reloadAllTimelines()
            if settings.appearance != oldValue.appearance { applyAppearance() }
            if settings.reminders != oldValue.reminders || settings.location != oldValue.location
                || settings.zmanim != oldValue.zmanim || settings.useElevation != oldValue.useElevation
                || settings.useUSNO != oldValue.useUSNO {
                ReminderScheduler.shared.reschedule(settings)
            }
            if settings.calendarSync != oldValue.calendarSync || settings.location != oldValue.location {
                syncCalendarIfEnabled()
            }
        }
    }

    /// The day shown in the popover (independent of "today").
    @Published var selectedDate = Date()
    @Published private(set) var menuBarTitle = ""
    @Published private(set) var now = Date()
    /// Set to ask the calendar card to open its "new event" form.
    @Published var newEventRequest = 0

    private var timer: Timer?
    private var todayCache: (key: String, zmanim: [ComputedZman], tomorrow: [ComputedZman])?
    private var lastDayKey = ""

    private init() {
        settings = AppSettings.load()
        settings.save()  // refresh the widget's copy
        tick()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
        ReminderScheduler.shared.reschedule(settings)
        enableLaunchAtLoginOnFirstRun()
        showDisclaimerOnFirstRun()
        DispatchQueue.main.async { self.applyAppearance() }
        // Activate whenever the menu bar popover is shown, so it renders as an active window.
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? NSWindow, w.className.contains("MenuBarExtra"),
                  w.occlusionState.contains(.visible), !NSApp.isActive else { return }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKey()
        }
    }

    func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func showDisclaimerOnFirstRun() {
        let key = "didShowDisclaimer"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundleIdentifier != nil else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let alert = NSAlert()
            alert.messageText = "לתשומת לבך"
            alert.informativeText = Disclaimer.full
            alert.addButton(withTitle: "הבנתי")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// Menu bar apps are expected to start with the Mac; turn that on once (it can be switched off in Settings).
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didOfferLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? LoginItem.set(true)
    }

    var format: ZmanFormat { ZmanFormat(settings) }
    var tz: TimeZone { settings.location.timeZone }

    func dayKey(_ d: Date) -> String {
        let c = ZmanEngine.gregorian(tz).dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    func isToday(_ d: Date) -> Bool { dayKey(d) == dayKey(Date()) }

    private func invalidate() {
        todayCache = nil
        tick()
    }

    private func tick() {
        let date = Date()
        now = date
        let key = dayKey(date)
        if key != lastDayKey {
            // Day rolled over: keep the popover on "today" if it was showing yesterday's today.
            if dayKey(selectedDate) == lastDayKey { selectedDate = date }
            lastDayKey = key
            todayCache = nil
            ReminderScheduler.shared.reschedule(settings)
            syncCalendarIfEnabled()
        }
        let title = buildMenuBarTitle(at: date)
        if title != menuBarTitle { menuBarTitle = title }
    }

    // MARK: - Today's zmanim

    func todayZmanim() -> (today: [ComputedZman], tomorrow: [ComputedZman]) {
        let now = Date()
        let key = dayKey(now)
        if let c = todayCache, c.key == key { return (c.zmanim, c.tomorrow) }
        let tomorrowDate = ZmanEngine.gregorian(tz).date(byAdding: .day, value: 1, to: now)!
        let today = ZmanEngine.zmanim(on: now, settings: settings)
        let tomorrow = ZmanEngine.zmanim(on: tomorrowDate, settings: settings)
        todayCache = (key, today, tomorrow)
        return (today, tomorrow)
    }

    /// The upcoming zman shown in the menu bar.
    func menuBarZman(at date: Date) -> ComputedZman? {
        let (today, tomorrow) = todayZmanim()
        switch settings.menuBar.zmanMode {
        case .none: return nil
        case .pinned:
            guard let id = settings.menuBar.pinnedZman else { return nil }
            if let z = today.first(where: { $0.id == id }), let t = z.time, t > date { return z }
            return tomorrow.first { $0.id == id }
        case .next:
            let upcoming = (today + tomorrow).filter { ($0.time ?? .distantPast) > date }
            return upcoming.min { $0.time! < $1.time! }
        }
    }

    func nextZmanID(at date: Date) -> UUID? {
        todayZmanim().today.filter { ($0.time ?? .distantPast) > date }.min { $0.time! < $1.time! }?.id
    }

    /// The Hebrew day, rolled to tomorrow after sunset if the user wants that.
    func currentHebrewDay(at date: Date) -> Date {
        guard settings.hebrewDateChangesAtSunset,
              let sunset = ZmanEngine.sunset(on: date, settings: settings), date >= sunset else { return date }
        return ZmanEngine.gregorian(tz).date(byAdding: .day, value: 1, to: date)!
    }

    private var infoCache: [String: DayInfo] = [:]

    func dayInfo(_ d: Date) -> DayInfo {
        let key = dayKey(d) + "|\(settings.inIsrael)|\(settings.useModernHolidays)"
        if let i = infoCache[key] { return i }
        if infoCache.count > 3000 { infoCache.removeAll() }
        let i = ZmanEngine.dayInfo(for: d, settings: settings)
        infoCache[key] = i
        return i
    }

    private func buildMenuBarTitle(at date: Date) -> String {
        let mb = settings.menuBar
        var parts: [String] = []
        if mb.showHebrewDate { parts.append(dayInfo(currentHebrewDay(at: date)).hebrewDayMonth) }
        if mb.showGregorianDate { parts.append(format.gregorianDate(date, style: "d/M")) }
        if let z = menuBarZman(at: date), let t = z.time {
            var s: [String] = []
            if mb.showZmanName { s.append(z.item.name) }
            if mb.showZmanTime { s.append(format.time(t)) }
            let left = t.timeIntervalSince(date)
            if mb.showCountdown, mb.countdownWithinMinutes == 0 || left <= Double(mb.countdownWithinMinutes * 60) {
                // LRM keeps the minus sign and digits in order inside RTL text.
                s.append("\u{200E}(\(ZmanFormat.countdown(left, showSeconds: settings.showSeconds)))")
            }
            if !s.isEmpty { parts.append(s.joined(separator: " ")) }
        }
        return parts.joined(separator: " · ")
    }

    func syncCalendarIfEnabled() {
        guard settings.calendarSync.enabled else { return }
        let s = settings
        Task { try? await CalendarSync.shared.sync(s, options: s.calendarSync) }
    }

    // MARK: - Mutations

    func select(location: Location) {
        settings.location = location
        if settings.inIsraelOverride != nil { settings.inIsraelOverride = nil }
    }
}
