import AppKit
import Combine
import SwiftUI
import os

/// The menu bar item and its popover, in AppKit.
///
/// Not SwiftUI's MenuBarExtra: it can't be opened from code (needed for widget clicks and after a permission
/// prompt closes it), and it re-renders its label into an image and rebuilds the status button on scene
/// updates, which once spun the main thread. Here the button's title is set only when the text changes.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let shared = StatusBarController()

    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    private var visibilityObservation: NSKeyValueObservation?
    private static let autosaveName = "MyZmanStatusItem"
    private let log = Logger(subsystem: "com.myzman.mac", category: "statusbar")

    func start() {
        let model = AppModel.shared
        model.menuBar.$text.removeDuplicates()
            .combineLatest(model.$settings.map { [$0.menuBar.showInMenuBar, $0.menuBar.showIcon] }.removeDuplicates())
            .sink { [weak self] title, flags in self?.update(title: title, show: flags[0], icon: flags[1]) }
            .store(in: &cancellables)
    }

    private func update(title: String, show: Bool, icon: Bool) {
        guard show else {
            popover?.performClose(nil)
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            visibilityObservation = nil
            return
        }
        let item = self.item ?? makeItem()
        guard let button = item.button else { return }
        let wantsImage = icon || title.isEmpty
        if wantsImage, button.image == nil {
            let image = NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: "זמנים")
            image?.isTemplate = true
            button.image = image
        } else if !wantsImage, button.image != nil {
            button.image = nil
        }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        // Digits of equal width, so a ticking countdown doesn't change the item's width (which re-lays out the
        // menu bar and re-snapshots the item on every display each second).
        if button.title != title {
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
        }
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        // Allow ⌘-dragging it out of the menu bar; that turns the setting off.
        item.behavior = .removalAllowed
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle(_:))
            // On mouse-down, like a menu – and the same event that the transient popover closes on (see toggle).
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { _, change in
            guard change.newValue == false else { return }
            Task { @MainActor in AppModel.shared.settings.menuBar.showInMenuBar = false }
        }
        self.item = item
        return item
    }

    /// A press on the button while the popover is open may first close the transient popover (AppKit closes it as
    /// the app's focus moves), and only then reach the button's action: that same press mustn't reopen it. The
    /// menu bar items are drawn by another process (MenuBarAgent), which forwards the press to the app a little
    /// later – by then the mouse may already be up (a quick tap), so the press can't be told apart by the mouse
    /// state. Instead: an action within a moment after the popover closed belongs to the press that closed it.
    private var closedAt: TimeInterval?
    private static let sameClick: TimeInterval = 0.4

    @objc private func toggle(_ sender: Any?) {
        let now = ProcessInfo.processInfo.systemUptime
        if popover?.isShown == true {
            popover?.performClose(sender)
        } else if let closedAt, now - closedAt < Self.sameClick {
            self.closedAt = nil
        } else {
            showPopover()
        }
    }

    func popoverWillClose(_ notification: Notification) {
        closedAt = nil
        // Only when the popover closes with the mouse over the menu bar item: a press there may be on its way.
        guard let button = item?.button, let window = button.window else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil)).insetBy(dx: -2, dy: -4)
        if frame.contains(NSEvent.mouseLocation) { closedAt = ProcessInfo.processInfo.systemUptime }
    }

    /// Opens the popover under the menu bar item (e.g. from a widget click). False if there's no item.
    @discardableResult
    func showPopover() -> Bool {
        // Not under an item that isn't on screen (e.g. hidden behind the notch on a full menu bar).
        guard let button = item?.button, button.window?.occlusionState.contains(.visible) == true else { return false }
        let popover = self.popover ?? makePopover()
        if !popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        log.debug("popover shown: \(popover.isShown, privacy: .public)")
        return true
    }

    func closePopover() { popover?.performClose(nil) }

    /// Drop the popover's content when it closes: nothing in it keeps updating in the background, and it's
    /// rebuilt (on the current day) the next time it opens.
    func popoverDidClose(_ notification: Notification) {
        log.debug("popover closed")
        popover = nil
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient   // closes when clicking elsewhere, like a menu
        popover.animates = false
        let host = NSHostingController(rootView: PopoverView()
            .environmentObject(AppModel.shared)
            .environment(\.layoutDirection, .rightToLeft))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.delegate = self
        self.popover = popover
        return popover
    }
}
