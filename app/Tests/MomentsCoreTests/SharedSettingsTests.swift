import Foundation
import Testing
@testable import MomentsCore

/// A throwaway folder, removed when the test ends.
final class TemporaryFolder {
    let url = FileManager.default.temporaryDirectory.appending(path: "MomentsCoreTests.\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A defaults suite of its own, so tests never touch the real shared domain. Named by an
/// absolute path in the temporary folder, so nothing is left in ~/Library/Preferences.
final class TemporaryDefaults {
    let name = FileManager.default.temporaryDirectory.appending(path: "MomentsCoreTests.\(UUID().uuidString)").path
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(atPath: name + ".plist")
    }

    /// What cfprefsd would write to the domain's plist file.
    func writeFile(to url: URL) throws {
        let values = defaults.persistentDomain(forName: name) ?? [:]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: url)
    }
}

@Suite("Shared settings")
struct SharedSettingsTests {
    let custom = ClockSettings(timeMode: .viewer, showsRealTime: false, showsRecords: true,
                               showsMatchMinuteFill: true, photos: .typeOnly)

    @Test func appWritesAndBothSidesReadTheSameValues() throws {
        let suite = try TemporaryDefaults()
        let home = try TemporaryFolder()
        custom.save(to: suite.defaults)

        // The app reads back through the same domain.
        #expect(ClockSettings(defaults: suite.defaults) == custom)

        // The saver reads the domain's file by path, with nothing of its own to fall back on.
        let file = try #require(SharedSettings.fileURL(home: home.url, hostUUID: "TEST-HOST"))
        try suite.writeFile(to: file)
        #expect(SharedSettings.load(file: file, fallback: nil) == custom)
    }

    @Test func fileIsInTheByHostFolder() throws {
        let file = try #require(SharedSettings.fileURL(home: URL(filePath: "/Users/viewer"), hostUUID: "ABC"))
        #expect(file.path == "/Users/viewer/Library/Preferences/ByHost/AG.SportingMomentsClock.saver.ABC.plist")
        #expect(SharedSettings.fileURL(hostUUID: nil) == nil)
        #expect(SharedSettings.hostUUID?.isEmpty == false)
    }

    @Test func fileWinsAndTheSaversOwnDefaultsFillGaps() throws {
        let home = try TemporaryFolder()
        let file = home.url.appending(path: "shared.plist")
        try PropertyListSerialization.data(fromPropertyList: ["timeMode": "viewer"], format: .xml, options: 0).write(to: file)
        let own = try TemporaryDefaults()
        ClockSettings(timeMode: .venue, showsRecords: false).save(to: own.defaults)

        let settings = SharedSettings.load(file: file, fallback: own.defaults)
        #expect(settings.timeMode == .viewer)
        #expect(settings.showsRecords == false)
    }

    @Test func noFileMeansTheSaversOwnDefaults() throws {
        let home = try TemporaryFolder()
        let own = try TemporaryDefaults()
        custom.save(to: own.defaults)
        #expect(SharedSettings.load(file: home.url.appending(path: "missing.plist"), fallback: own.defaults) == custom)
        #expect(SharedSettings.load(file: nil, fallback: nil) == ClockSettings())
    }

    @Test func identifiersMatchTheProject() throws {
        // project.yml names the test bundle $(APP_BUNDLE_ID).tests.
        #expect(Bundle(for: BundleToken.self).bundleIdentifier == AppIdentity.bundleID + ".tests")
        #expect(SharedSettings.domain == "AG.SportingMomentsClock.saver")
        #expect(SharedSettings.legacyDomain == "com.sportingmoments.clock.saver")
    }

    @Test func legacySettingsAreCopiedOnce() throws {
        let legacy = try TemporaryDefaults()
        let current = try TemporaryDefaults()
        custom.save(to: legacy.defaults)

        #expect(SharedSettings.migrate(from: legacy.defaults, to: current.defaults))
        #expect(ClockSettings(defaults: current.defaults) == custom)

        // Once only: a later change under the old domain is not copied again.
        ClockSettings().save(to: legacy.defaults)
        #expect(!SharedSettings.migrate(from: legacy.defaults, to: current.defaults))
        #expect(ClockSettings(defaults: current.defaults) == custom)
    }

    @Test func migrationNeverOverwritesCurrentSettings() throws {
        let legacy = try TemporaryDefaults()
        let current = try TemporaryDefaults()
        custom.save(to: legacy.defaults)
        current.defaults.set("venue", forKey: "timeMode")

        #expect(!SharedSettings.migrate(from: legacy.defaults, to: current.defaults))
        #expect(ClockSettings(defaults: current.defaults) == ClockSettings())
    }

    @Test func nothingToMigrateLeavesTheDomainEmpty() throws {
        let legacy = try TemporaryDefaults()
        let current = try TemporaryDefaults()
        #expect(!SharedSettings.migrate(from: legacy.defaults, to: current.defaults))
        #expect(current.defaults.persistentDomain(forName: current.name)?.isEmpty ?? true)
    }
}

@Suite("Screen saver install")
struct SaverInstallerTests {
    /// A minimal .saver bundle: Info.plist and an executable.
    private func makeSaver(in folder: URL, version: String = "1", binary: String = "build one",
                           bundleID: String = AppIdentity.saverBundleID) throws -> URL {
        let saver = folder.appending(path: "source/\(SaverInstaller.bundleName)", directoryHint: .isDirectory)
        let contents = saver.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        let info = ["CFBundleExecutable": "SportingMomentsClock", "CFBundleVersion": version, "CFBundleIdentifier": bundleID]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        try Data(binary.utf8).write(to: contents.appending(path: "MacOS/SportingMomentsClock"))
        return saver
    }

    @Test func installsIntoAnEmptyFolder() throws {
        let temp = try TemporaryFolder()
        let installer = SaverInstaller(source: try makeSaver(in: temp.url),
                                       directory: temp.url.appending(path: "Screen Savers"))
        #expect(installer.status() == .notInstalled)

        try installer.install()
        #expect(installer.status() == .upToDate)
        let installed = installer.destination.appending(path: "Contents/MacOS/SportingMomentsClock")
        #expect(try String(contentsOf: installed, encoding: .utf8) == "build one")
    }

    @Test func aNewBuildShowsAsDifferentThenUpdates() throws {
        let temp = try TemporaryFolder()
        let installer = SaverInstaller(source: try makeSaver(in: temp.url),
                                       directory: temp.url.appending(path: "Screen Savers"))
        try installer.install()

        // Same CFBundleVersion, different executable: still needs an update.
        _ = try makeSaver(in: temp.url, binary: "build two")
        #expect(installer.status() == .differs(installedVersion: "1"))

        try installer.install()
        #expect(installer.status() == .upToDate)
        let installed = installer.destination.appending(path: "Contents/MacOS/SportingMomentsClock")
        #expect(try String(contentsOf: installed, encoding: .utf8) == "build two")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installer.directory.path)
        #expect(leftovers == [SaverInstaller.bundleName])
    }

    /// Builds before 1.0 were com.sportingmoments.clock.saver under the same file name.
    @Test func replacesASaverInstalledUnderTheOldIdentifier() throws {
        let temp = try TemporaryFolder()
        let directory = temp.url.appending(path: "Screen Savers")
        let old = try makeSaver(in: temp.url.appending(path: "old"), binary: "old build", bundleID: AppIdentity.legacySaverBundleID)
        try SaverInstaller(source: old, directory: directory).install()

        let installer = SaverInstaller(source: try makeSaver(in: temp.url), directory: directory)
        #expect(installer.status() == .differs(installedVersion: "1"))
        try installer.install()
        #expect(installer.status() == .upToDate)

        let data = try Data(contentsOf: installer.destination.appending(path: "Contents/Info.plist"))
        let info = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == AppIdentity.saverBundleID)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [SaverInstaller.bundleName])
    }

    @Test func aDifferentVersionNumberShowsAsDifferent() throws {
        let temp = try TemporaryFolder()
        let installer = SaverInstaller(source: try makeSaver(in: temp.url, version: "1"),
                                       directory: temp.url.appending(path: "Screen Savers"))
        try installer.install()
        _ = try makeSaver(in: temp.url, version: "2")
        #expect(installer.status() == .differs(installedVersion: "1"))
    }

    @Test func aFailedCopyLeavesTheInstalledSaverWorking() throws {
        let temp = try TemporaryFolder()
        let source = try makeSaver(in: temp.url)
        let directory = temp.url.appending(path: "Screen Savers")
        try SaverInstaller(source: source, directory: directory).install()

        // A source that has gone missing: the copy fails before anything is replaced.
        let broken = SaverInstaller(source: temp.url.appending(path: "gone/\(SaverInstaller.bundleName)"), directory: directory)
        #expect(throws: (any Error).self) { try broken.install() }
        let installed = directory.appending(path: "\(SaverInstaller.bundleName)/Contents/MacOS/SportingMomentsClock")
        #expect(try String(contentsOf: installed, encoding: .utf8) == "build one")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [SaverInstaller.bundleName])
    }

    /// The installer fingerprints the saver by the executable its Info.plist names. Without
    /// CFBundleExecutable every build looked unavailable and could not be installed.
    @Test func theRealSaverNamesItsExecutable() throws {
        let plist = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/Saver/Info.plist")
        let info = try #require(SharedSettings.readPlist(at: plist))
        #expect(info["CFBundleExecutable"] as? String == "$(EXECUTABLE_NAME)")
    }

    @Test func noEmbeddedSaverMeansUnavailable() throws {
        let temp = try TemporaryFolder()
        let installer = SaverInstaller(source: nil, directory: temp.url)
        #expect(installer.status() == .unavailable)
        #expect(throws: (any Error).self) { try installer.install() }
    }
}
