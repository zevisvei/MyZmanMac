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

    var isDuration: Bool {
        if case .duration = calc { return true }
        return false
    }
}

enum ZmanCatalog {
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
