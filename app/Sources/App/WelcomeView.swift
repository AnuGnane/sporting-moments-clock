import MomentsCore
import SwiftUI

/// Shown once, over the clock window, on the first launch when the screen saver is not
/// installed yet: one click installs it and makes it the screen saver. Where that cannot be
/// done safely, it installs it and the user chooses it in System Settings.
struct WelcomeView: View {
    @State private var saver = ScreenSaverSetup()
    @Environment(\.dismiss) private var dismiss

    private static let shownKey = "didShowWelcome"

    /// True on the first launch only, and only when there is a saver to install.
    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: shownKey) else { return false }
        defaults.set(true, forKey: shownKey)
        return SaverInstaller(source: SaverInstaller.embeddedSaver()).status() == .notInstalled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Sporting Moments Clock")
                        .font(.title3.weight(.semibold))
                    Text(AppInfo.tagline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(saver.canSelectAutomatically
                 ? "Use it as your screen saver in one click. You can change this any time in System Settings under \(ScreenSaverActions.settingsPaneName)."
                 : "Install the screen saver, then choose it in System Settings under \(ScreenSaverActions.settingsPaneName).")
                .fixedSize(horizontal: false, vertical: true)
            switch saver.message {
            case .error(let text):
                Text(text).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .notice(let text):
                Text(text).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                EmptyView()
            }

            HStack {
                if saver.isDone {
                    Label("Sporting Moments Clock is your screen saver", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else if saver.isWorking {
                    ProgressView().controlSize(.small)
                } else if saver.install == .upToDate {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if saver.isDone {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else if saver.install == .upToDate && !saver.canSelectAutomatically {
                    Button("Done") { dismiss() }
                    Button("Open System Settings") {
                        ScreenSaverActions.openSettingsPane()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { dismiss() }
                        .disabled(saver.isWorking)
                    Button(saver.actionTitle, action: saver.useAsScreenSaver)
                        .disabled(saver.actionDisabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: saver.refresh)
    }
}
