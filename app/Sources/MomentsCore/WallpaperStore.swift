import Foundation

/// The wallpaper store file, read to tell which screen saver is chosen and rewritten to
/// choose this one. See `ScreenSaverSelection` for the layout.
///
/// Choosing works like this: back up the store, write the new one atomically, restart
/// WallpaperAgent so it reads it, then read the store again to confirm the agent kept the
/// change. If it did not, the backup goes back and the agent restarts once more.
public struct WallpaperStore: Sendable {
    public enum State: Equatable, Sendable {
        /// The screen saver at the given path is chosen for every display and space.
        case selected
        /// Another screen saver is chosen somewhere.
        case notSelected
        /// No store, or one this app cannot read safely: choose in System Settings.
        case unknown
    }

    public enum Failure: Error, Equatable, Sendable {
        /// Nothing was written. The store is missing, unreadable or laid out unexpectedly.
        case cannotSelect(String)
        /// The store was written but macOS did not keep the change. The backup is back.
        case didNotTake
        /// The change did not take and the backup could not be put back either.
        case restoreFailed(String)
    }

    /// WallpaperAgent's store.
    public let index: URL
    /// The copy of the store taken before each change. Only the latest is kept.
    public let backup: URL

    public static let defaultIndex = SharedSettings.realHome
        .appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist", directoryHint: .notDirectory)
    public static let defaultBackup = SharedSettings.realHome
        .appending(path: "Library/Application Support/\(AppIdentity.bundleID)/WallpaperIndex.backup.plist", directoryHint: .notDirectory)

    public init(index: URL = defaultIndex, backup: URL = defaultBackup) {
        self.index = index
        self.backup = backup
    }

    /// Whether `saver` is the chosen screen saver. Reads the file; never writes.
    public func state(of saver: URL) -> State {
        guard let data = try? Data(contentsOf: index),
              let selected = try? ScreenSaverSelection.isSelected(data, saver: saver)
        else { return .unknown }
        return selected ? .selected : .notSelected
    }

    /// Makes `saver` the screen saver.
    ///
    /// - Parameters:
    ///   - restartAgent: restarts WallpaperAgent so it reads the store again. Tests pass a fake.
    ///   - settle: how long to give the agent after a restart before each of the two checks.
    public func select(
        _ saver: URL,
        restartAgent: @Sendable () async -> Void,
        settle: Duration = .seconds(2)
    ) async throws(Failure) {
        let original: Data
        let updated: Data
        do {
            original = try Data(contentsOf: index)
        } catch {
            throw .cannotSelect("The wallpaper store could not be read.")
        }
        do throws(ScreenSaverSelection.Refusal) {
            if try ScreenSaverSelection.isSelected(original, saver: saver) { return }
            updated = try ScreenSaverSelection.select(original, saver: saver)
            // Never write what does not read back as chosen.
            guard try ScreenSaverSelection.isSelected(updated, saver: saver) else {
                throw .unexpected("the result")
            }
        } catch {
            throw .cannotSelect(error.description)
        }

        do {
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: backup, options: .atomic)
            try updated.write(to: index, options: .atomic)
        } catch {
            // The store is written last and atomically, so a failure here leaves it as it was.
            throw .cannotSelect(error.localizedDescription)
        }

        await restartAgent()
        // Twice, so a store the agent rewrites shortly after it starts is caught too.
        try? await Task.sleep(for: settle)
        if state(of: saver) == .selected {
            try? await Task.sleep(for: settle)
            if state(of: saver) == .selected { return }
        }

        do {
            try original.write(to: index, options: .atomic)
        } catch {
            throw .restoreFailed(error.localizedDescription)
        }
        await restartAgent()
        throw .didNotTake
    }
}
