import Foundation
import os

/// Holds every moment and the minute indexes the picker reads from.
///
/// Immutable after loading, apart from a small cache of viewer time zone indexes,
/// so one store can be shared by every screen and every test.
public final class MomentStore: Sendable {
    public enum Source: String, Sendable {
        /// `moments.json` from the data pipeline.
        case full
        /// `sample_moments.json`, used until the pipeline has run.
        case sample
        /// Moments handed in directly (tests and previews).
        case inMemory
    }

    /// Folder inside the bundle's Resources that holds the JSON files and `images/`.
    /// It is a folder reference in project.yml, so its name is kept as is.
    public static let dataFolder = "Resources"

    public let moments: [Moment]
    public let source: Source

    /// Real time candidates by venue minute of the day (0 to 1439).
    public let venueIndex: [Int: [Moment]]
    /// Record candidates by the minute of the day their mark reads as.
    public let recordIndex: [Int: [Moment]]
    /// Match minute fill candidates by `matchMinute mod 60`.
    public let fillIndex: [Int: [Moment]]

    private let imagesDirectory: URL?
    private let bundledImages: Set<String>
    private let viewerIndexes = OSAllocatedUnfairLock(initialState: [String: [Int: [Moment]]]())

    public init(moments: [Moment], source: Source = .inMemory, imagesDirectory: URL? = nil) {
        self.moments = moments
        self.source = source
        self.imagesDirectory = imagesDirectory

        var venue: [Int: [Moment]] = [:]
        var records: [Int: [Moment]] = [:]
        var fill: [Int: [Moment]] = [:]
        for moment in moments {
            if let local = moment.venueLocal { venue[local.minuteOfDay, default: []].append(moment) }
            if let minute = moment.recordMinuteOfDay { records[minute, default: []].append(moment) }
            if let matchMinute = moment.matchMinute { fill[matchMinute % 60, default: []].append(moment) }
        }
        venueIndex = venue
        recordIndex = records
        fillIndex = fill

        let files = imagesDirectory.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        bundledImages = Set(files)
    }

    /// Loads `moments.json` from `bundle`, or `sample_moments.json` when the full file is missing.
    /// Pass `Bundle(for: SomeClass.self)` from the saver: `Bundle.main` there is the host process.
    public convenience init(bundle: Bundle) throws {
        let folder = Self.dataFolder
        let imagesDirectory = bundle.resourceURL?.appending(path: "\(folder)/images", directoryHint: .isDirectory)
        let source: Source
        let url: URL
        if let full = bundle.url(forResource: "moments", withExtension: "json", subdirectory: folder) {
            (source, url) = (.full, full)
        } else if let sample = bundle.url(forResource: "sample_moments", withExtension: "json", subdirectory: folder) {
            (source, url) = (.sample, sample)
        } else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "No moments.json in \(bundle.bundlePath)"])
        }
        let file = try MomentsFile.decode(Data(contentsOf: url))
        if !file.skipped.isEmpty {
            Logger(subsystem: AppIdentity.bundleID, category: "data").error(
                "Skipped \(file.skipped.count) unreadable moments: \(file.skipped.prefix(10).joined(separator: "; "), privacy: .public)"
            )
        }
        self.init(moments: file.moments, source: source, imagesDirectory: imagesDirectory)
    }

    /// Real time candidates by the viewer's minute of the day, for one viewer time zone.
    /// Each instant is converted with the offset in force at that instant, so the index
    /// does not depend on today's date.
    public func viewerIndex(for zone: TimeZone) -> [Int: [Moment]] {
        if let cached = viewerIndexes.withLock({ $0[zone.identifier] }) { return cached }
        let calendar = Calendar.gregorian(in: zone)
        var index: [Int: [Moment]] = [:]
        for moment in moments {
            guard let instant = moment.instantUTC else { continue }
            index[LocalDateTime(instant: instant, calendar: calendar).minuteOfDay, default: []].append(moment)
        }
        let built = index
        viewerIndexes.withLock { $0[zone.identifier] = built }
        return built
    }

    /// The bundled photo for a moment, or nil when the file is not in the bundle
    /// (a missing file means a type only card).
    public func imageURL(for moment: Moment) -> URL? {
        guard let file = moment.image?.file, bundledImages.contains(file), let imagesDirectory else { return nil }
        return imagesDirectory.appending(path: file, directoryHint: .notDirectory)
    }
}
