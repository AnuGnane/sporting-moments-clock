import Foundation

/// Who took a bundled photo and under which licence, from `credits.json`.
///
/// `Tools/make_credits.py` writes that file before each build from
/// data/overrides/images.csv and images_related.csv, one entry per photo in `Resources/images/`.
public struct PhotoCredit: Codable, Hashable, Identifiable, Sendable {
    /// File name inside `Resources/images/`, as in `MomentImage.file`.
    public var file: String
    /// Every moment that shows this photo.
    public var moments: [String]
    public var author: String
    /// "CC BY-SA 4.0", "Public domain".
    public var licence: String
    /// Nil when the licence has no page to link to (public domain, a plain "Attribution").
    public var licenceURL: URL?
    public var commonsFile: String
    public var commonsPage: URL?
    /// Where the photo was found, when not Wikimedia Commons ("Flickr"). `commonsPage` is then its page there.
    public var source: String?
    /// Who or what a related photo shows ("Sergey Bubka in 2013"), for photos that are not of the moment itself.
    public var subject: String?

    /// The name of the site the photo came from.
    public var sourceName: String { source ?? "Wikimedia Commons" }

    public var id: String { file }

    /// The moment the photo belongs to: the one it is named after (M0095.jpg is M0095's),
    /// else the first that uses it.
    public var mainMomentID: String? {
        let stem = (file as NSString).deletingPathExtension
        return moments.contains(stem) ? stem : moments.first
    }
}

public enum Credits {
    struct File: Codable {
        var version: Int
        var photos: [PhotoCredit]
    }

    public static func decode(_ data: Data) throws -> [PhotoCredit] {
        try JSONDecoder().decode(File.self, from: data).photos
    }

    /// The photo credits bundled with `bundle`, empty when the file is missing.
    public static func load(from bundle: Bundle) throws -> [PhotoCredit] {
        guard let url = bundle.url(forResource: "credits", withExtension: "json", subdirectory: MomentStore.dataFolder) else {
            return []
        }
        return try decode(Data(contentsOf: url))
    }
}
