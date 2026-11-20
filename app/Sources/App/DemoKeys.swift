import AppKit
import SwiftUI

/// The demo keys: Left and Right arrows, Space and N, without modifiers.
///
/// A local event monitor scoped to the clock's own window. SwiftUI's `onKeyPress` needs
/// keyboard focus, which a full screen picture with no controls never reliably gets, and
/// plain Space and N do not go through menu key equivalents.
struct DemoKeys: NSViewRepresentable {
    let demo: DemoController

    func makeNSView(context: Context) -> KeyMonitorView {
        KeyMonitorView(demo: demo)
    }

    func updateNSView(_ view: KeyMonitorView, context: Context) {}

    final class KeyMonitorView: NSView {
        private let demo: DemoController
        private var monitor: Any?

        init(demo: DemoController) {
            self.demo = demo
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, event.window === self.window else { return false }
                    return self.handle(event)
                }
                return handled ? nil : event
            }
        }

        /// Returns whether the key was a demo key.
        private func handle(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard modifiers.isEmpty else { return false }
            switch event.keyCode {
            case 123: demo.step(forward: false)  // Left Arrow
            case 124: demo.step(forward: true)  // Right Arrow
            case 49: demo.togglePlay()  // Space
            default:
                guard event.charactersIgnoringModifiers?.lowercased() == "n" else { return false }
                demo.backToNow()
            }
            return true
        }
    }
}
