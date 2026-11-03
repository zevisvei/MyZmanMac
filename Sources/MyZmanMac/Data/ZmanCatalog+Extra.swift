import Foundation
import KosherSwift

/// Calculations beyond MyZman's list: zmanim Israeli and Sephardi luachs show (Amudei Horaah / Rav Ovadia,
/// Yalkut Yosef), Kiddush Levana, Samuch Lemincha Ketana and a few more KosherJava opinions.
extension ZmanCatalog {
    static let extra: [ZmanDef] = [
        // Amudei Horaah: degree-based zmanim scaled to the equinox in Jerusalem, as in Rabbi Ovadiah Yosef's luachs.
        ZmanDef(id: "GetAlosAmudeiHoraah", he: "עלות השחר עמודי הוראה", en: "Alos Amudei Horaah",
                heInfo: "עלות השחר לפי עמודי הוראה (שיטת הרב עובדיה יוסף): 16.04 מעלות ביום השוויון בירושלים, מומר לשעות זמניות של היום והמקום.",
                enInfo: "Alos per Amudei Horaah: 16.04° at the Jerusalem equinox, converted to zmaniyos minutes for the day and place.",
                calc: .time { $0.myzRestoringDate { $0.getAlosAmudeiHoraah() } }),
        ZmanDef(id: "GetMisheyakirAmudeiHoraah", he: "משיכיר עמודי הוראה", en: "Misheyakir Amudei Horaah",
                heInfo: "משיכיר לפי עמודי הוראה: 5/6 מזמן עלות השחר עמודי הוראה לפני הנץ.",
                enInfo: "Misheyakir per Amudei Horaah: 5/6 of the Amudei Horaah alos interval before sunrise.",
                calc: .time { $0.myzRestoringDate { $0.getMisheyakirAmudeiHoraah() } }),
        ZmanDef(id: "GetSofZmanShmaMGA72MinutesZmanisAmudeiHoraah", he: "סו״ז שמע מג״א עמודי הוראה", en: "Sof Zman Shma MGA Amudei Horaah",
                heInfo: "סוף זמן קריאת שמע למגן אברהם, מעלות השחר עד צאת הכוכבים 72 דקות זמניות לפי עמודי הוראה.",
                enInfo: "Latest Shma per the MGA, from Amudei Horaah alos to Amudei Horaah 72 zmaniyos tzais.",
                calc: .time { $0.myzRestoringDate { $0.getSofZmanShmaMGA72MinutesZmanisAmudeiHoraah() } }),
        ZmanDef(id: "GetPlagHaminchaYalkutYosef", he: "פלג המנחה ילקוט יוסף", en: "Plag Hamincha Yalkut Yosef",
                heInfo: "פלג המנחה לפי ילקוט יוסף: שעה ורבע זמנית לפני צאת הכוכבים (13.5 דקות זמניות אחרי השקיעה).",
                enInfo: "Plag hamincha per Yalkut Yosef: 1.25 zmaniyos hours before tzais of 13.5 zmaniyos minutes.",
                calc: .time { $0.getPlagHaminchaYalkutYosef() }),
        ZmanDef(id: "GetPlagHaminchaYalkutYosefAmudeiHoraah", he: "פלג המנחה ילקוט יוסף (עמודי הוראה)", en: "Plag Hamincha Yalkut Yosef (Amudei Horaah)",
                heInfo: "פלג המנחה לפי ילקוט יוסף, שעה ורבע זמנית לפני צאת הכוכבים של עמודי הוראה.",
                enInfo: "Plag hamincha per Yalkut Yosef, 1.25 zmaniyos hours before Amudei Horaah tzais.",
                calc: .time { $0.myzRestoringDate { $0.getPlagHaminchaYalkutYosefAmudeiHoraah() } }),
        ZmanDef(id: "GetTzais13Point5MinutesZmanis", he: "צאה״כ 13.5 דקות זמניות", en: "Tzais 13.5 Minutes Zmaniyos",
                heInfo: "צאת הכוכבים 13.5 דקות זמניות אחרי השקיעה (ילקוט יוסף, לארץ ישראל).",
                enInfo: "Tzais 13.5 zmaniyos minutes after sunset (Yalkut Yosef, for Israel).",
                calc: .time { $0.getTzais13Point5MinutesZmanis() }),
        ZmanDef(id: "GetTzaisAmudeiHoraah", he: "צאה״כ עמודי הוראה", en: "Tzais Amudei Horaah",
                heInfo: "צאת הכוכבים לפי עמודי הוראה (3.77 מעלות בשוויון בירושלים). לחוץ לארץ; בארץ ישראל מקובל 13.5 דקות זמניות.",
                enInfo: "Tzais per Amudei Horaah (3.77° at the Jerusalem equinox). For outside Israel; in Israel 13.5 zmaniyos minutes is used.",
                calc: .time { $0.myzRestoringDate { $0.getTzaisAmudeiHoraah() } }),
        ZmanDef(id: "GetTzaisAmudeiHoraahLChumra", he: "צאה״כ לחומרא עמודי הוראה", en: "Tzais L'Chumra Amudei Horaah",
                heInfo: "צאת הכוכבים לחומרא לפי עמודי הוראה (5.135 מעלות בשוויון בירושלים).",
                enInfo: "Tzais l'chumra per Amudei Horaah (5.135° at the Jerusalem equinox).",
                calc: .time { $0.myzRestoringDate { $0.getTzaisAmudeiHoraahLChumra() } }),
        ZmanDef(id: "GetTzaisShabbatAmudeiHoraah", he: "צאת השבת עמודי הוראה", en: "Tzais Shabbat Amudei Horaah",
                heInfo: "צאת השבת לפי עמודי הוראה: השמש 7.14 מעלות מתחת לאופק.",
                enInfo: "End of Shabbos per Amudei Horaah: the sun 7.14° below the horizon.",
                calc: .time { $0.getTzaisShabbatAmudeiHoraah() }),
        ZmanDef(id: "GetTzais72ZmanisAmudeiHoraah", he: "ר״ת 72 דקות זמניות עמודי הוראה", en: "Rabbeinu Tam 72 Zmaniyos Amudei Horaah",
                heInfo: "צאת הכוכבים לרבנו תם, 72 דקות זמניות לפי עמודי הוראה (16.01 מעלות בשוויון בירושלים).",
                enInfo: "Rabbeinu Tam tzais, 72 zmaniyos minutes per Amudei Horaah (16.01° at the Jerusalem equinox).",
                calc: .time { $0.myzRestoringDate { $0.getTzais72ZmanisAmudeiHoraah() } }),
        ZmanDef(id: "GetTzais72ZmanisAmudeiHoraahLkulah", he: "ר״ת 72 דקות זמניות לקולא עמודי הוראה", en: "Rabbeinu Tam 72 Zmaniyos L'Kulah Amudei Horaah",
                heInfo: "צאת הכוכבים לרבנו תם לקולא לפי עמודי הוראה: המוקדם מבין 72 דקות קבועות ו-72 דקות זמניות.",
                enInfo: "Rabbeinu Tam l'kulah per Amudei Horaah: the earlier of 72 fixed and 72 zmaniyos minutes.",
                calc: .time { $0.myzRestoringDate { $0.getTzais72ZmanisAmudeiHoraahLkulah() } }),
        ZmanDef(id: "GetSofZmanAchilatChametzAmudeiHoraah", he: "סו״ז אכילת חמץ עמודי הוראה", en: "Sof Zman Achilas Chametz Amudei Horaah",
                heInfo: "סוף זמן אכילת חמץ למג״א לפי עמודי הוראה (בערב פסח בלבד).",
                enInfo: "Latest time to eat chametz per the MGA, Amudei Horaah (erev Pesach only).",
                calc: .time { $0.myzOnErevPesach { $0.myzRestoringDate { $0.getSofZmanAchilatChametzAmudeiHoraah() } } }),
        ZmanDef(id: "GetSofZmanBiurChametzMGAAmudeiHoraah", he: "סו״ז ביעור חמץ עמודי הוראה", en: "Sof Zman Biur Chametz Amudei Horaah",
                heInfo: "סוף זמן ביעור חמץ למג״א לפי עמודי הוראה (בערב פסח בלבד).",
                enInfo: "Latest time to burn chametz per the MGA, Amudei Horaah (erev Pesach only).",
                calc: .time { $0.myzOnErevPesach { $0.myzRestoringDate { $0.getSofZmanBiurChametzMGAAmudeiHoraah() } } }),

        // More KosherJava opinions.
        ZmanDef(id: "GetMisheyakir66MinutesZmanit", he: "משיכיר 66 דקות זמניות", en: "Misheyakir 66 Minutes Zmaniyos",
                heInfo: "משיכיר 66 דקות זמניות לפני הנץ.", enInfo: "Misheyakir 66 zmaniyos minutes before sunrise.",
                calc: .time { $0.getMisheyakir66MinutesZmanit() }),
        ZmanDef(id: "GetMisheyakir60MinutesZmanit", he: "משיכיר 60 דקות זמניות", en: "Misheyakir 60 Minutes Zmaniyos",
                heInfo: "משיכיר 60 דקות זמניות לפני הנץ.", enInfo: "Misheyakir 60 zmaniyos minutes before sunrise.",
                calc: .time { $0.getMisheyakir60MinutesZmanit() }),
        ZmanDef(id: "GetSofZmanShmaGRASunriseToFixedLocalChatzos", he: "סו״ז שמע גר״א (נץ עד חצות קבוע)", en: "Sof Zman Shma GRA Sunrise to Fixed Local Chatzos",
                heInfo: "סוף זמן קריאת שמע לגר״א: מחצית הזמן מהנץ עד חצות ממוצע מקומי.",
                enInfo: "Latest Shma per the GRA: half the time from sunrise to fixed local chatzos.",
                calc: .time { $0.getSofZmanShmaGRASunriseToFixedLocalChatzos() }),
        ZmanDef(id: "GetSofZmanTfilaGRASunriseToFixedLocalChatzos", he: "סו״ז תפילה גר״א (נץ עד חצות קבוע)", en: "Sof Zman Tfila GRA Sunrise to Fixed Local Chatzos",
                heInfo: "סוף זמן תפילה לגר״א: שני שלישים מהזמן מהנץ עד חצות ממוצע מקומי.",
                enInfo: "Latest Shacharis per the GRA: two thirds of the time from sunrise to fixed local chatzos.",
                calc: .time { $0.getSofZmanTfilaGRASunriseToFixedLocalChatzos() }),
        ZmanDef(id: "GetMinchaGedolaAhavatShalom", he: "מנחה גדולה אהבת שלום", en: "Mincha Gedola Ahavat Shalom",
                heInfo: "מנחה גדולה לפי אהבת שלום.", enInfo: "Mincha gedola per Ahavat Shalom.",
                calc: .time { $0.getMinchaGedolaAhavatShalom() }),
        ZmanDef(id: "GetMinchaGedolaGRAFixedLocalChatzos30Minutes", he: "מנחה גדולה 30 דק׳ אחרי חצות קבוע", en: "Mincha Gedola 30 Minutes After Fixed Local Chatzos",
                heInfo: "מנחה גדולה חצי שעה אחרי חצות ממוצע מקומי.", enInfo: "Mincha gedola 30 minutes after fixed local chatzos.",
                calc: .time { $0.getMinchaGedolaGRAFixedLocalChatzos30Minutes() }),
        ZmanDef(id: "GetSamuchLeMinchaKetanaGRA", he: "סמוך למנחה קטנה גר״א", en: "Samuch LeMincha Ketana GRA",
                heInfo: "חצי שעה זמנית לפני מנחה קטנה (9 שעות זמניות מהנץ), שמאז אין להתחיל סעודה.",
                enInfo: "Half a zmaniyos hour before mincha ketana (9 hours after sunrise), when a meal shouldn't be started.",
                calc: .time { $0.getSamuchLeMinchaKetanaGRA() }),
        ZmanDef(id: "GetSamuchLeMinchaKetana16Point1Degrees", he: "סמוך למנחה קטנה 16.1 מעלות", en: "Samuch LeMincha Ketana 16.1 Degrees",
                heInfo: "סמוך למנחה קטנה, יום מעלות השחר עד צאת הכוכבים 16.1 מעלות.", enInfo: "Samuch lemincha ketana, day from alos to tzais 16.1°.",
                calc: .time { $0.getSamuchLeMinchaKetana16Point1Degrees() }),
        ZmanDef(id: "GetSamuchLeMinchaKetana72Minutes", he: "סמוך למנחה קטנה 72 דקות", en: "Samuch LeMincha Ketana 72 Minutes",
                heInfo: "סמוך למנחה קטנה, יום מעלות השחר עד צאת הכוכבים 72 דקות.", enInfo: "Samuch lemincha ketana, day from alos to tzais 72 minutes.",
                calc: .time { $0.getSamuchLeMinchaKetana72Minutes() }),
        ZmanDef(id: "GetMinchaKetanaAhavatShalom", he: "מנחה קטנה אהבת שלום", en: "Mincha Ketana Ahavat Shalom",
                heInfo: "מנחה קטנה לפי אהבת שלום.", enInfo: "Mincha ketana per Ahavat Shalom.",
                calc: .time { $0.getMinchaKetanaAhavatShalom() }),
        ZmanDef(id: "GetMinchaKetanaGRAFixedLocalChatzosToSunset", he: "מנחה קטנה (חצות קבוע עד שקיעה)", en: "Mincha Ketana Fixed Local Chatzos to Sunset",
                heInfo: "מנחה קטנה, מחצות ממוצע מקומי עד השקיעה.", enInfo: "Mincha ketana from fixed local chatzos to sunset.",
                calc: .time { $0.getMinchaKetanaGRAFixedLocalChatzosToSunset() }),
        ZmanDef(id: "GetPlagHaminchaGRAFixedLocalChatzosToSunset", he: "פלג המנחה (חצות קבוע עד שקיעה)", en: "Plag Hamincha Fixed Local Chatzos to Sunset",
                heInfo: "פלג המנחה, מחצות ממוצע מקומי עד השקיעה.", enInfo: "Plag hamincha from fixed local chatzos to sunset.",
                calc: .time { $0.getPlagHaminchaGRAFixedLocalChatzosToSunset() }),
        ZmanDef(id: "GetPlagAhavatShalom", he: "פלג המנחה אהבת שלום", en: "Plag Hamincha Ahavat Shalom",
                heInfo: "פלג המנחה לפי אהבת שלום.", enInfo: "Plag hamincha per Ahavat Shalom.",
                calc: .time { $0.getPlagAhavatShalom() }),
        ZmanDef(id: "GetTzaisGeonim4Point42Degrees", he: "צאה״כ 4.42 מעלות", en: "Tzais Geonim 4.42 Degrees",
                heInfo: "צאת הכוכבים כשהשמש 4.42 מעלות מתחת לאופק: 3/4 מיל של 22.5 דקות (16⅞ דקות) אחרי השקיעה בירושלים בשוויון. KosherJava 3 מחליפה בו את 4.37.",
                enInfo: "Tzais at 4.42° below the horizon: 3/4 of a 22.5-minute mil (16⅞ minutes) after sunset in Jerusalem around the equilux. Replaces 4.37° in KosherJava 3.",
                calc: .time { $0.myzTzaisDegrees(4.42) }),
        ZmanDef(id: "GetTzaisGeonim4Point66Degrees", he: "צאה״כ 4.66 מעלות", en: "Tzais Geonim 4.66 Degrees",
                heInfo: "צאת הכוכבים כשהשמש 4.66 מעלות מתחת לאופק: 3/4 מיל של 24 דקות (18 דקות) אחרי השקיעה בירושלים בשוויון. KosherJava 3 מחליפה בו את 4.61.",
                enInfo: "Tzais at 4.66° below the horizon: 3/4 of a 24-minute mil (18 minutes) after sunset in Jerusalem around the equilux. Replaces 4.61° in KosherJava 3.",
                calc: .time { $0.myzTzaisDegrees(4.66) }),
        ZmanDef(id: "GetTzais50", he: "צאה״כ 50 דקות", en: "Tzais 50 Minutes",
                heInfo: "צאת הכוכבים 50 דקות אחרי השקיעה.", enInfo: "Tzais 50 minutes after sunset.",
                calc: .time { $0.getTzais50() }),
        ZmanDef(id: "GetSofZmanBiurChametzMGA72MinutesZmanis", he: "סו״ז ביעור חמץ מג״א 72 דקות זמניות", en: "Sof Zman Biur Chametz MGA 72 Minutes Zmanis",
                heInfo: "סוף זמן ביעור חמץ למג״א, יום מעלות השחר עד צאת 72 דקות זמניות (בערב פסח בלבד).",
                enInfo: "Latest time to burn chametz per the MGA, 72 zmaniyos minutes (erev Pesach only).",
                calc: .time { $0.getSofZmanBiurChametzMGA72MinutesZmanis() }),

        // Kiddush Levana: each returns a time only on the day it falls on.
        ZmanDef(id: "GetTchilasZmanKidushLevana3Days", he: "תחילת זמן קידוש לבנה (3 ימים)", en: "Earliest Kiddush Levana (3 Days)",
                heInfo: "3 ימים אחרי המולד. מופיע רק ביום שבו הוא חל.", enInfo: "3 days after the molad; shown only on the day it falls on.",
                calc: .time { $0.getTchilasZmanKidushLevana3Days() }),
        ZmanDef(id: "GetTchilasZmanKidushLevana7Days", he: "תחילת זמן קידוש לבנה (7 ימים)", en: "Earliest Kiddush Levana (7 Days)",
                heInfo: "7 ימים אחרי המולד. מופיע רק ביום שבו הוא חל.", enInfo: "7 days after the molad; shown only on the day it falls on.",
                calc: .time { $0.getTchilasZmanKidushLevana7Days() }),
        ZmanDef(id: "GetSofZmanKidushLevanaBetweenMoldos", he: "סוף זמן קידוש לבנה (בין המולדות)", en: "Latest Kiddush Levana (Between Moldos)",
                heInfo: "חצי הזמן בין מולד למולד. מופיע רק ביום שבו הוא חל.", enInfo: "Halfway between moldos; shown only on the day it falls on.",
                calc: .time { $0.getSofZmanKidushLevanaBetweenMoldos() }),
        ZmanDef(id: "GetSofZmanKidushLevana15Days", he: "סוף זמן קידוש לבנה (15 יום)", en: "Latest Kiddush Levana (15 Days)",
                heInfo: "15 יום אחרי המולד. מופיע רק ביום שבו הוא חל.", enInfo: "15 days after the molad; shown only on the day it falls on.",
                calc: .time { $0.getSofZmanKidushLevana15Days() }),
        ZmanDef(id: "GetZmanMolad", he: "זמן המולד", en: "Molad",
                heInfo: "רגע המולד (שעון ירושלים). מופיע רק ביום שבו הוא חל.", enInfo: "The molad (Jerusalem time); shown only on its day.",
                calc: .time { $0.myzMolad() }),
    ]
}

extension ComplexZmanimCalendar {
    /// KosherSwift's Amudei Horaah zmanim move workingDate to the equinox and, on days they can't be
    /// calculated (the far north), return before moving it back – which would shift every later zman
    /// computed on the same calendar. Put it back regardless.
    func myzRestoringDate(_ f: (ComplexZmanimCalendar) -> Date?) -> Date? {
        let saved = workingDate
        defer { workingDate = saved }
        return f(self)
    }

    /// The molad if it falls on this civil day. (KosherSwift's getZmanMolad misses a molad at the end of the
    /// Hebrew month, e.g. New York 5 May 2027, because its month rollover fails.)
    func myzMolad() -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = geoLocation.timeZone
        for days in [0, 5, -5] {   // this Hebrew month's molad, or the next / previous one near a month's end
            let jc = JewishCalendar(workingDate: workingDate.addingTimeInterval(Double(days) * 86_400), timezone: geoLocation.timeZone)
            let molad = jc.getMoladAsDate()
            if cal.isDate(molad, inSameDayAs: workingDate) { return molad }
        }
        return nil
    }

    /// nil except on 14 Nisan, like KosherJava's own chametz zmanim.
    func myzOnErevPesach(_ f: (ComplexZmanimCalendar) -> Date?) -> Date? {
        let jc = JewishCalendar(workingDate: workingDate, timezone: geoLocation.timeZone)
        guard jc.getJewishMonth() == JewishCalendar.NISSAN, jc.getJewishDayOfMonth() == 14 else { return nil }
        return f(self)
    }
}
