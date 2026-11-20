import Foundation

/// One sporting moment, decoded from `moments.json` (see SPEC.md for the schema).
///
/// A moment can reach the screen in three ways: at the clock time it happened
/// (`instantUTC` / `venueLocal`), as a world record whose mark reads as a clock
/// time (`recordDigits`), or through the optional match minute fill (`matchMinute`).
public struct Moment: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sport: String
    public var caption: String

    /// The instant it happened. Nil when no clock time is known.
    public var instantUTC: Date?
    /// IANA zone of the venue, for example "Europe/Madrid".
    public var venueTZ: String?
    /// Venue wall clock date and time of `instantUTC`, after the midnight fix.
    public var venueLocal: LocalDateTime?
    /// "Stadium, City". Nil when not known for certain.
    public var place: String?
    public var basis: TimeBasis?
    public var plusMinusMin: Int?
    public var checked: Bool?

    /// "HH:mm" that the record mark reads as, for example "09:58" for 9.58.
    public var recordDigits: String?
    public var recordMark: String?
    public var recordEvent: String?
    /// What the record is called on the card: "World record", "Record", "The score".
    public var recordLabel: String?

    public var matchMinute: Int?
    public var matchMinuteLabel: String?

    /// 1 curated, 2 famous record, 3 harvested goal, 4 lesser record. Lower is more famous.
    public var fame: Int
    /// Tie break inside a fame tier, lower is better.
    public var fameSub: Int?
    public var sourceURL: URL?
    public var image: MomentImage?

    /// Venue local date, "yyyy-MM-dd". Used when there is no `venueLocal`
    /// (record only rows, fill cards without a time). Optional so older files still load.
    public var date: LocalDate?

    public init(
        id: String, sport: String = "Football", caption: String,
        instantUTC: Date? = nil, venueTZ: String? = nil, venueLocal: LocalDateTime? = nil,
        place: String? = nil, basis: TimeBasis? = nil, plusMinusMin: Int? = nil, checked: Bool? = nil,
        recordDigits: String? = nil, recordMark: String? = nil, recordEvent: String? = nil, recordLabel: String? = nil,
        matchMinute: Int? = nil, matchMinuteLabel: String? = nil,
        fame: Int, fameSub: Int? = nil, sourceURL: URL? = nil, image: MomentImage? = nil,
        date: LocalDate? = nil
    ) {
        self.id = id; self.sport = sport; self.caption = caption
        self.instantUTC = instantUTC; self.venueTZ = venueTZ; self.venueLocal = venueLocal
        self.place = place; self.basis = basis; self.plusMinusMin = plusMinusMin; self.checked = checked
        self.recordDigits = recordDigits; self.recordMark = recordMark; self.recordEvent = recordEvent
        self.recordLabel = recordLabel
        self.matchMinute = matchMinute; self.matchMinuteLabel = matchMinuteLabel
        self.fame = fame; self.fameSub = fameSub; self.sourceURL = sourceURL; self.image = image
        self.date = date
    }

    /// The venue's calendar date: from `venueLocal` when known, else `date`.
    public var venueDate: LocalDate? {
        venueLocal?.date ?? date
    }

    public var venueTimeZone: TimeZone? {
        venueTZ.flatMap(TimeZone.init(identifier:))
    }

    /// Minute of the day (0 to 1439) that `recordDigits` reads as.
    public var recordMinuteOfDay: Int? {
        recordDigits.flatMap(LocalDateTime.minuteOfDay(parsing:))
    }
}

public struct MomentImage: Codable, Hashable, Sendable {
    /// File name inside `Resources/images/`.
    public var file: String
    /// "Photo: Author · Licence · Wikimedia Commons".
    public var credit: String

    public init(file: String, credit: String) {
        self.file = file
        self.credit = credit
    }
}

public enum TimeBasis: String, Codable, Sendable {
    case documented, derived, scheduled, estimated, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TimeBasis(rawValue: raw) ?? .unknown
    }
}

/// The JSON file: `{ "version": 1, "generated": ..., "moments": [...] }`.
///
/// A moment that cannot be read (a missing field, a malformed date) is skipped and listed in
/// `skipped`, so one bad row from the pipeline costs one moment, not the whole clock.
public struct MomentsFile: Decodable, Sendable {
    public var version: Int
    public var moments: [Moment]
    /// "M0123: reason" for each entry that was skipped.
    public var skipped: [String]

    public static func decode(_ data: Data) throws -> MomentsFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MomentsFile.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case version, moments
    }

    /// Reads just the id of an entry, to name it when the full entry fails. Never throws,
    /// whatever the entry holds, so decoding it always moves on to the next entry.
    private struct EntryID: Decodable {
        private enum Key: String, CodingKey { case id }
        var id: String?

        init(from decoder: Decoder) {
            id = try? decoder.container(keyedBy: Key.self).decode(String.self, forKey: .id)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        var list = try container.nestedUnkeyedContainer(forKey: .moments)
        moments = []
        skipped = []
        while !list.isAtEnd {
            let index = list.currentIndex
            do {
                moments.append(try list.decode(Moment.self))
            } catch {
                // A failed decode stays on the same entry; read its id to move past it.
                let id = (try? list.decode(EntryID?.self))??.id ?? "entry \(index)"
                skipped.append("\(id): \(Self.reason(error))")
                if list.currentIndex == index { break }  // could not move on: stop rather than loop
            }
        }
    }

    private static func reason(_ error: Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, _): "no \(key.stringValue)"
        case .valueNotFound(_, let context), .typeMismatch(_, let context), .dataCorrupted(let context):
            "\(context.codingPath.last?.stringValue ?? "value"): \(context.debugDescription)"
        default: error.localizedDescription
        }
    }
}
