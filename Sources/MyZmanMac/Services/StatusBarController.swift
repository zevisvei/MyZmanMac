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
        model.$menuBarTitle.removeDuplicates()
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
        if button.title != title { button.title = title }
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { _, change in
            guard change.newValue == false else { return }
            Task { @MainActor in AppModel.shared.settings.menuBar.showInMenuBar = false }
        }
        self.item = item
        return item
    }

    /// When the transient popover last closed. A click on the button while it's open closes it on mouse-down
    /// (as a click outside it) before the button's action runs: that same click mustn't reopen it.
    private var lastClosed = Date.distantPast

    @objc private func toggle(_ sender: Any?) {
        if popover?.isShown == true {
            popover?.performClose(sender)
        } else if Date().timeIntervalSince(lastClosed) > 0.3 {
            showPopover()
        }
    }

    /// Opens the popover under the menu bar item (e.g. from a widget click). False if there's no item.
    @discardableResult
    func showPopover() -> Bool {
        guard let button = item?.button else { return false }
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
        lastClosed = Date()
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
