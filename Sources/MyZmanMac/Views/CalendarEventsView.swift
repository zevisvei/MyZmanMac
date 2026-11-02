import SwiftUI

/// The user's own Calendar events for the selected day, plus a quick "new event" form.
struct DayEventsSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var sync = CalendarSync.shared
    let date: Date
    var embedded = false
    @ViewState private var adding = false

    var body: some View {
        let opts = model.settings.calendarSync
        if opts.showCalendarEvents || adding {
            let _ = sync.version
            let cal = ZmanEngine.gregorian(model.tz)
            let start = cal.startOfDay(for: date)
            let events = sync.userEvents(from: start, to: cal.date(byAdding: .day, value: 1, to: start)!, options: opts)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("ביומן", systemImage: "calendar").font(.subheadline.bold())
                    Spacer()
                    Button { sync.openInCalendarApp(date) } label: { Image(systemName: "arrow.up.forward.app") }
                        .buttonStyle(.borderless).help("פתח ביומן")
                    if !adding {
                        Button { adding = true } label: { Label("אירוע חדש", systemImage: "plus") }
                            .controlSize(.small)
                            .disabled(!sync.hasAccess)
                    }
                }
                if !sync.hasAccess {
                    Button("אשר גישה ליומן") {
                        Task {
                            _ = try? await sync.requestAccess()
                            StatusItem.reopenPopover()
                        }
                    }.buttonStyle(.link)
                } else if events.isEmpty && !adding {
                    Text("אין אירועים").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(events) { e in
                    EventRow(event: e)
                }
                if adding {
                    NewEventForm(date: date) { adding = false }
                }
            }
            .onChange(of: model.newEventRequest) { adding = true }
            .padding(embedded ? 0 : 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(embedded ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary.opacity(0.5))))
        }
    }
}

private struct NewEventForm: View {
    @EnvironmentObject var model: AppModel
    let date: Date
    let done: () -> Void

    @ViewState private var title = ""
    @ViewState private var allDay = true
    @ViewState private var time = Date()
    @ViewState private var calendarID: String?
    @ViewState private var byHebrewDate = false
    @ViewState private var years = 10
    @ViewState private var error: String?
    @ViewState private var saving = false

    var body: some View {
        let sync = CalendarSync.shared
        let info = model.dayInfo(date)
        VStack(alignment: .leading, spacing: 6) {
            TextField("כותרת", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                Toggle("כל היום", isOn: $allDay)
                if !allDay {
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden().environment(\.timeZone, model.tz)
                }
            }
            Picker("לוח", selection: $calendarID) {
                Text("לוח היעד מההגדרות").tag(String?.none)
                ForEach(sync.writableCalendars()) { c in Text("\(c.title) (\(c.account))").tag(Optional(c.id)) }
            }
            Toggle("חוזר כל שנה לפי התאריך העברי (\(info.hebrewDayMonth))", isOn: $byHebrewDate)
            if byHebrewDate {
                Stepper("למשך \(years) שנים", value: $years, in: 2...50)
            }
            HStack {
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Spacer()
                Button("ביטול", action: done)
                Button("שמור ביומן", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .controlSize(.small)
        .onAppear {
            calendarID = model.settings.calendarSync.targetCalendarID
            time = ZmanEngine.gregorian(model.tz).date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
    }

    private func save() {
        let cal = ZmanEngine.gregorian(model.tz)
        let clock = cal.dateComponents([.hour, .minute], from: time)
        let start = allDay ? cal.startOfDay(for: date)
            : cal.date(bySettingHour: clock.hour ?? 9, minute: clock.minute ?? 0, second: 0, of: date)!
        let new = CalendarSync.NewEvent(title: title, start: start, allDay: allDay)
        saving = true
        Task {
            do {
                if byHebrewDate {
                    var hebrew = Calendar(identifier: .hebrew)
                    hebrew.timeZone = model.tz
                    let c = hebrew.dateComponents([.year, .month, .day], from: date)
                    try await CalendarSync.shared.addHebrewRecurring(
                        new, hebrewMonth: c.month!, hebrewDay: c.day!, fromYear: c.year!, years: years,
                        calendarID: calendarID, timeZone: model.tz)
                } else {
                    try await CalendarSync.shared.add(new, calendarID: calendarID, timeZone: model.tz)
                }
                done()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}

private struct EventRow: View {
    @EnvironmentObject var model: AppModel
    let event: CalendarSync.DayEvent
    @ViewState private var hover = false

    var body: some View {
        let e = event
        HStack(spacing: 6) {
            Circle().fill(Color(nsColor: e.color)).frame(width: 7, height: 7)
            Text(e.title).lineLimit(1)
            Spacer()
            Text(e.allDay ? "כל היום" : model.format.time(e.start))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.accentColor.opacity(0.15) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { CalendarSync.shared.openEvent(e) }
        .help("\(e.calendar) · לחיצה לפתיחה ביומן")
        .contextMenu {
            Button("פתח ביומן") { CalendarSync.shared.openEvent(e) }
            Button("העתק") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(e.title, forType: .string)
            }
            if e.canDelete {
                Divider()
                Button("מחק אירוע", role: .destructive) { try? CalendarSync.shared.delete(e) }
            }
        }
    }
}
