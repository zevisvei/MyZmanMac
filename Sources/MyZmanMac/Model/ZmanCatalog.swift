import Foundation
import KosherSwift

/// One calculation available to the user (the 166 functions MyZman exposes).
struct ZmanDef: Identifiable {
    enum Calc {
        case time((ComplexZmanimCalendar) -> Date?)
        /// A length of time in milliseconds, e.g. a shaah zmanis.
        case duration((ComplexZmanimCalendar) -> Int64)
    }

    let id: String
    let he: String
    let en: String
    let heInfo: String
    let enInfo: String
    let calc: Calc

    /// Which way rounding to the minute is stringent for this zman.
    enum Kind { case earliest, deadline, neutral }

    var kind: Kind {
        let earliest = ["GetMisheyakir", "ZmanGetMisheyakir", "GetSunrise", "VisibleSunrise", "GetSeaLevelSunrise", "GetTzais",
                        "GetMinchaGedola", "GetMinchaKetana", "GetTchilasZmanKidushLevana"]
        // Bein hashmashos (Yereim's and Rabbeinu Tam's) starts it: the end of the day, a deadline (mincha, melacha).
        let deadline = ["GetSofZman", "GetSunset", "VisibleSunset", "GetSeaLevelSunset", "GetCandleLighting", "ZmanGetCandleLighting",
                        "GetBainHasmashosYereim", "GetBainHasmashosRT", "ZmanGetBeinHashmases",
                        "GetSamuchLeMinchaKetana", "GetSolarMidnight"]
        // Alos both starts the day and ends the night, chatzos and plag serve both ways: nearest.
        if earliest.contains(where: id.hasPrefix) { return .earliest }
        if deadline.contains(where: id.hasPrefix) { return .deadline }
        return .neutral
    }

    var isDuration: Bool {
        if case .duration = calc { return true }
        return false
    }
}

enum ZmanCatalog {
    /// MyZman's 166 calculations, then the ones this app adds (ZmanCatalog+Extra).
    static let all = myZman.map(withKosherJavaNote) + extra

    /// Zmanim KosherJava 3 dropped or replaced as too early; kept (users may have them in their list), but labelled.
    private static let superseded: [String: String] = [
        "GetTzaisGeonim3Point65Degrees": "KosherJava 3 הסירה את הזמן הזה: הוא מוקדם מ-13.5 דקות בירושלים בשוויון.",
        "GetTzaisGeonim3Point676Degrees": "KosherJava 3 הסירה את הזמן הזה: הוא מוקדם מ-13.5 דקות בירושלים בשוויון.",
        "GetTzaisGeonim4Point37Degrees": "KosherJava 3 החליפה את הזמן הזה ב-4.42 מעלות (16⅞ דקות), כי 4.37 מוקדם מדי.",
        "GetTzaisGeonim4Point61Degrees": "KosherJava 3 החליפה את הזמן הזה ב-4.66 מעלות (18 דקות), כי 4.61 מוקדם מדי.",
        "GetTzaisGeonim5Point88Degrees": "KosherJava 3 הסירה את הזמן הזה כמוקדם מעט מדי.",
    ]

    private static func withKosherJavaNote(_ d: ZmanDef) -> ZmanDef {
        guard let note = superseded[d.id] else { return d }
        return ZmanDef(id: d.id, he: d.he + " (הוחלף)", en: d.en + " (superseded)", heInfo: d.heInfo + "\n\n⚠︎ " + note,
                       enInfo: d.enInfo + "\n\n⚠︎ Removed/replaced as too early in KosherJava 3.", calc: d.calc)
    }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func def(_ id: String) -> ZmanDef? { byID[id] }

    /// MyZman's default list.
    static let defaults: [ZmanItem] = [
        ("עלות (16.1°)", "GetAlos16Point1Degrees"),
        ("עלות (72)", "GetAlos72"),
        ("משיכיר (50)", "ZmanGetMisheyakir50"),
        ("משיכיר (11°)", "GetMisheyakir11Degrees"),
        ("נץ", "GetSunrise"),
        ("סזק״ש מג״א (16.1°)", "GetSofZmanShmaMGA16Point1Degrees"),
        ("סזק״ש מג״א (72)", "GetSofZmanShmaMGA72Minutes"),
        ("סזק״ש גר״א", "GetSofZmanShmaGRA"),
        ("סז״ת מג״א (72)", "GetSofZmanTfilaMGA72Minutes"),
        ("סז״ת גר״א", "GetSofZmanTfilaGRA"),
        ("חצות", "GetChatzos"),
        ("מנחה גדולה", "GetMinchaGedola"),
        ("פלג המנחה גר״א", "GetPlagHamincha"),
        ("פלג המנחה 8.5°", "ZmanGetPlagHamincha8Point5Degrees"),
        ("שקיעה", "GetSunset"),
        ("צאה״כ (7.08°)", "GetTzaisGeonim7Point083Degrees"),
        ("צאה״כ (8.5°)", "GetTzaisGeonim8Point5Degrees"),
        ("ר״ת (72)", "GetTzais72"),
        ("שעה זמנית גר״א", "GetShaahZmanisGra"),
        ("שעה זמנית מג״א", "GetShaahZmanis72Minutes"),
    ].map { ZmanItem(name: $0.0, defID: $0.1) }
}
