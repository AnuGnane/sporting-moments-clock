import AppKit

/// Calls `onTick` just after every minute boundary, and again straight away when the
/// Mac wakes or the system clock or time zone changes.
///
/// Each tick schedules the next one from the wall clock, so it does not drift and
/// it catches up after sleep (timers do not count time while the Mac is asleep).
@MainActor
public final class MinuteTicker {
    private let onTick: @MainActor () -> Void
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public init(onTick: @escaping @MainActor () -> Void) {
        self.onTick = onTick
    }

    public func start() {
        guard timer == nil else { return }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        observe(NotificationCenter.default, .NSSystemClockDidChange)
        observe(NotificationCenter.default, .NSSystemTimeZoneDidChange)
        scheduleNext()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func scheduleNext() {
        timer?.invalidate()
        let now = Date()
        // A twentieth of a second past the boundary, so the new minute has surely begun.
        let next = (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60.05
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: next), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        // Let the system fold this wake into others. A quarter second late is not visible on a minute clock.
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        onTick()
        if timer != nil { scheduleNext() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        observers.append((center, token))
    }
}
