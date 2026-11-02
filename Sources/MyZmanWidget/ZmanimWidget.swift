import WidgetKit
import SwiftUI
import KosherSwift

/// Desktop / Notification Center widgets. They calculate zmanim themselves (same model code as the app)
/// from the settings file the app writes, and schedule a timeline entry at every zman.
@main
struct ZmanimWidgets: WidgetBundle {
    var body: some Widget {
        NextZmanWidget()
        ZmanimListWidget()
        HebrewDateWidget()
        ShabbatWidget()
    }
}

// MARK: - Timeline

struct ZmanimEntry: TimelineEntry {
    let date: Date
    let settings: AppSettings
}

struct ZmanimProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZmanimEntry { ZmanimEntry(date: Date(), settings: AppSettings()) }

    func getSnapshot(in context: Context, completion: @escaping (ZmanimEntry) -> Void) {
        completion(ZmanimEntry(date: Date(), settings: AppSettings.loadShared()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZmanimEntry>) -> Void) {
        let settings = AppSettings.loadShared()
        let now = Date()
        let cal = ZmanEngine.gregorian(settings.location.timeZone)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        // A new entry at each upcoming zman (so "next" advances), at sunset (Hebrew date) and at midnight.
        var times = (ZmanEngine.zmanim(on: now, settings: settings) + ZmanEngine.zmanim(on: tomorrow, settings: settings))
            .compactMap(\.time).filter { $0 > now }
        if let sunset = ZmanEngine.sunset(on: now, settings: settings), sunset > now { times.append(sunset) }
        let midnight = cal.startOfDay(for: tomorrow)
        times.append(midnight)
        let entries = [ZmanimEntry(date: now, settings: settings)]
            + Set(times.filter { $0 <= midnight.addingTimeInterval(60) }).sorted().map { ZmanimEntry(date: $0, settings: settings) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

/// Values every widget view needs for an entry.
struct WidgetDay {
    let s: AppSettings
    let now: Date
    let fmt: ZmanFormat
    let cal: Calendar
    let info: DayInfo
    let today: [ComputedZman]
    let upcoming: [ComputedZman]

    init(_ entry: ZmanimEntry) {
        s = entry.settings
        now = entry.date
        fmt = ZmanFormat(s)
        cal = ZmanEngine.gregorian(s.location.timeZone)
        let s = s, now = now, cal = cal
        let hebrewDay: Date = {
            guard s.hebrewDateChangesAtSunset, let ss = ZmanEngine.sunset(on: now, settings: s), now >= ss else { return now }
            return cal.date(byAdding: .day, value: 1, to: now)!
        }()
        info = ZmanEngine.dayInfo(for: hebrewDay, settings: s)
        today = ZmanEngine.zmanim(on: now, settings: s).filter { $0.item.def?.isDuration == false }
        upcoming = (today + ZmanEngine.zmanim(on: cal.date(byAdding: .day, value: 1, to: now)!, settings: s)
            .filter { $0.item.def?.isDuration == false })
            .filter { ($0.time ?? .distantPast) > now }
            .sorted { $0.time! < $1.time! }
    }
}

private extension View {
    func widgetStyle() -> some View {
        environment(\.layoutDirection, .rightToLeft)
            .containerBackground(.background, for: .widget)
    }
}

// MARK: - 1. Next zman

struct NextZmanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextZman", provider: ZmanimProvider()) { NextZmanView(day: WidgetDay($0)).widgetStyle() }
            .configurationDisplayName("הזמן הבא")
            .description("הזמן הבא ברשימה עם ספירה לאחור.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextZmanView: View {
    let day: WidgetDay
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.info.hebrewDayMonth).font(.headline)
                Spacer()
                Text(day.s.location.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            if let next = day.upcoming.first, let t = next.time {
                Text(next.item.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(day.fmt.time(t)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text(t, style: .timer)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.orange)
            }
            if family == .systemMedium {
                Divider()
                ForEach(day.upcoming.dropFirst().prefix(2)) { z in
                    HStack {
                        Text(z.item.name).lineLimit(1)
                        Spacer()
                        Text(day.fmt.time(z.time)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }
}

// MARK: - 2. Today's list

struct ZmanimListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZmanimList", provider: ZmanimProvider()) { ZmanimListView(day: WidgetDay($0)).widgetStyle() }
            .configurationDisplayName("זמני היום")
            .description("רשימת הזמנים של היום – מה שעבר באפור, הזמן הבא מודגש.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ZmanimListView: View {
    let day: WidgetDay
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let nextID = day.upcoming.first?.id
        let rows: [ComputedZman] = {
            guard family == .systemMedium else { return day.today }
            // Medium: a window of 5 around the next zman.
            let idx = day.today.firstIndex { $0.id == nextID } ?? max(0, day.today.count - 5)
            let start = max(0, min(idx - 1, day.today.count - 5))
            return Array(day.today[start..<min(day.today.count, start + 5)])
        }()

        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(day.info.hebrewDate).font(.headline)
                Spacer()
                Text(day.s.location.displayName).font(.caption2).foregroundStyle(.secondary)
            }
            if family == .systemLarge, !day.info.parsha.isEmpty {
                Text(([day.info.parsha] + day.info.events).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Divider()
            ForEach(rows) { z in
                let past = (z.time ?? .distantFuture) < day.now
                let isNext = z.id == nextID
                HStack {
                    Text(z.item.name).lineLimit(1)
                    Spacer()
                    Text(day.fmt.time(z.time)).monospacedDigit()
                }
                .font(.system(size: 12, weight: isNext ? .bold : .regular))
                .foregroundStyle(past ? AnyShapeStyle(.secondary) : isNext ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            Spacer(minLength: 0)
            if family == .systemLarge {
                Text(Disclaimer.short).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 3. Hebrew date (calendar page)

struct HebrewDateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HebrewDate", provider: ZmanimProvider()) { HebrewDateView(day: WidgetDay($0)).widgetStyle() }
            .configurationDisplayName("תאריך עברי")
            .description("דף לוח: התאריך העברי, הפרשה, החגים והדף היומי.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HebrewDateView: View {
    let day: WidgetDay
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let parts = day.info.hebrewDate.split(separator: " ")
        VStack(spacing: 2) {
            Text(day.info.weekday).font(.caption.bold()).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(day.info.isShabbosOrYomTov ? Color.orange : Color.accentColor))
            Text(day.info.hebrewDayNumber).font(.system(size: family == .systemSmall ? 40 : 46, weight: .bold, design: .rounded))
            Text(parts.dropFirst().joined(separator: " ")).font(.subheadline)
            Text(day.fmt.localizedDate(day.now, template: "dMMMyyyy")).font(.caption2).foregroundStyle(.secondary)
            if family == .systemMedium {
                Divider()
                Text(([day.info.parsha] + day.info.events).filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).lineLimit(2).multilineTextAlignment(.center)
                if !day.info.dafYomi.isEmpty {
                    Text("דף יומי: \(day.info.dafYomi)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 4. Shabbos times

struct ShabbatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Shabbat", provider: ZmanimProvider()) { ShabbatView(day: WidgetDay($0)).widgetStyle() }
            .configurationDisplayName("זמני שבת")
            .description("הדלקת נרות וצאת השבת הקרובה, והפרשה.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ShabbatView: View {
    let day: WidgetDay
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let cal = day.cal
        // The coming Friday (today if it's Friday; Shabbos itself counts the Friday before).
        let weekday = cal.component(.weekday, from: day.now)
        let toFriday = weekday == 7 ? -1 : (6 - weekday + 7) % 7
        let friday = cal.date(byAdding: .day, value: toFriday, to: day.now)!
        let shabbos = cal.date(byAdding: .day, value: 1, to: friday)!
        // Customary candle-lighting offsets: Jerusalem 40, Haifa 30, else 18 minutes before sunset.
        let name = day.s.location.nameEn.lowercased()
        let offset: Double = name.contains("jerusalem") ? 40 : name.contains("haifa") ? 30 : 18
        let candles = ZmanEngine.calendar(for: friday, settings: day.s).myzCandleLighting(offset)
        let czcShabbos = ZmanEngine.calendar(for: shabbos, settings: day.s)
        let havdalah = czcShabbos.getTzaisGeonim8Point5Degrees()
        let rt = czcShabbos.getTzais72()
        let info = ZmanEngine.dayInfo(for: shabbos, settings: day.s)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("שבת").font(.headline)
                if !info.parsha.isEmpty { Text(info.parsha).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
            }
            Text(day.s.location.displayName).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            row("🕯️ הדלקת נרות", day.fmt.time(candles))
            row("✨ צאת השבת", day.fmt.time(havdalah))
            if family == .systemMedium {
                row("ר״ת", day.fmt.time(rt))
                Text("נרות \(Int(offset)) דק׳ לפני השקיעה · צאת השבת 8.5°").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Text(value).font(.system(.body, design: .rounded).bold()).monospacedDigit()
        }
    }
}
