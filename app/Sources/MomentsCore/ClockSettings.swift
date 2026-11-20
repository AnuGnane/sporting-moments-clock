import Foundation

/// What the viewer has chosen in Settings. The same options exist in the app and the saver.
public struct ClockSettings: Equatable, Sendable {
    public enum TimeMode: String, CaseIterable, Sendable {
        /// Moments show at the wall clock time of the venue (the default).
        case venue
        /// Moments show at the time the viewer's own clock read at that instant.
        case viewer
    }

    public enum Photos: String, CaseIterable, Sendable {
        case whenAvailable
        case typeOnly
    }

    public var timeMode: TimeMode = .venue
    public var showsRealTime = true
    public var showsRecords = true
    public var showsMatchMinuteFill = false
    public var photos: Photos = .whenAvailable

    public init() {}

    public init(
        timeMode: TimeMode = .venue, showsRealTime: Bool = true, showsRecords: Bool = true,
        showsMatchMinuteFill: Bool = false, photos: Photos = .whenAvailable
    ) {
        self.timeMode = timeMode
        self.showsRealTime = showsRealTime
        self.showsRecords = showsRecords
        self.showsMatchMinuteFill = showsMatchMinuteFill
        self.photos = photos
    }
}

// MARK: - Persistence

extension ClockSettings {
    private enum Key {
        static let timeMode = "timeMode"
        static let showsRealTime = "showsRealTime"
        static let showsRecords = "showsRecords"
        static let showsMatchMinuteFill = "showsMatchMinuteFill"
        static let photos = "photos"
    }

    /// Every key the settings are saved under.
    static let keys = [Key.timeMode, Key.showsRealTime, Key.showsRecords, Key.showsMatchMinuteFill, Key.photos]

    /// Reads settings, falling back to the defaults for anything missing.
    /// The app passes the shared `ScreenSaverDefaults`, see `SharedSettings`.
    public init(defaults: UserDefaults) {
        self.init(value: defaults.object(forKey:))
    }

    /// Reads settings from a plist dictionary (the shared settings file, read directly by the
    /// saver), using `fallback` for keys the dictionary lacks, then the defaults.
    public init(plist: [String: Any], fallback: UserDefaults? = nil) {
        self.init { key in plist[key] ?? fallback?.object(forKey: key) }
    }

    private init(value: (String) -> Any?) {
        self.init()
        if let raw = value(Key.timeMode) as? String, let mode = TimeMode(rawValue: raw) { timeMode = mode }
        if let raw = value(Key.photos) as? String, let photos = Photos(rawValue: raw) { self.photos = photos }
        if let on = value(Key.showsRealTime) as? Bool { showsRealTime = on }
        if let on = value(Key.showsRecords) as? Bool { showsRecords = on }
        if let on = value(Key.showsMatchMinuteFill) as? Bool { showsMatchMinuteFill = on }
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(timeMode.rawValue, forKey: Key.timeMode)
        defaults.set(showsRealTime, forKey: Key.showsRealTime)
        defaults.set(showsRecords, forKey: Key.showsRecords)
        defaults.set(showsMatchMinuteFill, forKey: Key.showsMatchMinuteFill)
        defaults.set(photos.rawValue, forKey: Key.photos)
    }
}
