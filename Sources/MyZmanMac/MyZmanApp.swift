import SwiftUI
import ServiceManagement

@main
struct MyZmanApp: App {
    @StateObject private var model = AppModel.shared

    init() {
        if CommandLine.arguments.contains("--dump") { DebugDump.run(); exit(0) }
        if let i = CommandLine.arguments.firstIndex(of: "--preview") { DebugDump.preview(tab: CommandLine.arguments.dropFirst(i + 1).first) }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
        } label: {
            MenuBarLabel(title: model.menuBarTitle, showIcon: model.settings.menuBar.showIcon)
        }
        .menuBarExtraStyle(.window)

        Window("הגדרות זמנים", id: "settings") {
            SettingsView()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    let title: String
    let showIcon: Bool

    // Keep this a single, structurally stable Text: if the label's view tree changes shape
    // MenuBarExtra creates a fresh status item each time.
    var body: some View {
        if showIcon || title.isEmpty {
            Text("\(Image(systemName: "sun.horizon"))\(title.isEmpty ? "" : " " + title)")
        } else {
            Text(title)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

enum StatusItem {
    /// Re-opens the menu bar popover, e.g. after a system permission prompt took focus and closed it.
    @MainActor static func reopenPopover() {
        func button(in view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            if let b = view as? NSStatusBarButton { return b }
            for v in view.subviews { if let b = button(in: v) { return b } }
            return nil
        }
        let window = NSApp.windows.first { $0.className.contains("NSStatusBarWindow") && $0.frame.origin.y >= 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            button(in: window?.contentView)?.performClick(nil)
        }
    }
}

extension View {
    /// Brings an agent (menu-bar-only) app's window to the front.
    func activatingApp() -> some View {
        onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

/// `MyZman --dump [yyyy-MM-dd] [city]` prints a day's calculations to the terminal, for checking against a luach.
enum DebugDump {
    /// `--preview [tab]` shows the popover content in an ordinary window (for screenshots during development).
    @MainActor static func preview(tab: String?) {
        if let i = CommandLine.arguments.firstIndex(of: "--date"), i + 1 < CommandLine.arguments.count {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: CommandLine.arguments[i + 1]) { AppModel.shared.selectedDate = d }
        }
        DispatchQueue.main.async {
            let root: AnyView = tab?.hasPrefix("settings") == true
                ? AnyView(SettingsView(initialTab: Int(tab!.dropFirst(8)) ?? 0)
                    .environmentObject(AppModel.shared).environment(\.layoutDirection, .rightToLeft))
                : AnyView(PopoverView(initialTab: tab.flatMap(PopoverTab.init(rawValue:)) ?? .zmanim)
                    .environmentObject(AppModel.shared).environment(\.layoutDirection, .rightToLeft))
            let big = tab?.hasPrefix("settings") == true
            let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: big ? 620 : 370, height: big ? 560 : 600),
                             styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: root)
            if CommandLine.arguments.contains("--dark") { w.appearance = NSAppearance(named: .darkAqua) }
            if CommandLine.arguments.contains("--light") { w.appearance = NSAppearance(named: .aqua) }
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("window", w.windowNumber)
            fflush(stdout)
        }
    }

    @MainActor static func run() {
        var s = AppSettings.load()
        let args = CommandLine.arguments.drop { $0 != "--dump" }.dropFirst()
        if let city = args.dropFirst().first, let loc = Location.builtIn.first(where: { $0.nameEn == city || $0.nameHe == city }) {
            s.location = loc
        }
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        parse.timeZone = s.location.timeZone
        let day = args.first.flatMap { parse.date(from: $0) } ?? Date()
        let info = ZmanEngine.dayInfo(for: day, settings: s)
        print("\(s.location.nameEn) \(ZmanFormat(s).gregorianDate(day)) | \(info.hebrewDate) | \(info.weekday) | \(info.parsha) | \(info.events) | \(info.dafYomi)")
        let f = ZmanFormat(s)
        for z in ZmanEngine.zmanim(on: day, settings: s) {
            print("  \(z.item.name): \(z.item.def?.isDuration == true ? ZmanFormat.duration(z.duration) : f.time(z.time))")
        }
        if args.contains("--plan") {
            var t = Reminder(kind: .time); t.hour = 7; t.minute = 30; t.repeatMode = .weekdays; t.weekdays = [1, 3]; t.label = "שיעור"
            var o = Reminder(kind: .time); o.hour = 20; o.repeatMode = .once; o.onceDate = day.addingTimeInterval(3 * 86400); o.label = "פעם אחת"
            let z = Reminder(zmanID: s.zmanim.first { $0.defID == "GetSunset" }!.id, minutesBefore: 15)
            s.reminders = [t, o, z]
            let f = ZmanFormat(s)
            for p in ReminderScheduler.plan(s, from: day, days: 7) {
                print("  ⏰ \(f.localizedDate(p.fire, template: "EEEdMMM")) \(f.time(p.fire)) | \(p.title) | \(p.body)")
            }
        }
        if args.contains("--all") {
            let czc = ZmanEngine.calendar(for: day, settings: s)
            for d in ZmanCatalog.all {
                let (t, dur) = ZmanEngine.compute(d, on: czc)
                print("  [\(d.id)] \(d.isDuration ? ZmanFormat.duration(dur) : f.time(t))")
            }
        }
    }
}
