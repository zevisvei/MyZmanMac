import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case zmanim = "זמנים", calendar = "לוח", converter = "ממיר"
    var id: String { rawValue }
}

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
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
        // (Not the app's own main window, which shows this same view when the menu bar item is off.)
        let popover = NSApp.windows.first { $0.className.contains("MenuBarExtra") && $0.isVisible }
            ?? NSApp.keyWindow.flatMap { AppWindows.isManaged($0) ? nil : $0 }
        popover?.close()
        AppWindows.showSettings()
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
                    .buttonStyle(.borderless).help("יום קודם (→)")
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Spacer()
                VStack(spacing: 2) {
                    Text(info.hebrewDate)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.opacity)
                    Text(model.format.localizedDate(date, template: "EEEEdMMMMyyyy"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("יום הבא (←)")
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            .scrollStep { shift($0) }
            .help("גלגלת – מעבר בין ימים")

            if isToday, model.settings.hebrewDateChangesAtSunset,
               !cal.isDate(model.currentHebrewDay(at: Date()), inSameDayAs: date) {
                Text("אחרי השקיעה – התאריך העברי: \(model.dayInfo(model.currentHebrewDay(at: Date())).hebrewDayMonth)")
                    .font(.caption).foregroundStyle(.orange)
            }

            FlowChips(items: ([info.parsha] + info.events).filter { !$0.isEmpty })
            if model.settings.showTefila, !info.tefila.isEmpty {
                FlowChips(items: info.tefila, tint: .green)
                    .help("שינויים בתפילת היום (לפי KosherJava; יש לבדוק במנהג המקום)")
            }
            if !info.molad.isEmpty {
                Label(info.molad, systemImage: "moon").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !info.dafYomi.isEmpty {
                    Label("דף יומי: \(info.dafYomi)", systemImage: "book.closed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.settings.showYerushalmi, !info.yerushalmi.isEmpty {
                    Text("ירושלמי: \(info.yerushalmi)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !isToday {
                    Button("חזרה להיום") { withAnimation(.easeInOut(duration: 0.15)) { model.selectedDate = Date() } }
                        .buttonStyle(.link).font(.caption)
                        .keyboardShortcut("t", modifiers: .command)
                }
                DateJumpButton(date: $model.selectedDate)
                    .controlSize(.small)
            }
        }
    }

    private func shift(_ days: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
            model.selectedDate = ZmanEngine.gregorian(model.tz).date(byAdding: .day, value: days, to: model.selectedDate)!
        }
    }
}

struct FlowChips: View {
    let items: [String]
    var tint: Color = .accentColor
    var body: some View {
        if !items.isEmpty {
            WrapLayout(spacing: 6) {
                ForEach(items, id: \.self) { s in
                    Text(s)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.15)))
                }
            }
        }
    }
}

/// Lays children out in rows, wrapping to the next row when one is full; each row is centered.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]], x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.map { $0.map(\.1.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map { $0.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, $0.count - 1)) }.max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let rowWidth = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            let height = row.map(\.1.height).max() ?? 0
            var x = bounds.midX - rowWidth / 2
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing
        }
    }
}
