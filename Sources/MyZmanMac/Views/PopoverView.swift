import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case zmanim = "זמנים", calendar = "לוח", converter = "ממיר"
    var id: String { rawValue }
}

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ViewState private var tab: PopoverTab

    init(initialTab: PopoverTab = .zmanim) {
        _tab = ViewState(wrappedValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 10) {
            TopBar(openSettings: openSettings)
            if tab != .calendar {
                DayHeader(date: model.selectedDate)
            }
            Picker("", selection: $tab) {
                ForEach(PopoverTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .zmanim: ZmanimListView()
                case .calendar: MonthCalendarView(onPick: { tab = .zmanim })
                case .converter: ConverterView(onShow: { tab = .zmanim })
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Text("⚠︎ " + Disclaimer.short)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .help(Disclaimer.full)
        }
        .padding(12)
        .frame(width: 370, height: 600)
        // Opaque, so the window behind the popover doesn't wash out the colors.
        .background(Color(nsColor: .windowBackgroundColor))
        // Bring the (menu-bar-only) app forward so controls render active, in the accent color.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func openSettings() {
        // Close the menu bar popover first, otherwise it stays on top of the settings window.
        let popover = NSApp.windows.first { $0.className.contains("MenuBarExtra") && $0.isVisible } ?? NSApp.keyWindow
        popover?.close()
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first { $0.title == "הגדרות זמנים" }?.makeKeyAndOrderFront(nil)
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                let s = model.settings
                if !s.customLocations.isEmpty {
                    Section("מיקומים שלי") {
                        ForEach(s.customLocations) { loc in Button(loc.displayName) { model.select(location: loc) } }
                    }
                }
                ForEach(Region.allCases.filter { $0 != .custom }) { region in
                    Menu(region.title) {
                        ForEach(Location.builtIn.filter { $0.region == region }.sorted { $0.displayName < $1.displayName }) { loc in
                            Button(loc.displayName) { model.select(location: loc) }
                        }
                    }
                }
                Divider()
                Button("ניהול מיקומים…", action: openSettings)
            } label: {
                Label(model.settings.location.displayName, systemImage: "mappin.and.ellipse")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(model.format.time(ctx.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("השעה במיקום הנבחר")
            }

            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("הגדרות")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless)
                .help("יציאה")
        }
    }
}

struct DayHeader: View {
    @EnvironmentObject var model: AppModel
    let date: Date

    var body: some View {
        let isToday = model.isToday(date)
        let info = model.dayInfo(date)
        let cal = ZmanEngine.gregorian(model.tz)

        VStack(spacing: 6) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).help("יום קודם")
                Spacer()
                VStack(spacing: 2) {
                    Text(info.hebrewDate)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(model.format.localizedDate(date, template: "EEEEdMMMMyyyy"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("יום הבא")
            }

            if isToday, model.settings.hebrewDateChangesAtSunset,
               !cal.isDate(model.currentHebrewDay(at: model.now), inSameDayAs: date) {
                Text("אחרי השקיעה – התאריך העברי: \(model.dayInfo(model.currentHebrewDay(at: model.now)).hebrewDayMonth)")
                    .font(.caption).foregroundStyle(.orange)
            }

            FlowChips(items: ([info.parsha] + info.events).filter { !$0.isEmpty })

            HStack(spacing: 12) {
                if !info.dafYomi.isEmpty {
                    Label("דף יומי: \(info.dafYomi)", systemImage: "book.closed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !isToday {
                    Button("חזרה להיום") { model.selectedDate = Date() }
                        .buttonStyle(.link).font(.caption)
                }
                DateJumpButton(date: $model.selectedDate)
                    .controlSize(.small)
            }
        }
    }

    private func shift(_ days: Int) {
        model.selectedDate = ZmanEngine.gregorian(model.tz).date(byAdding: .day, value: days, to: model.selectedDate)!
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { s in
                    Text(s)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
        }
    }
}
