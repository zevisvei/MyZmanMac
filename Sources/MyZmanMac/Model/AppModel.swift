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
            if settings.zmanim != oldValue.zmanim, pruneOrphans() { return }  // didSet runs again with the pruned settings
            settings.save()
            if settings.menuBar.showInMenuBar != UserDefaults.standard.bool(forKey: Self.showInMenuBarKey) {
                UserDefaults.standard.set(settings.menuBar.showInMenuBar, forKey: Self.showInMenuBarKey)
            }
            invalidate()
            WidgetCenter.shared.reloadAllTimelines()
            if settings.appearance != oldValue.appearance { applyAppearance() }
            // Anything that moves a zman's time (or how it's rounded) moves reminders and synced events.
            let timesChanged = settings.location != oldValue.location || settings.zmanim != oldValue.zmanim
                || settings.useElevation != oldValue.useElevation || settings.useUSNO != oldValue.useUSNO
                || settings.inIsrael != oldValue.inIsrael || settings.rounding != oldValue.rounding
                || settings.showSeconds != oldValue.showSeconds || settings.candleLightingOffset != oldValue.candleLightingOffset
                || settings.havdalahDefID != oldValue.havdalahDefID || settings.fastStartDefID != oldValue.fastStartDefID
                || settings.fastEndDefID != oldValue.fastEndDefID
            if settings.reminders != oldValue.reminders || timesChanged {
                ReminderScheduler.shared.reschedule(settings)
            }
            let old = oldValue.calendarSync, new = settings.calendarSync
            if old.enabled && (!new.enabled || old.targetCalendarID != new.targetCalendarID) {
                // Don't leave stale synced zmanim in a calendar we no longer write to.
                Task { try? await CalendarSync.shared.removeSynced(options: old) }
            }
            if new != old || timesChanged {
                syncCalendarIfEnabled()
            }
        }
    }

    /// The day shown in the popover (independent of "today"). Always kept at noon in the
    /// location's time zone, so it stays the same calendar day whatever zone it's read in.
    @Published var selectedDate = Date() {
        didSet {
            let n = ZmanEngine.noon(of: selectedDate, in: tz)
            if n != selectedDate { selectedDate = n }
        }
    }
    @Published private(set) var menuBarTitle = ""
    /// Not published: views that need a ticking clock use TimelineView, so the popover
    /// doesn't re-render every second.
    private(set) var now = Date()
    /// Set to ask the calendar card to open its "new event" form.
    @Published var newEventRequest = 0

    private var timer: Timer?
    private var todayCache: (key: String, zmanim: [ComputedZman], tomorrow: [ComputedZman])?
    private var lastDayKey = ""

    /// Mirrors settings.menuBar.showInMenuBar for the MenuBarExtra (see MyZmanApp).
    static let showInMenuBarKey = "showInMenuBar"

    private init() {
        settings = AppSettings.load()
        UserDefaults.standard.set(settings.menuBar.showInMenuBar, forKey: Self.showInMenuBarKey)
        // ⌘-dragging the item out of the menu bar clears the stored flag: reflect that in the settings.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let stored = UserDefaults.standard.object(forKey: Self.showInMenuBarKey) as? Bool ?? true
                if stored != self.settings.menuBar.showInMenuBar { self.settings.menuBar.showInMenuBar = stored }
            }
        }
        settings.save()  // refresh the widget's copy
        tick()
        // After sleep or a clock change, a pending tick may be far off: catch up now.
        for name in [NSWorkspace.didWakeNotification, Notification.Name.NSSystemClockDidChange] {
            let center = name == NSWorkspace.didWakeNotification ? NSWorkspace.shared.notificationCenter : .default
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.infoCache.removeAll()
                self.invalidate()
                ReminderScheduler.shared.reschedule(self.settings)
            }
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
        let key = tz.identifier + "|" + dayKey(date)
        if key != lastDayKey {
            // Day rolled over: keep the popover on "today" if it was showing yesterday's today.
            // (A location change alters the key too, but isn't a rollover.)
            let sameZone = lastDayKey.hasPrefix(tz.identifier + "|")
            if sameZone, tz.identifier + "|" + dayKey(selectedDate) == lastDayKey { selectedDate = date }
            lastDayKey = key
            todayCache = nil
            ReminderScheduler.shared.reschedule(settings)
            syncCalendarIfEnabled()
        }
        let title = buildMenuBarTitle(at: date)
        if title != menuBarTitle { menuBarTitle = title }
        scheduleNextTick(after: date)
    }

    /// The next moment the menu bar title (or the day) can change – not a fixed 1-second timer.
    private func scheduleNextTick(after date: Date) {
        let mb = settings.menuBar
        var ticks = Ticks()
        if mb.showInMenuBar, let t = menuBarZman(at: date)?.time {
            ticks.changes.append(t)    // the next zman takes over
            if mb.showCountdown {
                let within = Double(mb.countdownWithinMinutes * 60)
                if within > 0 { ticks.changes.append(t.addingTimeInterval(-within)) }  // the countdown appears
                if within == 0 || t.timeIntervalSince(date) <= within {
                    if settings.showSeconds { ticks.everySecond = true } else { ticks.countdowns = [t] }
                }
            }
        }
        if mb.showHebrewDate, settings.hebrewDateChangesAtSunset, let sunset = ZmanEngine.sunset(on: date, settings: settings) {
            ticks.changes.append(sunset)
        }
        // A hair after the boundary, so the new value is already current when we look.
        let fire = ticks.next(after: date).addingTimeInterval(0.02)
        timer?.invalidate()
        let t = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = ticks.everySecond || fire.timeIntervalSince(date) < 2 ? 0.05 : 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        let key = dayKey(d) + "|\(settings.location.id)|\(settings.inIsrael)|\(settings.useModernHolidays)"
        if let i = infoCache[key] { return i }
        if infoCache.count > 3000 { infoCache.removeAll() }
        let i = ZmanEngine.dayInfo(for: d, settings: settings)
        infoCache[key] = i
        return i
    }

    private var specialCache: [String: [SpecialTime]] = [:]

    func specialTimes(_ d: Date) -> [SpecialTime] {
        let key = dayKey(d) + "|\(settings.location.id)|\(settings.inIsrael)|\(settings.useElevation)|\(settings.useUSNO)"
            + "|\(settings.candleLightingOffset)|\(settings.havdalahDefID)|\(settings.fastStartDefID)|\(settings.fastEndDefID)|\(settings.use24h)|\(settings.showSeconds)|\(settings.rounding)"
        if let t = specialCache[key] { return t }
        if specialCache.count > 500 { specialCache.removeAll() }
        let t = SpecialTimes.on(d, settings: settings)
        specialCache[key] = t
        return t
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

    private var syncWork: DispatchWorkItem?

    /// Debounced, so flipping several options in a row rewrites the calendar once.
    func syncCalendarIfEnabled() {
        syncWork?.cancel()
        guard settings.calendarSync.enabled else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let s = self.settings
            Task { try? await CalendarSync.shared.sync(s, options: s.calendarSync) }
        }
        syncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Drops reminders / pins / calendar choices that point at zmanim no longer in the list.
    /// Returns true if it changed the settings.
    private func pruneOrphans() -> Bool {
        let ids = Set(settings.zmanim.map(\.id))
        var s = settings
        s.reminders.removeAll { $0.kind == .zman && !($0.zmanID.map(ids.contains) ?? false) }
        if let p = s.menuBar.pinnedZman, !ids.contains(p) { s.menuBar.pinnedZman = nil }
        s.calendarSync.zmanIDs.removeAll { !ids.contains($0) }
        guard s != settings else { return false }
        settings = s
        return true
    }

    /// Restores MyZman's default list, keeping the identity of zmanim that are already in it
    /// (so their reminders and pins survive).
    func restoreDefaultZmanim() {
        let existing = Dictionary(settings.zmanim.map { ($0.defID, $0.id) }, uniquingKeysWith: { a, _ in a })
        settings.zmanim = ZmanCatalog.defaults.map { d in
            var item = d
            if let id = existing[d.defID] { item.id = id }
            return item
        }
    }

    // MARK: - Mutations

    func select(location: Location) {
        // Keep the same calendar day selected in the new location.
        let c = ZmanEngine.gregorian(tz).dateComponents([.year, .month, .day], from: selectedDate)
        settings.location = location
        if settings.inIsraelOverride != nil { settings.inIsraelOverride = nil }
        if let d = ZmanEngine.gregorian(tz).date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) {
            selectedDate = d
        }
    }
}
