import AppKit
import Observation

/// Desk clock mode is the clock window in full screen. While it is on, the app holds a
/// power assertion so the display does not sleep; leaving full screen releases it.
@MainActor
@Observable
final class DeskClockMode {
    private(set) var isOn = false

    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let changes: [(Notification.Name, Bool)] = [
            (NSWindow.didEnterFullScreenNotification, true),
            (NSWindow.didExitFullScreenNotification, false),
            (NSWindow.willCloseNotification, false),
        ]
        observers = changes.map { name, on in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    guard let window, Self.isClock(window) else { return }
                    self?.setOn(on)
                }
            }
        } + [
            // Belt and braces: never leave the assertion behind when the app quits.
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setOn(false) }
            },
        ]
    }

    /// Enters or leaves full screen on the clock window.
    func toggle() {
        NSApp.windows.first { Self.isClock($0) && $0.isVisible }?.toggleFullScreen(nil)
    }

    private static func isClock(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(WindowID.clock) == true
    }

    private func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "Sporting Moments Clock is in desk clock mode"
            )
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
