import AppKit
import EventKit
import UniformTypeIdentifiers

/// Two-way integration with the macOS Calendar (and every account connected to it: iCloud, Google, Exchange…).
/// Writes: synced zmanim/Hebrew dates and events the user adds from the app.
/// Reads: the user's events, shown next to the zmanim.
@MainActor
final class CalendarSync: ObservableObject {
    static let shared = CalendarSync()
    static let calendarTitle = "זמנים"
    /// Appended to the notes of synced events. Only events carrying it are ever deleted by a re-sync,
    /// so writing into a shared calendar (e.g. a Google calendar) never touches anything else.
    static let syncMarker = "‏· נוצר ע״י MyZman"
    /// Also set as the event's URL: the notes can be edited (by the user, or by Exchange appending text),
    /// the URL survives that.
    static let syncURL = URL(string: "myzman://sync")!

    /// Whether the sync wrote this event (and so may delete it).
    static func isSynced(_ e: EKEvent) -> Bool {
        e.url?.absoluteString.hasPrefix(syncURL.absoluteString) == true || e.notes?.contains(syncMarker) == true
    }

    let store = EKEventStore()
    private let calendarIDKey = "calendarSync.calendarID"
    /// True only if the app itself created the dedicated calendar (never for an adopted one).
    private let createdKey = "calendarSync.createdByApp"

    /// Bumped whenever the calendar database changes, so views reload events.
    @Published private(set) var version = 0
    @Published private(set) var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.version += 1 }
        }
    }

    enum Failure: LocalizedError {
        case denied, noSource, calendarGone, eventGone
        var errorDescription: String? {
            switch self {
            case .denied: "אין הרשאת גישה ללוח השנה. ניתן לאפשר בהגדרות המערכת ← פרטיות ואבטחה ← לוחות שנה."
            case .noSource: "לא נמצא חשבון לוח שנה מתאים (iCloud או 'במחשב')."
            case .calendarGone: "הלוח שנבחר לא נמצא – בחרו לוח אחר בהגדרות."
            case .eventGone: "האירוע לא נמצא – ייתכן שכבר נמחק."
            }
        }
    }

    @discardableResult
    func requestAccess() async throws -> Bool {
        let ok = try await store.requestFullAccessToEvents()
        // Only on a change: each bump redraws (and re-queries) every view that shows calendar events.
        if ok != hasAccess {
            hasAccess = ok
            if ok { store.refreshSourcesIfNecessary(); version += 1 }
        }
        return ok
    }

    // MARK: - Calendars

    struct CalendarInfo: Identifiable, Hashable {
        let id: String
        let title: String
        let account: String
        let color: NSColor
    }

    private func info(_ c: EKCalendar) -> CalendarInfo {
        CalendarInfo(id: c.calendarIdentifier, title: c.title, account: c.source.title,
                     color: c.color ?? .systemGray)
    }

    /// Every calendar the user has, grouped later by account (iCloud, Google, …).
    func allCalendars() -> [CalendarInfo] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).map(info).sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func writableCalendars() -> [CalendarInfo] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).filter(\.allowsContentModifications).map(info)
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    private func dedicatedCalendar() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarIDKey) {
            if let cal = store.calendar(withIdentifier: id) { return cal }
            // The calendar we used is gone: forget it, so a same-named calendar adopted below is never
            // taken for one the app created (and deleted by removeSynced).
            UserDefaults.standard.removeObject(forKey: calendarIDKey)
            UserDefaults.standard.removeObject(forKey: createdKey)
        }
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: calendarIDKey)
            return existing
        }
        let sources = store.sources
        // Google/Exchange accounts don't allow creating calendars from the Mac; iCloud or local do.
        guard let source = sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") })
                ?? sources.first(where: { $0.sourceType == .local })
                ?? store.defaultCalendarForNewEvents?.source else { throw Failure.noSource }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = Self.calendarTitle
        cal.source = source
        cal.cgColor = NSColor.systemOrange.cgColor
        try store.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: calendarIDKey)
        UserDefaults.standard.set(true, forKey: createdKey)
        return cal
    }

    /// EventKit treats all-day dates in the Mac's own zone; convert a day in the location's zone to that.
    static func allDayDate(_ day: Date, in tz: TimeZone) -> Date {
        let c = ZmanEngine.gregorian(tz).dateComponents([.year, .month, .day], from: day)
        return Calendar.current.date(from: c) ?? day
    }

    private func target(_ options: CalendarSyncOptions) throws -> EKCalendar {
        guard let id = options.targetCalendarID else { return try dedicatedCalendar() }
        guard let cal = store.calendar(withIdentifier: id) else { throw Failure.calendarGone }
        return cal
    }

    // MARK: - Write: sync

    /// Replaces previously synced events in the target calendar. Returns the number of events written.
    @discardableResult
    func sync(_ settings: AppSettings, options: CalendarSyncOptions, onlyIfEnabled: Bool = false) async throws -> Int {
        guard try await requestAccess() else { throw Failure.denied }
        // An automatic sync that waited for access while sync was turned off (and its events removed) must not write.
        if onlyIfEnabled, !AppModel.shared.settings.calendarSync.enabled { return 0 }
        let cal = try target(options)
        let tz = settings.location.timeZone
        let tzCal = ZmanEngine.gregorian(tz)
        let start = tzCal.startOfDay(for: Date())
        let to = tzCal.date(byAdding: .day, value: 400, to: start)!

        // Each event carries a key of everything it shows (in its URL): only what changed is removed and added,
        // instead of rewriting every event each time (slow, and churn for iCloud / Google). Past days are left
        // as they were written.
        var wanted: [String: Item] = [:]
        // Up to a year of days: calculated off the main thread.
        let items = await Task.detached { Self.events(settings, options: options) }.value
        for item in items { wanted[Self.key(item, tz: tz, alert: options.alertMinutes)] = item }
        var kept = Set<String>()
        var added = 0
        do {
            for e in store.events(matching: store.predicateForEvents(withStart: start, end: to, calendars: [cal]))
            where Self.isSynced(e) {
                // Older events (no key) and duplicates go; current ones stay.
                if let key = Self.key(of: e), wanted[key] != nil, kept.insert(key).inserted { continue }
                try store.remove(e, span: .thisEvent, commit: false)
            }
            for (key, item) in wanted where !kept.contains(key) {
                let e = EKEvent(eventStore: store)
                e.calendar = cal
                e.title = item.title
                e.notes = (item.notes.map { $0 + "\n" } ?? "") + Self.syncMarker
                e.url = URL(string: Self.syncURL.absoluteString + "/" + key)
                e.isAllDay = item.allDay
                let start = item.allDay ? Self.allDayDate(item.start, in: tz) : item.start
                e.startDate = start
                e.endDate = item.allDay ? start : start.addingTimeInterval(60)
                e.timeZone = item.allDay ? nil : tz
                e.availability = .free
                if !item.allDay, let m = options.alertMinutes {
                    e.addAlarm(EKAlarm(relativeOffset: -Double(m * 60)))
                }
                try store.save(e, span: .thisEvent, commit: false)
                added += 1
            }
            try store.commit()
            return added
        } catch {
            // Drop the half-done batch, so a later commit (e.g. adding an event) doesn't apply it.
            store.reset()
            throw error
        }
    }

    /// A stable key for a synced event: what it shows, when, and its alert.
    private static func key(_ item: Item, tz: TimeZone, alert: Int?) -> String {
        var h: UInt64 = 0xcbf29ce484222325       // FNV-1a
        let text = "\(item.allDay)|\(item.title)|\(item.notes ?? "")|\(Int(item.start.timeIntervalSince1970))|\(tz.identifier)|\(alert ?? -1)"
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    private static func key(of e: EKEvent) -> String? {
        guard let url = e.url?.absoluteString, url.hasPrefix(syncURL.absoluteString + "/") else { return nil }
        return String(url.dropFirst(syncURL.absoluteString.count + 1))
    }

    /// Removes everything the sync wrote. Only marked events are deleted; the dedicated calendar itself
    /// is removed only if the app created it and nothing else is left in it.
    func removeSynced(options: CalendarSyncOptions) async throws {
        guard try await requestAccess() else { throw Failure.denied }
        let cal: EKCalendar?
        if let id = options.targetCalendarID {
            cal = store.calendar(withIdentifier: id)
        } else {
            cal = UserDefaults.standard.string(forKey: calendarIDKey).flatMap { store.calendar(withIdentifier: $0) }
        }
        guard let cal else { return }
        let now = Date()
        let range = store.predicateForEvents(withStart: now.addingTimeInterval(-400 * 86_400),
                                             end: now.addingTimeInterval(400 * 86_400), calendars: [cal])
        let events = store.events(matching: range)
        var remaining = 0
        do {
            for e in events {
                if Self.isSynced(e) {
                    try store.remove(e, span: .thisEvent, commit: false)
                } else {
                    remaining += 1
                }
            }
            try store.commit()
        } catch {
            store.reset()   // don't leave a half-done batch for the next commit
            throw error
        }
        if options.targetCalendarID == nil, remaining == 0, UserDefaults.standard.bool(forKey: createdKey) {
            try store.removeCalendar(cal, commit: true)
            UserDefaults.standard.removeObject(forKey: calendarIDKey)
            UserDefaults.standard.removeObject(forKey: createdKey)
        }
    }

    // MARK: - Write: user-added events

    struct NewEvent {
        var title: String
        var start: Date
        var allDay: Bool
        var durationMinutes = 30
        var alarmMinutes: Int?
        var notes: String?
    }

    func add(_ new: NewEvent, calendarID: String?, timeZone: TimeZone) async throws {
        guard try await requestAccess() else { throw Failure.denied }
        try save(new, in: try calendar(for: calendarID), timeZone: timeZone, commit: true)
        version += 1
    }

    /// Adds the same event on a Hebrew date for `years` consecutive years starting at `fromYear`
    /// (a yahrzeit or Hebrew birthday – something Calendar's own recurrence can't express).
    /// `original` is the Hebrew date of the event itself (year/month/day, Apple's numbering);
    /// `rule` decides where it falls in years whose months differ. Returns the Gregorian dates written.
    @discardableResult
    func addHebrewRecurring(_ new: NewEvent, original: DateComponents, rule: HebrewDates.Rule, fromYear: Int, years: Int,
                            calendarID: String?, timeZone: TimeZone) async throws -> [Date] {
        guard try await requestAccess() else { throw Failure.denied }
        let cal = try calendar(for: calendarID)
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = timeZone
        let clock = ZmanEngine.gregorian(timeZone).dateComponents([.hour, .minute], from: new.start)
        var written: [Date] = []
        do {
            for y in fromYear..<(fromYear + years) {
                guard let day = HebrewDates.anniversary(of: original, in: y, rule: rule, calendar: hebrew) else { continue }
                var e = new
                e.start = new.allDay ? day : ZmanEngine.gregorian(timeZone).date(bySettingHour: clock.hour ?? 9,
                                                                                  minute: clock.minute ?? 0, second: 0, of: day)!
                try save(e, in: cal, timeZone: timeZone, commit: false)
                written.append(day)
            }
            try store.commit()
            version += 1
        } catch {
            store.reset()   // all or nothing: no half the years written by the next commit
            throw error
        }
        return written
    }

    private func calendar(for id: String?) throws -> EKCalendar {
        guard let id else { return try target(CalendarSyncOptions()) }
        guard let cal = store.calendar(withIdentifier: id) else { throw Failure.calendarGone }
        return cal
    }

    private func save(_ new: NewEvent, in cal: EKCalendar, timeZone: TimeZone, commit: Bool) throws {
        let e = EKEvent(eventStore: store)
        e.calendar = cal
        e.title = new.title
        e.notes = new.notes
        e.isAllDay = new.allDay
        let start = new.allDay ? Self.allDayDate(new.start, in: timeZone) : new.start
        e.startDate = start
        e.endDate = new.allDay ? start : start.addingTimeInterval(Double(new.durationMinutes * 60))
        e.timeZone = new.allDay ? nil : timeZone
        if let m = new.alarmMinutes { e.addAlarm(EKAlarm(relativeOffset: -Double(m * 60))) }
        try store.save(e, span: .thisEvent, commit: commit)
    }

    // MARK: - Read

    struct DayEvent: Identifiable, Hashable {
        let id: String
        let eventID: String
        let itemID: String
        let canDelete: Bool
        let title: String
        /// Where it's shown: for all-day events, the day's midnight in the location's zone.
        let start: Date
        /// The event's own start and end dates in EventKit (this occurrence's).
        let eventStart: Date
        let eventEnd: Date
        let allDay: Bool
        let color: NSColor
        let calendar: String
    }

    private func readCalendars(_ options: CalendarSyncOptions) -> [EKCalendar]? {
        guard hasAccess else { return nil }
        let all = store.calendars(for: .event)
        let chosen = all.filter { options.readCalendarIDs.contains($0.calendarIdentifier) }
        // Nothing chosen, or every chosen calendar has since been deleted: read them all.
        let result = chosen.isEmpty ? all : chosen
        return result.isEmpty ? nil : result
    }

    /// The user's events between two dates in `tz` (synced zmanim excluded).
    /// All-day events are floating days in the Mac's own zone, so they're matched by calendar day,
    /// and reported starting at that day's midnight in `tz`.
    /// The views ask on every redraw (each day clicked): the store is queried again only after a change.
    private var eventsCache: (version: Int, entries: [String: [DayEvent]]) = (0, [:])

    func userEvents(from start: Date, to end: Date, tz: TimeZone, options: CalendarSyncOptions) -> [DayEvent] {
        let key = "\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(tz.identifier)|\(hasAccess)|\(options.showCalendarEvents)|\(options.readCalendarIDs)"
        if eventsCache.version != version || eventsCache.entries.count > 100 { eventsCache = (version, [:]) }
        if let cached = eventsCache.entries[key] { return cached }
        let events = fetchUserEvents(from: start, to: end, tz: tz, options: options)
        eventsCache.entries[key] = events
        return events
    }

    private func fetchUserEvents(from start: Date, to end: Date, tz: TimeZone, options: CalendarSyncOptions) -> [DayEvent] {
        guard options.showCalendarEvents, let cals = readCalendars(options) else { return [] }
        let loc = ZmanEngine.gregorian(tz)
        let mac = Calendar.current
        func locDay(_ d: Date) -> Date {
            loc.date(from: mac.dateComponents([.year, .month, .day], from: d)) ?? d
        }
        let pred = store.predicateForEvents(withStart: start.addingTimeInterval(-86_400), end: end.addingTimeInterval(86_400),
                                            calendars: cals)
        return store.events(matching: pred).compactMap { e -> DayEvent? in
            guard !Self.isSynced(e) else { return nil }
            var shown = e.startDate!
            if e.isAllDay {
                let first = locDay(e.startDate)
                let last = locDay(max(e.startDate, e.endDate.addingTimeInterval(-1)))
                guard first < end, loc.date(byAdding: .day, value: 1, to: last)! > start else { return nil }
                shown = max(first, loc.startOfDay(for: start))
            } else {
                guard e.startDate < end, e.endDate > start || e.startDate >= start else { return nil }
            }
            return DayEvent(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                            eventID: e.eventIdentifier ?? "", itemID: e.calendarItemIdentifier,
                            canDelete: e.calendar.allowsContentModifications,
                            title: e.title ?? "", start: shown, eventStart: e.startDate, eventEnd: e.endDate, allDay: e.isAllDay,
                            color: e.calendar.color ?? .systemBlue, calendar: e.calendar.title)
        }
        .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
    }

    /// Days (as AppModel day keys would see them, i.e. `tz` midnights) that have user events, for the month grid.
    func busyDays(from start: Date, to end: Date, tz: TimeZone, options: CalendarSyncOptions) -> [Date] {
        let loc = ZmanEngine.gregorian(tz)
        var days: [Date] = []
        for e in userEvents(from: start, to: end, tz: tz, options: options) {
            days.append(e.start)
            // Multi-day all-day events mark every day they cover. (This occurrence's dates: looking the event up
            // by identifier would give a recurring series' first occurrence.)
            guard e.allDay else { continue }
            let last = loc.date(from: Calendar.current.dateComponents([.year, .month, .day],
                                                                       from: max(e.eventStart, e.eventEnd.addingTimeInterval(-1))))
            var d = e.start
            while let next = loc.date(byAdding: .day, value: 1, to: d), let last, next <= last, next < end {
                days.append(next); d = next
            }
        }
        return days
    }

    /// Opens a specific event in Calendar.app.
    func openEvent(_ e: DayEvent) {
        let id = e.eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? e.eventID
        if let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"), NSWorkspace.shared.open(url) { return }
        openInCalendarApp(e.start)
    }

    /// Deletes one occurrence of an event (used from the popover's context menu).
    func delete(_ e: DayEvent) throws {
        // event(withIdentifier:) returns a recurring series' first occurrence, so find this exact one.
        let pred = store.predicateForEvents(withStart: e.eventStart.addingTimeInterval(-1), end: e.eventStart.addingTimeInterval(86_400), calendars: nil)
        guard let ev = store.events(matching: pred).first(where: { $0.calendarItemIdentifier == e.itemID && $0.startDate == e.eventStart })
        else { throw Failure.eventGone }
        try store.remove(ev, span: .thisEvent, commit: true)
        version += 1
    }

    func openInCalendarApp(_ date: Date) {
        // Calendar.app understands ical:// with a timestamp; fall back to just opening it.
        if let url = URL(string: "ical://\(Int(date.timeIntervalSinceReferenceDate))"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    // MARK: - Event list (shared by EventKit sync and .ics export)

    struct Item {
        var title: String
        var notes: String?
        var start: Date
        var allDay: Bool
    }

    nonisolated static func events(_ settings: AppSettings, options: CalendarSyncOptions, from: Date = Date()) -> [Item] {
        let tzCal = ZmanEngine.gregorian(settings.location.timeZone)
        var items: [Item] = []
        let chosen = Set(options.zmanIDs)
        for offset in 0..<max(1, options.daysAhead) {
            let day = tzCal.date(byAdding: .day, value: offset, to: tzCal.startOfDay(for: from))!
            let info = ZmanEngine.dayInfo(for: day, settings: settings)
            if options.includeHebrewDate {
                items.append(Item(title: info.hebrewDate, notes: info.dafYomi.isEmpty ? nil : "דף יומי: \(info.dafYomi)",
                                  start: day, allDay: true))
            }
            if options.includeEvents {
                for e in info.events { items.append(Item(title: e, start: day, allDay: true)) }
                if tzCal.component(.weekday, from: day) == 7, !info.parsha.isEmpty {
                    items.append(Item(title: info.parsha, start: day, allDay: true))
                }
            }
            if options.includeSpecialTimes {
                for t in SpecialTimes.on(day, settings: settings) {
                    guard let time = t.time else { continue }
                    let notes = [t.note, settings.location.displayName].filter { !$0.isEmpty }.joined(separator: " · ")
                    items.append(Item(title: t.title, notes: notes, start: time, allDay: false))
                }
            }
            if !chosen.isEmpty {
                for z in ZmanEngine.zmanim(on: day, settings: settings) where chosen.contains(z.id) {
                    guard let t = z.time else { continue }
                    items.append(Item(title: z.item.name, notes: settings.location.displayName, start: t, allDay: false))
                }
            }
        }
        return items
    }

    // MARK: - .ics export

    /// Writes the synced events as an .ics file (RFC 5545). Throws if the file can't be written.
    func exportICS(_ settings: AppSettings, options: CalendarSyncOptions) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.nameFieldStringValue = "זמנים - \(settings.location.displayName).ics"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try Self.ics(settings, items: Self.events(settings, options: options), alertMinutes: options.alertMinutes)
            .write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func ics(_ settings: AppSettings, items: [Item], alertMinutes: Int?, now: Date = Date()) -> String {
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let dayF = DateFormatter()
        dayF.locale = utc.locale
        dayF.timeZone = settings.location.timeZone
        dayF.dateFormat = "yyyyMMdd"
        let dayCal = ZmanEngine.gregorian(settings.location.timeZone)

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: "\\n")
        }
        /// Content lines are at most 75 octets; longer ones continue on lines starting with a space,
        /// split between characters (never inside a UTF-8 sequence).
        func fold(_ line: String) -> [String] {
            var out: [String] = [], cur = "", size = 0
            for ch in line {
                let n = String(ch).utf8.count
                if size + n > (out.isEmpty ? 75 : 74) { out.append(cur); cur = ""; size = 0 }
                cur.append(ch); size += n
            }
            out.append(cur)
            return out.enumerated().map { $0.offset == 0 ? $0.element : " " + $0.element }
        }
        /// Stable across exports, so importing a newer file updates events instead of duplicating them.
        func uid(_ item: Item) -> String {
            var h: UInt64 = 0xcbf29ce484222325       // FNV-1a
            for b in "\(settings.location.id)|\(item.title)|\(item.start.timeIntervalSince1970)".utf8 {
                h = (h ^ UInt64(b)) &* 0x100000001b3
            }
            return String(h, radix: 16) + "@myzman"
        }

        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//MyZman Mac//HE", "CALSCALE:GREGORIAN",
                     "X-WR-CALNAME:\(Self.calendarTitle) – \(esc(settings.location.displayName))"]
        let stamp = utc.string(from: now)
        for item in items {
            lines += ["BEGIN:VEVENT", "UID:\(uid(item))", "DTSTAMP:\(stamp)", "SUMMARY:\(esc(item.title))"]
            if item.allDay {
                let next = dayCal.date(byAdding: .day, value: 1, to: item.start)!
                lines += ["DTSTART;VALUE=DATE:\(dayF.string(from: item.start))", "DTEND;VALUE=DATE:\(dayF.string(from: next))"]
            } else {
                lines += ["DTSTART:\(utc.string(from: item.start))", "DTEND:\(utc.string(from: item.start.addingTimeInterval(60)))"]
            }
            lines.append("TRANSP:TRANSPARENT")
            // Properties first, then sub-components.
            if let n = item.notes { lines.append("DESCRIPTION:\(esc(n))") }
            if !item.allDay, let m = alertMinutes {
                lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(esc(item.title))", "TRIGGER:-PT\(m)M", "END:VALARM"]
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.flatMap(fold).joined(separator: "\r\n") + "\r\n"
    }
}

/// Helpers for Apple's Hebrew calendar (month numbering: Tishrei = 1, Cheshvan = 2, Kislev = 3, Teves = 4, Shevat = 5,
/// Adar I = 6, Adar/Adar II = 7, Nisan = 8 …; month 6 doesn't exist in a common year).
enum HebrewDates {
    /// How a Hebrew anniversary moves in years whose months differ from the original year's.
    enum Rule: String, CaseIterable, Identifiable, Codable {
        /// The same day and month; a missing 30th becomes the 29th, Adar of a common year becomes Adar II.
        case plain
        /// Birthday / bar mitzvah (Shulchan Aruch OC 55:10): Adar → Adar II; a missing 30th → the 1st of the next month.
        case birthday
        /// Yahrzeit (Shulchan Aruch OC 568:7, Magen Avraham 568:20), as Hebcal computes it, with Adar of
        /// a common year → Adar I (Rema) in a leap year.
        case yahrzeitAdarI
        /// The same, but Adar → Adar II (Mechaber; Sephardi custom).
        case yahrzeitAdarII

        var id: String { rawValue }
        var title: String {
            switch self {
            case .plain: "תאריך קבוע"
            case .birthday: "יום הולדת / בר מצווה"
            case .yahrzeitAdarI: "יארצייט (אדר → אדר א׳)"
            case .yahrzeitAdarII: "יארצייט (אדר → אדר ב׳)"
            }
        }
    }

    static func isLeap(_ year: Int, calendar: Calendar) -> Bool {
        calendar.date(from: DateComponents(era: 0, year: year, month: 6, day: 1))
            .map { calendar.component(.month, from: $0) == 6 } ?? false
    }

    /// The exact Hebrew date, or nil if that day doesn't exist (e.g. 30 Cheshvan in a short year).
    static func exact(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(era: 0, year: year, month: month, day: day)),
              calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func has30(_ year: Int, month: Int, calendar: Calendar) -> Bool {
        exact(year: year, month: month, day: 30, calendar: calendar) != nil
    }

    /// The Gregorian day of the anniversary of `original` (Hebrew year/month/day) in Hebrew year `year`.
    static func anniversary(of original: DateComponents, in year: Int, rule: Rule, calendar: Calendar) -> Date? {
        guard let oy = original.year, var m = original.month, var d = original.day else { return nil }
        let origLeap = isLeap(oy, calendar: calendar), leap = isLeap(year, calendar: calendar)
        let nextMonth = [2: 3, 3: 4, 6: 8]  // after Cheshvan, Kislev, and Adar I of a common year (= Adar) comes…

        switch rule {
        case .plain:
            if m == 6, !leap { m = 7 }
            return exact(year: year, month: m, day: d, calendar: calendar)
                ?? exact(year: year, month: m, day: d - 1, calendar: calendar)
        case .birthday:
            if m == 6, !leap {
                if d == 30 { m = 8; d = 1 } else { m = 7 }
            } else if d == 30, m == 2 || m == 3, !has30(year, month: m, calendar: calendar) {
                m = nextMonth[m]!; d = 1
            }
        case .yahrzeitAdarI, .yahrzeitAdarII:
            if d == 30, m == 2 || m == 3, !has30(oy + 1, month: m, calendar: calendar) {
                // The first anniversary had no 30th, so it was kept on the month's last day: keep it there.
                return exact(year: year, month: m, day: has30(year, month: m, calendar: calendar) ? 30 : 29, calendar: calendar)
            } else if m == 6, !leap {
                if d == 30 { m = 5 } else { m = 7 }      // 30 Adar I → 30 Shevat
            } else if m == 7, !origLeap, leap {
                m = rule == .yahrzeitAdarI ? 6 : 7
            }
            if d == 30, m == 2 || m == 3, !has30(year, month: m, calendar: calendar) {
                m = nextMonth[m]!; d = 1
            }
        }
        return exact(year: year, month: m, day: d, calendar: calendar)
    }
}
