import Foundation
import KosherSwift

/// The haftara of Shabbos, Yom Tov and fast days, Ashkenaz or Sefard, Israel or the diaspora.
/// Follows @hebcal/leyning, except that Shabbos Rosh Chodesh Elul reads עניה סוערה (שו״ע תכ״ה:א׳)
/// and Yom Ha'atzmaut has no haftara.
enum Haftara {
    enum Book: String {
        case yehoshua = "יהושע", shoftim = "שופטים", shmuel1 = "שמואל א׳", shmuel2 = "שמואל ב׳"
        case melachim1 = "מלכים א׳", melachim2 = "מלכים ב׳", yeshayahu = "ישעיהו", yirmiyahu = "ירמיהו"
        case yechezkel = "יחזקאל", hoshea = "הושע", yoel = "יואל", amos = "עמוס", ovadia = "עובדיה"
        case yona = "יונה", micha = "מיכה", chavakuk = "חבקוק", zecharia = "זכריה", malachi = "מלאכי"
    }

    /// A run of verses, `chapter:verse`–`chapter:verse`.
    struct Part {
        let book: Book
        let from: (Int, Int)
        let to: (Int, Int)
    }

    private static func p(_ b: Book, _ c1: Int, _ v1: Int, _ c2: Int, _ v2: Int) -> Part { Part(book: b, from: (c1, v1), to: (c2, v2)) }
    private static func p(_ b: Book, _ c: Int, _ v1: Int, _ v2: Int) -> Part { p(b, c, v1, c, v2) }

    // MARK: Parshiyos

    /// Ashkenaz, and Sefard where it differs. A combined parsha reads the second one's
    /// (אחרי מות–קדושים reads אחרי מות's, נצבים–וילך reads נצבים's).
    private static let parshiyos: [JewishCalendar.Parsha: (ash: [Part], sef: [Part]?)] = [
        .BERESHIS: ([p(.yeshayahu, 42, 5, 43, 10)], [p(.yeshayahu, 42, 5, 21)]),
        .NOACH: ([p(.yeshayahu, 54, 1, 55, 5)], [p(.yeshayahu, 54, 1, 10)]),
        .LECH_LECHA: ([p(.yeshayahu, 40, 27, 41, 16)], nil),
        .VAYERA: ([p(.melachim2, 4, 1, 37)], [p(.melachim2, 4, 1, 23)]),
        .CHAYEI_SARA: ([p(.melachim1, 1, 1, 31)], nil),
        .TOLDOS: ([p(.malachi, 1, 1, 2, 7)], nil),
        .VAYETZEI: ([p(.hoshea, 12, 13, 14, 10)], [p(.hoshea, 11, 7, 12, 12)]),
        .VAYISHLACH: ([p(.ovadia, 1, 1, 21)], nil),
        .VAYESHEV: ([p(.amos, 2, 6, 3, 8)], nil),
        .MIKETZ: ([p(.melachim1, 3, 15, 4, 1)], nil),
        .VAYIGASH: ([p(.yechezkel, 37, 15, 28)], nil),
        .VAYECHI: ([p(.melachim1, 2, 1, 12)], nil),
        .SHEMOS: ([p(.yeshayahu, 27, 6, 28, 13), p(.yeshayahu, 29, 22, 23)], [p(.yirmiyahu, 1, 1, 2, 3)]),
        .VAERA: ([p(.yechezkel, 28, 25, 29, 21)], nil),
        .BO: ([p(.yirmiyahu, 46, 13, 28)], nil),
        .BESHALACH: ([p(.shoftim, 4, 4, 5, 31)], [p(.shoftim, 5, 1, 31)]),
        .YISRO: ([p(.yeshayahu, 6, 1, 7, 6), p(.yeshayahu, 9, 5, 6)], [p(.yeshayahu, 6, 1, 13)]),
        .MISHPATIM: ([p(.yirmiyahu, 34, 8, 22), p(.yirmiyahu, 33, 25, 26)], nil),
        .TERUMAH: ([p(.melachim1, 5, 26, 6, 13)], nil),
        .TETZAVEH: ([p(.yechezkel, 43, 10, 27)], nil),
        .KI_SISA: ([p(.melachim1, 18, 1, 39)], [p(.melachim1, 18, 20, 39)]),
        .VAYAKHEL: ([p(.melachim1, 7, 40, 50)], [p(.melachim1, 7, 13, 26)]),
        .PEKUDEI: ([p(.melachim1, 7, 51, 8, 21)], [p(.melachim1, 7, 40, 50)]),
        .VAYIKRA: ([p(.yeshayahu, 43, 21, 44, 23)], nil),
        .TZAV: ([p(.yirmiyahu, 7, 21, 8, 3), p(.yirmiyahu, 9, 22, 23)], nil),
        .SHMINI: ([p(.shmuel2, 6, 1, 7, 17)], [p(.shmuel2, 6, 1, 19)]),
        .TAZRIA: ([p(.melachim2, 4, 42, 5, 19)], nil),
        .METZORA: ([p(.melachim2, 7, 3, 20)], nil),
        .ACHREI_MOS: ([p(.amos, 9, 7, 15)], [p(.yechezkel, 22, 1, 16)]),
        .KEDOSHIM: ([p(.yechezkel, 22, 1, 19)], [p(.yechezkel, 20, 2, 20)]),
        .EMOR: ([p(.yechezkel, 44, 15, 31)], nil),
        .BEHAR: ([p(.yirmiyahu, 32, 6, 27)], nil),
        .BECHUKOSAI: ([p(.yirmiyahu, 16, 19, 17, 14)], nil),
        .BAMIDBAR: ([p(.hoshea, 2, 1, 22)], nil),
        .NASSO: ([p(.shoftim, 13, 2, 25)], nil),
        .BEHAALOSCHA: ([p(.zecharia, 2, 14, 4, 7)], nil),
        .SHLACH: ([p(.yehoshua, 2, 1, 24)], nil),
        .KORACH: ([p(.shmuel1, 11, 14, 12, 22)], nil),
        .CHUKAS: ([p(.shoftim, 11, 1, 33)], nil),
        .BALAK: ([p(.micha, 5, 6, 6, 8)], nil),
        .PINCHAS: ([p(.melachim1, 18, 46, 19, 21)], nil),
        .MATOS: ([p(.yirmiyahu, 1, 1, 2, 3)], nil),
        .MASEI: ([p(.yirmiyahu, 2, 4, 28), p(.yirmiyahu, 3, 4, 4)], [p(.yirmiyahu, 2, 4, 28), p(.yirmiyahu, 4, 1, 2)]),
        .DEVARIM: ([p(.yeshayahu, 1, 1, 27)], nil),
        .VAESCHANAN: ([p(.yeshayahu, 40, 1, 26)], nil),
        .EIKEV: ([p(.yeshayahu, 49, 14, 51, 3)], nil),
        .REEH: ([p(.yeshayahu, 54, 11, 55, 5)], nil),
        .SHOFTIM: ([p(.yeshayahu, 51, 12, 52, 12)], nil),
        .KI_SEITZEI: ([p(.yeshayahu, 54, 1, 10)], nil),
        .KI_SAVO: ([p(.yeshayahu, 60, 1, 22)], nil),
        .NITZAVIM: ([p(.yeshayahu, 61, 10, 63, 9)], nil),
        .VAYEILECH: ([p(.yeshayahu, 55, 6, 56, 8)], nil),
        .HAAZINU: ([p(.shmuel2, 22, 1, 51)], nil),
        .VZOS_HABERACHA: ([p(.yehoshua, 1, 1, 18)], [p(.yehoshua, 1, 1, 9)]),
    ]

    private static let combined: [JewishCalendar.Parsha: JewishCalendar.Parsha] = [
        .VAYAKHEL_PEKUDEI: .PEKUDEI, .TAZRIA_METZORA: .METZORA, .ACHREI_MOS_KEDOSHIM: .ACHREI_MOS,
        .BEHAR_BECHUKOSAI: .BECHUKOSAI, .CHUKAS_BALAK: .BALAK, .MATOS_MASEI: .MASEI, .NITZAVIM_VAYEILECH: .NITZAVIM,
    ]

    // MARK: Special days

    private static let roshChodesh = [p(.yeshayahu, 66, 1, 24)]
    private static let macharChodesh = [p(.shmuel1, 20, 18, 42)]
    private static let chanukah = [p(.zecharia, 2, 14, 4, 7)]
    private static let chanukah2 = [p(.melachim1, 7, 40, 50)]
    private static let fastMincha = [p(.yeshayahu, 55, 6, 56, 8)]

    /// Selects the custom: `sef` is the Sefardi haftara where it differs.
    private static func pick(_ ash: [Part], _ sef: [Part]? = nil, _ sefard: Bool) -> [Part] { sefard ? sef ?? ash : ash }

    /// The morning haftara, as verse runs.
    static func parts(for jc: JewishCalendar, sefard s: Bool) -> [Part]? {
        let day = jc.getJewishDayOfMonth(), month = jc.getJewishMonth(), israel = jc.getInIsrael()
        let shabbos = jc.getDayOfWeek() == 7

        switch jc.getYomTovIndex() {
        case JewishCalendar.ROSH_HASHANA:
            return day == 1 ? [p(.shmuel1, 1, 1, 2, 10)] : [p(.yirmiyahu, 31, 2, 20)]
        case JewishCalendar.YOM_KIPPUR:
            return [p(.yeshayahu, 57, 14, 58, 14)]
        case JewishCalendar.SUCCOS:
            return day == 15 ? [p(.zecharia, 14, 1, 21)] : [p(.melachim1, 8, 2, 21)]
        case JewishCalendar.CHOL_HAMOED_SUCCOS:
            return shabbos ? [p(.yechezkel, 38, 18, 39, 16)] : nil
        case JewishCalendar.SHEMINI_ATZERES:
            return israel ? [p(.yehoshua, 1, 1, 18)] : [p(.melachim1, 8, 54, 66)]
        case JewishCalendar.SIMCHAS_TORAH:
            return [p(.yehoshua, 1, 1, 18)]
        case JewishCalendar.PESACH:
            switch day {
            case 15: return pick([p(.yehoshua, 3, 5, 7), p(.yehoshua, 5, 2, 6, 1), p(.yehoshua, 6, 27, 27)],
                                 [p(.yehoshua, 5, 2, 6, 1), p(.yehoshua, 6, 27, 27)], s)
            case 16: return [p(.melachim2, 23, 1, 9), p(.melachim2, 23, 21, 25)]
            case 21: return [p(.shmuel2, 22, 1, 51)]
            default: return [p(.yeshayahu, 10, 32, 12, 6)]
            }
        case JewishCalendar.CHOL_HAMOED_PESACH:
            return shabbos ? [p(.yechezkel, 37, 1, 14)] : nil
        case JewishCalendar.SHAVUOS:
            return day == 6 ? [p(.yechezkel, 1, 1, 28), p(.yechezkel, 3, 12, 12)]
                : pick([p(.chavakuk, 3, 1, 19)], [p(.chavakuk, 2, 20, 3, 19)], s)
        case JewishCalendar.TISHA_BEAV:
            return [p(.yirmiyahu, 8, 13, 9, 23)]
        default:
            break
        }
        guard shabbos else { return nil }

        let chanukahDay = jc.getDayOfChanukah()
        if chanukahDay > 0 { return chanukahDay == 8 ? chanukah2 : chanukah }

        let parsha = jc.getParshah()
        switch jc.getSpecialShabbos() {
        case .SHKALIM: return pick([p(.melachim2, 12, 1, 17)], [p(.melachim2, 11, 17, 12, 17)], s)
        case .ZACHOR: return pick([p(.shmuel1, 15, 2, 34)], [p(.shmuel1, 15, 1, 34)], s)
        case .PARA: return pick([p(.yechezkel, 36, 16, 38)], [p(.yechezkel, 36, 16, 36)], s)
        case .HACHODESH: return pick([p(.yechezkel, 45, 16, 46, 18)], [p(.yechezkel, 45, 18, 46, 15)], s)
        case .HAGADOL: return [p(.malachi, 3, 4, 24)]
        case .SHUVA:
            let hosea = p(.hoshea, 14, 2, 10), micah = p(.micha, 7, 18, 20), joel = p(.yoel, 2, 15, 27)
            return parsha == .HAAZINU ? pick([hosea, joel], [hosea, micah], s) : [hosea, micah]
        default: break
        }

        guard parsha != .NONE else { return nil }
        let own = combined[parsha] ?? parsha
        // Pinchas after the 17th of Tammuz is the first of the three of affliction.
        if own == .PINCHAS, day > 17 { return [p(.yirmiyahu, 1, 1, 2, 3)] }
        if day == 30 || day == 1 {
            // Shabbos Rosh Chodesh Av keeps שמעו, Rosh Chodesh Elul (ראה) keeps עניה סוערה.
            if own == .MASEI {
                return pick(parshiyos[.MASEI]!.ash, [p(.yirmiyahu, 2, 4, 28), p(.yirmiyahu, 4, 1, 2),
                                                     p(.yeshayahu, 66, 1, 1), p(.yeshayahu, 66, 23, 23)], s)
            }
            if own != .REEH { return roshChodesh }
        }
        // Kedoshim read alone after Achrei Mos had a special haftara (Shabbos HaGadol, Pesach in the
        // diaspora, Machar Chodesh) reads Achrei Mos's.
        if parsha == .KEDOSHIM, [26, 28, 6].contains(day) {
            return pick(parshiyos[.ACHREI_MOS]!.ash, parshiyos[.KEDOSHIM]!.sef, s)
        }
        // Erev Rosh Chodesh (not in Av, where the haftarot of affliction and consolation stand).
        if day == 29, month != JewishCalendar.AV { return macharChodesh }

        let entry = parshiyos[own]!
        if parsha == .ACHREI_MOS_KEDOSHIM { return pick(entry.ash, parshiyos[.KEDOSHIM]!.sef, s) }
        return pick(entry.ash, entry.sef, s)
    }

    /// The mincha haftara: Yom Kippur, Tisha B'Av, and (Ashkenaz only) the other public fasts.
    static func minchaParts(for jc: JewishCalendar, sefard: Bool) -> [Part]? {
        switch jc.getYomTovIndex() {
        case JewishCalendar.YOM_KIPPUR:
            return [p(.yona, 1, 1, 4, 11), p(.micha, 7, 18, 20)]
        case JewishCalendar.TISHA_BEAV:
            return fastMincha
        case JewishCalendar.SEVENTEEN_OF_TAMMUZ, JewishCalendar.FAST_OF_GEDALYAH,
             JewishCalendar.TENTH_OF_TEVES, JewishCalendar.FAST_OF_ESTHER:
            return sefard ? nil : fastMincha
        default:
            return nil
        }
    }

    // MARK: Formatting

    private static func num(_ n: Int) -> String { ZmanEngine.formatter.formatHebrewNumber(number: n) }

    /// "ישעיהו מ״ב:ה׳–מ״ג:י׳"; parts joined with " ; ", the book named once while it repeats.
    static func format(_ parts: [Part]) -> String {
        var out: [String] = [], book: Book?
        for part in parts {
            var s = "\(num(part.from.0)):\(num(part.from.1))"
            if part.to != part.from {
                s += "–" + (part.to.0 == part.from.0 ? num(part.to.1) : "\(num(part.to.0)):\(num(part.to.1))")
            }
            out.append(part.book == book ? s : "\(part.book.rawValue) \(s)")
            book = part.book
        }
        return out.joined(separator: " ; ")
    }

    /// The haftara read on this day (Shabbos or Yom Tov / fast day with a haftara), or nil. Hebrew, e.g. "ישעיהו מ״ב:ה׳–מ״ג:י׳".
    /// The morning reading only; see `minchaReading`.
    static func reading(for jc: JewishCalendar, sefard: Bool) -> String? {
        parts(for: jc, sefard: sefard).map(format)
    }

    /// The haftara at mincha (Yom Kippur, fast days), or nil.
    static func minchaReading(for jc: JewishCalendar, sefard: Bool) -> String? {
        minchaParts(for: jc, sefard: sefard).map(format)
    }
}
