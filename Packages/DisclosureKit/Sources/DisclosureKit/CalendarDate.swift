import Foundation

/// A date with no time and no time zone — which is all a disclosure form actually states.
///
/// Filings print `MM/DD/YYYY` and nothing more. Modelling that as a `Date` forces an
/// arbitrary instant, and any mismatch between the parsing and formatting time zones
/// shifts the displayed day. Keeping the calendar fields makes that class of bug
/// unrepresentable.
public struct CalendarDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`.
    public init?(iso: String) {
        let p = iso.split(separator: "-")
        guard p.count == 3,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Parses `MM/DD/YYYY` as printed on the House form. Scanned filings sometimes carry
    /// a two-digit year (`01/10/25`), which is read as 20xx.
    public init?(formStyle: String) {
        let p = formStyle.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard p.count == 3,
              let m = Int(p[0]), let d = Int(p[1]), var y = Int(p[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        if y < 100 { y += 2000 }
        guard y > 1900, y < 2200 else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    public static func < (a: CalendarDate, b: CalendarDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Midnight in the given calendar, for formatting only.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// Whole days from this date to `other`, negative if `other` is earlier.
    public func days(to other: CalendarDate, in calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(in: calendar), to: other.date(in: calendar)).day ?? 0
    }

    public static func today(in calendar: Calendar = .current) -> CalendarDate {
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return CalendarDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    // Encoded as the plain ISO string so the feed stays readable and diffable.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = CalendarDate(iso: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "bad date \(raw)")
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}
