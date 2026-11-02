import WidgetKit
import SwiftUI

/// Desktop / Notification Center widget. It calculates zmanim itself (same model code as the app)
/// from the settings file the app writes, and schedules a timeline entry at every zman.
@main
struct ZmanimWidgets: WidgetBundle {
    var body: some Widget {
        ZmanimWidget()
    }
}

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

struct ZmanimWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZmanimWidget", provider: ZmanimProvider()) { entry in
            ZmanimWidgetView(entry: entry)
                .environment(\.layoutDirection, .rightToLeft)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("זמנים")
        .description("התאריך העברי והזמן הבא, עם ספירה לאחור.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ZmanimWidgetView: View {
    let entry: ZmanimEntry
    @Environment(\.widgetFamily) private var family

    private var s: AppSettings { entry.settings }

    var body: some View {
        let now = entry.date
        let fmt = ZmanFormat(s)
        let cal = ZmanEngine.gregorian(s.location.timeZone)
        let hebrewDay: Date = {
            guard s.hebrewDateChangesAtSunset, let ss = ZmanEngine.sunset(on: now, settings: s), now >= ss else { return now }
            return cal.date(byAdding: .day, value: 1, to: now)!
        }()
        let info = ZmanEngine.dayInfo(for: hebrewDay, settings: s)
        let today = ZmanEngine.zmanim(on: now, settings: s).filter { $0.item.def?.isDuration == false }
        let upcoming = (today + ZmanEngine.zmanim(on: cal.date(byAdding: .day, value: 1, to: now)!, settings: s))
            .filter { ($0.time ?? .distantPast) > now }
        let next = upcoming.first

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.hebrewDayMonth).font(.headline)
                Spacer()
                Text(s.location.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if family != .systemSmall {
                Text(([info.parsha] + info.events).filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            if let next, let t = next.time {
                Spacer(minLength: 2)
                Text(next.item.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(fmt.time(t)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text(t, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                }
            }

            if family != .systemSmall {
                let rows = family == .systemLarge ? today : Array(upcoming.dropFirst().prefix(3))
                Divider()
                ForEach(rows) { z in
                    let past = (z.time ?? .distantFuture) < now
                    HStack {
                        Text(z.item.name).lineLimit(1)
                        Spacer()
                        Text(fmt.time(z.time)).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(past ? .secondary : .primary)
                }
            }
            Spacer(minLength: 0)
            if family == .systemLarge {
                Text(Disclaimer.short).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}
