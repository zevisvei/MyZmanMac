import Foundation

/// Daily learning cycles, ported from @hebcal/learning (mishnaYomi, nachYomi, rambam1, rambam3, chofetzChaim).
enum DailyLearning {
    enum Cycle: String, CaseIterable, Codable {
        case mishnaYomit, nachYomi, rambam1, rambam3, chofetzChaim
    }

    static func title(_ c: Cycle) -> String {
        switch c {
        case .mishnaYomit: return "משנה יומית"
        case .nachYomi: return "נ״ך יומי"
        case .rambam1: return "רמב״ם – פרק אחד ליום"
        case .rambam3: return "רמב״ם – שלושה פרקים ליום"
        case .chofetzChaim: return "חפץ חיים"
        }
    }

    /// Today's portion in Hebrew, or "" before the cycle began.
    static func portion(_ c: Cycle, on date: Date, calendar: Calendar) -> String {
        let g = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = g.year, let m = g.month, let d = g.day else { return "" }
        let day = absDay(year: y, month: m, day: d)
        switch c {
        case .mishnaYomit:
            guard let r = mishna(day) else { return "" }
            let (a, b) = (r[0], r[1])
            if a.t != b.t {
                return "\(tractates[a.t]) \(heb(a.p)):\(heb(a.m)) – \(tractates[b.t]) \(heb(b.p)):\(heb(b.m))"
            }
            return "\(tractates[a.t]) " + range([a.p, a.m], [b.p, b.m])
        case .nachYomi:
            guard let r = nach(day) else { return "" }
            return "\(nachBooks[r.book]) \(heb(r.chapter))"
        case .rambam1:
            guard let r = rambam1(day) else { return "" }
            return rambamText(r)
        case .rambam3:
            guard let r = rambam3(day) else { return "" }
            return r.map(rambamText).joined(separator: ", ")
        case .chofetzChaim:
            guard let r = chofetzChaim(gregorian: (y, m, d)) else { return "" }
            return chofetzChaimText(r)
        }
    }

    // MARK: - Shared helpers

    private static func heb(_ n: Int) -> String { ZmanEngine.formatter.formatHebrewNumber(number: n) }

    /// "א׳:ג׳–ה׳", "א׳:ז׳–ב׳:ב׳", "ד׳–ה׳", "ג׳".
    private static func range(_ a: [Int], _ b: [Int]?) -> String {
        let join = { (x: [Int]) in x.map(heb).joined(separator: ":") }
        guard let b, b != a else { return join(a) }
        if a.count == 2, b.count == 2, a[0] == b[0] { return join(a) + "–" + heb(b[1]) }
        return join(a) + "–" + join(b)
    }

    /// A hebcal-style reference ("3", "4-5", "1:1-4:8", "2.10") in Hebrew numerals.
    private static func range(_ ref: String, separator: Character) -> String {
        let nums = { (s: Substring) in s.split(separator: separator).compactMap { Int($0) } }
        let sides = ref.split(separator: "-")
        guard let first = sides.first else { return "" }
        return range(nums(first), sides.count > 1 ? nums(sides[1]) : nil)
    }

    /// Days since 31 Dec 1 BCE (R.D.), as hebcal's greg2abs.
    static func absDay(year y: Int, month m: Int, day d: Int) -> Int {
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        let before = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][m - 1] + (m > 2 && leap ? 1 : 0)
        let p = y - 1
        return d + before + 365 * p + p / 4 - p / 100 + p / 400
    }

    // MARK: - Mishna Yomit: two mishnayot a day since 1 Sivan 5707 (20 May 1947)

    private static let tractates = [
        "ברכות", "פאה", "דמאי", "כלאים", "שביעית", "תרומות", "מעשרות", "מעשר שני", "חלה", "ערלה",
        "ביכורים", "שבת", "עירובין", "פסחים", "שקלים", "יומא", "סוכה", "ביצה", "ראש השנה", "תענית",
        "מגילה", "מועד קטן", "חגיגה", "יבמות", "כתובות", "נדרים", "נזיר", "סוטה", "גיטין", "קידושין",
        "בבא קמא", "בבא מציעא", "בבא בתרא", "סנהדרין", "מכות", "שבועות", "עדיות", "עבודה זרה", "אבות", "הוריות",
        "זבחים", "מנחות", "חולין", "בכורות", "ערכין", "תמורה", "כריתות", "מעילה", "תמיד", "מידות",
        "קינים", "כלים", "אהלות", "נגעים", "פרה", "טהרות", "מקואות", "נדה", "מכשירין", "זבים",
        "טבול יום", "ידים", "עוקצים",
    ]
    /// Mishnayot per perek, per tractate.
    private static let mishnayot: [[Int]] = [
        [5,8,6,7,5,8,5,8,5], [6,8,8,11,8,11,8,9], [4,5,6,7,11,12,8], [9,11,7,9,8,9,8,6,10],
        [8,10,10,10,9,6,7,11,9,9], [10,6,9,13,9,6,7,12,7,12,10], [8,8,10,6,8], [7,10,13,12,15],
        [9,8,10,11], [9,17,9], [11,11,12,5], [11,7,6,2,4,10,4,7,7,6,6,6,7,4,3,8,8,3,6,5,3,6,5,5],
        [10,6,9,11,9,10,11,11,4,15], [7,8,8,9,10,6,13,8,11,9], [7,5,4,9,6,6,7,8], [8,7,11,6,7,8,5,9],
        [11,9,15,10,8], [10,10,8,7,7], [9,9,8,9], [7,10,9,8],
        [11,6,6,10], [10,5,9], [8,7,8], [4,10,10,13,6,6,6,6,6,9,7,6,13,9,10,7],
        [10,10,9,12,9,7,10,8,9,6,6,4,11], [4,5,11,8,6,10,9,7,10,8,12], [7,10,7,7,7,11,4,2,5], [9,6,8,5,5,4,8,7,15],
        [6,7,8,9,9,7,9,10,10], [10,10,13,14], [4,6,11,9,7,6,7,7,12,10], [8,11,12,12,11,8,11,9,13,6],
        [6,14,8,9,11,8,4,8,10,8], [6,5,8,5,5,6,11,7,6,6,6], [10,8,16], [7,5,11,13,5,7,8,6],
        [14,10,12,12,7,3,9,7], [9,7,10,12,12], [18,16,18,22,23,11], [5,7,8],
        [4,5,6,6,8,7,6,12,7,8,8,6,8,10], [4,5,7,5,9,7,6,7,9,9,9,5,11], [7,10,7,7,5,7,6,6,8,4,2,5], [7,9,4,10,6,12,7,10,8],
        [4,6,5,4,6,5,5,7,8], [6,3,5,4,6,5,6], [7,6,10,3,8,9], [4,9,8,6,5,6],
        [4,5,9,3,6,3,4], [9,6,8,7,4], [4,5,6], [9,8,8,4,11,4,6,11,8,8,9,8,8,8,6,8,17,9,10,7,3,10,5,17,9,9,12,10,8,4],
        [8,7,7,3,7,7,6,6,16,7,9,8,6,7,10,5,5,10], [6,5,8,11,5,8,5,10,3,10,12,7,12,13], [4,5,11,4,9,5,12,11,9,6,9,11], [9,8,8,13,9,10,9,9,9,8],
        [8,10,4,5,6,11,7,5,7,8], [7,7,7,7,9,14,5,4,11,8], [6,11,8,10,11,8], [6,4,3,7,12],
        [5,8,6,7], [5,4,5,8], [6,10,12],
    ]
    private static let mishnaStart = absDay(year: 1947, month: 5, day: 20)
    private static let mishnaCount = mishnayot.joined().reduce(0, +)   // 4192

    /// (tractate index, perek, mishna) of the day's two mishnayot.
    static func mishna(_ day: Int) -> [(t: Int, p: Int, m: Int)]? {
        guard day >= mishnaStart else { return nil }
        let first = (day - mishnaStart) % (mishnaCount / 2) * 2
        return [first, first + 1].map { n in
            var n = n
            for (t, perakim) in mishnayot.enumerated() {
                for (p, count) in perakim.enumerated() {
                    if n < count { return (t, p + 1, n + 1) }
                    n -= count
                }
            }
            return (0, 1, 1)   // unreachable
        }
    }

    // MARK: - Nach Yomi: a chapter a day since 1 Nov 2007

    private static let nachBooks = [
        "יהושע", "שופטים", "שמואל א׳", "שמואל ב׳", "מלכים א׳", "מלכים ב׳", "ישעיהו", "ירמיהו", "יחזקאל",
        "הושע", "יואל", "עמוס", "עובדיה", "יונה", "מיכה", "נחום", "חבקוק", "צפניה", "חגי", "זכריה", "מלאכי",
        "תהלים", "משלי", "איוב", "שיר השירים", "רות", "איכה", "קהלת", "אסתר", "דניאל", "עזרא", "נחמיה",
        "דברי הימים א׳", "דברי הימים ב׳",
    ]
    private static let nachChapters = [24, 21, 31, 24, 22, 25, 66, 52, 48, 14, 4, 9, 1, 4, 7, 3, 3, 3, 2, 14, 3,
                                       150, 31, 42, 8, 4, 5, 12, 10, 12, 10, 13, 29, 36]
    private static let nachStart = absDay(year: 2007, month: 11, day: 1)

    static func nach(_ day: Int) -> (book: Int, chapter: Int)? {
        guard day >= nachStart else { return nil }
        var n = (day - nachStart) % nachChapters.reduce(0, +)   // 742
        for (book, count) in nachChapters.enumerated() {
            if n < count { return (book, n + 1) }
            n -= count
        }
        return nil
    }

    // MARK: - Rambam: 1 or 3 chapters a day since 27 Nisan 5744 (29 Apr 1984)

    private static let halachot = [
        "מסירת תורה שבעל פה", "מצוות עשה", "מצוות לא תעשה", "תוכן החיבור",
        "הלכות יסודי התורה", "הלכות דעות", "הלכות תלמוד תורה", "הלכות עבודה זרה וחוקות הגויים",
        "הלכות תשובה", "הלכות קריאת שמע", "הלכות תפילה וברכת כהנים", "הלכות תפילין ומזוזה וספר תורה",
        "הלכות ציצית", "הלכות ברכות", "הלכות מילה", "סדר התפילה",
        "הלכות שבת", "הלכות עירובין", "הלכות שביתת עשור", "הלכות שביתת יום טוב",
        "הלכות חמץ ומצה", "הלכות שופר וסוכה ולולב", "הלכות שקלים", "הלכות קידוש החודש",
        "הלכות תעניות", "הלכות מגילה וחנוכה", "הלכות אישות", "הלכות גירושין",
        "הלכות יבום וחליצה", "הלכות נערה בתולה", "הלכות סוטה", "הלכות איסורי ביאה",
        "הלכות מאכלות אסורות", "הלכות שחיטה", "הלכות שבועות", "הלכות נדרים",
        "הלכות נזירות", "הלכות ערכים וחרמין", "הלכות כלאים", "הלכות מתנות עניים",
        "הלכות תרומות", "הלכות מעשרות", "הלכות מעשר שני ונטע רבעי", "הלכות ביכורים ושאר מתנות כהונה שבגבולין",
        "הלכות שמיטה ויובל", "הלכות בית הבחירה", "הלכות כלי המקדש והעובדין בו", "הלכות ביאת מקדש",
        "הלכות איסורי המזבח", "הלכות מעשה הקרבנות", "הלכות תמידים ומוספין", "הלכות פסולי המוקדשין",
        "הלכות עבודת יום הכפורים", "הלכות מעילה", "הלכות קרבן פסח", "הלכות חגיגה",
        "הלכות בכורות", "הלכות שגגות", "הלכות מחוסרי כפרה", "הלכות תמורה",
        "הלכות טומאת מת", "הלכות פרה אדומה", "הלכות טומאת צרעת", "הלכות מטמאי משכב ומושב",
        "הלכות שאר אבות הטומאות", "הלכות טומאת אוכלים", "הלכות כלים", "הלכות מקואות",
        "הלכות נזקי ממון", "הלכות גניבה", "הלכות גזילה ואבידה", "הלכות חובל ומזיק",
        "הלכות רוצח ושמירת נפש", "הלכות מכירה", "הלכות זכייה ומתנה", "הלכות שכנים",
        "הלכות שלוחין ושותפין", "הלכות עבדים", "הלכות שכירות", "הלכות שאלה ופיקדון",
        "הלכות מלווה ולווה", "הלכות טוען ונטען", "הלכות נחלות", "הלכות סנהדרין והעונשין המסורין להם",
        "הלכות עדות", "הלכות ממרים", "הלכות אבל", "הלכות מלכים ומלחמות",
    ]
    private static let perakim = [
        3, 3, 3, 3, 10, 7, 7, 12, 10, 4, 15, 10, 3, 11, 3, 4, 30, 8, 3, 8,
        9, 8, 4, 19, 5, 4, 25, 13, 8, 3, 4, 22, 17, 14, 12, 13, 10, 8, 10, 10,
        15, 14, 11, 12, 13, 8, 10, 9, 7, 19, 10, 19, 5, 8, 10, 3, 8, 15, 5, 4,
        25, 15, 16, 13, 20, 16, 28, 11, 14, 9, 18, 8, 13, 30, 12, 14, 10, 9, 13, 8,
        27, 16, 11, 26, 22, 7, 14, 12,
    ]
    /// The introduction's first four sections are learned as ranges, not chapters.
    private static let introRanges = [
        ["1-21", "22-33", "34-45"],             // מסירת תורה שבעל פה
        ["1-83", "84-166", "167-248"],          // מצוות עשה
        ["1-122", "123-245", "246-365"],        // מצוות לא תעשה
        ["1:1-4:8", "5:1-9:9", "10:1-14:10"],   // תוכן החיבור
    ]
    private static let orderOfPrayer = 15, chametz = 20
    private static let rambamStart = absDay(year: 1984, month: 4, day: 29)
    private static let rambamDays = perakim.reduce(0, +)   // 1017

    /// A reading: halachot index and a hebcal-style perek reference ("3", "4-5", "1-21").
    typealias RambamReading = (h: Int, perek: String)

    private static func chapter(_ idx: Int, _ counts: [Int]) -> (h: Int, chap: Int) {
        var n = idx
        for (h, count) in counts.enumerated() {
            if n < count { return (h, n + 1) }
            n -= count
        }
        return (counts.count - 1, counts[counts.count - 1])   // unreachable
    }

    private static func reading(_ idx: Int, _ counts: [Int]) -> RambamReading {
        let (h, chap) = chapter(idx, counts)
        return (h, h < 4 ? introRanges[h][chap - 1] : String(chap))
    }

    static func rambam1(_ day: Int) -> RambamReading? {
        guard day >= rambamStart else { return nil }
        var r = reading((day - rambamStart) % rambamDays, perakim)
        if r.h == orderOfPrayer && r.perek == "4" { r.perek = "4-5" }
        return r
    }

    static func rambam3(_ day: Int) -> [RambamReading]? {
        guard day >= rambamStart else { return nil }
        var counts = perakim
        counts[orderOfPrayer] = 5   // an extra day for סדר התפילה
        counts[chametz] = 8         // the last two chapters of חמץ ומצה on one day
        let idx = (day - rambamStart) % (rambamDays / 3) * 3
        var r = (0..<3).map { reading(idx + $0, counts) }
        if r[0].h == chametz && r[0].perek == "8" { r[0].perek = "8-9" }
        // Collapse adjacent chapters of the same halachot into a range.
        func combine(_ a: RambamReading, _ b: RambamReading) -> RambamReading {
            let from = a.perek.split(separator: "-")[0]
            let to = b.perek.split(separator: "-").last!
            return (a.h, "\(from)-\(to)")
        }
        if r[0].h == r[1].h && r[1].h == r[2].h { return [combine(r[0], r[2])] }
        if r[0].h == r[1].h { r = [combine(r[0], r[1]), r[2]] }
        else if r[1].h == r[2].h { r = [r[0], combine(r[1], r[2])] }
        return r
    }

    private static func rambamText(_ r: RambamReading) -> String {
        let text = range(r.perek, separator: ":")
        if r.h < 4 { return "\(halachot[r.h]) \(text)" }
        return "\(halachot[r.h]) \(r.perek.contains("-") ? "פרקים" : "פרק") \(text)"
    }

    // MARK: - Chofetz Chaim: a fixed schedule by Hebrew date, three times a year, since 1 Tishrei 5634

    private static let ccSections = ["הקדמה", "פתיחה", "לאווין", "עשיין", "ארורין", "הלכות לשון הרע", "הלכות רכילות", "ציורים"]
    /// "section|begin|end[|text begin|text end]", one per day of a column (see `chofetzChaim`).
    private static let ccSimple = [
        "0|1|4|ברוך ד׳|שכינתו בתוכנו", "0|5|10|וכאשר נחפשה|מגדל העון", "0|11|16|ונראה פשוט|לאין שעור", "0|17|22|ואחשבה|בפנים הספר",
        "0|23|27|על כן|צד הדי", "0|28|33,34|ואחלה להקורא|במהרה בימינו אמן", "0|29|32|ואל יפלא|לעון כלל",
        "1|1|4", "1|5|11", "2|1|2", "2|3|4", "2|5|6", "2|7|9", "2|10|11", "2|12|13", "2|14|15", "2|16|17",
        "3|1|2", "3|3|4", "3|5|6", "3|7|8", "3|9|10", "3|11|12", "3|13|14", "4||",
        "5|1.1|1.2", "5|1.3|1.4", "5|1.5|1.6", "5|1.7|1.9", "5|2.1|2.2", "5|2.3|2.4", "5|2.5|2.6", "5|2.7|2.8",
        "5|2.9|2.10", "5|2.11|", "5|2.12|2.13", "5|3.1|3.2", "5|3.3|3.4", "5|3.5|3.6", "5|3.7|3.8", "5|4.1|4.2",
        "5|4.3|4.4", "5|4.5|4.6", "5|4.7|4.8", "5|4.9|4.10", "5|4.11|", "5|4.12|5.1", "5|5.2|5.4", "5|5.5|5.6",
        "5|5.7|5.8", "5|6.1|6.2", "5|6.3|6.4", "5|6.5|6.6", "5|6.7|6.8", "5|6.9|6.10", "5|6.11|6.12", "5|7.1|7.2",
        "5|7.3|7.4", "5|7.5|7.6", "5|7.7|7.8", "5|7.9|", "5|7.10|7.12", "5|7.13|7.14", "5|8.1|8.2", "5|8.3|8.4",
        "5|8.5|8.7", "5|8.8|8.9", "5|8.10|8.11", "5|8.12|", "5|8.13|8.14", "5|9.1|9.2", "5|9.3|9.4", "5|9.5|9.6",
        "5|10.1|10.2", "5|10.3|10.4", "5|10.5|10.6", "5|10.7|10.8", "5|10.9|10.10", "5|10.11|10.12", "5|10.13|10.14",
        "5|10.15|10.16", "5|10.17|",
        "6|1.1|1.3", "6|1.4|1.5", "6|1.6|1.7", "6|1.8|1.9", "6|1.10|1.11", "6|2.1|2.2", "6|2.3|2.4", "6|3.1|",
        "6|3.2|3.4", "6|4.1|4.3", "6|5.1|5.2", "6|5.3|5.4", "6|5.5|", "6|5.6|5.7", "6|6.1|6.2", "6|6.3|6.4",
        "6|6.5|6.7", "6|6.8|6.10", "6|7.1|", "6|7.2|", "6|7.3|7.4", "6|7.5|", "6|8.1|8.3", "6|8.4|8.5",
        "6|9.1|9.2", "6|9.3|9.4", "6|9.5|9.6", "6|9.7|9.9", "6|9.10|", "6|9.11|9.12", "6|9.13|", "6|9.14|9.15",
        "7|1|3", "7|4|5", "7|6|7", "7|8|9", "7|10|11",
    ]
    private static let ccLeap = Array(ccSimple[0..<46]) + [
        "5|4.12|4.12", "5|5.1|5.1", "5|5.2|5.2", "5|5.3|5.4", "5|5.5|5.6", "5|5.7|5.8", "5|6.1|6.2", "5|6.3|6.4",
        "5|6.5|6.6", "5|6.7|6.8", "5|6.9|6.10", "5|6.11|6.12", "5|7.1|7.2", "5|7.3|7.4", "5|7.5|7.6", "5|7.7|7.8",
        "5|7.9|", "5|7.10|", "5|7.11|7.12", "5|7.13|7.14", "5|8.1|8.2", "5|8.3|8.4", "5|8.5|8.5", "5|8.6|8.7",
        "5|8.8|8.9", "5|8.10|8.11", "5|8.12|", "5|8.13|8.14", "5|9.1|9.2", "5|9.3|9.4", "5|9.5|9.6", "5|10.1|10.2",
        "5|10.3|10.3", "5|10.4|10.4", "5|10.5|10.6", "5|10.7|10.8", "5|10.9|10.10", "5|10.11|10.12", "5|10.13|10.13",
        "5|10.14|10.14", "5|10.15|10.16", "5|10.17|",
        "6|1.1|1.2", "6|1.3|1.3", "6|1.4|1.5", "6|1.6|1.7", "6|1.8|1.9", "6|1.10|1.11", "6|2.1|2.2", "6|2.3|2.4",
        "6|3.1|", "6|3.2|3.4", "6|4.1|4.3", "6|5.1|5.2", "6|5.3|5.4", "6|5.5|", "6|5.6|5.7", "6|6.1|6.2",
        "6|6.3|6.4", "6|6.5|6.6", "6|6.7|6.7", "6|6.8|6.9", "6|6.10|", "6|7.1|", "6|7.2|", "6|7.3|7.4",
        "6|7.5|", "6|8.1|8.3", "6|8.4|8.5", "6|9.1|9.2", "6|9.3|9.4", "6|9.5|9.6", "6|9.7|9.9", "6|9.10|",
        "6|9.11|9.12", "6|9.13|", "6|9.14|9.15",
        "7|1|2", "7|3|3", "7|4|5", "7|6|7", "7|8|9", "7|10|11",
    ]
    private static let ccStart = absDay(year: 1873, month: 9, day: 22)   // 1 Tishrei 5634

    struct ChofetzChaimReading: Equatable {
        var section: Int, begin: String, end: String, textBegin = "", textEnd = ""
    }

    private static func ccEntry(_ s: String) -> ChofetzChaimReading {
        let f = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return ChofetzChaimReading(section: Int(f[0])!, begin: f[1], end: f[2],
                                   textBegin: f.count > 3 ? f[3] : "", textEnd: f.count > 4 ? f[4] : "")
    }

    static func chofetzChaim(gregorian g: (y: Int, m: Int, d: Int)) -> ChofetzChaimReading? {
        guard absDay(year: g.y, month: g.m, day: g.d) >= ccStart else { return nil }
        let utc = TimeZone(identifier: "UTC")!
        var greg = Calendar(identifier: .gregorian), hebrew = Calendar(identifier: .hebrew)
        greg.timeZone = utc
        hebrew.timeZone = utc
        guard let noon = greg.date(from: DateComponents(year: g.y, month: g.m, day: g.d, hour: 12)) else { return nil }
        // Foundation's months: 1 Tishrei … 5 Shevat, 6 Adar I (leap years only), 7 Adar / Adar II, 8 Nisan … 13 Elul.
        let h = hebrew.dateComponents([.year, .month, .day], from: noon)
        guard let year = h.year, let month = h.month, let day = h.day,
              let roshHashana = hebrew.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12)),
              let nextRoshHashana = hebrew.date(from: DateComponents(year: year + 1, month: 1, day: 1, hour: 12)),
              let yearLength = greg.dateComponents([.day], from: roshHashana, to: nextRoshHashana).day
        else { return nil }
        let leap = (7 * year + 1) % 19 < 7

        // Day of the year as if Cheshvan and Kislev were both 30 days; short months fold the 30th into the 29th.
        let nominal = [30, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29]
        let offset = (1..<month).filter { $0 != 6 || leap }.map { nominal[$0 - 1] }.reduce(0, +) + day - 1
        // The book is learned three times a year, in columns starting
        // 1 Tishrei, 1 Shevat, 1 Sivan (or 1 Tishrei, 11 Shevat, 20 Iyar in a leap year).
        let table = leap ? ccLeap : ccSimple
        let starts = leap ? [0, 129, 257] : [0, 119, 237]
        let column = starts.lastIndex { $0 <= offset }!
        func lookup(_ pos: Int) -> ChofetzChaimReading? {
            // The first column splits the Hakdamah's last day (6–7 Tishrei); the others learn it on one day.
            if column == 0 || pos < 5 { return pos < table.count ? ccEntry(table[pos]) : nil }
            if pos > 5 { return pos + 1 < table.count ? ccEntry(table[pos + 1]) : nil }
            var r = ccEntry(table[5])
            let next = ccEntry(table[6])
            r.end = String(r.end.split(separator: ",").last!)
            r.textEnd = next.textEnd
            return r
        }
        let pos = offset - starts[column]
        guard var r = lookup(pos) else { return nil }
        let shortCheshvan = month == 2 && yearLength % 10 != 5
        let shortKislev = month == 3 && yearLength % 10 == 3
        if day == 29 && (shortCheshvan || shortKislev), let extra = lookup(pos + 1) {
            r.end = extra.end.isEmpty ? extra.begin : extra.end
        }
        return r
    }

    private static func chofetzChaimText(_ r: ChofetzChaimReading) -> String {
        let name = ccSections[r.section]
        if !r.textBegin.isEmpty { return "\(name): \(r.textBegin) – \(r.textEnd)" }
        if r.begin.isEmpty { return name }
        let ref = r.end.isEmpty || r.end.contains(",") ? r.begin : "\(r.begin)-\(r.end)"
        return "\(name) " + range(ref, separator: ".")
    }
}
