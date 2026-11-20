import AppKit
import MomentsCore
import Observation
import OSLog
import ScreenSaver
import ServiceManagement

extension SharedSettings {
    /// The shared domain, for the app (not sandboxed) to read and write.
    @MainActor
    static func defaults() -> UserDefaults {
        ScreenSaverDefaults(forModuleWithName: domain) ?? .standard
    }

    /// Carries settings saved under the bundle identifier used before version 1.0 across, once.
    @MainActor
    static func migrateLegacySettings(to defaults: UserDefaults) {
        guard let legacy = ScreenSaverDefaults(forModuleWithName: legacyDomain),
              migrate(from: legacy, to: defaults)
        else { return }
        defaults.synchronize()
        Logger(subsystem: AppIdentity.bundleID, category: "settings").notice("Copied settings from \(legacyDomain, privacy: .public)")
    }
}

/// Starting the screen saver and opening its pane in System Settings.
@MainActor
enum ScreenSaverActions {
    static let engine = URL(filePath: "/System/Library/CoreServices/ScreenSaverEngine.app")

    /// Starts whichever screen saver is chosen in System Settings.
    ///
    /// The saver reads the shared settings file, which cfprefsd writes a few seconds after
    /// a change. So wait (up to five seconds) until the file holds `settings`.
    static func startNow(with settings: ClockSettings) {
        Task {
            var tries = 0
            while SharedSettings.load(fallback: nil) != settings, tries < 25 {
                tries += 1
                try? await Task.sleep(for: .milliseconds(200))
            }
            NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    /// Screen savers moved into the Wallpaper pane in macOS 26. Before that they had their own pane.
    static var settingsPaneURL: URL {
        if #available(macOS 26, *) {
            URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!
        } else {
            URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!
        }
    }

    /// Where screen savers are chosen in System Settings, for the words on screen.
    static var settingsPaneName: String {
        if #available(macOS 26, *) { "Wallpaper" } else { "Screen Saver" }
    }

    static func openSettingsPane() {
        NSWorkspace.shared.open(settingsPaneURL)
    }
}

/// The installed screen saver compared with the one inside this app, for the Settings window.
@MainActor
@Observable
final class SaverInstallState {
    private(set) var status: SaverInstaller.Status = .unavailable
    private(set) var error: String?
    private let installer: SaverInstaller

    /// Cheap on purpose: SwiftUI may build this more than once. The Settings window calls
    /// `refresh()` when it appears, which hashes both copies of the saver.
    init(installer: SaverInstaller = SaverInstaller(source: SaverInstaller.embeddedSaver())) {
        self.installer = installer
    }

    func refresh() {
        status = installer.status()
    }

    func install() {
        do {
            try installer.install()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}

/// Open at login, through the app's own login item.
@MainActor
@Observable
final class LoginItem {
    /// Read by `refresh()`, which the Settings window calls when it appears.
    private(set) var isOn = false
    private(set) var needsApproval = false
    private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isOn = status == .enabled
        needsApproval = status == .requiresApproval
    }
}
