import Foundation
import KosherSwift

struct ComputedZman: Identifiable, Hashable {
    let item: ZmanItem
    let time: Date?
    let duration: TimeInterval?

    var id: UUID { item.id }
}

struct DayInfo: Hashable {
    var hebrewDate: String       // י״א חשון תשפ״ז
    var hebrewDayMonth: String   // י״א חשון
    var hebrewDayNumber: String  // י״א
    var weekday: String
    var parsha: String
    var events: [String]         // holidays, rosh chodesh, omer, special shabbos
    var dafYomi: String
    var isShabbosOrYomTov: Bool
}

enum Disclaimer {
    static let short = "הזמנים מחושבים אסטרונומית ועלולים לסטות בכמה דקות. אין לסמוך עליהם להלכה למעשה."
    static let full = """
    הזמנים מחושבים לפי נוסחאות אסטרונומיות (KosherJava) ואינם לוקחים בחשבון תנאי שבירת אור, גובה ותוואי שטח מדויקים. \
    ייתכנו סטיות של מספר דקות, ורשימת המיקומים לא נבדקה.

    אין לסמוך על הזמנים להלכה למעשה – יש לבדוק מול לוח מוסמך או רב.
    """
}

enum ZmanEngine {
    static func gregorian(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        cal.locale = Locale(identifier: "he_IL")
        return cal
    }

    /// Noon of the given day in the location's time zone, so the calculations land on the right civil day.
    static func noon(of day: Date, in tz: TimeZone) -> Date {
        let cal = gregorian(tz)
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    static func calendar(for day: Date, settings: AppSettings) -> ComplexZmanimCalendar {
        let loc = settings.location
        let czc = ComplexZmanimCalendar(location: loc.geoLocation())
        czc.workingDate = noon(of: day, in: loc.timeZone)
        czc.useElevation = settings.useElevation
        if settings.useUSNO { czc.astronomicalCalculator = SunTimesCalculator() }
        return czc
    }

    static func compute(_ def: ZmanDef, on czc: ComplexZmanimCalendar) -> (Date?, TimeInterval?) {
        switch def.calc {
        case .time(let f): return (f(czc), nil)
        case .duration(let f):
            let ms = f(czc)
            return (nil, ms > 0 && ms < 86_400_000 ? TimeInterval(ms) / 1000 : nil)
        }
    }

    static func zmanim(on day: Date, settings: AppSettings) -> [ComputedZman] {
        let czc = calendar(for: day, settings: settings)
        return settings.zmanim.map { item in
            guard let def = item.def else { return ComputedZman(item: item, time: nil, duration: nil) }
            let (t, d) = compute(def, on: czc)
            return ComputedZman(item: item, time: t, duration: d)
        }
    }

    static func time(of item: ZmanItem, on day: Date, settings: AppSettings) -> Date? {
        guard let def = item.def else { return nil }
        return compute(def, on: calendar(for: day, settings: settings)).0
    }

    static func sunset(on day: Date, settings: AppSettings) -> Date? {
        calendar(for: day, settings: settings).getSunset()
    }

    static func jewishCalendar(for day: Date, settings: AppSettings) -> JewishCalendar {
        let tz = settings.location.timeZone
        let jc = JewishCalendar(workingDate: noon(of: day, in: tz), timezone: tz,
                                inIsrael: settings.inIsrael, useModernHolidays: settings.useModernHolidays)
        return jc
    }

    static let formatter: HebrewDateFormatter = {
        let f = HebrewDateFormatter()
        f.hebrewFormat = true
        f.useGershGershayim = true
        return f
    }()

    static func dayInfo(for day: Date, settings: AppSettings) -> DayInfo {
        let jc = jewishCalendar(for: day, settings: settings)
        let f = formatter
        let dayNum = f.formatHebrewNumber(number: jc.getJewishDayOfMonth())
        let month = f.formatMonth(jewishCalendar: jc)
        let year = f.formatHebrewNumber(number: jc.getJewishYear() % 1000 == 0 ? jc.getJewishYear() : jc.getJewishYear() % 1000)

        var events: [String] = []
        for s in [f.formatYomTov(jewishCalendar: jc), f.formatRoshChodesh(jewishCalendar: jc),
                  f.formatOmer(jewishCalendar: jc), f.formatSpecialParsha(jewishCalendar: jc)] where !s.isEmpty {
            if !events.contains(s) { events.append(s) }
        }
        if jc.getDayOfWeek() == 7, jc.isShabbosMevorchim() { events.append("שבת מברכים") }

        // On Shabbos itself use that day's parsha; getUpcomingParshah() would give next week's.
        let today = jc.getParshah()
        let parsha = f.formatParsha(parsha: jc.getDayOfWeek() == 7 && today != .NONE ? today : jc.getUpcomingParshah())
        let daf = DafYomi.format(day, calendar: gregorian(settings.location.timeZone))

        let weekday = gregorian(settings.location.timeZone)
            .weekdaySymbols[jc.getDayOfWeek() - 1]

        return DayInfo(hebrewDate: "\(dayNum) \(month) \(year)",
                       hebrewDayMonth: "\(dayNum) \(month)",
                       hebrewDayNumber: dayNum,
                       weekday: weekday,
                       parsha: parsha.isEmpty ? "" : "פרשת \(parsha)",
                       events: events,
                       dafYomi: daf,
                       isShabbosOrYomTov: jc.getDayOfWeek() == 7 || jc.isYomTovAssurBemelacha())
    }
}

/// Time/duration formatting in the selected location's time zone.
struct ZmanFormat {
    let tz: TimeZone
    let use24h: Bool
    let seconds: Bool

    init(_ s: AppSettings) {
        tz = s.location.timeZone
        use24h = s.use24h
        seconds = s.showSeconds
    }

    private static var cache: [String: DateFormatter] = [:]

    private func formatter(_ pattern: String, locale: String = "en_US_POSIX") -> DateFormatter {
        let key = "\(tz.identifier)|\(pattern)|\(locale)"
        if let f = Self.cache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.timeZone = tz
        f.dateFormat = pattern
        Self.cache[key] = f
        return f
    }

    func time(_ d: Date?) -> String {
        guard let d else { return "—" }
        let p = (use24h ? "HH:mm" : "h:mm") + (seconds ? ":ss" : "")
        return formatter(p).string(from: d)
    }

    func gregorianDate(_ d: Date, style: String = "d/M/yyyy") -> String {
        formatter(style).string(from: d)
    }

    /// The user's own language (System Settings ← Language & Region), with their region's conventions.
    static let userLocale: Locale = {
        let lang = Locale.preferredLanguages.first ?? "en"
        let region = Locale.current.region?.identifier
        return Locale(identifier: region.map { "\(Locale(identifier: lang).language.languageCode?.identifier ?? lang)_\($0)" } ?? lang)
    }()

    /// Gregorian date with month/day names in the user's language, e.g. template "EEEEdMMMMyyyy".
    func localizedDate(_ d: Date, template: String) -> String {
        let pattern = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: Self.userLocale) ?? template
        return formatter(pattern, locale: Self.userLocale.identifier).string(from: d)
    }

    static func duration(_ t: TimeInterval?, seconds: Bool = true) -> String {
        guard let t else { return "—" }
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if seconds { return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s) }
        return String(format: "%d:%02d", h, m)
    }

    /// "1:05" style countdown, always with seconds below one hour.
    static func countdown(_ t: TimeInterval, showSeconds: Bool) -> String {
        let total = max(0, Int(t))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if showSeconds || h == 0 && m < 10 {
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        }
        return String(format: "%d:%02d", h, m)
    }
}
