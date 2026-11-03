import SwiftUI

struct ZmanimListView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.settings
        let date = model.selectedDate
        let isToday = model.isToday(date)
        let computed = isToday ? model.todayZmanim().today : ZmanEngine.zmanim(on: date, settings: s)
        let zmanim = s.sortByTime ? ZmanEngine.timeOrdered(computed) : computed
        let cal = ZmanEngine.gregorian(model.tz)
        let dayDiff = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        let dayState: ZmanRow.DayState = dayDiff == 0 ? .today : dayDiff < 0 ? .past : .future

        // One container: the popover gives its tab content maxHeight: .infinity, which would
        // otherwise be applied to each top-level view here and stretch the banner.
        VStack(spacing: 4) {
        if dayDiff != 0 {
            HStack {
                Image(systemName: dayDiff < 0 ? "clock.arrow.circlepath" : "calendar.badge.clock")
                Text(dayDiff == -1 ? "אתמול" : dayDiff == 1 ? "מחר"
                     : dayDiff < 0 ? "לפני \(-dayDiff) ימים" : "בעוד \(dayDiff) ימים")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(dayDiff < 0 ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 8)
        }

        // Rows change state at each zman (and the countdown on the minute); a per-second countdown, if seconds
        // are shown, ticks on its own in the next row – the rest of the list doesn't redraw every second.
        let times = isToday ? zmanim.compactMap(\.time) : []
        TimelineView(Ticks(changes: times)) { ctx in
            let now = ctx.date
            let nextID = isToday ? model.nextZmanID(at: now) : nil
            ScrollView {
                SpecialTimesCard(date: date, now: now, isToday: isToday)
                VStack(spacing: 2) {
                    ForEach(zmanim) { z in
                        ZmanRow(z: z, now: now, day: dayState, isNext: z.id == nextID)
                    }
                }
                .padding(.bottom, 14)   // so the last row clears the fade below
            }
            // No permanent scroller track ("show scroll bars: always" draws a wide white one); a soft fade at
            // the bottom shows there's more instead.
            .scrollIndicators(.never)
            .mask(VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 14)
            })
        }
        .id(model.dayKey(date))
        if s.zmanim.isEmpty {
            Text("הרשימה ריקה – הוסיפו זמנים בהגדרות").foregroundStyle(.secondary)
        }
        }
    }
}

/// Candle lighting, the end of Shabbos, fasts, chametz, Chanukah… – only on the days they apply.
private struct SpecialTimesCard: View {
    @EnvironmentObject var model: AppModel
    let date: Date
    let now: Date
    let isToday: Bool

    var body: some View {
        let times = model.specialTimes(date)
        if !times.isEmpty {
            VStack(spacing: 3) {
                ForEach(times) { t in
                    let past = isToday && (t.time ?? .distantFuture) < now
                    HStack(spacing: 6) {
                        Image(systemName: t.symbol).frame(width: 16).foregroundStyle(.orange)
                        Text(t.title).fontWeight(.medium)
                        Spacer()
                        Text(model.format.time(t.time)).monospacedDigit().fontWeight(.semibold)
                    }
                    .opacity(past ? 0.5 : 1)
                    .help(t.note)
                }
            }
            .font(.callout)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            .padding(.bottom, 4)
        }
    }
}

private struct ZmanRow: View {
    @EnvironmentObject var model: AppModel
    let z: ComputedZman
    let now: Date
    let day: DayState
    let isNext: Bool
    @ViewState private var hover = false
    @ViewState private var expanded = false

    enum DayState { case past, today, future }

    var body: some View {
        let s = model.settings
        let isDuration = z.item.def?.isDuration == true
        let past: Bool = switch day {
        case .past: true
        case .future: false
        case .today: z.time.map { $0 < now } ?? false
        }

        VStack(alignment: .leading, spacing: 4) {
        HStack {
                Group {
                    if isDuration { Image(systemName: "hourglass") }
                    else if isNext { Image(systemName: "arrowtriangle.left.fill") }
                    else if past { Image(systemName: "checkmark.circle") }
                    else { Image(systemName: "circle") }
                }
                .font(.caption2)
                .frame(width: 12)
                Text(z.item.name)
                    .lineLimit(1)
                if s.menuBar.zmanMode == .pinned && s.menuBar.pinnedZman == z.id {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                }
                if s.menuBar.zmanMode == .next && s.menuBar.hiddenZmanim.contains(z.id) {
                    Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.tertiary)
                        .help("לא מוצג בשורת התפריטים")
                }
                if s.reminders.contains(where: { $0.zmanID == z.id && $0.enabled }) {
                    Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isNext, let t = z.time {
                    TimelineView(Ticks(everySecond: s.showSeconds)) { ctx in
                        Text("בעוד \(ZmanFormat.countdown(t.timeIntervalSince(ctx.date), showSeconds: s.showSeconds))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(isDuration ? ZmanFormat.duration(z.duration, seconds: s.showSeconds) : model.format.time(z.time))
                    .monospacedDigit()
                    .fontWeight(isNext ? .bold : .regular)
            }
            if expanded, let def = z.item.def {
                VStack(alignment: .leading, spacing: 3) {
                    Text(def.he).font(.caption.bold())
                    Text(def.heInfo).font(.caption).fixedSize(horizontal: false, vertical: true)
                    if let t = z.time, !isDuration {
                        let diff = t.timeIntervalSince(now)
                        Text(diff >= 0 ? "בעוד \(ZmanFormat.countdown(diff, showSeconds: false))" : "לפני \(ZmanFormat.countdown(-diff, showSeconds: false))")
                            .font(.caption2.monospacedDigit())
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(color(past: past, isDuration: isDuration))
        .opacity(past && !isDuration ? 0.8 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(
            isNext ? Color.accentColor.opacity(0.18) : hover ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }
        .help("לחיצה – הסבר על הזמן · לחיצה ימנית – אפשרויות")
        .contextMenu { menu(isDuration: isDuration) }
    }

    private func color(past: Bool, isDuration: Bool) -> Color {
        guard !isDuration else { return .secondary }
        if model.settings.colorPastZmanim { return Color(nsColor: past ? .systemRed : .systemBlue) }
        return past ? .secondary : .primary
    }

    @ViewBuilder
    private func menu(isDuration: Bool) -> some View {
        if !isDuration {
            let mb = model.settings.menuBar
            let pinned = mb.zmanMode == .pinned && mb.pinnedZman == z.id
            let hidden = mb.hiddenZmanim.contains(z.id)
            Menu("שורת התפריטים") {
                if pinned {
                    Button("בטל הצמדה (הצג את הזמן הבא)") { model.settings.menuBar.zmanMode = .next }
                } else {
                    Button("הצמד זמן זה לשורת התפריטים") {
                        model.settings.menuBar.zmanMode = .pinned
                        model.settings.menuBar.pinnedZman = z.id
                        model.settings.menuBar.hiddenZmanim.removeAll { $0 == z.id }
                    }
                }
                Divider()
                if hidden {
                    Button("הצג זמן זה כ„הזמן הבא”") { model.settings.menuBar.hiddenZmanim.removeAll { $0 == z.id } }
                } else {
                    Button("אל תציג זמן זה בשורת התפריטים") {
                        var m = model.settings.menuBar
                        m.hiddenZmanim.append(z.id)
                        if pinned { m.zmanMode = .next }
                        model.settings.menuBar = m   // one change
                    }
                }
                if mb.zmanMode != .next && !pinned {
                    Button("הצג את הזמן הבא") { model.settings.menuBar.zmanMode = .next }
                }
            }
            Divider()
            Menu("תזכורת") {
                Section("כל יום") {
                    ForEach([0, 5, 10, 15, 30, 60], id: \.self) { m in
                        Button(m == 0 ? "בזמן" : "\(m) דקות לפני") {
                            var reminders = model.settings.reminders
                            reminders.removeAll { $0.zmanID == z.id && $0.kind == .zman && $0.repeatMode == .daily }
                            reminders.append(Reminder(zmanID: z.id, minutesBefore: m))
                            model.settings.reminders = reminders  // one change, one reschedule
                        }
                    }
                }
                // Once, on the day shown (today or another day picked in the popover) – if it's still ahead.
                if let t = z.time, t > Date() {
                    Section("פעם אחת – \(model.format.localizedDate(model.selectedDate, template: "EEEdMMM"))") {
                        ForEach([0, 5, 10, 15, 30, 60], id: \.self) { m in
                            if t.addingTimeInterval(-Double(m * 60)) > Date() {
                                Button(m == 0 ? "בזמן" : "\(m) דקות לפני") {
                                    var r = Reminder(zmanID: z.id, minutesBefore: m)
                                    r.repeatMode = .once
                                    r.onceDate = model.selectedDate
                                    model.settings.reminders.append(r)
                                }
                            }
                        }
                    }
                }
                if model.settings.reminders.contains(where: { $0.zmanID == z.id }) {
                    Divider()
                    Button("בטל תזכורת") { model.settings.reminders.removeAll { $0.zmanID == z.id } }
                }
            }
        }
        if !isDuration, let t = z.time {
            Button("הוסף ליומן") {
                let new = CalendarSync.NewEvent(title: z.item.name, start: t, allDay: false, durationMinutes: 15,
                                                notes: model.settings.location.displayName)
                let tz = model.tz, target = model.settings.calendarSync.targetCalendarID
                Task {
                    do { try await CalendarSync.shared.add(new, calendarID: target, timeZone: tz) }
                    catch { UserMessage.show("ההוספה ליומן נכשלה: \(error.localizedDescription)") }
                }
            }
        }
        Button("העתק") {
            let text = "\(z.item.name): \(isDuration ? ZmanFormat.duration(z.duration) : model.format.time(z.time))"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
