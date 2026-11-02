import Foundation

/// A zman in the user's list: a display name over one of the catalog calculations.
struct ZmanItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var defID: String

    var def: ZmanDef? { ZmanCatalog.def(defID) }
}

struct Reminder: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case zman, time
        var id: String { rawValue }
        var title: String { self == .zman ? "לפי זמן" : "שעה קבועה" }
    }

    enum Repeat: String, Codable, CaseIterable, Identifiable {
        case daily, weekdays, once
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: "כל יום"
            case .weekdays: "ימים מסוימים"
            case .once: "פעם אחת"
            }
        }
    }

    var id = UUID()
    var kind: Kind = .zman
    /// For `.zman` reminders.
    var zmanID: UUID?
    var minutesBefore: Int = 10
    /// For `.time` reminders (in the selected location's time zone).
    var hour = 8
    var minute = 0
    var repeatMode: Repeat = .daily
    /// 1 = Sunday … 7 = Shabbos, for `.weekdays`.
    var weekdays: [Int] = [1, 2, 3, 4, 5]
    /// The day of a one-time reminder (any time on that day).
    var onceDate: Date?
    /// Custom notification title; empty = the zman's name / "תזכורת".
    var label = ""
    var enabled = true

    init(zmanID: UUID, minutesBefore: Int) {
        self.zmanID = zmanID
        self.minutesBefore = minutesBefore
    }

    init(kind: Kind) { self.kind = kind }

    // Lenient decoding: older settings only had zmanID/minutesBefore/enabled.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .zman
        zmanID = try? c.decodeIfPresent(UUID.self, forKey: .zmanID)
        minutesBefore = (try? c.decode(Int.self, forKey: .minutesBefore)) ?? 10
        hour = (try? c.decode(Int.self, forKey: .hour)) ?? 8
        minute = (try? c.decode(Int.self, forKey: .minute)) ?? 0
        repeatMode = (try? c.decode(Repeat.self, forKey: .repeatMode)) ?? .daily
        weekdays = (try? c.decode([Int].self, forKey: .weekdays)) ?? [1, 2, 3, 4, 5]
        onceDate = try? c.decodeIfPresent(Date.self, forKey: .onceDate)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    }

    static let weekdayLetters = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]

    /// Whether the reminder applies on `day` (a date in the location's calendar).
    func applies(on day: Date, calendar: Calendar) -> Bool {
        switch repeatMode {
        case .daily: true
        case .weekdays: weekdays.contains(calendar.component(.weekday, from: day))
        case .once: onceDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
    }

    /// When it fires on `day`, or nil if the zman doesn't occur that day.
    func fireDate(on day: Date, settings: AppSettings) -> Date? {
        let cal = ZmanEngine.gregorian(settings.location.timeZone)
        switch kind {
        case .time:
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        case .zman:
            guard let id = zmanID, let item = settings.zmanim.first(where: { $0.id == id }),
                  let t = ZmanEngine.time(of: item, on: day, settings: settings) else { return nil }
            return t.addingTimeInterval(-Double(minutesBefore * 60))
        }
    }

    func title(in settings: AppSettings) -> String {
        if !label.isEmpty { return label }
        if kind == .zman, let name = settings.zmanim.first(where: { $0.id == zmanID })?.name { return name }
        return "תזכורת"
    }

    /// e.g. "סזק״ש גר״א · 10 דק׳ לפני · א׳ ב׳ ג׳" – shown in Settings.
    func summary(in settings: AppSettings, format: ZmanFormat) -> String {
        var parts: [String] = []
        switch kind {
        case .zman:
            parts.append(settings.zmanim.first { $0.id == zmanID }?.name ?? "זמן שנמחק")
            parts.append(minutesBefore == 0 ? "בזמן" : "\(minutesBefore) דק׳ לפני")
        case .time:
            parts.append(String(format: "%02d:%02d", hour, minute))
        }
        switch repeatMode {
        case .daily: parts.append("כל יום")
        case .weekdays: parts.append(weekdays.sorted().map { Self.weekdayLetters[$0 - 1] }.joined(separator: " "))
        case .once: parts.append(onceDate.map { format.gregorianDate($0) } ?? "—")
        }
        return parts.joined(separator: " · ")
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "לפי המערכת"
        case .light: "בהיר"
        case .dark: "כהה"
        }
    }
}

enum MenuBarZmanMode: String, Codable, CaseIterable, Identifiable {
    case next, pinned, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .next: "הזמן הבא ברשימה"
        case .pinned: "זמן קבוע"
        case .none: "ללא"
        }
    }
}

struct MenuBarOptions: Codable, Hashable {
    var showIcon = true
    var showHebrewDate = true
    var showGregorianDate = false
    var zmanMode: MenuBarZmanMode = .next
    var pinnedZman: UUID?
    var showZmanName = true
    var showZmanTime = false
    var showCountdown = true
    /// Show the countdown only once the zman is this close (0 = always).
    var countdownWithinMinutes = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuBarOptions()
        showIcon = (try? c.decode(Bool.self, forKey: .showIcon)) ?? d.showIcon
        showHebrewDate = (try? c.decode(Bool.self, forKey: .showHebrewDate)) ?? d.showHebrewDate
        showGregorianDate = (try? c.decode(Bool.self, forKey: .showGregorianDate)) ?? d.showGregorianDate
        zmanMode = (try? c.decode(MenuBarZmanMode.self, forKey: .zmanMode)) ?? d.zmanMode
        pinnedZman = try? c.decodeIfPresent(UUID.self, forKey: .pinnedZman)
        showZmanName = (try? c.decode(Bool.self, forKey: .showZmanName)) ?? d.showZmanName
        showZmanTime = (try? c.decode(Bool.self, forKey: .showZmanTime)) ?? d.showZmanTime
        showCountdown = (try? c.decode(Bool.self, forKey: .showCountdown)) ?? d.showCountdown
        countdownWithinMinutes = (try? c.decode(Int.self, forKey: .countdownWithinMinutes)) ?? d.countdownWithinMinutes
    }
}

/// Decodes an array element by element, skipping elements that fail instead of dropping the whole array.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private extension KeyedDecodingContainer {
    func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        (try? decode([Lossy<T>].self, forKey: key)).map { $0.compactMap(\.value) }
    }
}

struct CalendarSyncOptions: Codable, Hashable {
    var enabled = false
    var daysAhead = 30
    var includeHebrewDate = true
    var includeEvents = true      // holidays, rosh chodesh, omer, parsha
    var zmanIDs: [UUID] = []      // timed events
    var alertMinutes: Int?        // alarm on the timed events
    /// Where synced/added events go. nil = a dedicated "זמנים" calendar the app creates.
    var targetCalendarID: String?
    /// Show the user's own calendar events in the popover.
    var showCalendarEvents = true
    /// Calendars to read from; empty = all.
    var readCalendarIDs: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CalendarSyncOptions()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        daysAhead = (try? c.decode(Int.self, forKey: .daysAhead)) ?? d.daysAhead
        includeHebrewDate = (try? c.decode(Bool.self, forKey: .includeHebrewDate)) ?? d.includeHebrewDate
        includeEvents = (try? c.decode(Bool.self, forKey: .includeEvents)) ?? d.includeEvents
        zmanIDs = (try? c.decode([UUID].self, forKey: .zmanIDs)) ?? d.zmanIDs
        alertMinutes = try? c.decodeIfPresent(Int.self, forKey: .alertMinutes)
        targetCalendarID = try? c.decodeIfPresent(String.self, forKey: .targetCalendarID)
        showCalendarEvents = (try? c.decode(Bool.self, forKey: .showCalendarEvents)) ?? d.showCalendarEvents
        readCalendarIDs = (try? c.decode([String].self, forKey: .readCalendarIDs)) ?? d.readCalendarIDs
    }
}

struct AppSettings: Codable, Hashable {
    var location: Location = .jerusalem
    var customLocations: [Location] = []
    var zmanim: [ZmanItem] = ZmanCatalog.defaults
    var reminders: [Reminder] = []
    var menuBar = MenuBarOptions()
    var calendarSync = CalendarSyncOptions()

    /// nil = derive from the location.
    var inIsraelOverride: Bool?
    var useModernHolidays = false
    var useElevation = false
    var useUSNO = false
    var use24h = true
    var showSeconds = false
    var colorPastZmanim = true
    var hebrewDateChangesAtSunset = true
    var appearance: AppearanceMode = .system

    var inIsrael: Bool { inIsraelOverride ?? location.isInIsrael }

    init() {}

    // Decode leniently so settings survive new fields being added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        location = (try? c.decode(Location.self, forKey: .location)) ?? d.location
        customLocations = c.lossyArray(Location.self, forKey: .customLocations) ?? d.customLocations
        zmanim = c.lossyArray(ZmanItem.self, forKey: .zmanim) ?? d.zmanim
        reminders = c.lossyArray(Reminder.self, forKey: .reminders) ?? d.reminders
        menuBar = (try? c.decode(MenuBarOptions.self, forKey: .menuBar)) ?? d.menuBar
        calendarSync = (try? c.decode(CalendarSyncOptions.self, forKey: .calendarSync)) ?? d.calendarSync
        inIsraelOverride = try? c.decodeIfPresent(Bool.self, forKey: .inIsraelOverride)
        useModernHolidays = (try? c.decode(Bool.self, forKey: .useModernHolidays)) ?? d.useModernHolidays
        useElevation = (try? c.decode(Bool.self, forKey: .useElevation)) ?? d.useElevation
        useUSNO = (try? c.decode(Bool.self, forKey: .useUSNO)) ?? d.useUSNO
        use24h = (try? c.decode(Bool.self, forKey: .use24h)) ?? d.use24h
        showSeconds = (try? c.decode(Bool.self, forKey: .showSeconds)) ?? d.showSeconds
        colorPastZmanim = (try? c.decode(Bool.self, forKey: .colorPastZmanim)) ?? d.colorPastZmanim
        hebrewDateChangesAtSunset = (try? c.decode(Bool.self, forKey: .hebrewDateChangesAtSunset)) ?? d.hebrewDateChangesAtSunset
        appearance = (try? c.decode(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
    }

    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
            // Copy for the (sandboxed) widget, which may read only this folder.
            try? FileManager.default.createDirectory(at: Self.sharedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.sharedFile, options: .atomic)
        }
    }

    /// ~/Library/Application Support/MyZman/settings.json, resolved from the real home folder
    /// (inside the widget's sandbox NSHomeDirectory() points at its container).
    static var sharedFile: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MyZman/settings.json")
    }

    static func loadShared() -> AppSettings {
        guard let data = try? Data(contentsOf: sharedFile),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }
}
