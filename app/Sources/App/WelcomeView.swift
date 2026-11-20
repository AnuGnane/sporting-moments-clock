import MomentsCore
import SwiftUI

/// Shown once, over the clock window, on the first launch when the screen saver is not
/// installed yet: install it, then choose it in System Settings.
struct WelcomeView: View {
    @State private var saver = SaverInstallState()
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

            Text("Install the screen saver, then choose it in System Settings under \(ScreenSaverActions.settingsPaneName).")
                .fixedSize(horizontal: false, vertical: true)
            if let error = saver.error {
                Text(error).foregroundStyle(.red)
            }

            HStack {
                if isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isInstalled ? "Done" : "Not Now") { dismiss() }
                if isInstalled {
                    Button("Open System Settings") {
                        ScreenSaverActions.openSettingsPane()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Install Screen Saver", action: saver.install)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: saver.refresh)
    }

    private var isInstalled: Bool { saver.status == .upToDate }
}
