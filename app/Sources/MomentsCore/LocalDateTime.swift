import Foundation

/// A calendar date with no time zone, coded as "yyyy-MM-dd".
public struct LocalDate: Codable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalDate(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected yyyy-MM-dd, got \(text)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }

    /// "26 May 1999". Captions are English, so the date is too.
    public var formatted: String {
        "\(day) \(Self.monthNames[month - 1]) \(year)"
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}

/// A wall clock date and time with no time zone, coded as "yyyy-MM-ddTHH:mm".
public struct LocalDateTime: Codable, Hashable, Sendable {
    public var date: LocalDate
    public var hour: Int
    public var minute: Int

    public init(date: LocalDate, hour: Int, minute: Int) {
        self.date = date
        self.hour = hour
        self.minute = minute
    }

    public init?(_ text: String) {
        let halves = text.split(separator: "T")
        guard halves.count == 2,
              let date = LocalDate(String(halves[0])),
              let minuteOfDay = Self.minuteOfDay(parsing: String(halves[1].prefix(5)))
        else { return nil }
        self.init(date: date, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
    }

    /// The wall clock reading of `instant` in `zone`, using the offset in force at that instant.
    public init(instant: Date, in zone: TimeZone) {
        self.init(instant: instant, calendar: .gregorian(in: zone))
    }

    /// The wall clock reading of `instant` in `calendar`'s time zone. For loops: one calendar for many instants.
    init(instant: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        self.init(date: LocalDate(year: c.year!, month: c.month!, day: c.day!), hour: c.hour!, minute: c.minute!)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalDateTime(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected yyyy-MM-ddTHH:mm, got \(text)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02dT%02d:%02d", date.year, date.month, date.day, hour, minute))
    }

    public var minuteOfDay: Int { hour * 60 + minute }

    /// "22:35".
    public var timeText: String { Self.timeText(minuteOfDay: minuteOfDay) }

    /// Parses "HH:mm" into a minute of the day, 0 to 1439.
    public static func minuteOfDay(parsing text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// "HH:mm", 24 hour.
    public static func timeText(minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}

extension Calendar {
    /// A Gregorian calendar in `zone`, independent of the user's own calendar settings.
    static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
