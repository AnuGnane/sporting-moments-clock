import Foundation
import IOKit

/// One set of settings for the app and the screen saver.
///
/// They live in the saver's per host defaults domain, the one
/// `ScreenSaverDefaults(forModuleWithName:)` opens for `domain`. On disk that is
/// `~/Library/Preferences/ByHost/AG.SportingMomentsClock.saver.<host UUID>.plist`.
///
/// The app writes it (see `SharedSettings.defaults()` in the app target). The saver cannot
/// use the same call to read it: macOS runs savers inside legacyScreenSaver, a sandboxed
/// host, so its `ScreenSaverDefaults` point into the host's container instead. The host may
/// read any file, though, so the saver reads this plist by path and uses its own defaults
/// only for keys the file lacks.
///
/// This file does not import ScreenSaver: linking it pulls Photos and Contacts into the test
/// runner, which then logs address book errors.
public enum SharedSettings {
    public static let domain = AppIdentity.saverBundleID
    /// The domain before version 1.0. Its settings are copied across once, see `migrate`.
    public static let legacyDomain = AppIdentity.legacySaverBundleID

    /// Copies the settings saved under the old bundle identifier into the current domain,
    /// but only while the current domain holds none, so it happens once and never
    /// overwrites a newer choice. Returns whether anything was copied.
    @discardableResult
    public static func migrate(from legacy: UserDefaults, to current: UserDefaults) -> Bool {
        let keys = ClockSettings.keys
        guard !keys.contains(where: { current.object(forKey: $0) != nil }) else { return false }
        let values = keys.compactMap { key in legacy.object(forKey: key).map { (key, $0) } }
        for (key, value) in values {
            current.set(value, forKey: key)
        }
        return !values.isEmpty
    }

    /// The settings the saver should use: the shared file first, then `fallback`
    /// (the saver's own defaults), then the built in defaults.
    public static func load(file: URL? = fileURL(), fallback: UserDefaults?) -> ClockSettings {
        ClockSettings(plist: file.flatMap(readPlist) ?? [:], fallback: fallback)
    }

    /// The shared plist, or nil when the host UUID cannot be read.
    public static func fileURL(home: URL = realHome, hostUUID: String? = hostUUID) -> URL? {
        guard let hostUUID else { return nil }
        return home.appending(path: "Library/Preferences/ByHost/\(domain).\(hostUUID).plist", directoryHint: .notDirectory)
    }

    static func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// The user's real home folder. Inside a sandbox `NSHomeDirectory()` is the container.
    public static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    }

    /// The hardware UUID that names per host preference files.
    public static var hostUUID: String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
