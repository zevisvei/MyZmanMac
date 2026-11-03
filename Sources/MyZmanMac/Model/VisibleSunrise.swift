import Foundation
import KosherSwift

/// Visible-sunrise (and, if present, visible-sunset) times imported from ChaiTables (or similar) tables.
///
/// Supported inputs (all checked against real files from chaitables.com, Nov 2026):
/// - ChaiTables result pages (`ChaiTables.cgi`, "Your Chai Table") saved from the browser as HTML or as a
///   Safari web archive, English or Hebrew, sunrise, sunset or the combined "זריחה ושקיעה הנראים" page,
///   12- or 24-hour times, with or without daylight saving time. These are grids of one Hebrew year:
///   a column per Hebrew month (Tishrei … Elul, Adar I/II in a leap year) and a row per day (1 / א …),
///   Shabbos underlined.
/// - The calendar export (.ics, "ייצא ליומן") of the new ChaiTables site (chai-tables.base44.app), whose events
///   are named "נץ הנראה" / "שקיעה הנראית".
/// - CSV / TSV / plain text with a civil date and a time on each row (e.g. a table copied into Excel and saved as CSV).
struct VisibleSunriseTable: Codable, Hashable {
    var source: String            // e.g. file name / "ChaiTables"
    var locationName: String
    var timeZoneID: String
    var sunrise: [String: String] // "yyyy-MM-dd" -> "HH:mm:ss" local
    var sunset: [String: String]

    // MARK: Lookup

    /// The imported tables by location (`key(latitude:longitude:)`), for the zmanim that read them. Set from the
    /// settings each time a calendar is made (ZmanEngine.calendar), so it always matches the settings in use.
    nonisolated(unsafe) static var imported: [String: VisibleSunriseTable] = [:]

    static func key(latitude: Double, longitude: Double) -> String { "\(latitude)|\(longitude)" }

    /// The imported table for the calendar's location, looked up on its working day.
    static func lookup(_ czc: ComplexZmanimCalendar, _ pick: (VisibleSunriseTable, Date, Calendar) -> Date?) -> Date? {
        let geo = czc.geoLocation
        guard let table = imported[key(latitude: geo.latitude, longitude: geo.longitude)] else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = geo.timeZone
        return pick(table, czc.workingDate, cal)
    }

    func sunrise(on day: Date, calendar: Calendar) -> Date? { time(in: sunrise, on: day, calendar: calendar) }
    func sunset(on day: Date, calendar: Calendar) -> Date? { time(in: sunset, on: day, calendar: calendar) }

    /// First and last date covered ("yyyy-MM-dd"), for showing the user what was imported.
    var dateRange: (first: String, last: String)? {
        let keys = Array(sunrise.keys) + Array(sunset.keys)
        guard let first = keys.min(), let last = keys.max() else { return nil }
        return (first, last)
    }

    /// This table with `other`'s days added; `other` wins on days both cover (import a newer year on top of an older one).
    func merging(_ other: VisibleSunriseTable) -> VisibleSunriseTable {
        var result = self
        result.sunrise.merge(other.sunrise) { _, new in new }
        result.sunset.merge(other.sunset) { _, new in new }
        if !other.locationName.isEmpty { result.locationName = other.locationName }
        result.source = other.source
        return result
    }

    private func time(in table: [String: String], on day: Date, calendar: Calendar) -> Date? {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        guard let y = d.year, let m = d.month, let dd = d.day,
              let value = table[Self.key(y, m, dd)], let t = Self.parseStoredTime(value) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? calendar.timeZone
        return cal.date(from: DateComponents(year: y, month: m, day: dd, hour: t / 3600, minute: t / 60 % 60, second: t % 60))
    }

    private static func parseStoredTime(_ s: String) -> Int? {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2 else { return nil }
        return p[0] * 3600 + p[1] * 60 + (p.count > 2 ? p[2] : 0)
    }

    fileprivate static func key(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }
    fileprivate static func timeString(_ seconds: Int) -> String {
        let s = ((seconds % 86400) + 86400) % 86400
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    // MARK: Errors

    enum ImportError: LocalizedError, Equatable {
        case unreadable
        case excel
        case pdf
        case chaiTablesErrorPage
        case zmanimTable
        case notVisible
        case yearUnknown
        case notRecognized

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "לא ניתן לקרוא את הקובץ. ודא שזהו קובץ טקסט, HTML, CSV או ICS תקין."
            case .excel:
                return "קובצי Excel אינם נתמכים ישירות. פתח את הקובץ ב-Excel ושמור אותו בתבנית CSV (\"שמור בשם\" ← CSV), ואז ייבא את קובץ ה-CSV."
            case .pdf:
                return "קובצי PDF אינם נתמכים. באתר לוחות חי, שמור את דף הלוח עצמו (קובץ ← שמור בשם, או ⌘S) ולא \"הדפס ל-PDF\"."
            case .chaiTablesErrorPage:
                return "הקובץ הוא דף שגיאה של אתר לוחות חי ולא לוח זמנים. חזור לאתר, בחר ישוב ושנה, ונסה לחשב את הלוח שוב."
            case .zmanimTable:
                return "זהו לוח של זמני היום, ולא לוח הנץ הנראה. באתר לוחות חי, בשדה \"בחר את סוג הלוח\" בחר \"זריחה הנראית\" (או \"זריחה ושקיעה הנראים\"), והשאר את \"זמני היום לפי שיטות\" על \"אף אחד\"."
            case .notVisible:
                return "הלוח בקובץ הוא של זריחה/שקיעה מישורית או אסטרונומית, ולא של הנץ הנראה. באתר לוחות חי בחר בסוג הלוח \"זריחה הנראית\"."
            case .yearUnknown:
                return "לא ניתן לקבוע לאיזו שנה עברית שייך הלוח. הוסף את השנה לשם הקובץ (למשל \"ירושלים 5787.html\" או \"ירושלים תשפ״ז.html\") ונסה שוב."
            case .notRecognized:
                return "הקובץ אינו מזוהה כלוח נץ החמה הנראה. ייבא דף לוח שנשמר מאתר לוחות חי (chaitables.com), קובץ יומן (ICS) מהאתר, או קובץ CSV שבכל שורה בו תאריך ושעת הנץ."
            }
        }
    }

    // MARK: Parsing

    static func parse(_ data: Data, fileName: String, timeZoneID: String) throws -> VisibleSunriseTable {
        let tz = TimeZone(identifier: timeZoneID) ?? .current
        let parser = Parser(fileName: fileName, timeZone: tz)
        var source = fileName
        let raw = try parser.decode(data)
        let text = raw.text
        var urlText = raw.url ?? ""

        let result: Parser.Result
        if text.range(of: "BEGIN:VCALENDAR", options: .caseInsensitive) != nil {
            result = try parser.parseICS(text)
        } else if text.range(of: "<table", options: .caseInsensitive) != nil
                    || text.range(of: "<html", options: .caseInsensitive) != nil {
            urlText += " " + text   // "saved from url=…cgi_yrheb=5787…" comment, links
            result = try parser.parseHTML(text, urlText: urlText)
            if text.range(of: "Chai Table", options: .caseInsensitive) != nil || text.contains("לוחות \"חי\"") {
                source = fileName.isEmpty ? "ChaiTables" : "ChaiTables – \(fileName)"
            }
        } else {
            result = try parser.parseDelimited(text)
        }

        guard !result.sunrise.isEmpty || !result.sunset.isEmpty else { throw ImportError.notRecognized }
        var location = result.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if location.isEmpty {
            location = (fileName as NSString).deletingPathExtension
        }
        return VisibleSunriseTable(source: source, locationName: location, timeZoneID: tz.identifier,
                                   sunrise: result.sunrise, sunset: result.sunset)
    }
}

// MARK: - Parser

private struct Parser {
    let fileName: String
    let timeZone: TimeZone

    struct Result {
        var sunrise: [String: String] = [:]
        var sunset: [String: String] = [:]
        var location: String?
    }

    enum Kind { case sunrise, sunset }

    init(fileName: String, timeZone: TimeZone) {
        self.fileName = fileName
        self.timeZone = timeZone
    }

    var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    var hebrew: Calendar {
        var c = Calendar(identifier: .hebrew)
        c.timeZone = timeZone
        return c
    }

    // MARK: Decoding

    func decode(_ data: Data) throws -> (text: String, url: String?) {
        guard !data.isEmpty else { throw VisibleSunriseTable.ImportError.unreadable }
        let head = [UInt8](data.prefix(8))
        if head.starts(with: Array("bplist".utf8)) { return try decodeWebArchive(data) }
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) || head.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {
            throw VisibleSunriseTable.ImportError.excel
        }
        if head.starts(with: Array("%PDF".utf8)) { throw VisibleSunriseTable.ImportError.pdf }
        guard let text = Self.string(from: data, encodingName: nil) else { throw VisibleSunriseTable.ImportError.unreadable }
        return (text, nil)
    }

    /// Safari's default "Save As" format: a binary plist holding the page's HTML and URL.
    private func decodeWebArchive(_ data: Data) throws -> (text: String, url: String?) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let main = plist["WebMainResource"] as? [String: Any],
              let html = main["WebResourceData"] as? Data,
              let text = Self.string(from: html, encodingName: main["WebResourceTextEncodingName"] as? String)
        else { throw VisibleSunriseTable.ImportError.unreadable }
        return (text, main["WebResourceURL"] as? String)
    }

    static func string(from data: Data, encodingName: String?) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: data, encoding: .utf16LittleEndian).map(dropBOM) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16BigEndian).map(dropBOM) }
        let hebrewEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsHebrew.rawValue)))
        var declared: String.Encoding?
        if let name = encodingName?.lowercased() {
            if name.contains("1255") || name.contains("8859-8") { declared = hebrewEncoding }
            if name.contains("utf-16") { declared = .utf16 }
        } else if let sniff = String(data: data.prefix(4096), encoding: .isoLatin1)?.lowercased(),
                  sniff.contains("windows-1255") || sniff.contains("iso-8859-8") {
            declared = hebrewEncoding
        }
        if let declared, let s = String(data: data, encoding: declared) { return dropBOM(s) }
        if let s = String(data: data, encoding: .utf8) { return dropBOM(s) }
        // ChaiTables' zmanim pages are UTF-8 with a few stray Windows-1255 bytes: keep the UTF-8 when it is nearly all valid.
        let lossy = String(decoding: data, as: UTF8.self)
        let invalid = lossy.unicodeScalars.reduce(0) { $1 == "\u{FFFD}" ? $0 + 1 : $0 }
        if invalid * 200 < max(data.count, 1) { return dropBOM(lossy) }
        for enc in [hebrewEncoding, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return dropBOM(s) }
        }
        return nil
    }

    private static func dropBOM(_ s: String) -> String { s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }

    // MARK: Text helpers

    /// Lowercased, without quote marks / geresh / punctuation, single spaces.
    static func normalize(_ s: String) -> String {
        var out = ""
        var lastSpace = true
        for ch in s.lowercased() {
            if "\"'״׳`”“’‘.,:-_()[]".contains(ch) {
                continue
            }
            if ch.isWhitespace {
                if !lastSpace { out.append(" ") }
                lastSpace = true
            } else {
                out.append(ch)
                lastSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func hasAny(_ s: String, _ words: [String]) -> Bool { words.contains { s.contains($0) } }

    static let sunriseWords = ["נץ", "הנץ", "זריחה", "זריחת", "sunrise", "netz", "neitz"]
    static let sunsetWords = ["שקיעה", "שקיעת", "sunset", "shkia", "shekia", "shkiah"]
    static let visibleWords = ["נראה", "נראית", "נראים", "הנראה", "visible", "nirei", "hanirei"]
    static let flatWords = ["מישור", "אסטרונומ", "sea level", "sealevel", "astronomical", "mishor", "geometric"]

    /// Value of Hebrew letters (gematria), ignoring other characters. Used for day labels ("טו") and years ("תשפז").
    static func gematria(_ s: String) -> Int? {
        let values: [Character: Int] = [
            "א": 1, "ב": 2, "ג": 3, "ד": 4, "ה": 5, "ו": 6, "ז": 7, "ח": 8, "ט": 9,
            "י": 10, "כ": 20, "ך": 20, "ל": 30, "מ": 40, "ם": 40, "נ": 50, "ן": 50, "ס": 60, "ע": 70,
            "פ": 80, "ף": 80, "צ": 90, "ץ": 90, "ק": 100, "ר": 200, "ש": 300, "ת": 400,
        ]
        var sum = 0
        var any = false
        for ch in s {
            if let v = values[ch] { sum += v; any = true } else if !"\"'״׳ ”".contains(ch) { return nil }
        }
        return any ? sum : nil
    }

    static func dayNumber(_ label: String) -> Int? {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = Int(t) ?? gematria(t)
        guard let n, (1...30).contains(n) else { return nil }
        return n
    }

    static func firstMatch(_ pattern: String, in s: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    static func lastMatch(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.matches(in: s, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    /// A time of day "6:20:24", "18:53", "6:53 PM" → seconds after midnight, plus whether it said AM / PM.
    static func parseTime(_ s: String) -> (seconds: Int, meridiem: String?)? {
        guard let m = firstMatch(#"(?<![\d:])(\d{1,2}):(\d{2})(?::(\d{2}))?(?![\d:])\s*(am|pm|a\.m\.|p\.m\.|לפנה"צ|אחה"צ|לפנה״צ|אחה״צ)?"#, in: s),
              let h = Int(m[1]), let min = Int(m[2]), h < 24, min < 60 else { return nil }
        let sec = Int(m[3]) ?? 0
        guard sec < 60 else { return nil }
        var hour = h
        let mer = m[4].isEmpty ? nil : m[4].lowercased()
        if let mer {
            let pm = mer.hasPrefix("p") || mer.hasPrefix("אחה")
            if pm, hour < 12 { hour += 12 }
            if !pm, hour == 12 { hour = 0 }
        }
        return (hour * 3600 + min * 60 + sec, mer)
    }

    /// A Hebrew year written in letters after "לשנת" or in the file name ("תשפ״ז", "ה'תשפ\"ז") or as a number (5787).
    static func hebrewYear(in s: String, lettersOnlyAfterLeshnas: Bool) -> Int? {
        if let m = firstMatch(#"(?<!\d)(5[6-9]\d\d)(?!\d)"#, in: s), let y = Int(m[1]) { return y }
        let pattern = lettersOnlyAfterLeshnas
            ? #"לשנת\s+(?:ה['׳]?)?(ת[א-ת"״׳']{1,5})"#
            : #"(?:^|[^א-ת])(?:ה['׳]?)?(ת[א-ת]{0,2}["״׳']?[א-ת])(?![א-ת])"#
        if let m = firstMatch(pattern, in: s), let g = gematria(m[1]) {
            let y = g + 5000
            if (5700...5999).contains(y) { return y }
        }
        return nil
    }

    // MARK: Days

    /// A day's time with seconds after local midnight; kind and DST handling are applied afterwards.
    struct Entry {
        var date: DateComponents   // gregorian y/m/d
        var seconds: Int
        var meridiem: String?
    }

    func key(_ d: DateComponents) -> String? {
        guard let y = d.year, let m = d.month, let dd = d.day else { return nil }
        return VisibleSunriseTable.key(y, m, dd)
    }

    /// Converts 12-hour sunset times to 24-hour, and adds DST when a table was made in standard time only
    /// (ChaiTables' "שעון חורף בלבד" option): such a table has no ~1-hour jump where the zone's clock changes.
    /// `standardTime`: true when the table is known to be without DST, nil to detect it.
    func finalize(_ entries: [Entry], kind: Kind, standardTime: Bool? = nil, into dict: inout [String: String]) {
        guard !entries.isEmpty else { return }
        var fixed = entries
        for i in fixed.indices where fixed[i].meridiem == nil {
            if kind == .sunset, fixed[i].seconds < 12 * 3600 { fixed[i].seconds += 12 * 3600 }
        }
        let cal = gregorian
        func noon(_ d: DateComponents) -> Date? {
            var c = d
            c.hour = 12
            return cal.date(from: c)
        }
        var byKey: [String: (Int, Date)] = [:]
        for e in fixed {
            if let k = key(e.date), let n = noon(e.date) { byKey[k] = (e.seconds, n) }
        }
        var withDST = 0
        var withoutDST = 0
        for (_, (secs, date)) in byKey {
            guard let next = cal.date(byAdding: .day, value: 1, to: date),
                  let nk = key(cal.dateComponents([.year, .month, .day], from: next)),
                  let (nsecs, _) = byKey[nk] else { continue }
            let dstNow = timeZone.daylightSavingTimeOffset(for: date)
            let dstNext = timeZone.daylightSavingTimeOffset(for: next)
            guard dstNow != dstNext else { continue }
            let expected = Int(dstNext - dstNow)
            let jump = nsecs - secs
            if abs(jump - expected) < abs(jump) { withDST += 1 } else { withoutDST += 1 }
        }
        let addDST = standardTime ?? (withoutDST > withDST)
        for (k, (secs, date)) in byKey {
            let s = addDST ? secs + Int(timeZone.daylightSavingTimeOffset(for: date)) : secs
            dict[k] = VisibleSunriseTable.timeString(s)
        }
    }

    // MARK: HTML

    struct Cell {
        var text = ""
        var underlined = false
    }

    struct Table {
        var rows: [[Cell]] = []
        var precedingText = ""
    }

    /// A minimal, forgiving HTML table reader: every <table> with its rows and cells (nested tables are kept
    /// separate), plus the page text that came before it (titles such as "Visible Sunset Times of … for the Year 5787").
    static func tables(in html: String) -> (tables: [Table], text: String) {
        guard let re = try? NSRegularExpression(
            pattern: #"<!--[\s\S]*?-->|<(script|style)\b[^>]*>[\s\S]*?</\1\s*>|<(/?)([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>"#,
            options: [.caseInsensitive]) else { return ([], "") }
        let ns = html as NSString
        var stack: [(table: Table, row: [Cell]?, cell: Cell?, textStart: Int)] = []
        var done: [Table] = []
        var allText = ""
        var lastTableEnd = 0  // in allText characters (unicode scalars count via NSString length)
        var allTextNS: Int { (allText as NSString).length }

        func addText(_ t: String) {
            guard !t.isEmpty else { return }
            allText += t
            if !stack.isEmpty, stack[stack.count - 1].cell != nil { stack[stack.count - 1].cell!.text += t }
        }
        func closeCell() {
            guard !stack.isEmpty, let c = stack[stack.count - 1].cell else { return }
            if stack[stack.count - 1].row == nil { stack[stack.count - 1].row = [] }
            stack[stack.count - 1].row!.append(c)
            stack[stack.count - 1].cell = nil
        }
        func closeRow() {
            closeCell()
            guard !stack.isEmpty, let r = stack[stack.count - 1].row else { return }
            stack[stack.count - 1].table.rows.append(r)
            stack[stack.count - 1].row = nil
        }

        var pos = 0
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                addText(decodeEntities(ns.substring(with: NSRange(location: pos, length: m.range.location - pos))))
            }
            pos = m.range.location + m.range.length
            guard m.range(at: 3).location != NSNotFound else { continue }  // comment / script / style
            let closing = ns.substring(with: m.range(at: 2)) == "/"
            let name = ns.substring(with: m.range(at: 3)).lowercased()
            switch (name, closing) {
            case ("table", false):
                stack.append((Table(), nil, nil, allTextNS))
            case ("table", true):
                guard !stack.isEmpty else { continue }
                closeRow()
                var t = stack.removeLast()
                let start = min(lastTableEnd, t.textStart)
                t.table.precedingText = (allText as NSString).substring(with: NSRange(location: start, length: t.textStart - start))
                if Self.monthHeader(in: t.table) != nil { lastTableEnd = allTextNS }
                done.append(t.table)
                addText(" ")
            case ("tr", false):
                closeRow()
                if !stack.isEmpty { stack[stack.count - 1].row = [] }
            case ("tr", true):
                closeRow()
                addText("\n")
            case ("td", false), ("th", false):
                closeCell()
                if !stack.isEmpty { stack[stack.count - 1].cell = Cell() }
            case ("td", true), ("th", true):
                closeCell()
                addText(" ")
            case ("u", false):
                if !stack.isEmpty, stack[stack.count - 1].cell != nil { stack[stack.count - 1].cell!.underlined = true }
            case ("br", _), ("p", _), ("div", _), ("h1", _), ("h2", _), ("h3", _), ("h4", _), ("li", _):
                addText("\n")
            default:
                break
            }
        }
        if pos < ns.length { addText(decodeEntities(ns.substring(from: pos))) }
        while !stack.isEmpty {
            closeRow()
            done.append(stack.removeLast().table)
        }
        return (done, allText)
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["nbsp": " ", "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "rlm": "", "lrm": "",
                     "ndash": "–", "mdash": "—", "copy": "©"]
        guard let re = try? NSRegularExpression(pattern: #"&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);"#) else { return s }
        let ns = s as NSString
        var out = ""
        var pos = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: pos, length: m.range.location - pos))
            let body = ns.substring(with: m.range(at: 1))
            var rep: String?
            if body.hasPrefix("#") {
                let hex = body.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
                let digits = body.dropFirst(hex ? 2 : 1)
                if let v = UInt32(digits, radix: hex ? 16 : 10), let u = Unicode.Scalar(v) { rep = String(Character(u)) }
            } else {
                rep = named[body.lowercased()]
            }
            out += rep ?? ns.substring(with: m.range)
            pos = m.range.location + m.range.length
        }
        out += ns.substring(from: pos)
        return out
    }

    // Hebrew months by their position in a leap year: Tishrei 0 … Shevat 4, Adar I 5, Adar II 6, Nisan 7 … Elul 12.
    // Plain "Adar" is -1 (Adar of a regular year, or Adar I next to an "Adar II" column).
    static func month(_ raw: String) -> Int? {
        let n = normalize(raw)
        guard !n.isEmpty, n.count <= 16 else { return nil }
        let adarII = ["adar ii", "adar 2", "adar b", "adar beis", "adar sheni", "second adar", "אדר ב", "אדר שני", "אדר ii", "ve adar", "veadar", "ואדר"]
        let adarI = ["adar i", "adar 1", "adar a", "adar aleph", "adar alef", "adar rishon", "first adar", "אדר א", "אדר ראשון", "אדר i"]
        if adarII.contains(n) { return 6 }
        if adarI.contains(n) { return 5 }
        let table: [(Int, [String])] = [
            (0, ["tishrey", "tishrei", "tishri", "tisheri", "תשרי"]),
            (1, ["chesvan", "cheshvan", "heshvan", "marcheshvan", "marchesvan", "mar cheshvan", "חשון", "חשוון", "מרחשון", "מרחשוון", "מר חשון"]),
            (2, ["kislev", "kislef", "כסלו", "כסליו"]),
            (3, ["teves", "tevet", "teveth", "tebeth", "טבת"]),
            (4, ["shvat", "shevat", "shevet", "sh'vat", "שבט"]),
            (-1, ["adar", "אדר"]),
            (7, ["nisan", "nissan", "ניסן"]),
            (8, ["iyar", "iyyar", "iyor", "אייר", "איר"]),
            (9, ["sivan", "סיון", "סיוון"]),
            (10, ["tamuz", "tammuz", "תמוז"]),
            (11, ["av", "menachem av", "אב", "מנחם אב"]),
            (12, ["elul", "אלול"]),
        ]
        for (m, names) in table where names.contains(n) { return m }
        return nil
    }

    /// The row holding Hebrew month names, and which cell index is which month.
    static func monthHeader(in table: Table) -> (row: Int, columns: [Int: Int])? {
        for (i, row) in table.rows.enumerated() where row.count >= 3 {
            var cols: [Int: Int] = [:]
            for (j, c) in row.enumerated() {
                if let m = month(c.text) { cols[j] = m }
            }
            if cols.count >= 3, Set(cols.values).count == cols.count { return (i, cols) }
        }
        return nil
    }

    struct GridCell {
        var month: Int   // see month(_:)
        var day: Int
        var seconds: Int
        var meridiem: String?
        var underlined: Bool
    }

    func parseHTML(_ html: String, urlText: String) throws -> Result {
        let (tables, pageText) = Self.tables(in: html)
        let grids = tables.compactMap { t -> (Table, Int, [Int: Int])? in
            guard let h = Self.monthHeader(in: t) else { return nil }
            return (t, h.row, h.columns)
        }
        /// No usable month grid: maybe a table with a civil date on every row (other sites), else say why not.
        func withoutGrid() throws -> Result {
            let rows = tables.flatMap { $0.rows.map { $0.map(\.text) } }
            if let r = try? parseRows(rows, requireHeader: true), !(r.sunrise.isEmpty && r.sunset.isEmpty) { return r }
            let n = Self.normalize(pageText)
            let isChai = n.contains("chai table") || n.contains("לוחות חי")
            if isChai, Self.hasAny(n, ["שגיעה", "שגיעות", "error"]) { throw VisibleSunriseTable.ImportError.chaiTablesErrorPage }
            if isChai, Self.hasAny(n, ["תאריך לועזי", "civil date", "english date", "secular date", "זמנים אלו מבוססים", "these times are based", "zmanim are based"]) {
                throw VisibleSunriseTable.ImportError.zmanimTable
            }
            throw VisibleSunriseTable.ImportError.notRecognized
        }
        if grids.isEmpty { return try withoutGrid() }

        // Year hints that apply to the whole document: the page's URL (web archive / "saved from url" comment) and the file name.
        let docYear = Self.firstMatch(#"cgi_yrheb=(5\d{3})"#, in: urlText).flatMap { Int($0[1]) }
            ?? Self.hebrewYear(in: fileName, lettersOnlyAfterLeshnas: false)
        let docStandardTimeOnly = Self.firstMatch(#"cgi_DST=OFF"#, in: urlText) != nil

        var result = Result()
        var kindOrdinal: [Kind: Int] = [:]
        var rejectedFlat = false
        for (index, (table, headerRow, columns)) in grids.enumerated() {
            let context = Self.normalize(table.precedingText)
            // Which kind: the last sunrise/sunset word before the table (the title right above it).
            let lastRise = Self.hasAny(context, Self.sunriseWords) ? Self.sunriseWords.compactMap { context.range(of: $0, options: .backwards)?.lowerBound }.max() : nil
            let lastSet = Self.hasAny(context, Self.sunsetWords) ? Self.sunsetWords.compactMap { context.range(of: $0, options: .backwards)?.lowerBound }.max() : nil
            let titleWindow: String
            if let r = lastRise, let s = lastSet { titleWindow = String(context[max(r, s)...]) } else { titleWindow = context }

            // Cells.
            var cells: [GridCell] = []
            var anyAfternoon = false
            for row in table.rows.dropFirst(headerRow + 1) {
                guard let first = row.first, let day = Self.dayNumber(first.text) ?? row.last.flatMap({ Self.dayNumber($0.text) }) else { continue }
                for (j, m) in columns where j < row.count {
                    guard let t = Self.parseTime(row[j].text) else { continue }
                    if t.seconds >= 12 * 3600 { anyAfternoon = true }
                    cells.append(GridCell(month: m, day: day, seconds: t.seconds, meridiem: t.meridiem, underlined: row[j].underlined))
                }
            }
            guard !cells.isEmpty else { continue }

            let kind: Kind
            switch (lastRise, lastSet) {
            case let (r?, s?): kind = s > r ? .sunset : .sunrise
            case (_?, nil): kind = .sunrise
            case (nil, _?): kind = .sunset
            case (nil, nil): kind = anyAfternoon || index > 0 ? .sunset : .sunrise
            }
            // Mishori / astronomical tables aren't visible sunrise.
            let windowAroundTitle = String(titleWindow.prefix(200))
            if Self.hasAny(windowAroundTitle, Self.flatWords), !Self.hasAny(windowAroundTitle, Self.visibleWords) {
                rejectedFlat = true
                continue
            }

            let leap = columns.values.contains(5) || columns.values.contains(6) || columns.count >= 13
            let ordinal = kindOrdinal[kind, default: 0]
            kindOrdinal[kind] = ordinal + 1
            let explicitYear = Self.hebrewYear(in: Self.lastMatch(#"(?:year|לשנת|שנת)\s+\S+"#, in: table.precedingText)?[0] ?? "", lettersOnlyAfterLeshnas: true)
                ?? Self.lastMatch(#"(?<!\d)(5[6-9]\d\d)(?!\d)"#, in: table.precedingText).flatMap { Int($0[1]) }
                ?? docYear.map { $0 + ordinal }
            guard let year = explicitYear ?? inferYear(cells, leap: leap) else { throw VisibleSunriseTable.ImportError.yearUnknown }
            guard let map = hebrewYearMap(year) else { continue }

            var entries: [Entry] = []
            for c in cells {
                let m = Self.position(of: c.month, leapTable: leap, leapYear: map.leap)
                guard let d = map.days[m * 100 + c.day] else { continue }
                entries.append(Entry(date: d, seconds: c.seconds, meridiem: c.meridiem))
            }
            let standardTime: Bool? = docStandardTimeOnly ? true : nil
            if kind == .sunrise {
                finalize(entries, kind: kind, standardTime: standardTime, into: &result.sunrise)
            } else {
                finalize(entries, kind: kind, standardTime: standardTime, into: &result.sunset)
            }
            if result.location == nil { result.location = Self.location(from: table.precedingText) }
        }
        if result.sunrise.isEmpty, result.sunset.isEmpty {
            if rejectedFlat { throw VisibleSunriseTable.ImportError.notVisible }
            return try withoutGrid()
        }
        return result
    }

    /// "…Visible Sunrise Times of Jerusalem for the Year 5787" / "לוח … לזמני הנץ החמה הנראה בירושלים".
    static func location(from text: String) -> String? {
        if let m = lastMatch(#"(?:Times|Region|Sunrise|Sunset) of\s+(.+?)\s+for the Year"#, in: text) {
            return m[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let m = lastMatch(#"(?m)(?:הנראה|הנראית|הנראים)\s+ב([^\n]+?)(?:\s+לשנת.*)?$"#, in: text) {
            return m[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let m = lastMatch(#"לוח\s+"?בכורי יוסף"?\s+ל([^\n]+?)\s+לשנת"#, in: text) {
            return m[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Index in the Hebrew year (0 = Tishrei) of a month column.
    static func position(of month: Int, leapTable: Bool, leapYear: Bool) -> Int {
        if leapYear {
            return month == -1 ? 5 : month
        }
        switch month {
        case -1, 5, 6: return 5
        case 7...: return month - 1
        default: return month
        }
    }

    /// Every day of Hebrew year `year`: (monthIndex * 100 + day) → gregorian date.
    func hebrewYearMap(_ year: Int) -> (days: [Int: DateComponents], leap: Bool)? {
        let heb = hebrew
        let greg = gregorian
        guard let start = heb.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12)) else { return nil }
        var days: [Int: DateComponents] = [:]
        var monthIndex = -1
        var lastMonth: Int?
        var date = start
        for _ in 0..<390 {
            let h = heb.dateComponents([.year, .month, .day], from: date)
            guard h.year == year, let m = h.month, let d = h.day else { break }
            if m != lastMonth {
                monthIndex += 1
                lastMonth = m
            }
            days[monthIndex * 100 + d] = greg.dateComponents([.year, .month, .day], from: date)
            guard let next = greg.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        guard monthIndex >= 11 else { return nil }
        return (days, monthIndex == 12)
    }

    /// For pages that don't print the year (ChaiTables' Hebrew pages): the year around now whose Shabbosim
    /// fall on the underlined cells.
    func inferYear(_ cells: [GridCell], leap: Bool) -> Int? {
        let underlined = cells.filter(\.underlined)
        guard underlined.count >= 4 else { return nil }
        let now = hebrew.component(.year, from: Date())
        let candidates = [now, now + 1, now - 1, now + 2, now - 2, now + 3]
        let greg = gregorian
        for y in candidates {
            guard let map = hebrewYearMap(y), map.leap == leap else { continue }
            let allShabbos = underlined.allSatisfy { c in
                let m = Self.position(of: c.month, leapTable: leap, leapYear: map.leap)
                guard var d = map.days[m * 100 + c.day] else { return false }
                d.hour = 12
                guard let date = greg.date(from: d) else { return false }
                return greg.component(.weekday, from: date) == 7
            }
            if allShabbos { return y }
        }
        return nil
    }

    // MARK: Calendar (.ics)

    func parseICS(_ text: String) throws -> Result {
        // Unfold continuation lines.
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            if let f = line.first, f == " " || f == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else if !line.isEmpty {
                lines.append(line)
            }
        }
        struct Event { var summary = ""; var date: DateComponents?; var seconds = 0 }
        var events: [Event] = []
        var current: Event?
        var calendarName: String?
        for line in lines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" { current = Event(); continue }
            if upper == "END:VEVENT" {
                if let e = current { events.append(e) }
                current = nil
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let prop = name.split(separator: ";").first.map { $0.uppercased() } ?? ""
            if current == nil, prop == "X-WR-CALNAME" { calendarName = value }
            guard current != nil else { continue }
            if prop == "SUMMARY" {
                current?.summary = value.replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            } else if prop == "DTSTART" {
                guard let m = Self.firstMatch(#"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z?)$"#, in: value.trimmingCharacters(in: .whitespaces)),
                      let y = Int(m[1]), let mo = Int(m[2]), let d = Int(m[3]), let h = Int(m[4]), let mi = Int(m[5]) else { continue }
                let s = Int(m[6]) ?? 0
                var sourceTZ: TimeZone? = nil  // nil = floating (already local)
                if m[7] == "Z" {
                    sourceTZ = TimeZone(identifier: "UTC")
                } else if let tzid = Self.firstMatch(#";TZID=("?)([^;:"]+)\1"#, in: name)?[2], let tz = TimeZone(identifier: tzid) {
                    sourceTZ = tz
                }
                if let src = sourceTZ, src.identifier != timeZone.identifier {
                    var c = Calendar(identifier: .gregorian)
                    c.timeZone = src
                    guard let instant = c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)) else { continue }
                    let local = gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
                    current?.date = DateComponents(year: local.year, month: local.month, day: local.day)
                    current?.seconds = (local.hour ?? 0) * 3600 + (local.minute ?? 0) * 60 + (local.second ?? 0)
                } else {
                    current?.date = DateComponents(year: y, month: mo, day: d)
                    current?.seconds = h * 3600 + mi * 60 + s
                }
            }
        }
        var rise: [(Event, Bool)] = []
        var set: [(Event, Bool)] = []
        var sawFlat = false
        for e in events where e.date != nil {
            let n = Self.normalize(e.summary)
            let visible = Self.hasAny(n, Self.visibleWords)
            if Self.hasAny(n, Self.flatWords), !visible { sawFlat = true; continue }
            if Self.hasAny(n, Self.sunsetWords) {
                set.append((e, visible))
            } else if Self.hasAny(n, Self.sunriseWords), !n.contains("סוף") {
                rise.append((e, visible))
            }
        }
        // When the calendar names visible times explicitly, ignore any other sunrise/sunset events in it.
        if rise.contains(where: \.1) { rise = rise.filter(\.1) }
        if set.contains(where: \.1) { set = set.filter(\.1) }
        var result = Result()
        for (e, _) in rise { if let d = e.date, let k = key(d) { result.sunrise[k] = VisibleSunriseTable.timeString(e.seconds) } }
        for (e, _) in set { if let d = e.date, let k = key(d) { result.sunset[k] = VisibleSunriseTable.timeString(e.seconds) } }
        if result.sunrise.isEmpty, result.sunset.isEmpty {
            throw sawFlat ? VisibleSunriseTable.ImportError.notVisible : VisibleSunriseTable.ImportError.notRecognized
        }
        if let name = calendarName {
            let parts = name.components(separatedBy: CharacterSet(charactersIn: "—–-"))
            result.location = parts.count > 1 ? parts.last?.trimmingCharacters(in: .whitespaces) : name
        }
        return result
    }

    // MARK: CSV / TSV / text

    func parseDelimited(_ text: String) throws -> Result {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw VisibleSunriseTable.ImportError.notRecognized }
        let sample = lines.prefix(20).joined(separator: "\n")
        var delimiter: Character = "\t"
        var best = 0
        for candidate: Character in ["\t", ";", ","] {
            let count = sample.reduce(0) { $1 == candidate ? $0 + 1 : $0 }
            if count > best { best = count; delimiter = candidate }
        }
        let rows = lines.map { Self.splitCSV($0, delimiter) }
        return try parseRows(rows, requireHeader: false)
    }

    static func splitCSV(_ line: String, _ delimiter: Character) -> [String] {
        var out: [String] = []
        var field = ""
        var quoted = false
        var it = Array(line)
        var i = 0
        while i < it.count {
            let ch = it[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < it.count, it[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"", field.isEmpty {
                quoted = true
            } else if ch == delimiter {
                out.append(field)
                field = ""
            } else {
                field.append(ch)
            }
            i += 1
        }
        out.append(field)
        it.removeAll()
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A civil date in a cell: 2026-09-12, 12/9/2026, 12.9.2026, 12-09-26 (day first unless that's impossible).
    static func civilDate(_ s: String) -> DateComponents? {
        if let m = firstMatch(#"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#, in: s),
           let y = Int(m[1]), let mo = Int(m[2]), let d = Int(m[3]), (1...12).contains(mo), (1...31).contains(d) {
            return DateComponents(year: y, month: mo, day: d)
        }
        if let m = firstMatch(#"(?<![\d:])(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})(?![\d:])"#, in: s),
           let a = Int(m[1]), let b = Int(m[2]), var y = Int(m[3]) {
            if y < 100 { y += 2000 }
            var (d, mo) = (a, b)
            if mo > 12, d <= 12 { (d, mo) = (b, a) }
            guard (1...12).contains(mo), (1...31).contains(d) else { return nil }
            return DateComponents(year: y, month: mo, day: d)
        }
        return nil
    }

    func parseRows(_ rows: [[String]], requireHeader: Bool) throws -> Result {
        // Header: the last row before the first dated row that names sunrise/sunset columns.
        guard let firstDated = rows.firstIndex(where: { $0.contains { Self.civilDate($0) != nil } }) else {
            throw VisibleSunriseTable.ImportError.notRecognized
        }
        var riseCol: Int?
        var setCol: Int?
        var sawFlat = false
        for header in rows[..<firstDated].reversed() {
            var rises: [(Int, Bool)] = []
            var sets: [(Int, Bool)] = []
            for (j, cell) in header.enumerated() {
                let n = Self.normalize(cell)
                let visible = Self.hasAny(n, Self.visibleWords)
                if Self.hasAny(n, Self.flatWords), !visible { sawFlat = true; continue }
                if Self.hasAny(n, Self.sunsetWords) { sets.append((j, visible)) } else if Self.hasAny(n, Self.sunriseWords), !n.contains("סוף") { rises.append((j, visible)) }
            }
            if !rises.isEmpty || !sets.isEmpty {
                riseCol = (rises.first { $0.1 } ?? rises.first)?.0
                setCol = (sets.first { $0.1 } ?? sets.first)?.0
                break
            }
        }
        if riseCol == nil, setCol == nil {
            if requireHeader || sawFlat {
                throw sawFlat ? VisibleSunriseTable.ImportError.notVisible : VisibleSunriseTable.ImportError.notRecognized
            }
            // No header: a file of just "date, time" — take the first time column as sunrise.
            let row = rows[firstDated]
            riseCol = row.indices.first { Self.civilDate(row[$0]) == nil && Self.parseTime(row[$0]) != nil }
        }
        var rise: [Entry] = []
        var set: [Entry] = []
        for row in rows[firstDated...] {
            guard let date = row.lazy.compactMap(Self.civilDate).first else { continue }
            if let c = riseCol, c < row.count, let t = Self.parseTime(row[c]) { rise.append(Entry(date: date, seconds: t.seconds, meridiem: t.meridiem)) }
            if let c = setCol, c < row.count, let t = Self.parseTime(row[c]) { set.append(Entry(date: date, seconds: t.seconds, meridiem: t.meridiem)) }
        }
        var result = Result()
        finalize(rise, kind: .sunrise, into: &result.sunrise)
        finalize(set, kind: .sunset, into: &result.sunset)
        if result.sunrise.isEmpty, result.sunset.isEmpty { throw VisibleSunriseTable.ImportError.notRecognized }
        return result
    }
}
