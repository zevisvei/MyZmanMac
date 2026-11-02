import Foundation

/// A zman in the user's list: a display name over one of the catalog calculations.
struct ZmanItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var defID: String

    var def: ZmanDef? { ZmanCatalog.def(defID) }
}

struct Reminder: Codable, Hashable, Identifiable {
    var id = UUID()
    var zmanID: UUID
    var minutesBefore: Int = 10
    var enabled = true
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
        customLocations = (try? c.decode([Location].self, forKey: .customLocations)) ?? d.customLocations
        zmanim = (try? c.decode([ZmanItem].self, forKey: .zmanim)) ?? d.zmanim
        reminders = (try? c.decode([Reminder].self, forKey: .reminders)) ?? d.reminders
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
