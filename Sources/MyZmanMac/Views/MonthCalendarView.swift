import SwiftUI

/// A Hebrew month grid (like Itim's tray calendar). Clicking a day shows its zmanim.
struct MonthCalendarView: View {
    @EnvironmentObject var model: AppModel
    let onPick: () -> Void
    @ViewState private var monthOffset = 0

    private var hebrew: Calendar {
        var c = Calendar(identifier: .hebrew)
        c.timeZone = model.tz
        return c
    }

    var body: some View {
        let cal = hebrew
        let anchor = cal.date(byAdding: .month, value: monthOffset, to: model.selectedDate)!
        let monthStart = cal.date(from: cal.dateComponents([.era, .year, .month], from: anchor))!
        let days = cal.range(of: .day, in: .month, for: monthStart)!.count
        let lead = cal.component(.weekday, from: monthStart) - 1
        let dates = (0..<days).map { cal.date(byAdding: .day, value: $0, to: monthStart)! }
        let mid = model.dayInfo(dates[14])
        let _ = CalendarSync.shared.version
        let busyDays = Set(CalendarSync.shared.busyDays(from: monthStart, to: cal.date(byAdding: .day, value: days, to: monthStart)!,
                                                        tz: model.tz, options: model.settings.calendarSync).map { model.dayKey($0) })
        let monthTitle = mid.hebrewDate.split(separator: " ").dropFirst().joined(separator: " ")
        let greg = "\(model.format.localizedDate(dates.first!, template: "MMM")) – \(model.format.localizedDate(dates.last!, template: "MMMyyyy"))"

        VStack(spacing: 8) {
            HStack {
                Button { shiftYear(-1, from: anchor) } label: { Image(systemName: "chevron.right.2") }
                    .buttonStyle(.borderless).help("שנה קודמת")
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).help("חודש קודם")
                Spacer()
                Menu {
                    ForEach(monthsOfYear(containing: anchor), id: \.date) { m in
                        Button(m.title) { jump(to: m.date) }
                    }
                } label: {
                    Text(monthTitle).font(.headline)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("בחירת חודש")
                Spacer()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("חודש הבא")
                Button { shiftYear(1, from: anchor) } label: { Image(systemName: "chevron.left.2") }
                    .buttonStyle(.borderless).help("שנה הבאה")
            }

            // "Today" and the date picker are in the day header above, shared by all tabs.
            HStack {
                Text(greg).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("מועדים") {
                    ForEach(upcomingEvents(from: anchor), id: \.date) { e in
                        Button(e.title) { jump(to: e.date) }
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .help("דילוג לחג או מועד קרוב")
            }
            .padding(.top, -6)

            let cols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
            LazyVGrid(columns: cols, spacing: 3) {
                ForEach(["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"], id: \.self) {
                    Text($0).font(.caption.bold()).foregroundStyle(.secondary)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(dates, id: \.self) { d in
                    DayCell(date: d, hasCalendarEvent: busyDays.contains(model.dayKey(d)),
                            select: { jump(to: d) },
                            open: { jump(to: d); onPick() })
                        .contextMenu {
                            Button("אירוע חדש ביום זה") { jump(to: d); model.newEventRequest += 1 }
                            Button("זמני היום") { jump(to: d); onPick() }
                        }
                }
            }
            .scrollStep { monthOffset += $0 }

            Spacer(minLength: 0)

            // Floating card: the selected day's calendar events (its date and details are in the day header above).
            VStack(alignment: .trailing, spacing: 4) {
                ScrollView {
                    DayEventsSection(date: model.selectedDate, embedded: true)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 140)
                Button("זמני היום ←", action: onPick).buttonStyle(.link).font(.caption)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .help("לחיצה – בחירת יום · לחיצה כפולה – זמני היום · גלגלת – מעבר חודש")
        }
    }

    private func jump(to date: Date) {
        model.selectedDate = date
        monthOffset = 0
    }

    private func shiftYear(_ years: Int, from anchor: Date) {
        jump(to: hebrew.date(byAdding: .year, value: years, to: anchor)!)
    }

    private struct Entry { let title: String; let date: Date }

    /// The months of the Hebrew year containing `date`, starting from Tishrei.
    private func monthsOfYear(containing date: Date) -> [Entry] {
        let cal = hebrew
        let year = cal.component(.year, from: date)
        let day = min(cal.component(.day, from: date), 29)
        var seen = Set<Int>()
        return (1...13).compactMap { m in
            guard let d = cal.date(from: DateComponents(era: 0, year: year, month: m, day: day)),
                  cal.component(.month, from: d) == m, seen.insert(m).inserted else { return nil }
            let info = model.dayInfo(d)
            return Entry(title: info.hebrewDate.split(separator: " ").dropFirst().joined(separator: " "), date: d)
        }
    }

    private static var eventsCache: (key: String, entries: [Entry])?

    /// Holidays and fasts in the coming year (skips daily omer counts and repeated days).
    private func upcomingEvents(from date: Date) -> [Entry] {
        let key = model.dayKey(date) + "|\(model.settings.location.id)|\(model.settings.inIsrael)|\(model.settings.useModernHolidays)"
        if let c = Self.eventsCache, c.key == key { return c.entries }
        let entries = computeUpcomingEvents(from: date)
        Self.eventsCache = (key, entries)
        return entries
    }

    private func computeUpcomingEvents(from date: Date) -> [Entry] {
        let cal = ZmanEngine.gregorian(model.tz)
        var result: [Entry] = []
        var last: Set<String> = []
        for i in 0..<385 {
            let d = cal.date(byAdding: .day, value: i, to: date)!
            let events = model.dayInfo(d).events.filter { !$0.contains("עומר") && $0 != "שבת מברכים" }
            // Collapse multi-day runs (the eight days of Chanukah, two-day Rosh Chodesh) into their first day:
            // list only the events that weren't there the day before.
            let keys = events.map { $0.replacingOccurrences(of: #"^\S+ (?=חנוכה)"#, with: "", options: .regularExpression) }
            let fresh = zip(events, keys).filter { !last.contains($0.1) }.map(\.0)
            if !fresh.isEmpty {
                result.append(Entry(title: "\(fresh.joined(separator: " · ")) – \(model.format.gregorianDate(d, style: "d/M"))", date: d))
            }
            last = Set(keys)
        }
        return result
    }
}

private struct DayCell: View {
    @EnvironmentObject var model: AppModel
    let date: Date
    var hasCalendarEvent = false
    let select: () -> Void
    let open: () -> Void

    var body: some View {
        let info = model.dayInfo(date)
        let cal = ZmanEngine.gregorian(model.tz)
        let isToday = model.isToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: model.selectedDate)
        let hasEvent = !info.events.isEmpty

        VStack(spacing: 0) {
                Text(info.hebrewDayNumber)
                    .font(.system(size: 14, weight: isToday ? .bold : .medium))
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isToday ? Color.accentColor.opacity(0.35)
                          : info.isShabbosOrYomTov ? Color.secondary.opacity(0.15) : Color.clear)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                if hasEvent { Circle().fill(.orange).frame(width: 5, height: 5).padding(4) }
            }
            .overlay(alignment: .topTrailing) {
                if hasCalendarEvent { Circle().fill(.blue).frame(width: 5, height: 5).padding(4) }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: open)
            .onTapGesture(perform: select)
            .help((info.events + [info.parsha]).filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}
