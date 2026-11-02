import SwiftUI

struct ZmanimListView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.settings
        let date = model.selectedDate
        let isToday = model.isToday(date)
        let zmanim = isToday ? model.todayZmanim().today : ZmanEngine.zmanim(on: date, settings: s)
        let cal = ZmanEngine.gregorian(model.tz)
        let dayDiff = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        let dayState: ZmanRow.DayState = dayDiff == 0 ? .today : dayDiff < 0 ? .past : .future

        if dayDiff != 0 {
            HStack {
                Image(systemName: dayDiff < 0 ? "clock.arrow.circlepath" : "calendar.badge.clock")
                Text(dayDiff == -1 ? "אתמול" : dayDiff == 1 ? "מחר"
                     : dayDiff < 0 ? "לפני \(-dayDiff) ימים" : "בעוד \(dayDiff) ימים")
                Spacer()
                Button("חזרה להיום") { model.selectedDate = Date() }.buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(dayDiff < 0 ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 8)
        }

        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let now = ctx.date
                let nextID = isToday ? model.nextZmanID(at: now) : nil
                LazyVStack(spacing: 2) {
                    ForEach(zmanim) { z in
                        ZmanRow(z: z, now: now, day: dayState, isNext: z.id == nextID)
                    }
                }
            }
        }
        if s.zmanim.isEmpty {
            Text("הרשימה ריקה – הוסיפו זמנים בהגדרות").foregroundStyle(.secondary)
        }
    }
}

private struct ZmanRow: View {
    @EnvironmentObject var model: AppModel
    let z: ComputedZman
    let now: Date
    let day: DayState
    let isNext: Bool

    enum DayState { case past, today, future }

    var body: some View {
        let s = model.settings
        let isDuration = z.item.def?.isDuration == true
        let past: Bool = switch day {
        case .past: true
        case .future: false
        case .today: z.time.map { $0 < now } ?? false
        }

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
            if s.reminders.contains(where: { $0.zmanID == z.id && $0.enabled }) {
                Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isNext, let t = z.time {
                Text("\u{200E}-\(ZmanFormat.countdown(t.timeIntervalSince(now), showSeconds: true))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(isDuration ? ZmanFormat.duration(z.duration, seconds: s.showSeconds) : model.format.time(z.time))
                .monospacedDigit()
                .fontWeight(isNext ? .bold : .regular)
        }
        .foregroundStyle(color(past: past, isDuration: isDuration))
        .opacity(past && !isDuration ? 0.8 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(isNext ? Color.accentColor.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .help(z.item.def.map { "\($0.he)\n\n\($0.heInfo)" } ?? "")
        .contextMenu { menu(isDuration: isDuration) }
    }

    private func color(past: Bool, isDuration: Bool) -> Color {
        guard !isDuration else { return .secondary }
        if model.settings.colorPastZmanim { return Color(nsColor: past ? .systemRed : .systemGreen) }
        return past ? .secondary : .primary
    }

    @ViewBuilder
    private func menu(isDuration: Bool) -> some View {
        if !isDuration {
            Button("הצג בשורת התפריטים") {
                model.settings.menuBar.zmanMode = .pinned
                model.settings.menuBar.pinnedZman = z.id
            }
            Button("שורת התפריטים: הזמן הבא") { model.settings.menuBar.zmanMode = .next }
            Divider()
            Menu("תזכורת") {
                ForEach([0, 5, 10, 15, 30, 60], id: \.self) { m in
                    Button(m == 0 ? "בזמן" : "\(m) דקות לפני") {
                        model.settings.reminders.removeAll { $0.zmanID == z.id }
                        model.settings.reminders.append(Reminder(zmanID: z.id, minutesBefore: m))
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
                Task { try? await CalendarSync.shared.add(new, calendarID: target, timeZone: tz) }
            }
        }
        Button("העתק") {
            let text = "\(z.item.name): \(isDuration ? ZmanFormat.duration(z.duration) : model.format.time(z.time))"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
