import Foundation
import Testing
@testable import MomentsCore

/// One test per picker rule in SPEC.md, on small hand made stores.
@Suite("Picker rules")
struct PickerTests {
    let london = Fixtures.calendar("Europe/London")
    let defaults = ClockSettings()

    private func pick(_ moments: [Moment], at date: Date, calendar: Calendar? = nil,
                      settings: ClockSettings = ClockSettings()) -> Card? {
        MomentPicker(store: MomentStore(moments: moments)).card(at: date, calendar: calendar ?? london, settings: settings)
    }

    // Rule 1 and 2, venue mode.
    @Test func venueModeMatchesTheVenueWallClock() {
        let solskjaer = Fixtures.moment("M0054", at: "1999-05-26T22:35", zone: "Europe/Madrid", place: "Camp Nou, Barcelona", matchMinute: 93)
        // The viewer is in Kolkata, but venue mode shows it when the viewer's clock reads 22:35.
        let kolkata = Fixtures.calendar("Asia/Kolkata")
        let card = pick([solskjaer], at: Fixtures.date(2026, 11, 20, 22, 35, in: kolkata), calendar: kolkata)
        #expect(card?.moment.id == "M0054")
        #expect(card?.kind == .realTime)
        #expect(card?.time == "22:35")
        #expect(card?.label == "Around")
        // The moment's time only appears when it differs from the big clock (a kept card).
        #expect(card?.headline(clock: "22:35") == nil)
        #expect(card?.headline(clock: "22:39") == "Around 22:35")
        #expect(card?.detail == "26 May 1999 · Camp Nou, Barcelona · venue time")
        #expect(card?.venueTimeNote == nil)
        #expect(pick([solskjaer], at: Fixtures.date(2026, 11, 20, 22, 36, in: kolkata), calendar: kolkata) == nil)
    }

    // Rule 2, viewer mode: the instant in the viewer's zone, with the offset in force at that instant.
    @Test func viewerModeUsesTheOffsetInForceAtTheInstant() {
        let solskjaer = Fixtures.moment("M0054", at: "1999-05-26T22:35", zone: "Europe/Madrid", place: "Camp Nou, Barcelona")
        let viewer = ClockSettings(timeMode: .viewer)
        // 20:35 UTC was 21:35 in London that May (BST), even though today, in November, London is on GMT.
        let card = pick([solskjaer], at: Fixtures.date(2026, 11, 20, 21, 35, in: london), settings: viewer)
        #expect(card?.moment.id == "M0054")
        #expect(card?.label == "Around · your time")
        #expect(card?.venueTimeNote == "22:35 in Barcelona")
        #expect(card?.detail == "26 May 1999 · Camp Nou, Barcelona")
        #expect(pick([solskjaer], at: Fixtures.date(2026, 11, 20, 20, 35, in: london), settings: viewer) == nil)
    }

    @Test func viewerModeHandlesQuarterHourZones() {
        let kipchoge = Fixtures.moment("M0182", at: "2019-10-12T10:14", zone: "Europe/Vienna", basis: .documented, place: "Prater, Vienna")
        let kathmandu = Fixtures.calendar("Asia/Kathmandu")  // UTC+5:45
        let card = pick([kipchoge], at: Fixtures.date(2026, 11, 20, 13, 59, in: kathmandu),
                        calendar: kathmandu, settings: ClockSettings(timeMode: .viewer))
        #expect(card?.label == "Exactly · your time")
        #expect(card?.venueTimeNote == "10:14 in Vienna")
        #expect(card?.headline(clock: "13:59") == "10:14 in Vienna")
        #expect(card?.headline(clock: "14:02") == "At 13:59 your time · 10:14 in Vienna")
    }

    @Test func documentedTimesSayExactly() {
        let isner = Fixtures.moment("M0149", at: "2010-06-24T16:47", basis: .documented)
        let card = pick([isner], at: Fixtures.date(2026, 1, 3, 16, 47, in: london))
        #expect(card?.label == "Exactly")
        // On screen a documented time reads "At" once the card is kept past its minute.
        #expect(card?.headline(clock: "16:47") == nil)
        #expect(card?.headline(clock: "16:52") == "At 16:47")
    }

    @Test func viewerModeWithTheSameVenueTimeHasNoAccentLine() {
        let isner = Fixtures.moment("M0149", at: "2010-06-24T16:47", zone: "Europe/London", basis: .documented)
        // Wimbledon in June was BST; a viewer in Lagos (UTC+1, no summer time) shares that wall clock.
        let lagos = Fixtures.calendar("Africa/Lagos")
        let card = pick([isner], at: Fixtures.date(2026, 1, 3, 16, 47, in: lagos), calendar: lagos,
                        settings: ClockSettings(timeMode: .viewer))
        #expect(card?.venueTimeNote == nil)
        #expect(card?.headline(clock: "16:47") == nil)
        #expect(card?.headline(clock: "16:50") == "At 16:47 your time")
    }

    @Test func realTimeLayerCanBeSwitchedOff() {
        let isner = Fixtures.moment("M0149", at: "2010-06-24T16:47")
        let off = ClockSettings(showsRealTime: false)
        #expect(pick([isner], at: Fixtures.date(2026, 1, 3, 16, 47, in: london), settings: off) == nil)
    }

    // Rule 3: records.
    @Test func recordsShowWhenTheClockReadsTheirDigits() throws {
        let bolt = Fixtures.moment("M0172", at: "2009-08-16T21:35", zone: "Europe/Berlin", place: "Olympiastadion, Berlin",
                                   recordDigits: "09:58", recordMark: "9.58", recordLabel: "World record")
        let card = try #require(pick([bolt], at: Fixtures.date(2026, 11, 20, 9, 58, in: london)))
        #expect(card.kind == .record)
        #expect(card.label == "World record · the mark reads 9.58")
        #expect(card.headline(clock: "09:58") == card.label)
        #expect(card.headline(clock: "10:03") == card.label)
        #expect(card.detail == "16 August 2009 · Olympiastadion, Berlin")
        // The same moment still shows in real time at 21:35.
        #expect(pick([bolt], at: Fixtures.date(2026, 11, 20, 21, 35, in: london))?.kind == .realTime)
        // And not at all at 09:58 with the records layer off.
        #expect(pick([bolt], at: Fixtures.date(2026, 11, 20, 9, 58, in: london), settings: ClockSettings(showsRecords: false)) == nil)
    }

    @Test func recordLabelComesFromTheData() {
        let score = Fixtures.moment("R900", place: nil, recordDigits: "07:01", recordMark: nil, recordLabel: "The score", date: "1976-07-18")
        let card = pick([score], at: Fixtures.date(2026, 11, 20, 7, 1, in: london))
        #expect(card?.label == "The score")
        #expect(card?.detail == "18 July 1976")
    }

    @Test func recordOnlyEntriesUseTheirDate() {
        let record = Fixtures.moment("R001", fame: 2, place: "Olympiastadion, Berlin", recordDigits: "19:19", recordMark: "19.19",
                                     recordLabel: "World record", date: "2009-08-20")
        let card = pick([record], at: Fixtures.date(2026, 11, 20, 19, 19, in: london), settings: ClockSettings(timeMode: .viewer))
        #expect(card?.label == "World record · the mark reads 19.19")
        #expect(card?.detail == "20 August 2009 · Olympiastadion, Berlin")
    }

    /// Records from other sports may have no date and no place: the detail line just leaves them out.
    @Test func aRecordWithNoDateOrPlaceFromAnySport() throws {
        let bare = Moment(id: "X001", sport: "Cricket", caption: "Lara makes 400 not out", recordDigits: "04:00",
                          recordMark: "400*", recordLabel: "Test record", fame: 4)
        let at = Fixtures.date(2026, 11, 20, 4, 0, in: london)
        for mode in ClockSettings.TimeMode.allCases {
            let card = try #require(pick([bare], at: at, settings: ClockSettings(timeMode: mode)))
            #expect(card.kind == .record)
            #expect(card.label == "Test record · the number reads 400*")
            #expect(card.headline(clock: "04:00") == card.label)
            #expect(card.detail.isEmpty)
            #expect(card.venueTimeNote == nil)
        }
        var withEvent = bare
        withEvent.recordEvent = "Highest Test score"
        #expect(pick([withEvent], at: at)?.detail == "Highest Test score")
        // With match minute fill on, a bare record still reads the same.
        #expect(pick([bare], at: at, settings: ClockSettings(showsMatchMinuteFill: true))?.label == "Test record · the number reads 400*")
    }

    /// Times and measurements read as a mark; counts and scores read as a number.
    @Test func recordLabelSaysMarkOrNumber() {
        for mark in ["9.58", "2.43", "19.19", "1:59:40", "2:01:09", "8.95 m"] {
            #expect(Card.isMeasuredMark(mark), "\(mark) should read as a mark")
        }
        for mark in ["3", "755", "2,105", ".406", "501*", "952/6", "147"] {
            #expect(!Card.isMeasuredMark(mark), "\(mark) should read as a number")
        }
        let at = Fixtures.date(2026, 11, 20, 7, 55, in: london)
        let homeRuns = Fixtures.moment("X002", place: nil, recordDigits: "07:55", recordMark: "755", recordLabel: "Career home runs")
        #expect(pick([homeRuns], at: at)?.label == "Career home runs · the number reads 755")
        let jump = Fixtures.moment("X003", place: nil, recordDigits: "07:55", recordMark: "7.55", recordLabel: "World best")
        #expect(pick([jump], at: at)?.label == "World best · the mark reads 7.55")
    }

    // Rule 4: ranking.
    @Test func lowerFameWins() {
        let harvested = Fixtures.moment("M0400", at: "1966-07-30T16:30", fame: 3)
        let curated = Fixtures.moment("M0900", at: "1970-06-21T16:30", fame: 1)
        #expect(pick([harvested, curated], at: Fixtures.date(2026, 2, 1, 16, 30, in: london))?.moment.id == "M0900")
    }

    @Test func recordsRankAsFameTwoOrFour() {
        let at = Fixtures.date(2026, 2, 1, 9, 58, in: london)
        let goal = Fixtures.moment("M0500", at: "2000-01-01T09:58", fame: 3)
        let famous = Fixtures.moment("R001", fame: 2, recordDigits: "09:58", recordMark: "9.58")
        let lesser = Fixtures.moment("R002", fame: 4, recordDigits: "09:58", recordMark: "9.58")
        // A curated moment that is also a record competes as fame 2 at its digits.
        let curatedRecord = Fixtures.moment("M0172", at: "2009-08-16T21:35", fame: 1, recordDigits: "09:58", recordMark: "9.58")
        #expect(pick([goal, famous], at: at)?.moment.id == "R001")
        #expect(pick([goal, lesser], at: at)?.moment.id == "M0500")
        #expect(pick([curatedRecord, goal], at: at)?.moment.id == "M0172")
        let curatedAtThatTime = Fixtures.moment("M0001", at: "1990-01-01T09:58", fame: 1)
        #expect(pick([curatedRecord, curatedAtThatTime], at: at)?.moment.id == "M0001")
    }

    @Test func todaysAnniversaryWinsATie() {
        let other = Fixtures.moment("M0001", at: "1999-03-01T22:35")
        let anniversary = Fixtures.moment("M0002", at: "1999-05-26T22:35")
        #expect(pick([other, anniversary], at: Fixtures.date(2026, 5, 26, 22, 35, in: london))?.moment.id == "M0002")
        let lowerFameStillWins = Fixtures.moment("M0003", at: "1999-05-26T22:35", fame: 3)
        #expect(pick([other, lowerFameStillWins], at: Fixtures.date(2026, 5, 26, 22, 35, in: london))?.moment.id == "M0001")
    }

    @Test func lowerFameSubWinsATie() {
        let group = Fixtures.moment("M0500", at: "2002-06-01T15:00", fame: 3, fameSub: 5)
        let final = Fixtures.moment("M0600", at: "2002-06-30T15:00", fame: 3, fameSub: 0)
        #expect(pick([group, final], at: Fixtures.date(2026, 1, 10, 15, 0, in: london))?.moment.id == "M0600")
    }

    @Test func remainingTiesRotateDaily() {
        let ids = ["M0003", "M0001", "M0002"]
        let moments = ids.map { Fixtures.moment($0, at: "2000-01-01T12:00") }
        // Day of year 1 picks index 1 of the sorted ids, day 2 picks index 2, day 3 index 0.
        let jan1 = pick(moments, at: Fixtures.date(2026, 1, 1, 12, 0, in: london))?.moment.id
        let jan2 = pick(moments, at: Fixtures.date(2026, 1, 2, 12, 0, in: london))?.moment.id
        let jan3 = pick(moments, at: Fixtures.date(2026, 1, 3, 12, 0, in: london))?.moment.id
        #expect([jan1, jan2, jan3] == ["M0002", "M0003", "M0001"])
    }

    // Rule 5: match minute fill.
    @Test func matchMinuteFillIsOffByDefault() {
        let solskjaer = Fixtures.moment("M0054", at: "1999-05-26T22:35", zone: "Europe/Madrid", matchMinute: 93, matchMinuteLabel: "90+3")
        let at = Fixtures.date(2026, 11, 20, 14, 33, in: london)
        #expect(pick([solskjaer], at: at) == nil)
        let card = pick([solskjaer], at: at, settings: ClockSettings(showsMatchMinuteFill: true))
        #expect(card?.kind == .fill)
        #expect(card?.time == "14:33")
        #expect(card?.label == "Minute 90+3 · match clock, not time of day")
    }

    @Test func fillOnlyWhenNothingElseMatches() {
        let solskjaer = Fixtures.moment("M0054", at: "1999-05-26T22:35", zone: "Europe/Madrid", fame: 1, matchMinute: 93)
        let harvested = Fixtures.moment("M0700", at: "2004-01-01T14:33", fame: 3)
        let card = pick([solskjaer, harvested], at: Fixtures.date(2026, 11, 20, 14, 33, in: london),
                        settings: ClockSettings(showsMatchMinuteFill: true))
        #expect(card?.moment.id == "M0700")
    }

    // Rule 6: keep the previous card, and walk back on launch.
    @Test func keepsThePreviousCardWhenNothingMatches() throws {
        let picker = MomentPicker(store: MomentStore(moments: [Fixtures.moment("M0001", at: "2000-01-01T12:00")]))
        let noon = Fixtures.date(2026, 11, 20, 12, 0, in: london)
        let previous = try #require(picker.card(at: noon, calendar: london, settings: defaults))
        let later = noon.addingTimeInterval(37 * 60)
        #expect(picker.card(at: later, calendar: london, settings: defaults) == nil)
        #expect(picker.resolve(at: later, calendar: london, settings: defaults, previous: previous) == previous)
    }

    @Test func walksBackOnLaunch() {
        let picker = MomentPicker(store: MomentStore(moments: [Fixtures.moment("M0001", at: "2000-01-01T23:50")]))
        // Just after midnight, with no previous card: the walk back crosses into yesterday.
        let card = picker.resolve(at: Fixtures.date(2026, 11, 20, 0, 20, in: london), calendar: london, settings: defaults, previous: nil)
        #expect(card?.moment.id == "M0001")
        #expect(card?.time == "23:50")
    }

    @Test func nothingAtAllGivesNoCard() {
        let picker = MomentPicker(store: MomentStore(moments: [Fixtures.moment("M0001", at: "2000-01-01T23:50")]))
        let allOff = ClockSettings(showsRealTime: false, showsRecords: false, showsMatchMinuteFill: false)
        #expect(picker.resolve(at: .now, calendar: london, settings: allOff, previous: nil) == nil)
    }

    // Midnight: the date on the card is the real local date.
    @Test func midnightRolloverShowsTheRealLocalDate() {
        let istanbul = Fixtures.moment("M0069", at: "2005-05-26T00:30", zone: "Europe/Istanbul", place: "Atatürk Olympic Stadium, Istanbul")
        let venueCard = pick([istanbul], at: Fixtures.date(2026, 11, 20, 0, 30, in: london))
        #expect(venueCard?.detail == "26 May 2005 · Atatürk Olympic Stadium, Istanbul · venue time")
        // In London it was still 25 May, 22:30.
        let viewerCard = pick([istanbul], at: Fixtures.date(2026, 11, 20, 22, 30, in: london), settings: ClockSettings(timeMode: .viewer))
        #expect(viewerCard?.detail == "25 May 2005 · Atatürk Olympic Stadium, Istanbul")
        #expect(viewerCard?.venueTimeNote == "00:30 in Istanbul")
    }

    // Photos.
    @Test func missingPhotoFileMeansTypeOnly() {
        let withImage = Fixtures.moment("M0001", at: "2000-01-01T12:00", image: MomentImage(file: "not-bundled.jpg", credit: "Photo: Someone · CC BY 2.0 · Wikimedia Commons"))
        #expect(pick([withImage], at: Fixtures.date(2026, 11, 20, 12, 0, in: london))?.photo == nil)
    }

    @Test func typeOnlySettingDropsPhotos() throws {
        let store = Fixtures.bundledStore
        guard let withPhoto = store.moments.first(where: { store.imageURL(for: $0) != nil && $0.venueLocal != nil }) else { return }
        let picker = MomentPicker(store: MomentStore(moments: [withPhoto], imagesDirectory: store.imageURL(for: withPhoto)?.deletingLastPathComponent()))
        let local = try #require(withPhoto.venueLocal)
        let at = Fixtures.date(2026, 11, 20, local.hour, local.minute, in: london)
        #expect(picker.card(at: at, calendar: london, settings: defaults)?.photo != nil)
        #expect(picker.card(at: at, calendar: london, settings: ClockSettings(photos: .typeOnly))?.photo == nil)
    }

    @Test func captionsGetTypographicQuotes() {
        #expect(Card.typeset("\"And Solskjaer has won it\"") == "\u{201C}And Solskjaer has won it\u{201D}")
        #expect(Card.typeset("Perry's late winner") == "Perry\u{2019}s late winner")
    }
}

@Suite("Model")
struct ModelTests {
    @Test func decodesTheSpecExample() throws {
        let json = """
        {"version":1,"generated":"2026-11-20T00:00:00Z","moments":[{"id":"M0054","sport":"Football",
        "caption":"\\"And Solskjaer has won it\\"","instantUTC":"1999-05-26T20:35:00Z","venueTZ":"Europe/Madrid",
        "venueLocal":"1999-05-26T22:35","place":"Camp Nou, Barcelona","basis":"derived","plusMinusMin":4,"checked":false,
        "recordDigits":null,"recordMark":null,"recordEvent":null,"matchMinute":93,"matchMinuteLabel":"90+3","fame":1,
        "fameSub":0,"sourceURL":"https://en.wikipedia.org/wiki/1999_UEFA_Champions_League_final",
        "image":{"file":"M0054.jpg","credit":"Photo: Author Name · CC BY-SA 2.0 · Wikimedia Commons"}}]}
        """
        let moment = try #require(MomentsFile.decode(Data(json.utf8)).moments.first)
        #expect(moment.venueLocal == LocalDateTime("1999-05-26T22:35"))
        #expect(moment.instantUTC == Fixtures.instant("1999-05-26T20:35:00Z"))
        #expect(moment.basis == .derived)
        #expect(moment.image?.file == "M0054.jpg")
        #expect(moment.date == nil && moment.recordLabel == nil)
    }

    @Test func decodesARecordWithNullDateAndPlace() throws {
        let json = """
        {"version":1,"moments":[{"id":"X001","sport":"Cricket","caption":"Lara makes 400 not out","date":null,
        "instantUTC":null,"venueTZ":null,"venueLocal":null,"place":null,"basis":null,"plusMinusMin":null,"checked":false,
        "recordDigits":"04:00","recordMark":"400*","recordEvent":null,"recordLabel":"Test record","matchMinute":null,
        "matchMinuteLabel":null,"fame":4,"fameSub":1,"sourceURL":null,"image":null}]}
        """
        let file = try MomentsFile.decode(Data(json.utf8))
        #expect(file.skipped.isEmpty)
        let moment = try #require(file.moments.first)
        #expect(moment.sport == "Cricket" && moment.date == nil && moment.place == nil && moment.venueDate == nil)
        #expect(moment.recordMinuteOfDay == 240)
    }

    /// One bad entry from the pipeline costs that entry, not the whole file.
    @Test func skipsUnreadableEntriesAndKeepsTheRest() throws {
        let json = """
        {"version":1,"moments":[
          {"id":"M0001","sport":"Football","caption":"Fine","fame":1},
          {"id":"M0002","sport":"Football","caption":"Year only date","fame":1,"date":"1976"},
          {"id":"M0003","caption":"No sport","fame":1},
          null,
          42,
          {"id":"M0004","sport":"Tennis","caption":"Also fine","fame":1,"date":"2010-06-24"}
        ]}
        """
        let file = try MomentsFile.decode(Data(json.utf8))
        #expect(file.moments.map(\.id) == ["M0001", "M0004"])
        #expect(file.skipped.count == 4)
        #expect(file.skipped.first?.hasPrefix("M0002: date") == true)
        #expect(file.skipped[1].hasPrefix("M0003: no sport"))
    }

    @Test func settingsRoundTripThroughDefaults() throws {
        let suite = try TemporaryDefaults()
        let defaults = suite.defaults
        #expect(ClockSettings(defaults: defaults) == ClockSettings())
        let custom = ClockSettings(timeMode: .viewer, showsRealTime: false, showsRecords: true, showsMatchMinuteFill: true, photos: .typeOnly)
        custom.save(to: defaults)
        #expect(ClockSettings(defaults: defaults) == custom)
    }

    @Test func cityComesFromPlaceOrZone() {
        #expect(Card.city(of: Fixtures.moment("A", at: "2000-01-01T12:00", zone: "Europe/Vienna", place: "Prater, Vienna")) == "Vienna")
        #expect(Card.city(of: Fixtures.moment("B", at: "2000-01-01T12:00", zone: "America/New_York", place: nil)) == "New York")
    }
}
