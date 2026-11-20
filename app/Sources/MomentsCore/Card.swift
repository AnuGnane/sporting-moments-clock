import Foundation

/// Everything the card view needs to draw one moment. Built by `MomentPicker`.
public struct Card: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable {
        /// Shown at the clock time it happened.
        case realTime
        /// A record whose mark reads as the clock time.
        case record
        /// Match minute fill: a match minute equal to the minute of the hour.
        case fill
    }

    public struct Photo: Equatable, Sendable {
        public let url: URL
        public let credit: String
    }

    public let moment: Moment
    public let kind: Kind
    /// The viewer's clock minute this card was picked for, "22:35". The big figure on screen is
    /// always the current time; this one appears in the accent line once a kept card is older.
    public let time: String
    /// Accent label above the time, in sentence case ("Exactly · your time"). The view sets it in capitals.
    public let label: String
    /// Viewer mode only: the venue's wall clock beside the big time, "00:30 in Istanbul".
    public let venueTimeNote: String?
    public let caption: String
    /// "26 May 1999 · Camp Nou, Barcelona · venue time".
    public let detail: String
    /// Nil for type only cards.
    public let photo: Photo?

    public var id: String { "\(moment.id) \(kind) \(time)" }
}

extension Card {
    static let separator = " · "

    init(moment: Moment, kind: Kind, minuteOfDay: Int, mode: ClockSettings.TimeMode,
         viewerZone: TimeZone, photoURL: URL?) {
        self.moment = moment
        self.kind = kind
        self.time = LocalDateTime.timeText(minuteOfDay: minuteOfDay)
        self.caption = Self.typeset(moment.caption)
        if let photoURL, let credit = moment.image?.credit, !credit.isEmpty {
            self.photo = Photo(url: photoURL, credit: credit)
        } else {
            self.photo = nil
        }

        switch kind {
        case .realTime:
            let precision = moment.basis == .documented ? "Exactly" : "Around"
            switch mode {
            case .venue:
                label = precision
                venueTimeNote = nil
                detail = Self.join([moment.venueDate?.formatted, moment.place, "venue time"])
            case .viewer:
                label = precision + Self.separator + "your time"
                let viewerDate = moment.instantUTC.map { LocalDateTime(instant: $0, in: viewerZone).date }
                detail = Self.join([(viewerDate ?? moment.venueDate)?.formatted, moment.place])
                if let local = moment.venueLocal, local.timeText != time {
                    venueTimeNote = "\(local.timeText) in \(Self.city(of: moment))"
                } else {
                    venueTimeNote = nil
                }
            }
        case .record:
            let name = moment.recordLabel ?? "World record"
            label = moment.recordMark.map { mark in
                name + Self.separator + (Self.isMeasuredMark(mark) ? "the mark reads \(mark)" : "the number reads \(mark)")
            } ?? name
            venueTimeNote = nil
            detail = Self.join([moment.recordEvent, moment.venueDate?.formatted, moment.place])
        case .fill:
            let minute = moment.matchMinuteLabel ?? moment.matchMinute.map(String.init) ?? ""
            label = "Minute \(minute)" + Self.separator + "match clock, not time of day"
            venueTimeNote = nil
            detail = Self.join([moment.venueDate?.formatted, moment.place])
        }
    }

    /// The accent line above the big clock, which always shows `clock` (the current or demo time).
    /// Nil means no accent line.
    ///
    /// A real time moment names its own time only when that differs from the clock, as on a
    /// card kept from an earlier minute: "Around 16:03", "At 16:47" (documented), or
    /// "Around 13:44 your time · 10:14 in Vienna". When they match there is nothing to add,
    /// except in viewer mode the venue's own time: "10:14 in Vienna".
    /// Record and fill cards always show their label.
    public func headline(clock: String) -> String? {
        guard kind == .realTime else { return label }
        guard clock != time else { return venueTimeNote }
        var text = (moment.basis == .documented ? "At " : "Around ") + time
        if label.hasSuffix("your time") { text += " your time" }
        if let venueTimeNote { text += Self.separator + venueTimeNote }
        return text
    }

    /// A time or a measurement ("9.58", "2.43", "1:59:40") is a mark. Counts and scores
    /// ("3", "755", "2,105", ".406", "501*", "952/6") are numbers.
    static func isMeasuredMark(_ mark: String) -> Bool {
        mark.contains(":") || mark.wholeMatch(of: /\d+\.\d+.*/) != nil
    }

    /// Whether the caption is a quotation, which the card sets in italic.
    public var isQuotation: Bool {
        caption.first == "\u{201C}"
    }

    /// Straight quotes to typographic ones: "And Solskjaer has won it" becomes “And Solskjaer has won it”.
    public static func typeset(_ text: String) -> String {
        var result = ""
        var previous: Character?
        for character in text {
            let opens = previous == nil || previous!.isWhitespace || "([".contains(previous!)
            switch character {
            case "\"": result.append(opens ? "\u{201C}" : "\u{201D}")
            case "'": result.append(opens ? "\u{2018}" : "\u{2019}")
            default: result.append(character)
            }
            previous = character
        }
        return result
    }

    /// The city for "10:14 in Vienna": the last part of `place`, else the zone name.
    static func city(of moment: Moment) -> String {
        if let place = moment.place, let last = place.split(separator: ",").last {
            let city = last.trimmingCharacters(in: .whitespaces)
            if !city.isEmpty { return city }
        }
        let zoneCity = moment.venueTZ?.split(separator: "/").last.map(String.init) ?? ""
        return zoneCity.replacingOccurrences(of: "_", with: " ")
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: separator)
    }
}
