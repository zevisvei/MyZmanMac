import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case zmanim = "זמנים", calendar = "לוח", compare = "השוואה", converter = "ממיר"
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
            // The tabs stay put right under the top bar: the day header below them varies in height
            // (holidays, tefila, molad) and isn't shown on the calendar tab.
            Picker("", selection: $tab) {
                ForEach(PopoverTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // The same day header on every tab, so switching tabs only swaps the content below it.
            DayHeader(date: model.selectedDate)

            Group {
                switch tab {
                case .zmanim: ZmanimListView()
                case .calendar: MonthCalendarView(onPick: { tab = .zmanim })
                case .compare: CompareView()
                case .converter: ConverterView(onShow: { tab = .zmanim })
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            UpdateBanner()

            Text("⚠︎ " + Disclaimer.short)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .help(Disclaimer.full)
        }
        .padding(12)
        .frame(width: 370, height: 640)
        // Opaque, so the window behind the popover doesn't wash out the colors.
        .background(Color(nsColor: .windowBackgroundColor))
        // Bring the (menu-bar-only) app forward so controls render active, in the accent color.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func openSettings() {
        // The settings window first, then close the popover (which would otherwise stay on top of it): with the
        // popover closed first, the app is briefly left with no key window and the system hands the focus to
        // another app.
        AppWindows.showSettings()
        StatusBarController.shared.closePopover()
    }
}

/// A newer version, offered at the bottom of the popover until it's installed or dismissed.
private struct UpdateBanner: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if let r = updater.offered {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                Text("גרסה \(r.version) זמינה")
                Spacer()
                Button("עדכן") { Task { await updater.install(r) } }
                    .controlSize(.small)
                Button { updater.skip(r) } label: { Label("לא עכשיו", systemImage: "xmark").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
                    .help("דלג על גרסה זו")
            }
            .font(.callout)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if case .installFailed(_, let message) = updater.state {
            HStack(spacing: 8) {
                Text(message).foregroundStyle(.red)
                Link("להורדה", destination: Updater.releasesPage)
                Button { updater.dismissFailure() } label: { Label("סגור", systemImage: "xmark").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
        } else if updater.state == .installing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("מתקין את העדכון…")
            }
            .font(.callout)
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    let openSettings: () -> Void

    /// A long custom location name, shortened so it doesn't push the clock and buttons out of the popover.
    static func short(_ name: String) -> String {
        name.count > 22 ? String(name.prefix(21)) + "…" : name
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                LocationMenuItems { model.select(location: $0) }
                Divider()
                Button("ניהול מיקומים…", action: openSettings)
            } label: {
                Label(Self.short(model.settings.location.displayName), systemImage: "mappin.and.ellipse")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            TimelineView(Ticks(everySecond: model.settings.showSeconds)) { ctx in
                Text(model.format.time(ctx.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("השעה במיקום הנבחר")
            }

            Button(action: openSettings) { Label("הגדרות", systemImage: "gearshape").labelStyle(.iconOnly) }
                .buttonStyle(.borderless)
                .help("הגדרות")
            Button { NSApp.terminate(nil) } label: { Label("יציאה", systemImage: "power").labelStyle(.iconOnly) }
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

        VStack(spacing: 6) {
            HStack {
                Button { shift(-1) } label: { Label("יום קודם", systemImage: "chevron.right").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless).help("יום קודם (→)")
                    // Not while typing in a text field: there the arrows move the caret.
                    .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
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
                Button { shift(1) } label: { Label("יום הבא", systemImage: "chevron.left").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless).help("יום הבא (←)")
                    .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
            }
            .scrollStep { shift($0) }
            .help("גלגלת – מעבר בין ימים")

            // Fixed rows, each one line high whatever the day, so nothing below (the zmanim list, the month
            // grid) moves when the day changes: chips that don't fit collapse into "+N".
            OneLineChips(items: ([info.parsha] + info.events).filter { !$0.isEmpty })
            if model.settings.showTefila {
                OneLineChips(items: info.tefila, tint: .green)
                    .help("שינויים בתפילת היום (לפי KosherJava; יש לבדוק במנהג המקום)")
            }
            DayNoteLine(date: date, molad: info.molad)

            HStack(spacing: 12) {
                LearningButton(date: date, info: info)
                if model.settings.showYerushalmi, !info.yerushalmi.isEmpty {
                    // Gives way first when "back to today" also needs room.
                    Text("ירושלמי: \(info.yerushalmi)").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
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

/// The Daf Yomi on one line; a click shows the rest of the day's learning and the haftara, which
/// would otherwise make the header's height change from day to day.
private struct LearningButton: View {
    @EnvironmentObject var model: AppModel
    let date: Date
    let info: DayInfo
    @ViewState private var shown = false

    var body: some View {
        let items = learning()
        Button { shown.toggle() } label: {
            HStack(spacing: 3) {
                Label(info.dafYomi.isEmpty ? "לימוד היום" : "דף יומי: \(info.dafYomi)", systemImage: "book.closed")
                if items.count > 1 { Image(systemName: "chevron.down").imageScale(.small) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(items.count <= 1)
        .help(items.count > 1 ? "לימוד היום וההפטרה" : "")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(items, id: \.0) { title, text in
                    GridRow {
                        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(text).font(.callout).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(width: 320)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }

    private func learning() -> [(String, String)] {
        let s = model.settings
        var out: [(String, String)] = []
        if !info.dafYomi.isEmpty { out.append(("דף יומי", info.dafYomi)) }
        if s.showYerushalmi, !info.yerushalmi.isEmpty { out.append(("ירושלמי", info.yerushalmi)) }
        let cal = ZmanEngine.gregorian(model.tz)
        for c in s.learning {
            let text = DailyLearning.portion(c, on: date, calendar: cal)
            if !text.isEmpty { out.append((DailyLearning.title(c), text)) }
        }
        if s.showHaftara {
            let jc = ZmanEngine.jewishCalendar(for: date, settings: s)
            let sefard = s.nusach == .sefard
            if let h = Haftara.reading(for: jc, sefard: sefard) { out.append(("הפטרה", h)) }
            if let h = Haftara.minchaReading(for: jc, sefard: sefard) { out.append(("הפטרה במנחה", h)) }
        }
        return out
    }
}

/// Chips on a single line: as many as fit, then "+N" (all of them in the tooltip). Always one line high, empty or not.
struct OneLineChips: View {
    let items: [String]
    var tint: Color = .accentColor

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: items.count, through: 0, by: -1)), id: \.self) { shown in
                HStack(spacing: 6) {
                    ForEach(items.prefix(shown), id: \.self) { chip($0) }
                    if shown < items.count { chip("+\(items.count - shown)") }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .help(items.joined(separator: "\n"))
    }

    private func chip(_ s: String) -> some View {
        Text(s)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

/// One line, always there: after sunset (today) the evening's Hebrew date, otherwise the molad on Shabbos
/// Mevarchim, otherwise blank. Redraws itself at sunset.
private struct DayNoteLine: View {
    @EnvironmentObject var model: AppModel
    let date: Date
    let molad: String

    var body: some View {
        let sunset = model.isToday(date) ? ZmanEngine.sunset(on: date, settings: model.settings) : nil
        TimelineView(Ticks(changes: sunset.map { [$0] } ?? [])) { ctx in
            let evening = model.isToday(date) && model.settings.hebrewDateChangesAtSunset
                && !ZmanEngine.gregorian(model.tz).isDate(model.currentHebrewDay(at: ctx.date), inSameDayAs: date)
            HStack(spacing: 10) {
                if evening {
                    Text("אחרי השקיעה – התאריך העברי: \(model.dayInfo(model.currentHebrewDay(at: ctx.date)).hebrewDayMonth)")
                        .foregroundStyle(.orange)
                }
                if !molad.isEmpty { Label(molad, systemImage: "moon").foregroundStyle(.secondary) }
            }
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 15)
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

/// The user's locations, then the built-in ones by region – for a location menu.
struct LocationMenuItems: View {
    @EnvironmentObject var model: AppModel
    let pick: (Location) -> Void

    var body: some View {
        let s = model.settings
        if !s.favoriteLocations.isEmpty {
            Section("מועדפים") {
                ForEach(s.favoriteLocations) { loc in Button(loc.displayName) { pick(loc) } }
            }
        }
        let custom = s.customLocations.filter { !s.favoriteLocations.contains($0) }
        if !custom.isEmpty {
            Section("מיקומים שלי") {
                ForEach(custom) { loc in Button(loc.displayName) { pick(loc) } }
            }
        }
        ForEach(Region.allCases.filter { $0 != .custom }) { region in
            Menu(region.title) {
                ForEach(Location.builtIn.filter { $0.region == region }.sorted { $0.displayName < $1.displayName }) { loc in
                    Button(loc.displayName) { pick(loc) }
                }
            }
        }
    }
}
