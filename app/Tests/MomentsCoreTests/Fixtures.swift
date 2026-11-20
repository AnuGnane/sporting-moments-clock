import Foundation
@testable import MomentsCore

final class BundleToken {}

enum Fixtures {
    /// The test bundle carries the same Resources folder as the app and the saver.
    static let bundle = Bundle(for: BundleToken.self)

    /// moments.json when present, otherwise the sample. Loaded once.
    static let bundledStore: MomentStore = {
        do {
            return try MomentStore(bundle: bundle)
        } catch {
            fatalError("Could not load bundled moments: \(error)")
        }
    }()

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// A wall clock time in `calendar`'s zone.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func instant(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    /// Builds a moment that happened at `local` in `zone`.
    static func moment(
        _ id: String, at local: String? = nil, zone: String = "Europe/London", fame: Int = 1, fameSub: Int = 0,
        basis: TimeBasis = .derived, place: String? = "Wembley Stadium, London",
        recordDigits: String? = nil, recordMark: String? = nil, recordLabel: String? = nil,
        matchMinute: Int? = nil, matchMinuteLabel: String? = nil, date: String? = nil,
        image: MomentImage? = nil
    ) -> Moment {
        var instant: Date?
        var venueLocal: LocalDateTime?
        if let local, let parsed = LocalDateTime(local) {
            let calendar = calendar(zone)
            instant = Self.date(parsed.date.year, parsed.date.month, parsed.date.day, parsed.hour, parsed.minute, in: calendar)
            venueLocal = parsed
        }
        return Moment(
            id: id, caption: "Caption for \(id)", instantUTC: instant, venueTZ: local == nil ? nil : zone,
            venueLocal: venueLocal, place: place, basis: local == nil ? nil : basis,
            recordDigits: recordDigits, recordMark: recordMark, recordLabel: recordLabel,
            matchMinute: matchMinute, matchMinuteLabel: matchMinuteLabel,
            fame: fame, fameSub: fameSub, image: image, date: date.flatMap(LocalDate.init)
        )
    }
}
