/// The bundle identifiers, in one place for the Swift code.
///
/// `bundleID` must match APP_BUNDLE_ID in project.yml; a test checks it against the test
/// bundle's own identifier, which project.yml derives from the same setting.
public enum AppIdentity {
    /// The app, "AG.SportingMomentsClock". Also the OSLog subsystem.
    public static let bundleID = "AG.SportingMomentsClock"
    /// The screen saver. Its defaults domain holds the shared settings, see `SharedSettings`.
    public static let saverBundleID = bundleID + ".saver"
    /// The screen saver's identifier before version 1.0, kept to carry its settings across.
    public static let legacySaverBundleID = "com.sportingmoments.clock.saver"
}
