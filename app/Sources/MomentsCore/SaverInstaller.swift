import CryptoKit
import Foundation

/// Copies the screen saver embedded in the app into the Screen Savers folder, and tells
/// whether the copy there matches the embedded one.
///
/// Two copies match when their CFBundleVersion and the SHA 256 of their executable agree.
/// The executable carries the code signature, which seals the bundle's resources, so a
/// rebuild with new moments or photos changes the hash too.
public struct SaverInstaller: Sendable {
    public enum Status: Equatable, Sendable {
        case notInstalled
        case upToDate
        /// Installed, but not the build inside this app. Carries the installed CFBundleVersion.
        case differs(installedVersion: String?)
        /// This app has no embedded saver, so there is nothing to install.
        case unavailable
    }

    public static let bundleName = "SportingMomentsClock.saver"

    /// The embedded saver, nil if missing.
    public let source: URL?
    /// The Screen Savers folder. Injectable so tests never touch the real one.
    public let directory: URL

    public var destination: URL { directory.appending(path: Self.bundleName, directoryHint: .isDirectory) }

    public init(source: URL?, directory: URL = SharedSettings.realHome.appending(path: "Library/Screen Savers")) {
        self.source = source
        self.directory = directory
    }

    /// The saver inside the app bundle (Contents/Resources), copied there by a build phase.
    public static func embeddedSaver(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "SportingMomentsClock", withExtension: "saver")
    }

    public func status() -> Status {
        guard let source, let embedded = Fingerprint(saver: source) else { return .unavailable }
        guard FileManager.default.fileExists(atPath: destination.path) else { return .notInstalled }
        let installed = Fingerprint(saver: destination)
        return installed == embedded ? .upToDate : .differs(installedVersion: installed?.version)
    }

    /// Installs the embedded saver, replacing any copy already there.
    public func install() throws {
        guard let source else { throw CocoaError(.fileNoSuchFile) }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        // Copy beside the destination first, then swap it in, so a failed copy leaves the old saver working.
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)
        defer { try? files.removeItem(at: staging) }
        let copy = staging.appending(path: Self.bundleName, directoryHint: .isDirectory)
        try files.copyItem(at: source, to: copy)
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: copy)
        } else {
            try files.moveItem(at: copy, to: destination)
        }
    }

    /// What identifies one build of the saver.
    struct Fingerprint: Equatable {
        let version: String?
        let executableHash: String

        /// Reads Info.plist directly: `Bundle` caches by path and would miss a replaced copy.
        init?(saver: URL) {
            let contents = saver.appending(path: "Contents", directoryHint: .isDirectory)
            guard let data = try? Data(contentsOf: contents.appending(path: "Info.plist")),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let executable = info["CFBundleExecutable"] as? String,
                  let binary = try? Data(contentsOf: contents.appending(path: "MacOS/\(executable)"))
            else { return nil }
            version = info["CFBundleVersion"] as? String
            executableHash = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        }
    }
}
