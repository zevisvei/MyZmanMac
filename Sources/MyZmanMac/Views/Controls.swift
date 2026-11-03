import SwiftUI
import AppKit

/// A date button that opens a graphical calendar. Used instead of a field-style DatePicker,
/// which grabs keyboard focus when the popover opens and then swallows scroll-wheel events.
struct DateJumpButton: View {
    @EnvironmentObject var model: AppModel
    @Binding var date: Date
    @ViewState private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Label(model.format.localizedDate(date, template: "dMMMyyyy"), systemImage: "calendar")
        }
        .help("בחירת תאריך")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                DatePicker("", selection: Binding(get: { date }, set: { date = $0; open = false }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .environment(\.timeZone, model.tz)
                Button("היום") { date = Date(); open = false }
            }
            .padding(10)
        }
    }
}

/// Calls `onStep(+1/-1)` when the mouse wheel or a trackpad swipe is used over the view.
struct ScrollStep: ViewModifier {
    let onStep: (Int) -> Void
    @ViewState private var monitor: Any?
    @ViewState private var accumulated: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                if inside, monitor == nil {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                        handle(event)
                        return nil
                    }
                } else if !inside, let m = monitor {
                    NSEvent.removeMonitor(m)
                    monitor = nil
                    accumulated = 0
                }
            }
            .onDisappear {
                if let m = monitor { NSEvent.removeMonitor(m) }
                monitor = nil
            }
    }

    private func handle(_ event: NSEvent) {
        // Vertical wheel or horizontal swipe, whichever is larger.
        let d = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
        if !event.hasPreciseScrollingDeltas {  // mouse wheel: one notch = one step
            if d != 0 { onStep(d > 0 ? -1 : 1) }
            return
        }
        if event.phase == .began { accumulated = 0 }
        guard event.momentumPhase == [] else { return }  // ignore trackpad inertia
        accumulated += d
        if abs(accumulated) >= 40 {
            onStep(accumulated > 0 ? -1 : 1)
            accumulated = 0
        }
    }
}

extension View {
    func scrollStep(_ onStep: @escaping (Int) -> Void) -> some View { modifier(ScrollStep(onStep: onStep)) }
}

/// A short message from an action that has no form of its own to show it in (context menus etc.).
@MainActor
enum UserMessage {
    static func show(_ text: String, title: String = "זמנים") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "אישור")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Asks before something that can't be undone. Returns true to go ahead.
    static func confirm(_ text: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: action).hasDestructiveAction = true
        alert.addButton(withTitle: "ביטול")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
