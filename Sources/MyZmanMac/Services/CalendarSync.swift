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
        case denied, noSource, calendarGone
        var errorDescription: String? {
            switch self {
            case .denied: "אין הרשאת גישה ללוח השנה. ניתן לאפשר בהגדרות המערכת ← פרטיות ואבטחה ← לוחות שנה."
            case .noSource: "לא נמצא חשבון לוח שנה מתאים (iCloud או 'במחשב')."
            case .calendarGone: "הלוח שנבחר לא נמצא – בחרו לוח אחר בהגדרות."
            }
        }
    }

    @discardableResult
    func requestAccess() async throws -> Bool {
        let ok = try await store.requestFullAccessToEvents()
        hasAccess = ok
        if ok { store.refreshSourcesIfNecessary(); version += 1 }
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
        if let id = UserDefaults.standard.string(forKey: calendarIDKey),
           let cal = store.calendar(withIdentifier: id) { return cal }
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
    func sync(_ settings: AppSettings, options: CalendarSyncOptions) async throws -> Int {
        guard try await requestAccess() else { throw Failure.denied }
        let cal = try target(options)
        let tzCal = ZmanEngine.gregorian(settings.location.timeZone)
        let start = tzCal.startOfDay(for: Date())

        let from = tzCal.date(byAdding: .day, value: -60, to: start)!
        let to = tzCal.date(byAdding: .day, value: 400, to: start)!
        for e in store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [cal]))
        where e.notes?.hasSuffix(Self.syncMarker) == true {
            try store.remove(e, span: .thisEvent, commit: false)
        }

        var count = 0
        for event in events(settings, options: options) {
            let e = EKEvent(eventStore: store)
            e.calendar = cal
            e.title = event.title
            e.notes = (event.notes.map { $0 + "\n" } ?? "") + Self.syncMarker
            e.isAllDay = event.allDay
            let start = event.allDay ? Self.allDayDate(event.start, in: settings.location.timeZone) : event.start
            e.startDate = start
            e.endDate = event.allDay ? start : start.addingTimeInterval(60)
            e.timeZone = event.allDay ? nil : settings.location.timeZone
            e.availability = .free
            if !event.allDay, let m = options.alertMinutes {
                e.addAlarm(EKAlarm(relativeOffset: -Double(m * 60)))
            }
            try store.save(e, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        return count
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
        for e in events {
            if e.notes?.hasSuffix(Self.syncMarker) == true {
                try store.remove(e, span: .thisEvent, commit: false)
            } else {
                remaining += 1
            }
        }
        try store.commit()
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
    }

    /// Adds the same event on a Hebrew date for `years` consecutive years
    /// (a yahrzeit or Hebrew birthday – something Calendar's own recurrence can't express).
    /// Returns the Gregorian dates written.
    @discardableResult
    func addHebrewRecurring(_ new: NewEvent, hebrewMonth: Int, hebrewDay: Int, fromYear: Int, years: Int,
                            calendarID: String?, timeZone: TimeZone) async throws -> [Date] {
        guard try await requestAccess() else { throw Failure.denied }
        let cal = try calendar(for: calendarID)
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = timeZone
        let clock = ZmanEngine.gregorian(timeZone).dateComponents([.hour, .minute], from: new.start)
        var written: [Date] = []
        for y in fromYear..<(fromYear + years) {
            guard let day = HebrewDates.date(year: y, month: hebrewMonth, day: hebrewDay, calendar: hebrew) else { continue }
            var e = new
            e.start = new.allDay ? day : ZmanEngine.gregorian(timeZone).date(bySettingHour: clock.hour ?? 9,
                                                                              minute: clock.minute ?? 0, second: 0, of: day)!
            try save(e, in: cal, timeZone: timeZone, commit: false)
            written.append(day)
        }
        try store.commit()
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
        let start: Date
        let allDay: Bool
        let color: NSColor
        let calendar: String
    }

    private func readCalendars(_ options: CalendarSyncOptions) -> [EKCalendar]? {
        guard hasAccess else { return nil }
        let all = store.calendars(for: .event)
        let chosen = options.readCalendarIDs.isEmpty ? all : all.filter { options.readCalendarIDs.contains($0.calendarIdentifier) }
        return chosen.isEmpty ? nil : chosen
    }

    /// The user's events between two dates (synced zmanim excluded).
    func userEvents(from start: Date, to end: Date, options: CalendarSyncOptions) -> [DayEvent] {
        guard options.showCalendarEvents, let cals = readCalendars(options) else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: cals))
            .filter { $0.notes?.hasSuffix(Self.syncMarker) != true }
            .map { DayEvent(id: $0.calendarItemIdentifier + "\($0.startDate.timeIntervalSince1970)",
                            eventID: $0.eventIdentifier ?? "", itemID: $0.calendarItemIdentifier,
                            canDelete: $0.calendar.allowsContentModifications,
                            title: $0.title ?? "",
                            start: $0.startDate, allDay: $0.isAllDay, color: $0.calendar.color ?? .systemBlue,
                            calendar: $0.calendar.title) }
            .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
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
        let pred = store.predicateForEvents(withStart: e.start.addingTimeInterval(-1), end: e.start.addingTimeInterval(86_400), calendars: nil)
        guard let ev = store.events(matching: pred).first(where: { $0.calendarItemIdentifier == e.itemID && $0.startDate == e.start })
        else { return }
        try store.remove(ev, span: .thisEvent, commit: true)
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

    func events(_ settings: AppSettings, options: CalendarSyncOptions, from: Date = Date()) -> [Item] {
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

    func exportICS(_ settings: AppSettings, options: CalendarSyncOptions) {
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let dayF = DateFormatter()
        dayF.locale = utc.locale
        dayF.timeZone = settings.location.timeZone
        dayF.dateFormat = "yyyyMMdd"

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: "\\n")
        }

        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//MyZman Mac//HE", "CALSCALE:GREGORIAN",
                     "X-WR-CALNAME:\(Self.calendarTitle) – \(esc(settings.location.displayName))"]
        let stamp = utc.string(from: Date())
        for item in events(settings, options: options) {
            lines += ["BEGIN:VEVENT", "UID:\(UUID().uuidString)@myzman", "DTSTAMP:\(stamp)", "SUMMARY:\(esc(item.title))"]
            if item.allDay {
                let next = item.start.addingTimeInterval(86_400 + 3600)
                lines += ["DTSTART;VALUE=DATE:\(dayF.string(from: item.start))", "DTEND;VALUE=DATE:\(dayF.string(from: next))",
                          "TRANSP:TRANSPARENT"]
            } else {
                lines += ["DTSTART:\(utc.string(from: item.start))", "DTEND:\(utc.string(from: item.start.addingTimeInterval(60)))",
                          "TRANSP:TRANSPARENT"]
                if let m = options.alertMinutes {
                    lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(esc(item.title))", "TRIGGER:-PT\(m)M", "END:VALARM"]
                }
            }
            if let n = item.notes { lines.append("DESCRIPTION:\(esc(n))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.nameFieldStringValue = "זמנים - \(settings.location.displayName).ics"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? lines.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Helpers for Apple's Hebrew calendar (month numbering: Tishrei = 1 … Adar I = 6, Adar/Adar II = 7, Nisan = 8 …).
enum HebrewDates {
    static func isLeap(_ year: Int, calendar: Calendar) -> Bool {
        calendar.date(from: DateComponents(era: 0, year: year, month: 6, day: 1))
            .map { calendar.component(.month, from: $0) == 6 } ?? false
    }

    /// The Gregorian day for a Hebrew date, with the usual fallbacks:
    /// Adar I/II → Adar in a non-leap year, Adar → Adar II in a leap year, day 30 → day 29 when the month is short.
    static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var m = month
        if m == 6, !isLeap(year, calendar: calendar) { m = 7 }
        for d in stride(from: day, through: max(1, day - 1), by: -1) {
            if let date = calendar.date(from: DateComponents(era: 0, year: year, month: m, day: d)),
               calendar.component(.month, from: date) == m, calendar.component(.day, from: date) == d {
                return date
            }
        }
        return nil
    }
}
