import SwiftUI
import ServiceManagement

/// An AppKit app (no SwiftUI App/Scene): the menu bar item is an NSStatusItem with an NSPopover
/// (StatusBarController), and the settings / main windows are AppWindows.
@main
enum MyZmanApp {
    static func main() {
        if CommandLine.arguments.contains("--dump") { MainActor.assumeIsolated { DebugDump.run() }; exit(0) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar app, no Dock icon (also LSUIElement in Info.plist)
        app.mainMenu = MainMenu.make()
        app.run()
    }
}

/// The app has no visible menu bar of its own, but its key equivalents still work in its windows
/// (⌘C / ⌘V / ⌘A in text fields, ⌘W, ⌘Q) only if they're in the main menu.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "הסתר את זמנים", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "צא מזמנים", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "עריכה")
        edit.addItem(withTitle: "בטל", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "בצע שוב", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "גזור", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "העתק", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "הדבק", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "בחר הכל", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "חלון")
        window.addItem(withTitle: "סגור", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "מזער", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppModel.shared   // loads the settings, starts the clock, schedules reminders
        if let i = CommandLine.arguments.firstIndex(of: "--preview") {
            MainActor.assumeIsolated { DebugDump.preview(tab: CommandLine.arguments.dropFirst(i + 1).first) }
            return
        }
        MainActor.assumeIsolated { StatusBarController.shared.start() }
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

    /// The menu bar popover, or – when the app isn't in the menu bar – the same content in a window.
    static func showApp() {
        if !StatusBarController.shared.showPopover() { showMain() }
    }

    static func showMain() {
        show("main", title: "זמנים") { PopoverView() }
    }

    static func showSettings() {
        show("settings", title: "הגדרות זמנים") { SettingsView() }
    }

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
            w.delegate = closer
            if !w.setFrameUsingName(id) { w.center() }
            w.setFrameAutosaveName(id)
            windows[id] = w
            return w
        }()
        // While a window is open the app is in the Dock and ⌘-Tab, so it can be switched back to.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// On close: drop the window and its content (nothing keeps updating behind it), and when no window is
    /// left go back to being a menu bar app.
    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            guard let w = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                AppWindows.windows = AppWindows.windows.filter { $0.value !== w }
                if AppWindows.windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
    private static let closer = Closer()
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
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
            let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: big ? 620 : 370, height: big ? 560 : 640),
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
