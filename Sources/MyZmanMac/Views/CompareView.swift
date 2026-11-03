import SwiftUI

/// The selected day's zmanim in the current location next to up to three others, each in its own local time.
struct CompareView: View {
    @EnvironmentObject var model: AppModel
    static let maxOthers = 3

    var body: some View {
        let s = model.settings
        let locations = [s.location] + s.compareLocations.filter { $0 != s.location }.prefix(Self.maxOthers)
        let columns = locations.map { loc in (loc, zmanim(at: loc)) }
        let rows = (s.sortByTime ? ZmanEngine.timeOrdered(columns[0].1) : columns[0].1)
            .filter { $0.item.def?.isDuration != true }

        VStack(spacing: 8) {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                    GridRow {
                        Text("")
                        ForEach(locations, id: \.self) { loc in header(loc, isCurrent: loc == s.location) }
                    }
                    Divider()
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.item.name).lineLimit(1).font(.callout).layoutPriority(1).help(row.item.name)
                            ForEach(columns, id: \.0) { loc, zmanim in
                                Text(ZmanFormat(settings(at: loc)).time(zmanim.first { $0.id == row.id }?.time))
                                    .monospacedDigit().font(.callout).fixedSize()
                                    .gridColumnAlignment(.center)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)

            HStack {
                if locations.count <= Self.maxOthers {
                    Menu {
                        LocationMenuItems { loc in
                            guard loc != s.location, !s.compareLocations.contains(loc) else { return }
                            model.settings.compareLocations.append(loc)
                        }
                    } label: {
                        Label("הוסף מיקום להשוואה", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Spacer()
                Text("כל זמן בשעון המקומי של המיקום")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ loc: Location, isCurrent: Bool) -> some View {
        Text(TopBar.short(loc.displayName))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: 62)
            .gridColumnAlignment(.center)
            .foregroundStyle(isCurrent ? Color.accentColor : .primary)
            .help(isCurrent ? "המיקום הנבחר" : "לחיצה ימנית להסרה או להחלפה")
            .contextMenu {
                if !isCurrent {
                    Button("הצג זמנים למיקום זה") { model.select(location: loc) }
                    Button("הסר מההשוואה") { model.settings.compareLocations.removeAll { $0 == loc } }
                }
            }
    }

    private func settings(at loc: Location) -> AppSettings {
        var s = model.settings
        s.location = loc
        return s
    }

    /// The same calendar day as the one selected, in the other location's own time zone.
    private func zmanim(at loc: Location) -> [ComputedZman] {
        let c = ZmanEngine.gregorian(model.tz).dateComponents([.year, .month, .day], from: model.selectedDate)
        let day = ZmanEngine.gregorian(loc.timeZone)
            .date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) ?? model.selectedDate
        return ZmanEngine.zmanim(on: day, settings: settings(at: loc))
    }
}
