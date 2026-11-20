import Foundation
import Testing
@testable import MomentsCore

/// Runs the picker over every minute of the day against the bundled data, in venue
/// mode and in viewer mode for five zones, with every layer combination.
@Suite("Sweep over the bundled data")
struct SweepTests {
    enum Mode: CustomTestStringConvertible, Sendable {
        case venue
        case viewer(String)

        var testDescription: String {
            switch self {
            case .venue: "venue"
            case .viewer(let zone): "viewer \(zone)"
            }
        }

        var timeMode: ClockSettings.TimeMode {
            if case .venue = self { .venue } else { .viewer }
        }

        /// Venue mode does not depend on the viewer's zone; London stands in.
        var zone: String {
            if case .viewer(let zone) = self { zone } else { "Europe/London" }
        }
    }

    static let modes: [Mode] = [
        .venue,
        .viewer("Europe/London"), .viewer("America/New_York"), .viewer("Asia/Kolkata"),
        .viewer("Asia/Kathmandu"), .viewer("Australia/Sydney"),
    ]

    /// Every combination of the three layers.
    static let layerCombinations: [ClockSettings] = [false, true].flatMap { realTime in
        [false, true].flatMap { records in
            [false, true].map { fill in
                ClockSettings(showsRealTime: realTime, showsRecords: records, showsMatchMinuteFill: fill)
            }
        }
    }

    let store = Fixtures.bundledStore

    @Test(arguments: modes)
    func everyMinute(mode: Mode) throws {
        let calendar = Fixtures.calendar(mode.zone)
        let picker = MomentPicker(store: store)
        var report: [String] = []

        for var settings in Self.layerCombinations {
            settings.timeMode = mode.timeMode
            var covered = 0
            var previous: Card?
            var blankAfterFirstCard = 0
            var longestGap = 0
            var gap = 0

            for minute in 0..<1440 {
                let date = Fixtures.date(2026, 11, 20, minute / 60, minute % 60, in: calendar)
                let card = picker.card(at: date, calendar: calendar, settings: settings)
                if let card {
                    covered += 1
                    gap = 0
                    check(card, at: minute, settings: settings)
                } else {
                    gap += 1
                    longestGap = max(longestGap, gap)
                }

                // Rule 6 as the clock runs it: once any card has shown, there is always one.
                let shown = picker.resolve(at: date, calendar: calendar, settings: settings, previous: previous)
                if previous != nil, shown == nil { blankAfterFirstCard += 1 }
                if shown != nil { previous = shown }
            }

            #expect(blankAfterFirstCard == 0, "\(describe(settings)): \(blankAfterFirstCard) blank minutes after the first card")
            if covered > 0 {
                // With anything in the data, the launch walk back finds a card from the very first minute.
                let first = Fixtures.date(2026, 11, 20, 0, 0, in: calendar)
                #expect(picker.resolve(at: first, calendar: calendar, settings: settings, previous: nil) != nil)
            }
            if settings.showsMatchMinuteFill, store.source == .full {
                #expect(covered == 1440, "\(describe(settings)): only \(covered) of 1,440 minutes have a candidate")
            }
            report.append("\(describe(settings)): \(covered) minutes covered, longest gap \(longestGap) min")
        }
        print("Coverage, \(mode.testDescription), \(store.source.rawValue) data (\(store.moments.count) moments):\n  "
              + report.joined(separator: "\n  "))
    }

    private func check(_ card: Card, at minute: Int, settings: ClockSettings) {
        let time = LocalDateTime.timeText(minuteOfDay: minute)
        #expect(!card.caption.trimmingCharacters(in: .whitespaces).isEmpty, "\(card.moment.id) at \(time) has no caption")
        #expect(!card.label.isEmpty, "\(card.moment.id) at \(time) has no label")
        #expect(card.time == time)
        if let photo = card.photo {
            #expect(!photo.credit.isEmpty, "\(card.moment.id) has a photo without a credit")
            #expect(FileManager.default.fileExists(atPath: photo.url.path), "\(card.moment.id): \(photo.url.lastPathComponent) missing")
        }
    }

    private func describe(_ s: ClockSettings) -> String {
        let layers = [s.showsRealTime ? "real time" : nil, s.showsRecords ? "records" : nil, s.showsMatchMinuteFill ? "fill" : nil]
            .compactMap { $0 }
        return layers.isEmpty ? "no layers" : layers.joined(separator: " + ")
    }
}

/// Checks on the bundled data itself, so a pipeline mistake shows up as a failing test.
@Suite("Bundled data")
struct BundledDataTests {
    let store = Fixtures.bundledStore

    @Test func loads() {
        print("Bundled data: \(store.source.rawValue), \(store.moments.count) moments, "
              + "\(store.moments.filter { store.imageURL(for: $0) != nil }.count) with a bundled photo")
        #expect(!store.moments.isEmpty)
    }

    /// Every entry in the bundled file decodes: none is skipped.
    @Test func noEntryIsSkipped() throws {
        let url = try #require(Fixtures.bundle.url(forResource: store.source == .full ? "moments" : "sample_moments",
                                                   withExtension: "json", subdirectory: MomentStore.dataFolder))
        let file = try MomentsFile.decode(Data(contentsOf: url))
        #expect(file.skipped.isEmpty, "skipped: \(file.skipped.prefix(10).joined(separator: "; "))")
    }

    @Test func idsAreUnique() {
        #expect(Set(store.moments.map(\.id)).count == store.moments.count)
    }

    /// `venueLocal` must be the instant read in the venue zone. This is what catches a
    /// missed midnight rollover (Istanbul 2005 is 26 May, 00:30).
    @Test func venueLocalMatchesTheInstant() {
        for moment in store.moments {
            guard let instant = moment.instantUTC, let local = moment.venueLocal else { continue }
            guard let zone = moment.venueTimeZone else {
                Issue.record("\(moment.id) has an instant but no valid venueTZ (\(moment.venueTZ ?? "nil"))")
                continue
            }
            #expect(LocalDateTime(instant: instant, in: zone) == local, "\(moment.id): venueLocal disagrees with instantUTC in \(zone.identifier)")
        }
    }

    @Test func istanbulRollsOverMidnight() throws {
        let istanbul = try #require(store.moments.first { $0.id == "M0069" })
        let picker = MomentPicker(store: MomentStore(moments: [istanbul]))
        let london = Fixtures.calendar("Europe/London")
        let venue = picker.card(at: Fixtures.date(2026, 11, 20, 0, 30, in: london), calendar: london, settings: ClockSettings())
        #expect(venue?.detail.hasPrefix("26 May 2005") == true)
        let viewer = picker.card(at: Fixtures.date(2026, 11, 20, 22, 30, in: london), calendar: london,
                                 settings: ClockSettings(timeMode: .viewer))
        #expect(viewer?.detail.hasPrefix("25 May 2005") == true)
        #expect(viewer?.venueTimeNote == "00:30 in Istanbul")
    }

    /// Design decision: Kipchoge's 1:59:40 (M0182, a fame 1 curated moment) and Sawe's 1:59:30
    /// (R017, a fame 2 record) both read 01:59. As record candidates both rank as fame 2,
    /// so they tie and rotate daily, and each wins on its own anniversary.
    @Test func the0159RecordsRotateDaily() throws {
        let store = self.store
        try #require(store.moments.contains { $0.id == "M0182" } && store.moments.contains { $0.id == "R017" },
                     "M0182 and R017 are not both in the bundled data")
        let picker = MomentPicker(store: store)
        let london = Fixtures.calendar("Europe/London")
        func winner(_ month: Int, _ day: Int) -> String? {
            picker.card(at: Fixtures.date(2026, month, day, 1, 59, in: london), calendar: london, settings: ClockSettings())?.moment.id
        }
        let first = winner(11, 20)
        let second = winner(11, 21)
        #expect(Set([first, second]) == ["M0182", "R017"], "consecutive days gave \(String(describing: first)) and \(String(describing: second))")
        #expect(winner(10, 12) == "M0182")  // Vienna, 12 October 2019
        #expect(winner(4, 26) == "R017")  // London, 26 April 2026
        print("01:59 on 20 and 21 November: \(first ?? "nil"), \(second ?? "nil"); 12 October: \(winner(10, 12) ?? "nil"); 26 April: \(winner(4, 26) ?? "nil")")
    }

    @Test func everyReferencedPhotoIsBundledWithACredit() {
        for moment in store.moments {
            guard let image = moment.image else { continue }
            #expect(!image.credit.isEmpty, "\(moment.id) has an image without a credit")
            #expect(store.imageURL(for: moment) != nil, "\(moment.id): \(image.file) is not in Resources/images")
        }
    }

    @Test func recordDigitsAreClockTimes() {
        for moment in store.moments where moment.recordDigits != nil {
            #expect(moment.recordMinuteOfDay != nil, "\(moment.id): recordDigits \(moment.recordDigits!) is not HH:mm")
        }
    }
}
