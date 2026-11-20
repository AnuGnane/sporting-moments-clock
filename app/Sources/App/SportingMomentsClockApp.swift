import MomentsCore
import OSLog
import SwiftUI

@main
struct SportingMomentsClockApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model: ClockModel
    @State private var demo: DemoController
    @State private var deskClock = DeskClockMode()

    init() {
        let resources = AppResources.bundle
        Typography.registerFonts(in: resources)
        let store: MomentStore
        do {
            store = try MomentStore(bundle: resources)
        } catch {
            Logger(subsystem: AppIdentity.bundleID, category: "data").error("Could not load moments: \(error)")
            store = MomentStore(moments: [])
        }
        // One set of settings for the app and the screen saver, see SharedSettings.
        let defaults = SharedSettings.defaults()
        SharedSettings.migrateLegacySettings(to: defaults)
        let model = ClockModel(store: store, settings: ClockSettings(defaults: defaults))
        model.onSettingsChange = { settings in
            settings.save(to: defaults)
            defaults.synchronize()
        }
        // Runs while the windows are closed too, so the menu shows the current moment.
        model.start()
        _model = State(initialValue: model)
        _demo = State(initialValue: DemoController(model: model))
    }

    var body: some Scene {
        // The first scene opens at launch.
        Window("Sporting Moments Clock", id: WindowID.clock) {
            ClockWindow(model: model, demo: demo, deskClock: deskClock)
                .frame(minWidth: 480, minHeight: 300)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            AppCommands()
            DemoCommands(demo: demo)
        }

        Window("Settings", id: WindowID.settings) {
            SettingsView(model: model)
        }
        .defaultSize(width: 540, height: 780)
        .windowResizability(.contentMinSize)

        Window("Credits", id: WindowID.credits) {
            CreditsView(store: model.picker.store)
        }
        .defaultSize(width: 560, height: 640)

        Window("About Sporting Moments Clock", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarMenu(model: model, deskClock: deskClock)
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("Sporting Moments Clock")
        }
    }
}

enum WindowID {
    static let clock = "clock"
    static let settings = "settings"
    static let credits = "credits"
    static let about = "about"
    static let all = [clock, settings, credits, about]
}

/// The fonts, moments.json, credits.json and photos ship once, inside the embedded screen saver.
enum AppResources {
    static let bundle = SaverInstaller.embeddedSaver().flatMap(Bundle.init(url:)) ?? .main
}

/// Keeps the app alive in the menu bar, and shows the Dock icon only while a window is open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let names = [
            NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                // After the close has finished, so the closing window no longer counts.
                DispatchQueue.main.async { MainActor.assumeIsolated { Self.updateDockIcon() } }
            }
        }
        if Self.wasLaunchedAtLogin {
            // Opened at login: stay in the menu bar.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NSApp.windows.filter(Self.isAppWindow).forEach { $0.close() }
                    Self.updateDockIcon()
                }
            }
        }
    }

    /// The app's own windows, not the menu bar item's.
    static func isAppWindow(_ window: NSWindow) -> Bool {
        guard let id = window.identifier?.rawValue else { return false }
        return WindowID.all.contains { id.hasPrefix($0) }
    }

    /// A regular app with a Dock icon while one of its windows is open (or minimised),
    /// a menu bar utility otherwise.
    static func updateDockIcon() {
        let hasWindow = NSApp.windows.contains { isAppWindow($0) && ($0.isVisible || $0.isMiniaturized) }
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private static var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

extension OpenWindowAction {
    /// Opens (or brings forward) one of the app's windows, with the Dock icon, from the menu bar.
    @MainActor
    func bringForward(_ id: String) {
        NSApp.setActivationPolicy(.regular)
        callAsFunction(id: id)
        NSApp.activate()
    }
}

/// App menu: About and Credits, and Settings with Command Comma, opening the app's own windows.
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sporting Moments Clock") { openWindow.bringForward(WindowID.about) }
            Button("Credits") { openWindow.bringForward(WindowID.credits) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow.bringForward(WindowID.settings) }
                .keyboardShortcut(",")
        }
    }
}

/// The demo controls as a menu. The plain keys (arrows, Space, N) are handled by the
/// clock window itself, see `DemoKeys`.
struct DemoCommands: Commands {
    let demo: DemoController

    var body: some Commands {
        // Desk clock mode is full screen, so View > Enter Full Screen (Control Command F) already covers it.
        CommandMenu("Demo") {
            Button("Previous Moment") { demo.step(forward: false) }
            Button("Next Moment") { demo.step(forward: true) }
            Button(demo.isPlaying ? "Pause" : "Play the Day") { demo.togglePlay() }
            Divider()
            Button("Back to Now") { demo.backToNow() }
                .disabled(!demo.isActive)
        }
    }
}
