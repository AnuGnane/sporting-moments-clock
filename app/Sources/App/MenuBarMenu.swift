import MomentsCore
import SwiftUI

/// The menu under the menu bar icon: what is showing, the windows, the screen saver and
/// quick settings. Every change here is saved for the screen saver too.
struct MenuBarMenu: View {
    @Bindable var model: ClockModel
    let deskClock: DeskClockMode
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(nowShowing)

        Divider()

        Button("Open Clock") { openWindow.bringForward(WindowID.clock) }
        Toggle("Desk Clock Mode", isOn: Binding(get: { deskClock.isOn }, set: { _ in toggleDeskClock() }))
        Button("Start Screen Saver Now") { ScreenSaverActions.startNow(with: model.settings) }

        // Sections rather than inline pickers: adjacent inline pickers draw doubled separators.
        Section("Time Shown") {
            choice("Venue Time", \.timeMode, .venue)
            choice("My Time", \.timeMode, .viewer)
        }

        Section("Layers") {
            Toggle("Real Time", isOn: $model.settings.showsRealTime)
            Toggle("Records", isOn: $model.settings.showsRecords)
            Toggle("Match Minute Fill", isOn: $model.settings.showsMatchMinuteFill)
        }

        Section("Photos") {
            choice("When Available", \.photos, .whenAvailable)
            choice("Type Only", \.photos, .typeOnly)
        }

        Divider()

        Button("About Sporting Moments Clock") { openWindow.bringForward(WindowID.about) }
        Button("Credits") { openWindow.bringForward(WindowID.credits) }
        Button("Settings…") { openWindow.bringForward(WindowID.settings) }
            .keyboardShortcut(",")
        Button("Quit Sporting Moments Clock") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// "16:03  Kipchoge breaks two hours", the moment's own time and a short caption.
    private var nowShowing: String {
        guard let card = model.card else { return "No moment showing" }
        let limit = 38
        let caption = card.caption.count > limit
            ? card.caption.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
            : card.caption
        return "\(card.time)  \(caption)"
    }

    /// A checkable item that picks one value of a setting.
    private func choice<Value: Equatable>(_ title: String, _ key: WritableKeyPath<ClockSettings, Value>, _ value: Value) -> some View {
        Toggle(title, isOn: Binding(get: { model.settings[keyPath: key] == value }, set: { _ in model.settings[keyPath: key] = value }))
    }

    /// Desk clock mode is the clock window in full screen, so open the window first.
    private func toggleDeskClock() {
        if deskClock.isOn {
            deskClock.toggle()
            return
        }
        openWindow.bringForward(WindowID.clock)
        // Give the window a moment to appear and become key before going full screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { deskClock.toggle() }
    }
}
