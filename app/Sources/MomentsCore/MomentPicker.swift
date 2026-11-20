import Foundation

/// Chooses the moment for a minute, following the picker rules in SPEC.md.
///
/// Pure: the result depends only on the arguments. The calendar's time zone is the
/// viewer's zone, so tests can drive any date, zone and setting without touching the system.
public struct MomentPicker: Sendable {
    public let store: MomentStore

    public init(store: MomentStore) {
        self.store = store
    }

    /// Rules 1 to 5. Nil when nothing matches this minute.
    public func card(at date: Date, calendar: Calendar, settings: ClockSettings) -> Card? {
        let clock = calendar.dateComponents([.hour, .minute, .month, .day], from: date)
        let minuteOfDay = clock.hour! * 60 + clock.minute!

        var candidates = timeCandidates(minuteOfDay: minuteOfDay, zone: calendar.timeZone, settings: settings)
        if candidates.isEmpty, settings.showsMatchMinuteFill {
            candidates = (store.fillIndex[minuteOfDay % 60] ?? []).map { Candidate(moment: $0, kind: .fill, fame: $0.fame) }
        }
        guard !candidates.isEmpty else { return nil }

        let today = Today(
            month: clock.month!, day: clock.day!,
            dayOfYear: calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        )
        guard let winner = Self.best(of: candidates, today: today) else { return nil }

        let wantsPhoto = settings.photos == .whenAvailable
        return Card(
            moment: winner.moment, kind: winner.kind, minuteOfDay: minuteOfDay, mode: settings.timeMode,
            viewerZone: calendar.timeZone, photoURL: wantsPhoto ? store.imageURL(for: winner.moment) : nil
        )
    }

    /// Rule 6: the card for this minute, else the previous card, else (on launch) the
    /// first hit walking back minute by minute for up to a day.
    public func resolve(at date: Date, calendar: Calendar, settings: ClockSettings, previous: Card?) -> Card? {
        if let card = card(at: date, calendar: calendar, settings: settings) { return card }
        if let previous { return previous }
        for minutesBack in 1...1440 {
            let earlier = date.addingTimeInterval(TimeInterval(-60 * minutesBack))
            if let card = card(at: earlier, calendar: calendar, settings: settings) { return card }
        }
        return nil
    }

    /// For each of the 1,440 minutes of the day, whether any moment matches it.
    /// Ranking does not affect coverage, so no date is needed.
    public func coverage(zone: TimeZone, settings: ClockSettings) -> [Bool] {
        (0..<1440).map { minute in
            !timeCandidates(minuteOfDay: minute, zone: zone, settings: settings).isEmpty
                || (settings.showsMatchMinuteFill && store.fillIndex[minute % 60]?.isEmpty == false)
        }
    }

    // MARK: - Rules

    struct Candidate {
        let moment: Moment
        let kind: Card.Kind
        let fame: Int
    }

    struct Today {
        let month: Int
        let day: Int
        let dayOfYear: Int
    }

    /// Rules 2 and 3: real time and record candidates, at most one per moment.
    func timeCandidates(minuteOfDay: Int, zone: TimeZone, settings: ClockSettings) -> [Candidate] {
        var candidates: [Candidate] = []
        if settings.showsRealTime {
            let index = settings.timeMode == .venue ? store.venueIndex : store.viewerIndex(for: zone)
            candidates += (index[minuteOfDay] ?? []).map { Candidate(moment: $0, kind: .realTime, fame: $0.fame) }
        }
        if settings.showsRecords {
            candidates += (store.recordIndex[minuteOfDay] ?? []).compactMap { moment in
                // A moment that already matches in real time keeps that (more specific) card.
                guard !candidates.contains(where: { $0.moment.id == moment.id }) else { return nil }
                return Candidate(moment: moment, kind: .record, fame: moment.fame == 4 ? 4 : 2)
            }
        }
        return candidates
    }

    /// Rule 4: lower fame, then today's anniversary, then lower fameSub,
    /// then a daily rotation through whatever is still tied, sorted by id.
    static func best(of candidates: [Candidate], today: Today) -> Candidate? {
        func key(_ c: Candidate) -> (Int, Int, Int) {
            let date = c.moment.venueDate
            let isAnniversary = date?.month == today.month && date?.day == today.day
            return (c.fame, isAnniversary ? 0 : 1, c.moment.fameSub ?? 0)
        }
        guard let top = candidates.map(key).min(by: <) else { return nil }
        let tied = candidates.filter { key($0) == top }.sorted { $0.moment.id < $1.moment.id }
        return tied[today.dayOfYear % tied.count]
    }
}
