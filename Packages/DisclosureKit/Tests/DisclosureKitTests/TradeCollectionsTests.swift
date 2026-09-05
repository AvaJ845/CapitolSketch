import Foundation
import Testing
@testable import DisclosureKit

@Suite("Grouping a filing's transactions")
struct TradeCollectionsTests {

    @Test("inFiling returns every row of a multi-row filing and nothing else")
    func inFilingGroupsWholeFiling() {
        let filing = Fixture.pelosiMultiAsset.parse().trades
        #expect(filing.count == 7)
        let filingID = filing[0].filingID
        // Every one of the seven shares the filing id.
        #expect(Set(filing.map(\.filingID)) == [filingID])

        // A haystack that also holds an unrelated filing's rows.
        let other = Trade(
            id: "99999999-x", memberID: "z", memberName: "Someone Else", owner: .self,
            asset: "OTHER", ticker: "OTH", assetType: "ST", txType: .sell,
            txDate: CalendarDate(iso: "2026-01-01")!, disclosedDate: CalendarDate(iso: "2026-01-20")!,
            amount: .noneDisclosed, filingDescription: nil, filingID: "99999999", documentURL: nil
        )
        let haystack = filing + [other]

        let grouped = haystack.inFiling(filingID)
        #expect(grouped.count == 7)
        #expect(Set(grouped.map(\.id)) == Set(filing.map(\.id)))
        #expect(!grouped.contains { $0.id == "99999999-x" })

        #expect(haystack.inFiling("does-not-exist").isEmpty)
    }
}

@Suite("Disclosure-lag statistics")
struct DisclosureLagStatsTests {

    /// A trade filed `lag` days after a fixed transaction date. A negative `lag` makes an
    /// impossible date, which the stats must skip.
    private func trade(lag: Int) -> Trade {
        let tx = CalendarDate(iso: "2026-06-01")!
        let disclosed = Calendar.current.date(byAdding: .day, value: lag, to: tx.date())!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: disclosed)
        return Trade(
            id: "t\(lag)", memberID: "m", memberName: "M", owner: .self, asset: "A",
            ticker: "A", assetType: "ST", txType: .buy, txDate: tx,
            disclosedDate: CalendarDate(year: c.year!, month: c.month!, day: c.day!),
            amount: .noneDisclosed, filingDescription: nil, filingID: "f", documentURL: nil
        )
    }

    @Test("Median, mean, over-45 count and buckets against known lags")
    func knownLags() {
        // Lags: 1, 5, 10, 20, 40, 45, 46, 60, 100  (nine values) plus one impossible.
        let lags = [1, 5, 10, 20, 40, 45, 46, 60, 100]
        let trades = lags.map { trade(lag: $0) } + [trade(lag: -3)]

        let s = trades.disclosureLagStats
        #expect(s.count == 9)                    // impossible-date row excluded
        #expect(s.medianDays == 40)              // middle of nine
        #expect(s.meanDays == 36)                // 327 / 9 = 36.33 -> 36
        #expect(s.overFortyFiveCount == 3)       // 46, 60, 100
        #expect(s.overFortyFivePercent == 33)

        let byLabel = Dictionary(uniqueKeysWithValues: s.buckets.map { ($0.label, $0.count) })
        #expect(byLabel["7 days or fewer"] == 2)      // 1, 5
        #expect(byLabel["8 to 30 days"] == 2)         // 10, 20
        #expect(byLabel["31 to 45 days"] == 2)        // 40, 45
        #expect(byLabel["46 to 90 days"] == 2)        // 46, 60
        #expect(byLabel["More than 90 days"] == 1)    // 100
        #expect(s.buckets.reduce(0) { $0 + $1.count } == s.count)
    }

    @Test("Even sample averages the two middle values")
    func evenMedian() {
        let s = [trade(lag: 10), trade(lag: 20), trade(lag: 30), trade(lag: 44)].disclosureLagStats
        #expect(s.medianDays == 25)              // (20 + 30) / 2
    }

    @Test("An empty collection yields zeroes and empty buckets")
    func empty() {
        let s = [Trade]().disclosureLagStats
        #expect(s.count == 0)
        #expect(s.medianDays == 0)
        #expect(s.overFortyFivePercent == 0)
        #expect(s.buckets.count == 5)
        #expect(s.buckets.allSatisfy { $0.count == 0 })
    }
}
