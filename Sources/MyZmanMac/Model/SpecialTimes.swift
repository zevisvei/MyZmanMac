import Foundation
import KosherSwift

/// Times that only apply on some days: candle lighting, the end of Shabbos / Yom Tov, fasts, chametz,
/// Chanukah, tekufa, Kiddush Levana. Shown above the zmanim list and used by the Shabbos widget.
struct SpecialTime: Hashable, Identifiable {
    let title: String
    let time: Date?
    var note = ""
    let symbol: String

    var id: String { title }
}

enum SpecialTimes {
    /// `kind` overrides the zman's own rounding direction (alos as the start of a fast is a deadline for eating).
    private static func zman(_ id: String, on day: Date, _ s: AppSettings, kind: ZmanDef.Kind? = nil) -> Date? {
        guard let def = ZmanCatalog.def(id) else { return nil }
        return ZmanEngine.round(ZmanEngine.compute(def, on: ZmanEngine.calendar(for: day, settings: s)).0, kind ?? def.kind, s)
    }

    private static func round(_ t: Date?, _ kind: ZmanDef.Kind, _ s: AppSettings) -> Date? { ZmanEngine.round(t, kind, s) }

    static func havdalah(on day: Date, _ s: AppSettings) -> Date? { zman(s.havdalahDefID, on: day, s, kind: .earliest) }

    /// Candle lighting on the evening of `day` (which must be erev Shabbos / Yom Tov): before sunset,
    /// or – when `day` is itself Shabbos / Yom Tov going into a second holy day – only once it's over (from an
    /// existing flame). A Yom Tov on Friday still lights for Shabbos before sunset.
    static func candleLighting(on day: Date, _ s: AppSettings) -> (time: Date?, afterNightfall: Bool) {
        let jc = ZmanEngine.jewishCalendar(for: day, settings: s)
        if jc.isAssurBemelacha(), jc.getDayOfWeek() != 6 { return (havdalah(on: day, s), true) }
        return (round(ZmanEngine.calendar(for: day, settings: s).myzCandleLighting(Double(s.candleLightingOffset)), .deadline, s), false)
    }

    private static let tekufaNames = ["Tishri": "תשרי", "Tevet": "טבת", "Nissan": "ניסן", "Tammuz": "תמוז"]

    static func on(_ day: Date, settings s: AppSettings) -> [SpecialTime] {
        let cal = ZmanEngine.gregorian(s.location.timeZone)
        let jc = ZmanEngine.jewishCalendar(for: day, settings: s)
        let tomorrow = ZmanEngine.jewishCalendar(for: cal.date(byAdding: .day, value: 1, to: day)!, settings: s)
        let czc = ZmanEngine.calendar(for: day, settings: s)
        var out: [SpecialTime] = []

        // Fasts. Yom Kippur and Tisha B'Av start the evening before.
        if tomorrow.isYomKippur() || tomorrow.isTishaBav() {
            out.append(SpecialTime(title: "תחילת הצום", time: round(ZmanEngine.sunset(on: day, settings: s), .deadline, s), note: "בשקיעה", symbol: "moon"))
        }
        if jc.isTaanis() || jc.isTaanisBechoros() {
            if !jc.isYomKippur() && !jc.isTishaBav() {
                // Far north in summer there may be no alos at the chosen depression: then 72 minutes before sunrise.
                let chosen = zman(s.fastStartDefID, on: day, s, kind: .deadline)
                let start = chosen ?? zman("GetAlos72", on: day, s, kind: .deadline)
                let note = chosen != nil ? ZmanCatalog.def(s.fastStartDefID)?.he ?? ""
                    : "אין \(ZmanCatalog.def(s.fastStartDefID)?.he ?? "עלות השחר") היום – לפי 72 דקות לפני הנץ"
                out.append(SpecialTime(title: jc.isTaanisBechoros() ? "תחילת תענית בכורות" : "תחילת הצום", time: start,
                                       note: note, symbol: "sunrise"))
            }
            if !jc.isYomKippur() && !jc.isTaanisBechoros() {   // the firstborn's fast ends at the seder (or a siyum)
                let end = jc.isTishaBav() ? s.tishaBavEndDefID : s.fastEndDefID
                out.append(SpecialTime(title: "סוף הצום", time: zman(end, on: day, s, kind: .earliest),
                                       note: ZmanCatalog.def(end)?.he ?? "", symbol: "fork.knife"))
            }
        }

        // Erev Pesach. When it's on Shabbos the chametz is burned on Friday (SA OC 444:2), at the usual time of
        // day; on Shabbos itself what's left is eaten by the deadline and then nullified.
        let f = ZmanFormat(s)
        if jc.getJewishMonth() == JewishCalendar.NISSAN, jc.getJewishDayOfMonth() == 14 {
            out.append(SpecialTime(title: "סוף זמן אכילת חמץ", time: round(czc.getSofZmanAchilasChametzGRA(), .deadline, s),
                                   note: "גר״א · מג״א \(f.time(round(czc.getSofZmanAchilasChametzMGA72Minutes(), .deadline, s)))", symbol: "takeoutbag.and.cup.and.straw"))
            if jc.getDayOfWeek() == 7 {
                out.append(SpecialTime(title: "סוף זמן ביטול חמץ", time: round(czc.getSofZmanBiurChametzGRA(), .deadline, s),
                                       note: "שבת – השריפה הייתה ביום שישי", symbol: "flame"))
            } else {
                out.append(SpecialTime(title: "סוף זמן ביעור חמץ", time: round(czc.getSofZmanBiurChametzGRA(), .deadline, s),
                                       note: "גר״א · מג״א \(f.time(round(czc.getSofZmanBiurChametzMGA72Minutes(), .deadline, s)))", symbol: "flame"))
            }
        }
        if jc.getJewishMonth() == JewishCalendar.NISSAN, jc.getJewishDayOfMonth() == 13, tomorrow.getDayOfWeek() == 7 {
            // KosherSwift's chametz zmanim are only for the 14th: take the same hours of this day.
            let biur = czc.getShaahZmanisGra() == Int64.min ? nil
                : czc.getElevationAdjustedSunrise().map { $0.addingTimeInterval(Double(czc.getShaahZmanisGra()) * 5 / 1000) }
            out.append(SpecialTime(title: "שריפת חמץ (ערב פסח חל בשבת)", time: round(biur, .deadline, s),
                                   note: "בשעה שבה היו שורפים בערב פסח (גר״א)", symbol: "flame"))
        }

        // Candle lighting tonight, and the end of Shabbos / Yom Tov.
        if jc.hasCandleLighting() {
            let c = candleLighting(on: day, s)
            out.append(SpecialTime(title: "הדלקת נרות", time: c.time,
                                   note: c.afterNightfall ? "לא לפני צאת \(jc.getDayOfWeek() == 7 ? "השבת" : "החג"), מאש קיימת"
                                       : "\(s.candleLightingOffset) דק׳ לפני השקיעה",
                                   symbol: "flame"))
        }
        if jc.isAssurBemelacha() && !tomorrow.isAssurBemelacha() {
            let title = jc.getDayOfWeek() == 7 ? (jc.isYomTovAssurBemelacha() ? "צאת השבת והחג" : "צאת השבת") : "צאת החג"
            out.append(SpecialTime(title: title, time: havdalah(on: day, s),
                                   note: ZmanCatalog.def(s.havdalahDefID)?.he ?? "", symbol: "sparkles"))
        }

        // Chanukah: the candles of the coming night.
        if tomorrow.isChanukah() || (jc.isChanukah() && jc.getDayOfChanukah() < 8) {
            let n = tomorrow.isChanukah() ? tomorrow.getDayOfChanukah() : jc.getDayOfChanukah() + 1
            let weekday = jc.getDayOfWeek()
            let (time, note): (Date?, String) = weekday == 6
                ? (candleLighting(on: day, s).time, "לפני נרות שבת")
                : weekday == 7 ? (havdalah(on: day, s), "אחרי צאת השבת")
                : s.chanukahAtTzais ? (zman(s.fastEndDefID, on: day, s, kind: .earliest), "בצאת הכוכבים")
                : (round(ZmanEngine.sunset(on: day, settings: s), .neutral, s), "בשקיעה")
            out.append(SpecialTime(title: "נר \(ZmanEngine.formatter.formatHebrewNumber(number: n)) של חנוכה", time: time,
                                   note: note, symbol: "flame.fill"))
        }

        // Tekufa (Shmuel), with the customary half hour on either side when water isn't drunk. KosherSwift reports it
        // on its Jewish day, which began the evening before – and abroad the local civil day can differ – so look at
        // today's and tomorrow's Jewish day and keep the one that falls on this civil day.
        if let (t, name) = [jc, tomorrow].lazy.compactMap({ c in c.getTekufaAsDate().map { ($0, c.getTekufaName()) } })
            .first(where: { cal.isDate($0.0, inSameDayAs: day) }) {
            let name = tekufaNames[name].map { "תקופת \($0)" } ?? "תקופה"
            let f = ZmanFormat(s)
            out.append(SpecialTime(title: name, time: round(t, .neutral, s),
                                   note: "נמנעים משתיית מים \(f.time(t.addingTimeInterval(-1800)))–\(f.time(t.addingTimeInterval(1800)))",
                                   symbol: "drop"))
        }

        // Kiddush Levana – only on the nights the window opens or closes.
        if let t = czc.getTchilasZmanKidushLevana7Days() {
            out.append(SpecialTime(title: "תחילת זמן קידוש לבנה", time: round(t, .earliest, s), note: "7 ימים מהמולד", symbol: "moon.stars"))
        } else if let t = czc.getTchilasZmanKidushLevana3Days() {
            out.append(SpecialTime(title: "תחילת זמן קידוש לבנה (3 ימים)", time: round(t, .earliest, s), note: "יש הממתינים 7 ימים", symbol: "moon.stars"))
        }
        if let t = czc.getSofZmanKidushLevana15Days() {
            out.append(SpecialTime(title: "סוף זמן קידוש לבנה", time: round(t, .deadline, s), note: "15 יום מהמולד", symbol: "moon.stars"))
        }
        return out
    }

    /// The next Shabbos or Yom Tov from `now` on (the current one, until it's out): candle lighting,
    /// its end and a title, for the Shabbos widget.
    struct Period {
        let title: String
        let candles: Date?
        let candlesAfterNightfall: Bool
        let end: Date?
        let firstDay: Date
    }

    static func nextPeriod(from now: Date, settings s: AppSettings) -> Period? {
        let cal = ZmanEngine.gregorian(s.location.timeZone)
        func jcal(_ d: Date) -> JewishCalendar { ZmanEngine.jewishCalendar(for: d, settings: s) }
        for offset in -4..<16 {  // back far enough for a three-day Yom Tov + Shabbos
            let eve = cal.date(byAdding: .day, value: offset, to: now)!
            let jEve = jcal(eve)
            // The eve that starts a period (not a second day, which is itself a holy day).
            guard jEve.hasCandleLighting(), !jEve.isAssurBemelacha() else { continue }
            var days: [Date] = []
            var d = cal.date(byAdding: .day, value: 1, to: eve)!
            while jcal(d).isAssurBemelacha(), days.count < 4 {
                days.append(d)
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            guard let last = days.last else { continue }
            let end = havdalah(on: last, s)
            if let end, end <= now { continue }   // already over
            let first = jcal(days[0])
            let yomTov = days.map(jcal).first { $0.isYomTovAssurBemelacha() }
            let title = yomTov.map { ZmanEngine.formatter.formatYomTov(jewishCalendar: $0) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? (first.getDayOfWeek() == 7 ? "שבת" : "חג")
            let candles = candleLighting(on: eve, s)
            return Period(title: title, candles: candles.time, candlesAfterNightfall: candles.afterNightfall, end: end, firstDay: days[0])
        }
        return nil
    }
}
