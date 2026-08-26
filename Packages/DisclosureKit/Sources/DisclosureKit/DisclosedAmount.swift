import Foundation

/// The value column of a disclosure, which is almost never a single number.
///
/// The old model stored `low`/`high` and treated `high == low` as "upper bound still
/// missing". Three genuinely different things satisfy that condition — an open-ended top
/// bracket, an exact cash amount, and a range whose upper bound hasn't been read yet — so
/// an unrelated dollar figure from a later line could be welded onto a completed row.
/// Making the kind explicit means the parser has to say which one it means.
public struct DisclosedAmount: Codable, Hashable, Sendable {

    public enum Kind: String, Codable, Sendable {
        /// A normal bracket, e.g. `$1,001 - $15,000`.
        case range
        /// The open-ended top bracket, e.g. `$50,000,001 +`.
        case atLeast
        /// An exact figure, which the form occasionally carries for cash in lieu.
        case exact
        /// The literal `None (or less than $201)` option.
        case none
        /// Present but unreadable. Never silently treated as zero.
        case unknown
    }

    public let kind: Kind
    /// Stored in cents so an exact `$15.00` needs no separate representation.
    public let lowCents: Int
    /// Equals `lowCents` for every kind except `.range`.
    public let highCents: Int
    /// Exactly what the form said, for display and for audit.
    public let label: String

    public init(kind: Kind, lowCents: Int, highCents: Int, label: String) {
        self.kind = kind
        self.lowCents = lowCents
        self.highCents = highCents
        self.label = label
    }

    public static let noneDisclosed = DisclosedAmount(
        kind: .none, lowCents: 0, highCents: 0, label: "None (or less than $201)"
    )

    public static func unknown(_ raw: String) -> DisclosedAmount {
        DisclosedAmount(kind: .unknown, lowCents: 0, highCents: 0, label: raw)
    }

    /// True only when there are two genuinely different endpoints to draw.
    public var isRange: Bool { kind == .range && highCents > lowCents }

    /// Used for ordering by size. For a range this is the midpoint, which is an estimate
    /// and is never presented to the user as though it were a disclosed figure.
    public var sortMagnitudeCents: Int {
        isRange ? (lowCents + highCents) / 2 : lowCents
    }

    // MARK: - Formatting

    private static let dollars: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    public static func formatDollars(cents: Int) -> String {
        let whole = cents / 100
        let base = dollars.string(from: NSNumber(value: whole)) ?? "\(whole)"
        let remainder = cents % 100
        return remainder == 0 ? "$\(base)" : String(format: "$%@.%02d", base, remainder)
    }

    public var lowLabel: String { Self.formatDollars(cents: lowCents) }
    public var highLabel: String { Self.formatDollars(cents: highCents) }

    /// Builds the canonical label for a kind, matching how the form prints it.
    public static func makeLabel(kind: Kind, lowCents: Int, highCents: Int) -> String {
        switch kind {
        case .range: return "\(formatDollars(cents: lowCents)) – \(formatDollars(cents: highCents))"
        case .atLeast: return "\(formatDollars(cents: lowCents))+"
        case .exact: return formatDollars(cents: lowCents)
        case .none: return "None (or less than $201)"
        case .unknown: return "Amount unreadable"
        }
    }
}
