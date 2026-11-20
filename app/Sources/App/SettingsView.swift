import MomentsCore
import ServiceManagement
import SwiftUI

/// The Settings window. One set of settings for the clock window, the menu bar and the
/// screen saver; the preview at the top follows every change.
struct SettingsView: View {
    @Bindable var model: ClockModel
    @State private var saver = SaverInstallState()
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
                    Text("From Wikimedia Commons, credited on screen.")
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
    let saver: SaverInstallState
    let settings: ClockSettings

    var body: some View {
        Section {
            LabeledContent {
                Button(isUpdate ? "Update Screen Saver" : "Install Screen Saver", action: saver.install)
                    .disabled(saver.status == .upToDate || saver.status == .unavailable)
            } label: {
                Text("Screen saver")
                Text(statusText)
            }
            if let error = saver.error {
                Text(error).foregroundStyle(.red)
            }
            LabeledContent {
                Button("Open Screen Saver Settings", action: ScreenSaverActions.openSettingsPane)
            } label: {
                Text("Choose it")
                Text("Pick Sporting Moments Clock in System Settings under \(ScreenSaverActions.settingsPaneName).")
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
            Text("The screen saver uses the settings above the next time it starts.")
                .foregroundStyle(.secondary)
        }
    }

    private var isUpdate: Bool {
        if case .differs = saver.status { true } else { false }
    }

    private var statusText: String {
        switch saver.status {
        case .notInstalled: "Not installed."
        case .upToDate: "Installed and up to date."
        case .differs(let version):
            "Installed, but not the version in this app" + (version.map { " (build \($0))." } ?? ".")
        case .unavailable: "Not included in this copy of the app."
        }
    }
}
