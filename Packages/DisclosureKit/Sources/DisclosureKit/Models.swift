import Foundation

public enum Chamber: String, Codable, Sendable {
    case house, senate
    public var label: String { self == .house ? "House" : "Senate" }
}

public enum TradeOwner: String, Codable, Sendable, CaseIterable {
    case `self`, spouse, joint, dependent

    /// Shown in body weight, not as a muted chip — who traded is part of the fact.
    public var label: String {
        switch self {
        case .self: return "Member"
        case .spouse: return "Spouse"
        case .joint: return "Joint"
        case .dependent: return "Dependent"
        }
    }
}

public enum TradeType: String, Codable, Sendable, CaseIterable {
    case buy, sell
    case partialSell = "partial_sell"
    case exchange

    /// Direction is stated in words. Buying is not a gain and selling is not a loss,
    /// so this never carries green/red semantics.
    public var verb: String {
        switch self {
        case .buy: return "Bought"
        case .sell: return "Sold"
        case .partialSell: return "Sold (partial)"
        case .exchange: return "Exchanged"
        }
    }

    public var isAcquisition: Bool { self == .buy }
}

/// One transaction line item from a Periodic Transaction Report.
public struct Trade: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Bioguide ID when it could be resolved, otherwise a name-and-seat fallback slug.
    public let memberID: String
    public let memberName: String
    public let owner: TradeOwner
    public let asset: String
    public let ticker: String?
    /// House asset-type code: ST, OP, MF, EF, GS, and so on.
    public let assetType: String?
    public let txType: TradeType
    public let txDate: CalendarDate
    public let disclosedDate: CalendarDate
    public let amount: DisclosedAmount
    public let filingDescription: String?
    public let filingID: String
    public let documentURL: URL?
    /// Anything the parser was unsure about. Carried through rather than discarded.
    public let warnings: [String]

    public init(
        id: String, memberID: String, memberName: String, owner: TradeOwner,
        asset: String, ticker: String?, assetType: String?, txType: TradeType,
        txDate: CalendarDate, disclosedDate: CalendarDate, amount: DisclosedAmount,
        filingDescription: String?, filingID: String, documentURL: URL?,
        warnings: [String] = []
    ) {
        self.id = id
        self.memberID = memberID
        self.memberName = memberName
        self.owner = owner
        self.asset = asset
        self.ticker = ticker
        self.assetType = assetType
        self.txType = txType
        self.txDate = txDate
        self.disclosedDate = disclosedDate
        self.amount = amount
        self.filingDescription = filingDescription
        self.filingID = filingID
        self.documentURL = documentURL
        self.warnings = warnings
    }

    /// Days between trading and disclosing. The STOCK Act allows 45.
    public var disclosureLagDays: Int { txDate.days(to: disclosedDate) }

    /// A transaction dated after its own filing is a mistyped form, not a real event.
    public var hasImpossibleDate: Bool { txDate > disclosedDate }

    public var isLateFiling: Bool { !hasImpossibleDate && disclosureLagDays > 45 }

    public var isOption: Bool { assetType == "OP" }

    /// Sorting key. A mistyped transaction year would otherwise pin one row to the top
    /// of every list, so those fall back to the date the filing was made.
    public var sortDate: CalendarDate { hasImpossibleDate ? disclosedDate : txDate }

    public var displaySymbol: String { ticker ?? String(cleanAssetName.prefix(18)) }

    /// The asset name with the trailing "(TICK) [ST]" bookkeeping removed.
    public var cleanAssetName: String {
        asset
            .replacingOccurrences(of: #"\s*\([A-Z][A-Z0-9.\-]{0,6}\)\s*\[[A-Z]{2,4}\]\s*$"#,
                                  with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[[A-Z]{2,4}\]\s*$"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The honesty mechanic: the gap, stated in words.
    public var disclosureGapPhrase: String {
        if hasImpossibleDate { return "filing dates are inconsistent" }
        let d = disclosureLagDays
        switch d {
        case ..<0: return "disclosed before the trade date"
        case 0: return "disclosed the same day"
        case 1: return "disclosed 1 day later"
        default: return "disclosed \(d) days later"
        }
    }
}

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let bioguideID: String?
    public let name: String
    public let state: String
    public let district: String?
    public let chamber: Chamber

    public init(
        id: String, bioguideID: String?, name: String,
        state: String, district: String?, chamber: Chamber
    ) {
        self.id = id
        self.bioguideID = bioguideID
        self.name = name
        self.state = state
        self.district = district
        self.chamber = chamber
    }

    public var seat: String {
        if let d = district, !d.isEmpty { return "\(state)-\(d)" }
        return state
    }
}

/// Counts that would otherwise be swallowed. Filings that yield nothing are listed by
/// ID so a regression shows up as a number going the wrong way, not as missing data.
public struct ParseStats: Codable, Sendable, Hashable {
    public var filingsProcessed: Int
    public var tradesParsed: Int
    /// Readable text, but no transaction rows recognised. These are parser failures.
    public var filingsYieldingNoTrades: [String]
    /// No extractable text at all — scanned paper. Not a parser failure.
    public var filingsWithoutText: [String]
    /// Download or read errors.
    public var filingsFailedToFetch: [String]

    public init(
        filingsProcessed: Int = 0, tradesParsed: Int = 0,
        filingsYieldingNoTrades: [String] = [], filingsWithoutText: [String] = [],
        filingsFailedToFetch: [String] = []
    ) {
        self.filingsProcessed = filingsProcessed
        self.tradesParsed = tradesParsed
        self.filingsYieldingNoTrades = filingsYieldingNoTrades
        self.filingsWithoutText = filingsWithoutText
        self.filingsFailedToFetch = filingsFailedToFetch
    }

    public var coverageNote: String {
        let unreadable = filingsWithoutText.count
        guard filingsProcessed > 0 else { return "No filings processed." }
        let pct = Int((Double(unreadable) / Double(filingsProcessed) * 100).rounded())
        return "\(filingsProcessed) filings read, \(unreadable) were scanned paper with no readable text (\(pct)%)."
    }
}

public struct TradeFeed: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    /// Filing years covered, so an incremental refresh knows what it already has.
    public let indexYears: [Int]
    public let source: String
    public let chambersCovered: [Chamber]
    public let members: [Member]
    public let trades: [Trade]
    public let stats: ParseStats
    /// Lets on-device parsing resolve a filer to the same ID the seed used.
    public let nameToMemberID: [String: String]

    public init(
        schemaVersion: Int = TradeFeed.currentSchemaVersion,
        generatedAt: Date, indexYears: [Int], source: String,
        chambersCovered: [Chamber] = [.house],
        members: [Member], trades: [Trade], stats: ParseStats,
        nameToMemberID: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.indexYears = indexYears
        self.source = source
        self.chambersCovered = chambersCovered
        self.members = members
        self.trades = trades
        self.stats = stats
        self.nameToMemberID = nameToMemberID
    }

    public static let empty = TradeFeed(
        generatedAt: .distantPast, indexYears: [], source: "",
        members: [], trades: [], stats: ParseStats()
    )

    public static func makeCoder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (e, d)
    }
}
