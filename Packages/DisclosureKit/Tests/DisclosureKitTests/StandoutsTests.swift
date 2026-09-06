import Foundation
import Testing
@testable import DisclosureKit

/// The standout rules are pure functions over one feed. Every threshold in the spec is
/// pinned here against a hand-built feed (or a checked-in fixture), not captured from a
/// previous run.
@Suite("Standout predicates")
struct StandoutsTests {

    // MARK: - Builders

    private func amt(_ kind: DisclosedAmount.Kind, _ low: Int, _ high: Int? = nil) -> DisclosedAmount {
        let h = high ?? low
        return DisclosedAmount(
            kind: kind, lowCents: low, highCents: h,
            label: DisclosedAmount.makeLabel(kind: kind, lowCents: low, highCents: h)
        )
    }

    private func mk(
        _ id: String, member: String, ticker: String? = nil, assetType: String? = "ST",
        amount: DisclosedAmount? = nil, tx: String = "2026-03-01", disclosed: String = "2026-03-15",
        type: TradeType = .buy
    ) -> Trade {
        Trade(
            id: id, memberID: member, memberName: member, owner: .self,
            asset: ticker ?? "Some Asset", ticker: ticker, assetType: assetType, txType: type,
            txDate: CalendarDate(iso: tx)!, disclosedDate: CalendarDate(iso: disclosed)!,
            amount: amount ?? DisclosedAmount(kind: .range, lowCents: 100_100, highCents: 1_500_000,
                                              label: "$1,001 – $15,000"),
            filingDescription: nil, filingID: "f-\(member)", documentURL: nil
        )
    }

    // MARK: - Rule 1 · topBracket

    @Test("Top brackets: $5M-floor range qualifies, .atLeast sorts first, $1M–$5M does not")
    func topBracket() {
        let feed = makeFeed(
            Fixture.issaLargeBracket.parse().trades
            + Fixture.petersOverThreshold.parse().trades
            + Fixture.pelosiMultiAsset.parse().trades
        )
        let rows = Standouts.topBracket(in: feed)

        // Issa's $25,000,001 – $50,000,000 bracket is over the $5M floor.
        #expect(rows.contains { $0.trade.amount.lowCents == 25_000_001_00 })
        // Peters' open-ended bracket qualifies and outranks every range.
        #expect(rows.first?.trade.amount.kind == .atLeast)
        // Pelosi's largest is $1,000,001 – $5,000,000 — below the $5M floor.
        let pelosiIDs = Set(Fixture.pelosiMultiAsset.parse().trades.map(\.id))
        #expect(!rows.contains { pelosiIDs.contains($0.trade.id) })
        // The reason is the bracket exactly as the form states it.
        #expect(rows.allSatisfy { $0.reason == $0.trade.amount.label })
        // Every row is genuinely in the top brackets.
        #expect(rows.allSatisfy { $0.trade.amount.kind == .atLeast || $0.trade.amount.lowCents >= 500_000_000 })
    }

    // MARK: - Rule 2 · filedLate

    @Test("Filed late: 46 and 120 returned longest-first; 10 and an impossible date excluded")
    func filedLate() {
        let feed = makeFeed([
            mk("on-time", member: "m", tx: "2026-03-01", disclosed: "2026-03-11"),   // lag 10
            mk("late46", member: "m", tx: "2026-03-01", disclosed: "2026-04-16"),     // lag 46
            mk("late120", member: "m", tx: "2026-03-01", disclosed: "2026-06-29"),    // lag 120
            // Transaction dated after its own filing: the lag is not a real number.
            mk("impossible", member: "m", tx: "2027-06-01", disclosed: "2026-02-01"),
        ])
        let rows = Standouts.filedLate(in: feed)
        #expect(rows.map(\.trade.id) == ["late120", "late46"])
        #expect(rows.first?.reason == "Filed 120 days late")
        #expect(rows.last?.reason == "Filed 46 days late")
    }

    // MARK: - Rule 3 · widelyHeldTickers

    @Test("Widely held: AAA (4 members) kept, BBB (2 members) dropped")
    func widelyHeldTickers() {
        var trades = [
            mk("a-extra", member: "m1", ticker: "AAA"),   // m1 discloses AAA twice
        ]
        for m in ["m1", "m2", "m3", "m4"] {
            trades.append(mk("a-\(m)", member: m, ticker: "AAA"))
        }
        for m in ["m5", "m6"] {
            trades.append(mk("b-\(m)", member: m, ticker: "BBB"))
        }
        let rows = Standouts.widelyHeldTickers(in: makeFeed(trades))
        #expect(rows.map(\.ticker) == ["AAA"])
        #expect(rows.first?.memberCount == 4)
        #expect(rows.first?.tradeCount == 5)
    }

    // MARK: - Rule 4 · newPosition

    @Test("New position: first trade in the window qualifies; a 2nd trade, a lone trader, and a 60-day-old first do not")
    func newPosition() {
        let feed = makeFeed([
            // M1: two trades in AAA, ≥2 total. Earliest disclosed 20 days before the anchor.
            mk("m1-a1", member: "m1", ticker: "AAA", tx: "2026-05-01", disclosed: "2026-06-10"),
            mk("m1-a2", member: "m1", ticker: "AAA", tx: "2026-06-01", disclosed: "2026-06-30"), // anchor
            // M2: a single trade total — excluded even though it is a first in BBB.
            mk("m2-b1", member: "m2", ticker: "BBB", tx: "2026-05-01", disclosed: "2026-06-15"),
            // M3: ≥2 trades, but the first in CCC was disclosed 60 days before the anchor.
            mk("m3-c1", member: "m3", ticker: "CCC", tx: "2026-01-01", disclosed: "2026-05-01"),
            mk("m3-c2", member: "m3", ticker: "CCC", tx: "2026-04-01", disclosed: "2026-06-25"),
        ])
        let rows = Standouts.newPosition(in: feed)
        #expect(rows.map(\.trade.id) == ["m1-a1"])
        #expect(rows.first?.reason == "First disclosed AAA trade by this member")
    }

    // MARK: - Rule 5 · offPattern

    @Test("Off pattern: 9 funds + 1 stock flags the stock; 4-trade and 50/50 members do not")
    func offPattern() {
        var trades: [Trade] = []
        // P1: nine mutual-fund rows and one single stock.
        for i in 0..<9 { trades.append(mk("p1-mf\(i)", member: "p1", ticker: "VFIAX", assetType: "MF")) }
        trades.append(mk("p1-st", member: "p1", ticker: "AAPL", assetType: "ST"))
        // P2: three funds and one stock — only four trades total.
        for i in 0..<3 { trades.append(mk("p2-mf\(i)", member: "p2", ticker: "VFIAX", assetType: "MF")) }
        trades.append(mk("p2-st", member: "p2", ticker: "AAPL", assetType: "ST"))
        // P3: five funds and five stocks.
        for i in 0..<5 { trades.append(mk("p3-mf\(i)", member: "p3", ticker: "VFIAX", assetType: "MF")) }
        for i in 0..<5 { trades.append(mk("p3-st\(i)", member: "p3", ticker: "AAPL", assetType: "ST")) }

        let rows = Standouts.offPattern(in: makeFeed(trades))
        #expect(rows.map(\.trade.id) == ["p1-st"])
        #expect(rows.first?.reason == "Off this member's usual pattern — mostly funds")
    }

    // MARK: - Rule 6 · rareTrader

    @Test("Rare trader: a member with 2 trades has both surfaced; a member with 4 has none")
    func rareTrader() {
        var trades: [Trade] = [
            mk("r1-1", member: "r1", ticker: "AAA"),
            mk("r1-2", member: "r1", ticker: "BBB"),
        ]
        for i in 0..<4 { trades.append(mk("r2-\(i)", member: "r2", ticker: "CCC")) }

        let rows = Standouts.rareTrader(in: makeFeed(trades))
        #expect(Set(rows.map(\.trade.id)) == ["r1-1", "r1-2"])
        #expect(rows.allSatisfy { $0.reason == "1 of only 2 this member disclosed" })
    }

    // MARK: - Rule 7 · memberLargest

    @Test("Member largest: one row per member, biggest bracket, $250k floor drops the small member")
    func memberLargest() {
        let feed = makeFeed([
            // A: two large brackets — only the larger is kept, and only once.
            mk("a-1", member: "a", ticker: "AAA", amount: amt(.range, 100_000_100, 500_000_000)),
            mk("a-2", member: "a", ticker: "BBB", amount: amt(.range, 500_000_100, 2_500_000_000)),
            // B: largest is $1,001 – $15,000 — under the $250,000 floor.
            mk("b-1", member: "b", ticker: "CCC", amount: amt(.range, 100_100, 1_500_000)),
            // C: an open-ended bracket outranks every range.
            mk("c-1", member: "c", ticker: "DDD", amount: amt(.atLeast, 5_000_000_000)),
        ])
        let rows = Standouts.memberLargest(in: feed)
        #expect(rows.map(\.trade.memberID) == ["c", "a"])
        #expect(rows.map(\.trade.id) == ["c-1", "a-2"])
        #expect(rows.allSatisfy { $0.reason == "This member's largest disclosed" })
    }

    // MARK: - Determinism

    @Test("byCategory is deterministic for a given feed")
    func deterministic() {
        let feed = makeFeed(
            Fixture.issaLargeBracket.parse().trades
            + Fixture.pelosiMultiAsset.parse().trades
            + Fixture.petersOverThreshold.parse().trades
        )
        #expect(Standouts.byCategory(in: feed) == Standouts.byCategory(in: feed))
        #expect(Standouts.widelyHeldTickers(in: feed) == Standouts.widelyHeldTickers(in: feed))
    }
}
