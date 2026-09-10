import Foundation
import Testing
import DisclosureKit
@testable import CapitolSketch

/// `TradeFilter.apply` is navigation over rows already in the feed — it only ever
/// removes rows, never reorders or rewrites them. These pin each facet and the
/// active-count the toolbar badge shows.
@Suite("Feed filter")
struct TradeFilterTests {

    private let feed: [Trade] = [
        Build.trade(id: "buy-self", memberID: "A", memberName: "Ada Byron",
                    owner: .self, ticker: "NVDA", assetType: "ST", type: .buy,
                    tx: CalendarDate("2026-06-01"), disclosed: CalendarDate("2026-06-10"),
                    amount: Build.range(1_001, 15_000)),
        Build.trade(id: "sell-spouse", memberID: "B", memberName: "Blaise Pascal",
                    owner: .spouse, ticker: "AAPL", assetType: "ST", type: .sell,
                    tx: CalendarDate("2026-05-01"), disclosed: CalendarDate("2026-05-05"),
                    amount: Build.range(1_000_000, 5_000_000)),
        Build.trade(id: "opt-late", memberID: "A", memberName: "Ada Byron",
                    owner: .self, ticker: "TSLA", assetType: "OP", type: .buy,
                    tx: CalendarDate("2026-01-01"), disclosed: CalendarDate("2026-06-01"),
                    amount: Build.amount(.atLeast, low: 5_000_000_00)),
    ]

    private func apply(_ f: TradeFilter) -> [String] {
        f.apply(to: feed, stateOf: { ["A": "CA", "B": "NY"][$0] }).map(\.id)
    }

    @Test("No facets set keeps every row in the original order")
    func passthrough() {
        #expect(apply(TradeFilter()) == ["buy-self", "sell-spouse", "opt-late"])
    }

    @Test("Direction facet")
    func direction() {
        var f = TradeFilter(); f.types = [.sell]
        #expect(apply(f) == ["sell-spouse"])
    }

    @Test("Owner facet")
    func owner() {
        var f = TradeFilter(); f.owners = [.spouse]
        #expect(apply(f) == ["sell-spouse"])
    }

    @Test("Options-only keeps just the option row")
    func optionsOnly() {
        var f = TradeFilter(); f.optionsOnly = true
        #expect(apply(f) == ["opt-late"])
    }

    @Test("Filed-late keeps only filings over 45 days")
    func lateOnly() {
        var f = TradeFilter(); f.lateOnly = true
        #expect(apply(f) == ["opt-late"])
    }

    @Test("Minimum size keeps brackets at or above the floor, plus every open-ended top bracket")
    func minBracket() {
        var f = TradeFilter(); f.minBracket = .m50
        // Only the open-ended `.atLeast` row clears a $50M floor.
        #expect(apply(f) == ["opt-late"])

        f.minBracket = .m1
        #expect(apply(f) == ["sell-spouse", "opt-late"])
    }

    @Test("State facet resolves through the caller's closure")
    func state() {
        var f = TradeFilter(); f.states = ["NY"]
        #expect(apply(f) == ["sell-spouse"])
    }

    @Test("Search matches member, ticker, or company, case-insensitively")
    func search() {
        var f = TradeFilter(); f.search = "  ada  "
        #expect(apply(f) == ["buy-self", "opt-late"])

        f.search = "aapl"
        #expect(apply(f) == ["sell-spouse"])

        f.search = "acme"
        #expect(apply(f) == ["buy-self", "sell-spouse", "opt-late"])
    }

    @Test("Facets stack — direction AND owner")
    func stacked() {
        var f = TradeFilter(); f.types = [.buy]; f.owners = [.self]
        #expect(apply(f) == ["buy-self", "opt-late"])
    }

    @Test("isActive and activeCount reflect the set facets")
    func activeCount() {
        #expect(!TradeFilter().isActive)
        var f = TradeFilter()
        f.types = [.buy, .sell]
        f.optionsOnly = true
        f.minBracket = .m5
        #expect(f.isActive)
        #expect(f.activeCount == 4)
        // Search text alone is not a facet — it has its own field in the UI.
        var g = TradeFilter(); g.search = "nvda"
        #expect(!g.isActive)
    }
}
