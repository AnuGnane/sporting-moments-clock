import MomentsCore
import ServiceManagement
import SwiftUI

/// The Settings window. One set of settings for the clock window, the menu bar and the
/// screen saver; the preview at the top follows every change.
struct SettingsView: View {
    @Bindable var model: ClockModel
    @State private var saver = ScreenSaverSetup()
    @State private var loginItem = LoginItem()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                ClockScreen(model: model)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
                    .accessibilityLabel("Preview")
            }

            Section("Time") {
                Picker(selection: $model.settings.timeMode) {
                    Text("Venue time").tag(ClockSettings.TimeMode.venue)
                    Text("My time").tag(ClockSettings.TimeMode.viewer)
                } label: {
                    Text("Time shown")
                    Text(model.settings.timeMode == .venue
                         ? "A moment shows at the time the clock read where it happened."
                         : "A moment shows at the time your own clock read as it happened.")
                }
            }

            Section("Layers") {
                Toggle(isOn: $model.settings.showsRealTime) {
                    Text("Real time")
                    Text("Moments shown at the clock time they happened.")
                }
                Toggle(isOn: $model.settings.showsRecords) {
                    Text("Records")
                    Text("Records whose mark reads as the time, such as Bolt’s 9.58 at 09:58.")
                }
                Toggle(isOn: $model.settings.showsMatchMinuteFill) {
                    Text("Match minute fill")
                    Text("Fills empty minutes with match minutes: a 93rd minute goal shows at :33 of any hour.")
                }
            }

            Section("Photos") {
                Picker(selection: $model.settings.photos) {
                    Text("When available").tag(ClockSettings.Photos.whenAvailable)
                    Text("Type only").tag(ClockSettings.Photos.typeOnly)
                } label: {
                    Text("Photos")
                    Text("Freely licensed photos, credited on screen.")
                }
            }

            ScreenSaverSection(saver: saver, settings: model.settings)

            Section("General") {
                Toggle(isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) })) {
                    Text("Open at login")
                    Text("Keeps the clock in the menu bar after you log in.")
                }
                if loginItem.needsApproval {
                    LabeledContent("Waiting for your approval in Login Items.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red)
                }
                LabeledContent {
                    Button("Show Credits") { openWindow.bringForward(WindowID.credits) }
                } label: {
                    Text("Credits")
                    Text("Photos, fonts and where the moments come from.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .frame(minHeight: 480, idealHeight: 780)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        saver.refresh()
        loginItem.refresh()
    }
}

private struct ScreenSaverSection: View {
    let saver: ScreenSaverSetup
    let settings: ClockSettings

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if saver.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Button(saver.actionTitle, action: saver.useAsScreenSaver)
                        .disabled(saver.actionDisabled)
                }
            } label: {
                Text("Screen saver")
                Text(statusText)
            }
            switch saver.message {
            case .error(let text):
                Text(text).foregroundStyle(.red)
            case .notice(let text):
                Text(text).foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
            LabeledContent {
                Button("Open Screen Saver Settings", action: ScreenSaverActions.openSettingsPane)
            } label: {
                if saver.canSelectAutomatically {
                    Text("System Settings")
                    Text("Choose or change the screen saver under \(ScreenSaverActions.settingsPaneName).")
                } else {
                    Text("Choose it")
                    Text("Pick Sporting Moments Clock in System Settings under \(ScreenSaverActions.settingsPaneName).")
                }
            }
            LabeledContent {
                Button("Start Screen Saver Now") { ScreenSaverActions.startNow(with: settings) }
            } label: {
                Text("Try it")
                Text("Starts the screen saver chosen in System Settings.")
            }
        } header: {
            Text("Screen Saver")
        } footer: {
            Text(footerText)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if saver.isWorking { return "Setting it up\u{2026}" }
        switch (saver.install, saver.selection) {
        case (.unavailable, _): return "Not included in this copy of the app."
        case (.notInstalled, _): return "Not installed."
        case (.upToDate, .selected): return "Sporting Moments Clock is your screen saver."
        case (.differs(let version), .selected): return "Your screen saver, but not the version in this app" + build(version)
        case (_, .notSelected): return "Installed, but another screen saver is selected."
        case (.upToDate, .unknown): return "Installed."
        case (.differs(let version), .unknown): return "Installed, but not the version in this app" + build(version)
        }
    }

    private func build(_ version: String?) -> String {
        version.map { " (build \($0))." } ?? "."
    }

    private var footerText: String {
        let settings = "The screen saver uses the settings above the next time it starts."
        guard saver.canSelectAutomatically else { return settings }
        return "Use as Screen Saver sets it for every display and space. The desktop may blink once while macOS reloads it. " + settings
    }
}
