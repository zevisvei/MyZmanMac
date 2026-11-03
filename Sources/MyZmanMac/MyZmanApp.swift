import SwiftUI
import ServiceManagement

@main
struct MyZmanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    init() {
        if CommandLine.arguments.contains("--dump") { DebugDump.run(); exit(0) }
        if let i = CommandLine.arguments.firstIndex(of: "--preview") { DebugDump.preview(tab: CommandLine.arguments.dropFirst(i + 1).first) }
    }

    var body: some Scene {
        // Settings and the main window are AppKit windows (AppWindows), so they can be opened
        // even when there is no status item to host a SwiftUI openWindow action.
        MenuBarExtra(isInserted: $model.settings.menuBar.showInMenuBar) {
            PopoverView()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
        } label: {
            MenuBarLabel(title: model.menuBarTitle, showIcon: model.settings.menuBar.showIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--preview") else { return }
        // Without a status item nothing would show that the app opened, unless it started with the Mac.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        MainActor.assumeIsolated {
            if !AppModel.shared.settings.menuBar.showInMenuBar, !atLogin { AppWindows.showMain() }
        }
    }

    /// Opening the app again from Finder / Spotlight / Launchpad.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppWindows.showApp() }
        return false
    }

    /// myzman://open, from clicking a widget.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { AppWindows.showApp() }
    }
}

@MainActor
enum AppWindows {
    private static var windows: [String: NSWindow] = [:]

    /// The popover when the app is in the menu bar, otherwise the same content in a window.
    static func showApp() {
        if AppModel.shared.settings.menuBar.showInMenuBar { StatusItem.reopenPopover() } else { showMain() }
    }

    static func showMain() {
        show("main", title: "זמנים") { PopoverView() }
    }

    static func showSettings() {
        show("settings", title: "הגדרות זמנים") { SettingsView() }
    }

    static func isManaged(_ w: NSWindow) -> Bool { windows.values.contains(w) }

    private static func show<V: View>(_ id: String, title: String, content: () -> V) {
        let w = windows[id] ?? {
            let host = NSHostingController(rootView: content()
                .environmentObject(AppModel.shared)
                .environment(\.layoutDirection, .rightToLeft))
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.title = title
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            if !w.setFrameUsingName(id) { w.center() }
            w.setFrameAutosaveName(id)
            windows[id] = w
            return w
        }()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
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
        parse.dateFormat = "yyyy-MM-dd HH"
        parse.timeZone = s.location.timeZone
        // At noon: some zones skip midnight when DST starts, and "yyyy-MM-dd" alone would then not parse.
        let day = args.first.flatMap { parse.date(from: $0 + " 12") } ?? Date()
        let info = ZmanEngine.dayInfo(for: day, settings: s)
        print("\(s.location.nameEn) \(ZmanFormat(s).gregorianDate(day)) | \(info.hebrewDate) | \(info.weekday) | \(info.parsha) | \(info.events) | \(info.dafYomi)")
        let f = ZmanFormat(s)
        print("  ירושלמי: \(info.yerushalmi) | תפילה: \(info.tefila.joined(separator: ", ")) | \(info.molad)")
        for t in SpecialTimes.on(day, settings: s) { print("  * \(t.title): \(f.time(t.time)) (\(t.note))") }
        if args.contains("--shabbos"), let p = SpecialTimes.nextPeriod(from: day, settings: s) {
            print("  » \(p.title): נרות \(f.localizedDate(p.candles ?? day, template: "EEEdMMM")) \(f.time(p.candles)) · צאת \(f.localizedDate(p.end ?? day, template: "EEEdMMM")) \(f.time(p.end))")
        }
        for z in ZmanEngine.zmanim(on: day, settings: s) {
            print("  \(z.item.name): \(z.item.def?.isDuration == true ? ZmanFormat.duration(z.duration) : f.time(z.time))")
        }
        if args.contains("--plan") {
            var t = Reminder(kind: .time); t.hour = 7; t.minute = 30; t.repeatMode = .weekdays; t.weekdays = [1, 3]; t.label = "שיעור"
            var o = Reminder(kind: .time); o.hour = 20; o.repeatMode = .once; o.onceDate = day.addingTimeInterval(3 * 86400); o.label = "פעם אחת"
            let z = Reminder(zmanID: s.zmanim.first { $0.defID == "GetSunset" }!.id, minutesBefore: 15)
            var c = Reminder(kind: .candles); c.minutesBefore = 30
            s.reminders = [t, o, z, c]
            let f = ZmanFormat(s)
            for p in ReminderScheduler.plan(s, from: day, days: 7) {
                print("  ⏰ \(f.localizedDate(p.fire, template: "EEEdMMM")) \(f.time(p.fire)) | \(p.title) | \(p.body)")
            }
        }
        // `--anniversary <rule> <years>`: the Hebrew anniversaries of the dump's date, e.g. for checking against Hebcal.
        if let i = args.firstIndex(of: "--anniversary"), let rule = HebrewDates.Rule(rawValue: args[safe: i + 1] ?? "") {
            var hebrew = Calendar(identifier: .hebrew)
            hebrew.timeZone = s.location.timeZone
            let c = hebrew.dateComponents([.year, .month, .day], from: day)
            for y in c.year! + 1...c.year! + (Int(args[safe: i + 2] ?? "") ?? 10) {
                print("  \(y): \(HebrewDates.anniversary(of: c, in: y, rule: rule, calendar: hebrew).map { f.gregorianDate($0, style: "yyyy-MM-dd") } ?? "—")")
            }
        }
        if args.contains("--all") {
            let czc = ZmanEngine.calendar(for: day, settings: s)
            for d in ZmanCatalog.all {
                if args.contains("--trace") { FileHandle.standardError.write(Data("\(d.id)\n".utf8)) }
                let (t, dur) = ZmanEngine.compute(d, on: czc)
                print("  [\(d.id)] \(d.isDuration ? ZmanFormat.duration(dur) : f.time(t))")
            }
        }
    }
}

private extension Collection {
    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}
