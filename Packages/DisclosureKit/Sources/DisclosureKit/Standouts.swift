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

/// A one- or two-line plain-language summary of what stands out in a snapshot — the
/// thing the feed's entry card shows so the reader knows there's something worth a tap.
public struct StandoutHeadline: Sendable, Equatable {
    /// The single most striking fact, as a full sentence.
    public let lead: String
    /// A second fact, or `nil` when the snapshot only had one thing worth saying.
    public let supporting: String?

    public init(lead: String, supporting: String? = nil) {
        self.lead = lead
        self.supporting = supporting
    }

    /// The lead and supporting facts as one string — for a VoiceOver label or any other
    /// single-run context. On screen the two are rendered as separate lines.
    public var combined: String {
        lead + (supporting.map { " " + $0 } ?? "")
    }

    /// Stands in for a headline when the snapshot is too small to have produced one —
    /// `headline(in:)` returns `nil` only in that case.
    public static let placeholder =
        "The largest brackets, the latest filings, and the most widely traded stocks in this snapshot."
}

public enum Standouts {

    // MARK: - Headline

    /// One or two plain-language facts about the snapshot, favouring a *pattern* (a count)
    /// over a single outlier, since the worst single row is often a mistyped year. `nil`
    /// only for an empty or tiny snapshot.
    ///
    /// `byCategory` and `widelyHeld` are the lists `byCategory(in:)` / `widelyHeldTickers(in:)`
    /// already produce; pass them in when they are to hand so this does not recompute them.
    public static func headline(
        in feed: TradeFeed,
        byCategory: [Standout.Category: [Standout]]? = nil,
        widelyHeld: [WidelyHeldTicker]? = nil
    ) -> StandoutHeadline? {
        var facts: [String] = []

        // How many trades were disclosed more than a year after they happened — a robust
        // count, not the single most extreme lag, and bounded so a mistyped year does not
        // inflate it. This is its own query (365 days, every row) rather than the deduped
        // `filedLate` list, so the one Calendar pass it needs is unavoidable here.
        let overAYearLate = feed.trades.filter {
            !$0.hasImpossibleDate
                && (365 < $0.disclosureLagDays && $0.disclosureLagDays <= plausibleLateCeilingDays)
        }.count
        if overAYearLate >= 3 {
            facts.append("\(overAYearLate) trades were disclosed more than a year after "
                         + "they happened — the STOCK Act allows 45 days.")
        }

        // The form's top brackets ($5M and up) — reuse the caller's list when given.
        let big = byCategory?[.topBracket] ?? topBracket(in: feed)
        if big.count >= 3 {
            facts.append("\(big.count) trades landed in the form's top brackets "
                         + "($5,000,000 and up).")
        } else if let one = big.first {
            facts.append("The largest disclosed bracket this snapshot is "
                         + "\(one.trade.amount.label).")
        }

        // The single most widely traded ticker — again reuse the caller's list when given.
        if facts.count < 2 {
            let widely = widelyHeld ?? widelyHeldTickers(in: feed)
            if let top = widely.first, top.memberCount >= 3 {
                facts.append("\(top.ticker) appears in \(top.memberCount) members' filings, "
                             + "more than any other stock.")
            }
        }

        // Nothing stood out — say what the snapshot is. Count the members who actually
        // traded (an incremental feed can retain a member whose trades have all aged out),
        // and drop the year span when the feed carries no index years.
        if facts.isEmpty, !feed.trades.isEmpty {
            let traders = Set(feed.trades.map(\.memberID)).count
            let base = "\(traders) members disclosed \(feed.trades.count.formatted()) trades"
            let years = feed.indexYears.sorted()
            if let lo = years.first, let hi = years.last {
                facts.append(lo == hi ? "\(base) across \(lo)." : "\(base) across \(lo)–\(hi).")
            } else {
                facts.append("\(base).")
            }
        }

        guard let lead = facts.first else { return nil }
        return StandoutHeadline(lead: lead, supporting: facts.count > 1 ? facts[1] : nil)
    }

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

    /// A transaction disclosed this many days late is, past this point, almost always a
    /// mistyped transaction year rather than a real filing — a spouse account opened in
    /// 2015 disclosed in 2025. Beyond it the row still appears in the plain feed; it is
    /// just not held up here as a STOCK Act violation.
    static let plausibleLateCeilingDays = 1200

    /// Trades disclosed between 45 days and ~3.3 years after the transaction — over the
    /// STOCK Act's 45-day limit, but not so far over that the date is unbelievable.
    /// Rows with internally inconsistent dates are excluded. Longest gap first.
    public static func filedLate(in feed: TradeFeed) -> [Standout] {
        // `disclosureLagDays` goes through `Calendar`, so it is read once per row here
        // rather than once per sort comparison.
        feed.trades
            .compactMap { t -> (trade: Trade, lag: Int)? in
                guard !t.hasImpossibleDate else { return nil }
                let lag = t.disclosureLagDays
                return (45 < lag && lag <= plausibleLateCeilingDays) ? (t, lag) : nil
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
            .onePerMember()
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
        return out.sorted(by: recencyThenID).onePerMember()
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
                    reason: "A single stock — this member's filings are otherwise almost all funds"
                ))
            }
        }
        return out.sorted(by: recencyThenID).onePerMember()
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

extension Array where Element == Standout {
    /// Keeps the first row for each member. One representative whose backlog dump fills a
    /// whole list misrepresents the snapshot — the failure `topBracket` was already
    /// hardened against. The caller must have ordered the list so each member's most
    /// notable row comes first.
    func onePerMember() -> [Standout] {
        var seen = Set<String>()
        return filter { seen.insert($0.trade.memberID).inserted }
    }
}
