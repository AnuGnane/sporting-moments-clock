import Foundation

/// Which screen saver macOS uses, read from and written to the wallpaper store.
///
/// Since macOS 14 the choice lives in the store that WallpaperAgent keeps at
/// ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist. There is no public
/// API for it, so this type works on the file's bytes and nothing else. The layout is
/// Apple's and undocumented, so the type is strict: it reads the whole file and refuses
/// anything that is not exactly the layout below (as seen on macOS 27). The app then sends
/// the user to System Settings instead.
///
/// The layout, as far as it matters here. "$null" stands for an empty slot.
///
///     top level   AllSpacesAndDisplays: entry or "$null"
///                 SystemDefault: entry or "$null"
///                 Displays: [display UUID: entry]
///                 Spaces: [space UUID: [Default: entry or "$null", Displays: [display UUID: entry]]]
///     entry       [Type: "individual", Desktop: member, Idle: member]
///                 or [Type: "linked", Linked: member], one member used for both
///     member      [Content: [Choices: [choice], Shuffle, EncodedOptionValues], LastSet, LastUse]
///     choice      [Provider: String, Files: [Any], Configuration: Data]
///
/// Desktop is the wallpaper and Idle the screen saver. A third party screen saver is a choice
/// with the provider `screenSaverProvider` and a Configuration that is itself a binary plist,
/// `["module": ["relative": "file:///Users/me/Library/Screen%20Savers/Name.saver"]]`.
///
/// Pure: no file access, so tests can feed it any bytes.
public enum ScreenSaverSelection {
    /// Why the store cannot be read or changed. Any of them means: choose in System Settings.
    public enum Refusal: Error, Equatable, Sendable, CustomStringConvertible {
        /// Not a property list with a dictionary at the top.
        case unreadable
        /// Readable, but not the layout this type knows. Carries where, for the log.
        case unexpected(String)
        /// The layout is fine but holds no entry for a display or a space, so there is nothing to set.
        case noEntries

        public var description: String {
            switch self {
            case .unreadable: "The wallpaper store could not be read."
            case .unexpected(let place): "The wallpaper store has an unexpected layout at \(place)."
            case .noEntries: "The wallpaper store has no entries for displays or spaces."
            }
        }
    }

    public static let screenSaverProvider = "com.apple.wallpaper.choice.screen-saver"
    static let null = "$null"
    static let topLevelKeys: Set<String> = ["AllSpacesAndDisplays", "SystemDefault", "Displays", "Spaces"]
    static let spaceKeys: Set<String> = ["Default", "Displays"]

    /// True when `saver` is the screen saver in every entry for a display or a space.
    ///
    /// SystemDefault is left out: it is only the starting point for displays and spaces macOS
    /// has not seen yet, and choosing a screen saver in System Settings may leave it alone.
    /// `select` sets it all the same.
    public static func isSelected(_ data: Data, saver: URL) throws(Refusal) -> Bool {
        let root = try parse(data)
        let module = modulePath(saver)
        var found = false
        var selected = true
        _ = try mapEntries(root) { slot, entry in
            guard slot != .systemDefault else { return nil }
            found = true
            let member = entry["Idle"] ?? entry["Linked"]
            if !isChoice(of: module, member) { selected = false }
            return nil
        }
        return found && selected
    }

    /// The store with `saver` as the screen saver in every entry, Desktop untouched.
    ///
    /// A linked entry becomes an individual one: Desktop takes the old Linked member as it
    /// was, and Idle takes `saver`. An entry that already has `saver` is left as it is. Every
    /// other key and value is carried across unchanged.
    public static func select(_ data: Data, saver: URL, at date: Date = .now) throws(Refusal) -> Data {
        let root = try parse(data)
        let module = modulePath(saver)
        var entries = 0
        let updated = try mapEntries(root) { slot, entry in
            if slot != .systemDefault { entries += 1 }
            switch entry["Type"] as? String {
            case "individual":
                guard !isChoice(of: module, entry["Idle"]) else { return nil }
                var entry = entry
                entry["Idle"] = idleMember(from: entry["Idle"], module: module, date: date)
                return entry
            default:
                // Linked, the only other type `mapEntries` lets through.
                guard let linked = entry["Linked"] else { return nil }
                return ["Type": "individual", "Desktop": linked, "Idle": idleMember(from: linked, module: module, date: date)]
            }
        }
        guard entries > 0 else { throw .noEntries }
        do {
            return try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
        } catch {
            throw .unreadable
        }
    }

    /// The Configuration that names `saver`, byte for byte what System Settings writes.
    public static func configuration(for saver: URL) -> Data {
        let url = URL(filePath: modulePath(saver), directoryHint: .notDirectory)
        let plist: [String: Any] = ["module": ["relative": url.absoluteString]]
        // A dictionary of strings always serialises.
        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
    }

    /// The file path a screen saver choice's Configuration names, nil if it names none.
    public static func modulePath(inConfiguration data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let module = plist["module"] as? [String: Any],
              let relative = module["relative"] as? String
        else { return nil }
        let base = (module["base"] as? String).flatMap { URL(string: $0) }
        guard let url = URL(string: relative, relativeTo: base), url.isFileURL else { return nil }
        return modulePath(url)
    }

    // MARK: - Reading

    /// Where an entry sits in the store.
    enum Slot: Equatable {
        case allSpacesAndDisplays, systemDefault, display, spaceDefault, spaceDisplay
    }

    /// The top level, checked all the way down before anything is read from it.
    static func parse(_ data: Data) throws(Refusal) -> [String: Any] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw .unreadable
        }
        if let key = root.keys.first(where: { !topLevelKeys.contains($0) }) { throw .unexpected("top level key \(key)") }
        guard root["Displays"] is [String: Any] else { throw .unexpected("Displays") }
        guard let spaces = root["Spaces"] as? [String: Any] else { throw .unexpected("Spaces") }
        for (id, space) in spaces {
            guard let space = space as? [String: Any] else { throw .unexpected("space \(id)") }
            if let key = space.keys.first(where: { !spaceKeys.contains($0) }) { throw .unexpected("space \(id) key \(key)") }
            if let displays = space["Displays"], !(displays is [String: Any]) { throw .unexpected("space \(id) Displays") }
        }
        // Checks every entry, so a file with one odd entry is refused before any change.
        _ = try mapEntries(root) { _, _ in nil }
        return root
    }

    /// Calls `body` with each entry, after checking it, and puts back what it returns
    /// (nil keeps the entry). Throws on the first entry or slot that is not as expected.
    static func mapEntries(
        _ root: [String: Any], _ body: (Slot, [String: Any]) throws(Refusal) -> [String: Any]?
    ) throws(Refusal) -> [String: Any] {
        var root = root
        for (key, slot) in [("AllSpacesAndDisplays", Slot.allSpacesAndDisplays), ("SystemDefault", .systemDefault)] {
            if let value = root[key], let entry = try checkedEntry(value, at: key) {
                if let new = try body(slot, entry) { root[key] = new }
            }
        }
        if var displays = root["Displays"] as? [String: Any] {
            try mapDisplays(&displays, at: "Displays", slot: .display, body)
            root["Displays"] = displays
        }
        if var spaces = root["Spaces"] as? [String: Any] {
            for (id, value) in spaces {
                guard var space = value as? [String: Any] else { throw .unexpected("space \(id)") }
                if let value = space["Default"], let entry = try checkedEntry(value, at: "space \(id) Default") {
                    if let new = try body(.spaceDefault, entry) { space["Default"] = new }
                }
                if var displays = space["Displays"] as? [String: Any] {
                    try mapDisplays(&displays, at: "space \(id)", slot: .spaceDisplay, body)
                    space["Displays"] = displays
                }
                spaces[id] = space
            }
            root["Spaces"] = spaces
        }
        return root
    }

    private static func mapDisplays(
        _ displays: inout [String: Any], at place: String, slot: Slot,
        _ body: (Slot, [String: Any]) throws(Refusal) -> [String: Any]?
    ) throws(Refusal) {
        for (id, value) in displays {
            guard let entry = try checkedEntry(value, at: "\(place) display \(id)") else { continue }
            if let new = try body(slot, entry) { displays[id] = new }
        }
    }

    /// The entry in a slot, nil for an empty slot. Throws unless it is a known type with
    /// exactly its members, each well formed.
    static func checkedEntry(_ value: Any, at place: String) throws(Refusal) -> [String: Any]? {
        if let string = value as? String, string == null { return nil }
        guard let entry = value as? [String: Any] else { throw .unexpected(place) }
        let members: Set<String>
        switch entry["Type"] as? String {
        case "individual": members = ["Desktop", "Idle"]
        case "linked": members = ["Linked"]
        default: throw .unexpected("\(place) Type")
        }
        guard Set(entry.keys) == members.union(["Type"]) else { throw .unexpected("\(place) keys") }
        for name in members {
            try checkMember(entry[name], at: "\(place) \(name)")
        }
        return entry
    }

    /// A member needs Content with a list of well formed choices. Other keys may be there and
    /// are kept as they are.
    static func checkMember(_ value: Any?, at place: String) throws(Refusal) {
        guard let member = value as? [String: Any],
              let content = member["Content"] as? [String: Any],
              let choices = content["Choices"] as? [Any]
        else { throw .unexpected(place) }
        for choice in choices {
            guard let choice = choice as? [String: Any],
                  choice["Provider"] is String,
                  choice["Configuration"] is Data,
                  choice["Files"] is [Any]
            else { throw .unexpected("\(place) choice") }
        }
    }

    /// True when a member's one choice is the screen saver at `module`.
    static func isChoice(of module: String, _ member: Any?) -> Bool {
        guard let member = member as? [String: Any],
              let content = member["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              choices.count == 1,
              choices[0]["Provider"] as? String == screenSaverProvider,
              let configuration = choices[0]["Configuration"] as? Data
        else { return false }
        return modulePath(inConfiguration: configuration) == module
    }

    // MARK: - Writing

    /// An Idle member showing `module`, built on `old` so its other keys (such as
    /// EncodedOptionValues, which System Settings also leaves in place) are kept.
    static func idleMember(from old: Any?, module: String, date: Date) -> [String: Any] {
        var member = old as? [String: Any] ?? [:]
        var content = member["Content"] as? [String: Any] ?? [:]
        let choice: [String: Any] = [
            "Provider": screenSaverProvider,
            "Files": [Any](),
            "Configuration": configuration(for: URL(filePath: module)),
        ]
        content["Choices"] = [choice]
        content["Shuffle"] = null
        member["Content"] = content
        member["LastSet"] = date
        member["LastUse"] = date
        return member
    }

    /// A saver's path in the form the store uses: absolute, standardised, no trailing slash.
    static func modulePath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
