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
        /// Before candle lighting, on every erev Shabbos / Yom Tov.
        case candles
        /// At the end of Shabbos / Yom Tov (havdalah).
        case havdalah
        /// Sefiras HaOmer at nightfall, with that night's count.
        case omer
        var id: String { rawValue }
        var title: String {
            switch self {
            case .zman: "לפי זמן"
            case .time: "שעה קבועה"
            case .candles: "הדלקת נרות"
            case .havdalah: "הבדלה"
            case .omer: "ספירת העומר"
            }
        }
        /// Kinds tied to their own days (Shabbos, Yom Tov, the Omer): no repeat choice.
        var hasOwnDays: Bool { self == .candles || self == .havdalah || self == .omer }
    }

    enum Repeat: String, Codable, CaseIterable, Identifiable {
        case daily, weekdays, once
        /// Only on the eve of Shabbos / Yom Tov.
        case erevShabbos
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: "כל יום"
            case .weekdays: "ימים מסוימים"
            case .once: "פעם אחת"
            case .erevShabbos: "ערב שבת וחג"
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
    func applies(on day: Date, settings: AppSettings) -> Bool {
        if kind.hasOwnDays { return true }   // fireDate picks the days
        let calendar = ZmanEngine.gregorian(settings.location.timeZone)
        switch repeatMode {
        case .daily: return true
        case .weekdays: return weekdays.contains(calendar.component(.weekday, from: day))
        case .once: return onceDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        case .erevShabbos:
            let jc = ZmanEngine.jewishCalendar(for: day, settings: settings)
            return jc.hasCandleLighting() && !jc.isAssurBemelacha()   // the weekday eve, not a first day of Yom Tov
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
        case .candles:
            // Only before sunset; on a second day of Yom Tov candles are lit from an existing flame after nightfall.
            guard ZmanEngine.jewishCalendar(for: day, settings: settings).hasCandleLighting() else { return nil }
            let c = SpecialTimes.candleLighting(on: day, settings)
            guard !c.afterNightfall, let t = c.time else { return nil }
            return t.addingTimeInterval(-Double(minutesBefore * 60))
        case .havdalah:
            // The last day of Shabbos / Yom Tov (not the first of two).
            let jc = ZmanEngine.jewishCalendar(for: day, settings: settings)
            let tomorrow = ZmanEngine.jewishCalendar(for: cal.date(byAdding: .day, value: 1, to: day)!, settings: settings)
            guard jc.isAssurBemelacha(), !tomorrow.isAssurBemelacha(), let t = SpecialTimes.havdalah(on: day, settings) else { return nil }
            return t.addingTimeInterval(-Double(minutesBefore * 60))
        case .omer:
            guard Self.omerTonight(day, settings) > 0, let def = ZmanCatalog.def(settings.fastEndDefID) else { return nil }
            let t = ZmanEngine.round(ZmanEngine.compute(def, on: ZmanEngine.calendar(for: day, settings: settings)).0, .earliest, settings)
            return t?.addingTimeInterval(-Double(minutesBefore * 60))
        }
    }

    /// The Omer count of the night after `day` (0 outside the Omer).
    static func omerTonight(_ day: Date, _ settings: AppSettings) -> Int {
        let cal = ZmanEngine.gregorian(settings.location.timeZone)
        return ZmanEngine.jewishCalendar(for: cal.date(byAdding: .day, value: 1, to: day)!, settings: settings).getDayOfOmer()
    }

    func title(in settings: AppSettings) -> String {
        if !label.isEmpty { return label }
        if kind == .zman, let name = settings.zmanim.first(where: { $0.id == zmanID })?.name { return name }
        if kind.hasOwnDays { return kind.title }
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
        case .candles:
            parts.append(minutesBefore == 0 ? "בזמן ההדלקה" : "\(minutesBefore) דק׳ לפני ההדלקה")
            parts.append("בכל ערב שבת וחג")
            return parts.joined(separator: " · ")
        case .havdalah:
            parts.append(minutesBefore == 0 ? "בצאת השבת והחג" : "\(minutesBefore) דק׳ לפני צאת השבת והחג")
            return parts.joined(separator: " · ")
        case .omer:
            parts.append(minutesBefore == 0 ? "בצאת הכוכבים" : "\(minutesBefore) דק׳ לפני צאת הכוכבים")
            parts.append("בימי הספירה")
            return parts.joined(separator: " · ")
        }
        switch repeatMode {
        case .daily: parts.append("כל יום")
        case .weekdays: parts.append(weekdays.sorted().map { Self.weekdayLetters[$0 - 1] }.joined(separator: " "))
        case .once: parts.append(onceDate.map { format.gregorianDate($0) } ?? "—")
        case .erevShabbos: parts.append("בערבי שבת וחג")
        }
        return parts.joined(separator: " · ")
    }
}

/// How a zman is rounded to the minute when seconds aren't shown.
enum ZmanRounding: String, Codable, CaseIterable, Identifiable {
    /// Toward the stringent side: a time something may start from (netz, tzais, mincha) is rounded up,
    /// a deadline (sof zman, shkiah, candle lighting) down, anything else to the nearest minute.
    case stringent
    case nearest
    /// Drop the seconds (always earlier).
    case truncate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stringent: "לחומרא"
        case .nearest: "לדקה הקרובה"
        case .truncate: "השמטת השניות"
        }
    }
}

/// Prayer custom, where it changes what's shown (the haftara, Morid HaTal outside Israel).
enum Nusach: String, Codable, CaseIterable, Identifiable {
    case ashkenaz, sefard
    var id: String { rawValue }
    var title: String { self == .ashkenaz ? "אשכנז" : "ספרד / עדות המזרח" }
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
    /// Off = no status item at all (widgets only); opening the app again shows its window.
    var showInMenuBar = true
    var showIcon = true
    var showHebrewDate = true
    var showGregorianDate = false
    var zmanMode: MenuBarZmanMode = .next
    var pinnedZman: UUID?
    /// Zmanim left out of the "next zman" rotation in the menu bar (still in the list).
    var hiddenZmanim: [UUID] = []
    var showZmanName = true
    var showZmanTime = false
    var showCountdown = true
    /// Show the countdown only once the zman is this close (0 = always).
    var countdownWithinMinutes = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuBarOptions()
        showInMenuBar = (try? c.decode(Bool.self, forKey: .showInMenuBar)) ?? d.showInMenuBar
        showIcon = (try? c.decode(Bool.self, forKey: .showIcon)) ?? d.showIcon
        showHebrewDate = (try? c.decode(Bool.self, forKey: .showHebrewDate)) ?? d.showHebrewDate
        showGregorianDate = (try? c.decode(Bool.self, forKey: .showGregorianDate)) ?? d.showGregorianDate
        zmanMode = (try? c.decode(MenuBarZmanMode.self, forKey: .zmanMode)) ?? d.zmanMode
        pinnedZman = try? c.decodeIfPresent(UUID.self, forKey: .pinnedZman)
        hiddenZmanim = (try? c.decode([UUID].self, forKey: .hiddenZmanim)) ?? d.hiddenZmanim
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
    /// Candle lighting, end of Shabbos / Yom Tov, fasts… on the days they apply.
    var includeSpecialTimes = false
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
        includeSpecialTimes = (try? c.decode(Bool.self, forKey: .includeSpecialTimes)) ?? d.includeSpecialTimes
        alertMinutes = try? c.decodeIfPresent(Int.self, forKey: .alertMinutes)
        targetCalendarID = try? c.decodeIfPresent(String.self, forKey: .targetCalendarID)
        showCalendarEvents = (try? c.decode(Bool.self, forKey: .showCalendarEvents)) ?? d.showCalendarEvents
        readCalendarIDs = (try? c.decode([String].self, forKey: .readCalendarIDs)) ?? d.readCalendarIDs
    }
}

struct AppSettings: Codable, Hashable {
    var location: Location = .jerusalem
    var customLocations: [Location] = []
    /// Shown side by side with the current location in the comparison tab.
    var compareLocations: [Location] = []
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
    /// Show the list in time order instead of the order it's arranged in (durations go last).
    var sortByTime = false
    var hebrewDateChangesAtSunset = true
    var appearance: AppearanceMode = .system
    var rounding: ZmanRounding = .stringent
    /// Minutes before sunset; nil = the local custom (Jerusalem 40, Haifa 30, elsewhere 18).
    var candleLightingMinutes: Int?
    /// The catalog zman used for the end of Shabbos.
    var havdalahDefID = "GetTzaisGeonim8Point5Degrees"
    /// The catalog zmanim for the start and end of a daytime fast.
    var fastStartDefID = "GetAlos16Point1Degrees"
    var fastEndDefID = "GetTzaisGeonim7Point083Degrees"
    /// Tisha B'Av's end, which many luachs set later than the minor fasts'.
    var tishaBavEndDefID = "GetTzaisGeonim7Point083Degrees"
    /// Chanukah candles on weeknights at nightfall (fastEndDefID's tzais) instead of sunset.
    var chanukahAtTzais = false
    var nusach: Nusach = .ashkenaz
    /// Show the Yerushalmi daf next to the Bavli.
    var showYerushalmi = false
    /// Show the day's tefila changes (Ya'aleh Veyavo, Hallel, no Tachanun…).
    var showTefila = true
    var showHaftara = true
    /// Daily learning cycles shown beside the Daf Yomi, in this order.
    var learning: [DailyLearning.Cycle] = []

    var inIsrael: Bool { inIsraelOverride ?? location.isInIsrael }

    /// Whether anything the widgets show differs (reminders, calendar sync, the menu bar's look and the app's
    /// appearance don't reach them).
    func affectsWidgets(comparedTo other: AppSettings) -> Bool {
        func shown(_ s: AppSettings) -> AppSettings {
            var s = s
            s.reminders = []
            s.calendarSync = CalendarSyncOptions()
            s.menuBar = MenuBarOptions()
            s.appearance = .system
            s.customLocations = []
            s.compareLocations = []
            s.learning = []
            s.showHaftara = true
            return s
        }
        return shown(self) != shown(other)
    }

    var candleLightingOffset: Int { candleLightingMinutes ?? Self.localCandleLighting(location) }

    /// The local custom: Jerusalem and Petach Tikva 40 minutes, Haifa and Zichron Ya'akov 30, the rest of
    /// Israel 20 (as most Israeli luachs and Hebcal), elsewhere 18.
    static func localCandleLighting(_ loc: Location) -> Int {
        let name = loc.nameEn.lowercased() + " " + loc.nameHe
        if loc.isJerusalem || name.contains("petah tikva") || name.contains("פתח תקו") { return 40 }
        if name.contains("haifa") || name.contains("חיפה") || name.contains("zichron") || name.contains("זכרון יעקב") { return 30 }
        return loc.isInIsrael ? 20 : 18
    }

    init() {}

    // Decode leniently so settings survive new fields being added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        location = (try? c.decode(Location.self, forKey: .location)) ?? d.location
        customLocations = c.lossyArray(Location.self, forKey: .customLocations) ?? d.customLocations
        compareLocations = c.lossyArray(Location.self, forKey: .compareLocations) ?? d.compareLocations
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
        sortByTime = (try? c.decode(Bool.self, forKey: .sortByTime)) ?? d.sortByTime
        hebrewDateChangesAtSunset = (try? c.decode(Bool.self, forKey: .hebrewDateChangesAtSunset)) ?? d.hebrewDateChangesAtSunset
        appearance = (try? c.decode(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
        rounding = (try? c.decode(ZmanRounding.self, forKey: .rounding)) ?? d.rounding
        candleLightingMinutes = try? c.decodeIfPresent(Int.self, forKey: .candleLightingMinutes)
        havdalahDefID = (try? c.decode(String.self, forKey: .havdalahDefID)).flatMap { ZmanCatalog.def($0)?.id } ?? d.havdalahDefID
        fastStartDefID = (try? c.decode(String.self, forKey: .fastStartDefID)).flatMap { ZmanCatalog.def($0)?.id } ?? d.fastStartDefID
        fastEndDefID = (try? c.decode(String.self, forKey: .fastEndDefID)).flatMap { ZmanCatalog.def($0)?.id } ?? d.fastEndDefID
        showYerushalmi = (try? c.decode(Bool.self, forKey: .showYerushalmi)) ?? d.showYerushalmi
        showTefila = (try? c.decode(Bool.self, forKey: .showTefila)) ?? d.showTefila
        showHaftara = (try? c.decode(Bool.self, forKey: .showHaftara)) ?? d.showHaftara
        learning = c.lossyArray(DailyLearning.Cycle.self, forKey: .learning) ?? d.learning
        tishaBavEndDefID = (try? c.decode(String.self, forKey: .tishaBavEndDefID)).flatMap { ZmanCatalog.def($0)?.id } ?? d.tishaBavEndDefID
        chanukahAtTzais = (try? c.decode(Bool.self, forKey: .chanukahAtTzais)) ?? d.chanukahAtTzais
        nusach = (try? c.decode(Nusach.self, forKey: .nusach)) ?? d.nusach
        // The selected location is stored by value: pick up corrections made to the built-in list since.
        if location.region != .custom,
           let fresh = Location.builtIn.first(where: { $0.nameEn == location.nameEn && $0.nameHe == location.nameHe }) {
            location = fresh
        }
    }

    private static let key = "settings.v1"

    /// Only the installed app keeps settings. A development build (`swift run`, `--preview`, `--dump`) has no bundle
    /// or a different one, and must not write – the widget reads the shared file and would show its defaults.
    static var persists: Bool {
        Bundle.main.bundleIdentifier == "com.myzman.mac" && !CommandLine.arguments.contains("--preview")
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key) else { return AppSettings() }
        guard let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            // Unreadable (decoding is lenient, so this means corrupted): keep a copy before the defaults replace it.
            if persists { UserDefaults.standard.set(data, forKey: key + ".unreadable") }
            return AppSettings()
        }
        return s
    }

    func save() {
        guard Self.persists else { return }
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
