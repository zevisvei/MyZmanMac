import Foundation
import KosherSwift

/// Daf Yomi Bavli, ported from KosherJava's YomiCalculator.
/// (KosherSwift's port picks the wrong masechta and crashes near the end of a cycle.)
enum DafYomi {
    private static let masechtos = [
        "ברכות", "שבת", "עירובין", "פסחים", "שקלים", "יומא", "סוכה", "ביצה", "ראש השנה", "תענית",
        "מגילה", "מועד קטן", "חגיגה", "יבמות", "כתובות", "נדרים", "נזיר", "סוטה", "גיטין", "קידושין",
        "בבא קמא", "בבא מציעא", "בבא בתרא", "סנהדרין", "מכות", "שבועות", "עבודה זרה", "הוריות", "זבחים", "מנחות",
        "חולין", "בכורות", "ערכין", "תמורה", "כריתות", "מעילה", "קינים", "תמיד", "מידות", "נדה",
    ]
    private static let blatt = [64, 157, 105, 121, 22, 88, 56, 40, 35, 31, 32, 29, 27, 122, 112, 91, 66, 49, 90, 82,
                                119, 119, 176, 113, 24, 49, 76, 14, 120, 110, 142, 61, 34, 34, 28, 22, 4, 9, 5, 73]

    private static func julianDay(year: Int, month: Int, day: Int) -> Int {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = y / 100
        let b = 2 - a + a / 4
        return Int(floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(day + b) - 1524.5)
    }

    /// Hebrew "masechta daf", or "" before the first cycle.
    static func format(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let jd = julianDay(year: c.year!, month: c.month!, day: c.day!)
        let start = julianDay(year: 1923, month: 9, day: 11)
        let shekalimChange = julianDay(year: 1975, month: 6, day: 24)
        guard jd >= start else { return "" }

        let cycle: Int, dafNo: Int
        if jd >= shekalimChange {
            cycle = 8 + (jd - shekalimChange) / 2711
            dafNo = (jd - shekalimChange) % 2711
        } else {
            cycle = 1 + (jd - start) / 2702
            dafNo = (jd - start) % 2702
        }

        var counts = blatt
        counts[4] = cycle <= 7 ? 13 : 22   // Shekalim was shorter in the early cycles
        var total = 0
        for (i, n) in counts.enumerated() {
            total += n - 1
            if dafNo < total {
                var daf = 1 + n - (total - dafNo)
                switch i {                 // Kinnim, Tamid and Midos don't start at daf 2
                case 36: daf += 21
                case 37: daf += 24
                case 38: daf += 32
                default: break
                }
                return "\(masechtos[i]) \(ZmanEngine.formatter.formatHebrewNumber(number: daf))"
            }
        }
        return ""
    }
}
