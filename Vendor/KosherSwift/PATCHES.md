# KosherSwift – local patches

This is [KosherSwift](https://github.com/Elyahu41/KosherSwift) 2.0.0 (revision `e97a6f38`, LGPL 2.1),
vendored so the fixes below ship with the app. Every change is marked `MyZman patch` in the source.

1. **Crash in the Arctic / Antarctic** (`AstronomicalCalendar.getTimeOffset(time:offset: Double)`).
   An incalculable *shaah zmanis* is `Int64.min`; offsets built from it overflowed `Int64(offset)` and trapped.
   It now returns `nil`. Reproduce: Tromsø, 21 June – the default zmanim list crashed the app.
2. **More `Int64` overflows** in the same situation: `getShaahZmanis…() * 5` (biur chametz),
   `getPlagHaminchaYalkutYosef`, `getPlagHaminchaYalkutYosefAmudeiHoraah`, `getMisheyakir6xMinutesZmanit`,
   `getTzais13Point5MinutesZmanis`, `getSofZmanBiurChametzMGAAmudeiHoraah` – guarded / done in `Double`.
3. **Amudei Horaah zmanim left `workingDate` on 17 March** when they returned `nil` early, which shifted every
   later zman calculated on the same calendar. The date is now restored on that path too.
4. **Fixed local chatzos up to ~4 minutes off** (`getLocalMeanTime`): the longitude was truncated to whole degrees
   and seconds were mixed with milliseconds. Now UTC − longitude/15 h, which matches KosherJava.
5. **Evening events after local midnight landed a day early** (`getDateFromTime`), e.g. tzais 26° in a London
   summer, which broke plag / shaah zmanis 26°. The day is now chosen the way KosherJava does it (solar time +
   sunrise/sunset event).
6. **Sof zman Kiddush Levana between moldos 16.6 minutes late**: half a lunar month is 1,275,721.667 s,
   not 1,276,720.666.

7. **Molad in the midnight hour a day early** (`getMoladAsDate`: `moladHours > 6` → `>= 6`), and with it the Kiddush
   Levana times; also keeps the fraction of a second.
8. **`getDaysSinceStartOfJewishYear` a day off in Sivan and Av of common years**, plus upstream's `getDaysInJewishMonth`
   fix (2b4992a), which put Tekufat Nisan 24 hours early in common years.

9. **Taken from KosherJava 3.x** (not yet in KosherSwift):
   - No Tachanun on Erev Rosh Hashana (`TefilaRules`, KosherJava 0b6b95c).
   - `getAlos60()` from elevation-adjusted sunrise (f5a5b2c).
   - NOAA: retry with the declination at solar midnight before reporting that the Sun never reaches a zenith
     (ac7b4fb) – e.g. Tromsø 17 Aug: tzais 7.083° now 00:27, matching Skyfield, instead of none.
10. **`getSofZmanBiurChametzMGA72MinutesZmanis` 3–6 minutes early**: it used the fixed-72 shaah zmanis instead of the
    72-zmaniyos one (KosherJava and kosher-zmanim agree on the latter).

Submitted upstream (with the same fixes against `main`): https://github.com/Elyahu41/KosherSwift/pull/5

Known and not patched: `HebrewDateFormatter.formatRoshChodesh` names the wrong month on the 30th
(30 Nisan → "ניסן"); the app formats Rosh Chodesh itself.

Worth reporting upstream; drop the vendored copy once a release includes the fixes.
