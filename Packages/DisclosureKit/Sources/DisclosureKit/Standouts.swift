import Foundation

/// Factual superlatives over one loaded snapshot.
///
/// Every function here answers a single, mechanical question about the trades already in
/// `feed` — "which are in the form's top brackets", "which were filed latest", "which
/// tickers appear in the most members' filings". Nothing is scored, weighted against
/// another category, or merged into one ranked list. Each rule returns its own short list,
/// ordered only by the fact that put a row on it.
///
/// The reader's watchlist and followed-members list take no part. These functions read
/// only `TradeFeed`; the same standouts appear for every reader.
public struct Standout: Identifiable, Sendable, Hashable {

    public enum Category: String, Sendable, CaseIterable {
        case topBracket, filedLate, newPosition, offPattern, rareTrader, memberLargest
    }

    public let category: Category
    public let trade: Trade
    /// The plain-language tag naming the fact that surfaced this row, e.g.
    /// "Filed 112 days late".
    public let reason: String

    public var id: String { "\(category.rawValue)-\(trade.id)" }

    public init(category: Category, trade: Trade, reason: String) {
        self.category = category
        self.trade = trade
        self.reason = reason
    }
}

/// A ticker paired with how many distinct members disclosed a trade in it this snapshot,
/// and how many disclosed trades that is in total. A count of filers — never of shares or
/// dollars, which the form does not state.
public struct WidelyHeldTicker: Identifiable, Sendable, Hashable {
    public let ticker: String
    public let memberCount: Int
    public let tradeCount: Int
    public var id: String { ticker }

    public init(ticker: String, memberCount: Int, tradeCount: Int) {
        self.ticker = ticker
        self.memberCount = memberCount
        self.tradeCount = tradeCount
    }
}

public enum Standouts {

    // MARK: - Public entry points

    /// Every category's list, keyed by category. A category with no qualifying row is
    /// omitted. Deterministic: the same feed yields an equal dictionary every call.
    public static func byCategory(in feed: TradeFeed) -> [Standout.Category: [Standout]] {
        var out: [Standout.Category: [Standout]] = [:]
        let lists: [(Standout.Category, [Standout])] = [
            (.topBracket, topBracket(in: feed)),
            (.filedLate, filedLate(in: feed)),
            (.newPosition, newPosition(in: feed)),
            (.offPattern, offPattern(in: feed)),
            (.rareTrader, rareTrader(in: feed)),
            (.memberLargest, memberLargest(in: feed)),
        ]
        for (category, list) in lists where !list.isEmpty {
            out[category] = list
        }
        return out
    }

    // MARK: - Rule 1 · topBracket

    /// Trades whose disclosed floor is at least $5,000,000 — the top of the form's own
    /// bracket scale. Ranked by that floor, so a genuine `$50,000,001+` or
    /// `$25,000,001 – $50,000,000` leads and the reduced `Spouse/DC Over $1,000,000`
    /// standard (floor $1M — the form asks for nothing more precise) never appears here.
    /// The bracket is the only figure the form states, so it is the only figure shown.
    public static func topBracket(in feed: TradeFeed) -> [Standout] {
        feed.trades
            .filter { $0.amount.lowCents >= 500_000_000 }
            .sorted(by: bracketOrder)
            .map { Standout(category: .topBracket, trade: $0, reason: $0.amount.label) }
    }

    /// Larger disclosed floor first; at an equal floor the open-ended bracket (no stated
    /// ceiling) ranks above a bounded range; then most recently disclosed, then id.
    private static func bracketOrder(_ a: Trade, _ b: Trade) -> Bool {
        if a.amount.lowCents != b.amount.lowCents { return a.amount.lowCents > b.amount.lowCents }
        let aOpen = a.amount.kind == .atLeast
        let bOpen = b.amount.kind == .atLeast
        if aOpen != bOpen { return aOpen }
        if a.disclosedDate != b.disclosedDate { return a.disclosedDate > b.disclosedDate }
        return a.id < b.id
    }

    // MARK: - Rule 2 · filedLate

    /// Trades disclosed more than 45 days after the transaction — the STOCK Act's limit —
    /// excluding rows whose dates are internally inconsistent (a lag that is not a real
    /// number). Longest gap first.
    public static func filedLate(in feed: TradeFeed) -> [Standout] {
        // `disclosureLagDays` goes through `Calendar`, so it is read once per row here
        // rather than once per sort comparison.
        feed.trades
            .compactMap { t -> (trade: Trade, lag: Int)? in
                guard !t.hasImpossibleDate else { return nil }
                let lag = t.disclosureLagDays
                return lag > 45 ? (t, lag) : nil
            }
            .sorted { a, b in
                if a.lag != b.lag { return a.lag > b.lag }
                if a.trade.disclosedDate != b.trade.disclosedDate {
                    return a.trade.disclosedDate > b.trade.disclosedDate
                }
                return a.trade.id < b.trade.id
            }
            .map {
                Standout(category: .filedLate, trade: $0.trade,
                         reason: "Filed \($0.lag) days late")
            }
    }

    // MARK: - Rule 3 · widelyHeldTickers

    /// Tickers that appear in at least three distinct members' filings this snapshot,
    /// most members first. A count of filers, not of shares or dollars.
    public static func widelyHeldTickers(in feed: TradeFeed) -> [WidelyHeldTicker] {
        var members: [String: Set<String>] = [:]
        var trades: [String: Int] = [:]
        for t in feed.trades {
            guard let raw = t.ticker else { continue }
            let key = raw.uppercased()
            members[key, default: []].insert(t.memberID)
            trades[key, default: 0] += 1
        }
        return members
            .compactMap { key, memberIDs -> WidelyHeldTicker? in
                guard memberIDs.count >= 3 else { return nil }
                return WidelyHeldTicker(
                    ticker: key, memberCount: memberIDs.count, tradeCount: trades[key] ?? 0
                )
            }
            .sorted { a, b in
                a.memberCount != b.memberCount ? a.memberCount > b.memberCount : a.ticker < b.ticker
            }
    }

    // MARK: - Rule 4 · newPosition

    /// A member's first disclosed trade in a ticker — the earliest by transaction date
    /// across the whole feed — when that first trade was disclosed in the last 30 days of
    /// the snapshot and the member has disclosed at least two trades in total.
    public static func newPosition(in feed: TradeFeed) -> [Standout] {
        guard let anchor = feed.trades.map(\.disclosedDate).max() else { return [] }

        let tradesByMember = Dictionary(grouping: feed.trades, by: \.memberID)

        // Earliest trade per (member, ticker).
        var groups: [String: [Trade]] = [:]
        for t in feed.trades {
            guard let raw = t.ticker else { continue }
            groups["\(t.memberID)\u{1F}\(raw.uppercased())", default: []].append(t)
        }

        var out: [Standout] = []
        for (_, rows) in groups {
            guard let earliest = rows.min(by: firstTradeOrder) else { continue }
            guard earliest.disclosedDate.days(to: anchor) <= 30,
                  earliest.disclosedDate <= anchor else { continue }
            guard (tradesByMember[earliest.memberID]?.count ?? 0) >= 2 else { continue }
            let symbol = earliest.ticker?.uppercased() ?? ""
            out.append(Standout(
                category: .newPosition, trade: earliest,
                reason: "First disclosed \(symbol) trade by this member"
            ))
        }
        return out.sorted(by: recencyThenID)
    }

    /// Earliest by transaction date, then earliest disclosed, then id.
    private static func firstTradeOrder(_ a: Trade, _ b: Trade) -> Bool {
        if a.txDate != b.txDate { return a.txDate < b.txDate }
        if a.disclosedDate != b.disclosedDate { return a.disclosedDate < b.disclosedDate }
        return a.id < b.id
    }

    // MARK: - Rule 5 · offPattern

    /// A single-stock (or option) trade by a member whose disclosed history is otherwise
    /// almost entirely funds. A fact about this member's filing history, stated plainly.
    public static func offPattern(in feed: TradeFeed) -> [Standout] {
        let byMember = Dictionary(grouping: feed.trades, by: \.memberID)

        var out: [Standout] = []
        for (_, rows) in byMember {
            guard rows.count >= 5 else { continue }
            let fundLike = rows.filter { $0.assetType == "MF" || $0.assetType == "EF" || $0.ticker == nil }
            guard Double(fundLike.count) / Double(rows.count) >= 0.8 else { continue }
            for t in rows where t.ticker != nil && (t.assetType == "ST" || t.isOption) {
                out.append(Standout(
                    category: .offPattern, trade: t,
                    reason: "Off this member's usual pattern — mostly funds"
                ))
            }
        }
        return out.sorted(by: recencyThenID)
    }

    // MARK: - Rule 6 · rareTrader

    /// Every disclosed trade by a member who has disclosed three or fewer in the whole
    /// snapshot.
    public static func rareTrader(in feed: TradeFeed) -> [Standout] {
        let byMember = Dictionary(grouping: feed.trades, by: \.memberID)
        var out: [Standout] = []
        for (_, rows) in byMember where rows.count <= 3 {
            let reason = rows.count == 1
                ? "The only trade this member disclosed"
                : "1 of only \(rows.count) this member disclosed"
            for t in rows {
                out.append(Standout(category: .rareTrader, trade: t, reason: reason))
            }
        }
        return out.sorted(by: recencyThenID)
    }

    // MARK: - Rule 7 · memberLargest

    /// One row per member: the single largest bracket that member disclosed, kept only
    /// when that bracket's floor is at least $250,000.
    public static func memberLargest(in feed: TradeFeed) -> [Standout] {
        let byMember = Dictionary(grouping: feed.trades, by: \.memberID)
        var out: [Trade] = []
        for (_, rows) in byMember {
            guard let largest = rows.max(by: { bracketOrder($1, $0) }) else { continue }
            guard largest.amount.lowCents >= 25_000_000 else { continue }
            out.append(largest)
        }
        return out
            .sorted(by: bracketOrder)
            .map { Standout(category: .memberLargest, trade: $0, reason: "This member's largest disclosed") }
    }

    // MARK: - Shared ordering

    /// Most recently disclosed first, then id ascending.
    private static func recencyThenID(_ a: Standout, _ b: Standout) -> Bool {
        if a.trade.disclosedDate != b.trade.disclosedDate {
            return a.trade.disclosedDate > b.trade.disclosedDate
        }
        return a.trade.id < b.trade.id
    }
}
