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

/// Installing the screen saver and making it the chosen one, for the Settings window and
/// the welcome sheet. One action does both; where the wallpaper store cannot be changed
/// safely it installs only, and the user chooses in System Settings.
@MainActor
@Observable
final class ScreenSaverSetup {
    /// What happened on the last attempt, when it did not simply work.
    enum Message: Equatable {
        case error(String)
        /// Installed, but the user has to choose it in System Settings.
        case notice(String)
    }

    private(set) var install: SaverInstaller.Status = .unavailable
    private(set) var selection: WallpaperStore.State = .unknown
    private(set) var isWorking = false
    private(set) var message: Message?
    /// Set when an automatic choice was tried and did not stick, so the rest of this
    /// session offers System Settings instead of trying again.
    private var automaticFailed = false
    private let installer: SaverInstaller
    private let store: WallpaperStore

    /// Cheap on purpose: SwiftUI may build this more than once. The views call `refresh()`
    /// when they appear, which hashes both copies of the saver and reads the wallpaper store.
    init(installer: SaverInstaller = SaverInstaller(source: SaverInstaller.embeddedSaver()), store: WallpaperStore = WallpaperStore()) {
        self.installer = installer
        self.store = store
    }

    /// True when the wallpaper store can be changed safely, so one click can finish the job.
    var canSelectAutomatically: Bool { selection != .unknown && !automaticFailed }

    /// Installed, up to date and chosen: nothing left to do.
    var isDone: Bool { install == .upToDate && selection == .selected }

    func refresh() {
        install = installer.status()
        selection = store.state(of: installer.destination)
    }

    /// The title for the one button that installs (or updates) and chooses the saver.
    var actionTitle: String {
        let update = if case .differs = install { true } else { false }
        if !canSelectAutomatically || selection == .selected && update {
            return update ? "Update Screen Saver" : "Install Screen Saver"
        }
        return "Use as Screen Saver"
    }

    var actionDisabled: Bool {
        if isWorking || install == .unavailable { return true }
        return install == .upToDate && (selection == .selected || !canSelectAutomatically)
    }

    /// Installs or updates the saver if needed, then makes it the chosen screen saver.
    func useAsScreenSaver() {
        guard !isWorking else { return }
        message = nil
        if install != .upToDate {
            do {
                try installer.install()
            } catch {
                message = .error(error.localizedDescription)
                refresh()
                return
            }
        }
        refresh()
        guard selection != .selected else { return }
        // Without a store it can change, installing is all this button does.
        guard canSelectAutomatically else { return }
        isWorking = true
        let store = store
        let saver = installer.destination
        Task {
            do throws(WallpaperStore.Failure) {
                try await store.select(saver) { await WallpaperAgent.restart() }
            } catch {
                handle(error)
            }
            isWorking = false
            refresh()
        }
    }

    private func handle(_ failure: WallpaperStore.Failure) {
        let log = Logger(subsystem: AppIdentity.bundleID, category: "screen saver")
        switch failure {
        case .cannotSelect(let reason):
            log.notice("Could not choose the screen saver: \(reason, privacy: .public)")
            automaticFailed = true
            message = .notice("Installed, but it could not be chosen automatically.")
        case .didNotTake:
            log.error("macOS did not keep the screen saver choice; the wallpaper store was put back")
            automaticFailed = true
            message = .notice("macOS did not keep the change, so it was undone.")
        case .restoreFailed(let reason):
            log.error("Could not put the wallpaper store back: \(reason, privacy: .public)")
            automaticFailed = true
            message = .error("macOS did not keep the change, and the previous wallpaper settings could not be put back. A copy is at \(store.backup.path(percentEncoded: false)).")
        }
    }
}

/// The background process that draws the wallpaper and runs the screen saver.
enum WallpaperAgent {
    static let label = "com.apple.wallpaper.agent"

    /// Restarts WallpaperAgent so it reads its store again. launchd starts it straight
    /// back up; the desktop may blink while it does.
    static func restart() async {
        if await run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(label)"]) == 0 { return }
        _ = await run("/usr/bin/killall", ["WallpaperAgent"])
    }

    /// Runs a command and returns its exit status, -1 if it could not start.
    private static func run(_ path: String, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
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
