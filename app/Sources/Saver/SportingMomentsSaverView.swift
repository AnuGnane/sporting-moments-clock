import MomentsCore
import OSLog
import ScreenSaver
import SwiftUI

/// The screen saver: the same SwiftUI clock as the app, hosted in a ScreenSaverView.
///
/// macOS loads this bundle into its own host process (legacyScreenSaver), so resources
/// come from `Bundle(for:)`, never `Bundle.main`, and the clock drives itself with a
/// minute timer instead of `animateOneFrame`.
@objc(SportingMomentsSaverView)
final class SportingMomentsSaverView: ScreenSaverView {
    private static let bundle = Bundle(for: SportingMomentsSaverView.self)

    /// Loaded once per host process and shared by every screen.
    private static let store: MomentStore = {
        Typography.registerFonts(in: bundle)
        do {
            return try MomentStore(bundle: bundle)
        } catch {
            Logger(subsystem: AppIdentity.bundleID, category: "saver").error("Could not load moments: \(error, privacy: .public)")
            return MomentStore(moments: [])
        }
    }()

    /// The settings the app wrote, read afresh each time the saver starts. See `SharedSettings`.
    private static func loadSettings() -> ClockSettings {
        let own = ScreenSaverDefaults(forModuleWithName: SharedSettings.domain)
        let file = SharedSettings.fileURL()
        let settings = SharedSettings.load(file: file, fallback: own)
        let found = file.map { FileManager.default.isReadableFile(atPath: $0.path) } ?? false
        Logger(subsystem: AppIdentity.bundleID, category: "saver").notice(
            "Settings \(String(describing: settings), privacy: .public) from \(file?.path ?? "no file", privacy: .public) (readable: \(found, privacy: .public))"
        )
        return settings
    }

    /// The small preview in System Settings, decided from the frame because the
    /// `isPreview` flag has been unreliable on recent macOS versions.
    private let isThumbnail: Bool
    private let model: ClockModel
    private var sheet: NSWindow?

    override init?(frame: NSRect, isPreview: Bool) {
        isThumbnail = frame.width < 800 || frame.height < 500
        model = ClockModel(store: Self.store, settings: Self.loadSettings())
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        isThumbnail = false
        model = ClockModel(store: Self.store, settings: Self.loadSettings())
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        animationTimeInterval = 60  // unused: the clock ticks on the minute by itself
        updatePhotoPixelSize()
        let host = NSHostingView(rootView: ClockScreen(model: model))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenSaverWillStop(_:)),
            name: Notification.Name("com.apple.screensaver.willstop"), object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Animation

    override func startAnimation() {
        super.startAnimation()
        updatePhotoPixelSize()
        model.settings = Self.loadSettings()  // pick up changes made in the app
        model.start()
    }

    override func stopAnimation() {
        super.stopAnimation()
        model.stop()
    }

    /// The host does not always call `stopAnimation` (see `screenSaverWillStop`), so also stop
    /// when the view leaves its window, for example when System Settings closes the preview,
    /// and carry on if it is moved into another window while running.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            model.stop()
        } else if isAnimating {
            updatePhotoPixelSize()
            model.start()
        }
    }

    /// Photos are decoded for this view's own size: small for the System Settings thumbnail,
    /// and each display's own size when there are several.
    private func updatePhotoPixelSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        model.photoPixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    override func animateOneFrame() {
        // Nothing to do: ClockModel redraws on the minute.
    }

    /// On macOS 14 and later the host does not call `stopAnimation` when the saver is
    /// dismissed and keeps old views alive, so each start piles up another clock.
    /// The workaround used by Aerial and ScreenSaverMinimal: stop on the `willstop`
    /// notification, then quit the host process so the next start is clean.
    /// The System Settings preview is left alone so it does not go blank.
    @objc private func screenSaverWillStop(_ notification: Notification) {
        model.stop()
        guard !isThumbnail else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            exit(0)
        }
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let window = ConfigureSheet.makeWindow()
        sheet = window
        return window
    }
}
