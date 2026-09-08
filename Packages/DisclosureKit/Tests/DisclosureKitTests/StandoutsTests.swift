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

    @Test("Top brackets: floor ≥ $5M only; reduced Spouse/DC Over $1M is not a top bracket")
    func topBracket() {
        let open50M = mk("open-50m", member: "z", ticker: "ZZZ",
                         amount: amt(.atLeast, 50_000_001_00))
        let feed = makeFeed(
            Fixture.issaLargeBracket.parse().trades       // $25,000,001 – $50,000,000 range
            + Fixture.petersOverThreshold.parse().trades  // Spouse/DC Over $1,000,000 — floor $1M
            + Fixture.pelosiMultiAsset.parse().trades      // largest is $1,000,001 – $5,000,000
            + [open50M]
        )
        let rows = Standouts.topBracket(in: feed)

        // The $50M+ open bracket has the highest floor, so it leads.
        #expect(rows.first?.trade.id == "open-50m")
        // Issa's $25,000,001 – $50,000,000 bracket clears the $5M floor.
        #expect(rows.contains { $0.trade.amount.lowCents == 25_000_001_00 })
        // Spouse/DC Over $1,000,000 is the reduced reporting standard, floor $1M — excluded.
        let petersIDs = Set(Fixture.petersOverThreshold.parse().trades.map(\.id))
        #expect(!rows.contains { petersIDs.contains($0.trade.id) })
        // Pelosi's largest is $1,000,001 – $5,000,000 — below the $5M floor.
        let pelosiIDs = Set(Fixture.pelosiMultiAsset.parse().trades.map(\.id))
        #expect(!rows.contains { pelosiIDs.contains($0.trade.id) })
        // The reason is the bracket exactly as the form states it.
        #expect(rows.allSatisfy { $0.reason == $0.trade.amount.label })
        // Every row genuinely clears the $5M floor.
        #expect(rows.allSatisfy { $0.trade.amount.lowCents >= 500_000_000 })
        // Ordered by floor, descending.
        #expect(rows.map(\.trade.amount.lowCents) == rows.map(\.trade.amount.lowCents).sorted(by: >))
    }

    // MARK: - Rule 2 · filedLate

    @Test("Filed late: longest-first, one row per member; 10-day lag and an impossible date excluded")
    func filedLate() {
        let feed = makeFeed([
            mk("m1-on-time", member: "m1", tx: "2026-03-01", disclosed: "2026-03-11"),  // lag 10
            mk("m1-late46", member: "m1", tx: "2026-03-01", disclosed: "2026-04-16"),   // lag 46
            mk("m1-late120", member: "m1", tx: "2026-03-01", disclosed: "2026-06-29"),  // lag 120
            mk("m2-late80", member: "m2", tx: "2026-03-01", disclosed: "2026-05-20"),   // lag 80
            // Transaction dated after its own filing: the lag is not a real number.
            mk("impossible", member: "m3", tx: "2027-06-01", disclosed: "2026-02-01"),
        ])
        let rows = Standouts.filedLate(in: feed)
        // m1's worst (120) leads; m2 next; m1's second late filing (46) is dropped.
        #expect(rows.map(\.trade.id) == ["m1-late120", "m2-late80"])
        #expect(rows.first?.reason == "Filed 120 days late")
    }

    @Test("Filed late: a lag past ~3.3 years is treated as a mistyped year and excluded")
    func filedLateCeiling() {
        let feed = makeFeed([
            mk("real", member: "m1", tx: "2024-01-01", disclosed: "2025-06-01"),   // ~517 days
            mk("typo", member: "m2", tx: "2015-05-08", disclosed: "2025-06-22"),    // ~3700 days
        ])
        #expect(Standouts.filedLate(in: feed).map(\.trade.id) == ["real"])
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
        #expect(rows.first?.reason == "A single stock — this member's filings are otherwise almost all funds")
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
            // C: a $50M open-ended bracket — highest floor in the feed.
            mk("c-1", member: "c", ticker: "DDD", amount: amt(.atLeast, 5_000_000_000)),
        ])
        let rows = Standouts.memberLargest(in: feed)
        #expect(rows.map(\.trade.memberID) == ["c", "a"])
        #expect(rows.map(\.trade.id) == ["c-1", "a-2"])
        #expect(rows.allSatisfy { $0.reason == "This member's largest disclosed" })
    }

    // MARK: - Headline

    @Test("Headline leads with the over-a-year-late count when 3 or more")
    func headlineLeadsWithLatePattern() {
        var trades: [Trade] = []
        for i in 0..<4 {
            trades.append(mk("late\(i)", member: "m\(i)", tx: "2024-01-01", disclosed: "2026-01-01"))
        }
        trades.append(mk("big", member: "z", ticker: "NVDA",
                         amount: amt(.range, 500_000_100, 2_500_000_000)))
        let h = try! #require(Standouts.headline(in: makeFeed(trades)))
        #expect(h.lead == "4 trades were disclosed more than a year after they happened — the STOCK Act allows 45 days.")
        #expect(h.supporting?.contains("largest disclosed bracket") == true)
    }

    @Test("Headline falls back to the widely-held ticker when nothing is late or huge")
    func headlineFallsBackToWidelyHeld() {
        var trades: [Trade] = []
        for m in ["a", "b", "c", "d"] { trades.append(mk("t-\(m)", member: m, ticker: "AAPL")) }
        let h = try! #require(Standouts.headline(in: makeFeed(trades)))
        #expect(h.lead.contains("AAPL") && h.lead.contains("4 members"))
    }

    @Test("Headline describes the snapshot when nothing stands out")
    func headlineDescribesSnapshot() {
        let h = try! #require(Standouts.headline(in: makeFeed([
            mk("t1", member: "a", ticker: "AAA"), mk("t2", member: "b", ticker: "BBB"),
        ])))
        #expect(h.lead.contains("2 members disclosed 2 trades"))
    }

    @Test("Headline is nil for an empty snapshot")
    func headlineNilWhenEmpty() {
        #expect(Standouts.headline(in: makeFeed([])) == nil)
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
        #expect(Standouts.headline(in: feed) == Standouts.headline(in: feed))
    }
}

@Suite("Party")
struct PartyTests {

    @Test("Crosswalk strings map to the four cases")
    func crosswalkMapping() {
        #expect(Party(crosswalk: "Democrat") == .democrat)
        #expect(Party(crosswalk: "Republican") == .republican)
        #expect(Party(crosswalk: "Independent") == .independent)
        #expect(Party(crosswalk: "Libertarian") == .independent)  // any minor party → independent
        #expect(Party(crosswalk: nil) == .unknown)
        #expect(Party(crosswalk: "") == .unknown)
    }

    @Test("A member JSON written before the party key decodes as unknown")
    func decodesMemberWithoutPartyKey() throws {
        let older = Data("""
        { "id": "P000197", "bioguideID": "P000197", "name": "Nancy Pelosi",
          "state": "CA", "district": "11", "chamber": "house" }
        """.utf8)
        let (_, decoder) = TradeFeed.makeCoder()
        let m = try decoder.decode(Member.self, from: older)
        #expect(m.party == .unknown)
    }

    @Test("party survives a feed round-trip")
    func roundTrips() throws {
        let m = Member(id: "x", bioguideID: "X000001", name: "X", state: "CA",
                       district: "1", chamber: .house, party: .democrat)
        let feed = FeedBuilder.make(trades: [], members: [m],
                                    stats: ParseStats(), indexYears: [2026])
        let (e, d) = TradeFeed.makeCoder()
        let restored = try d.decode(TradeFeed.self, from: e.encode(feed))
        #expect(restored.members.first?.party == .democrat)
    }
}
