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
