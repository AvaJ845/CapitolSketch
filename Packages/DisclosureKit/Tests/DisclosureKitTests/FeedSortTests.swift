import Foundation
import Testing
@testable import DisclosureKit

/// `FeedBuilder.byDisclosureDate` is the order behind the feed's "Just disclosed" view.
/// It reorders the same rows by filing date; nothing is added or dropped.
@Suite("Feed ordering by disclosure date")
struct FeedSortTests {

    private func mk(_ id: String, tx: String, disclosed: String) -> Trade {
        Trade(
            id: id, memberID: "m", memberName: "M", owner: .self, asset: "A",
            ticker: "A", assetType: "ST", txType: .buy,
            txDate: CalendarDate(iso: tx)!, disclosedDate: CalendarDate(iso: disclosed)!,
            amount: .noneDisclosed, filingDescription: nil, filingID: "f-\(id)", documentURL: nil
        )
    }

    @Test("Newest disclosure first, regardless of transaction date")
    func newestDisclosedFirst() {
        // `b` traded first but disclosed last; `a` traded last but disclosed first.
        let a = mk("a", tx: "2026-05-01", disclosed: "2026-05-10")
        let b = mk("b", tx: "2026-01-01", disclosed: "2026-06-01")
        let c = mk("c", tx: "2026-03-01", disclosed: "2026-05-20")

        let ordered = FeedBuilder.byDisclosureDate([a, b, c])
        #expect(ordered.map(\.id) == ["b", "c", "a"])
    }

    @Test("Same disclosure date falls back to id descending, matching FeedBuilder.sorted")
    func stableTiebreak() {
        let x = mk("x", tx: "2026-02-01", disclosed: "2026-04-01")
        let y = mk("y", tx: "2026-01-01", disclosed: "2026-04-01")
        #expect(FeedBuilder.byDisclosureDate([x, y]).map(\.id) == ["y", "x"])
        #expect(FeedBuilder.byDisclosureDate([y, x]).map(\.id) == ["y", "x"])
    }

    @Test("A mistyped transaction year that pins a row under sorted does not pin it here")
    func impossibleDateRowNotPinned() {
        // Transaction date after the filing date — an obvious mistyped year.
        let impossible = mk("impossible", tx: "2027-08-01", disclosed: "2026-02-01")
        let recent = mk("recent", tx: "2026-06-01", disclosed: "2026-06-15")

        // `sorted` keeps the impossible row off the top by using `disclosedDate` for it.
        #expect(FeedBuilder.sorted([impossible, recent]).map(\.id) == ["recent", "impossible"])
        // `byDisclosureDate` sorts on the filing date for every row, so it lands by
        // its February disclosure.
        #expect(FeedBuilder.byDisclosureDate([impossible, recent]).map(\.id) == ["recent", "impossible"])
    }

    @Test("Reordering preserves the row set")
    func preservesRows() {
        let rows = (1...20).map { mk("t\($0)", tx: "2026-01-\(String(format: "%02d", $0))",
                                     disclosed: "2026-02-\(String(format: "%02d", $0))") }
        let ordered = FeedBuilder.byDisclosureDate(rows.shuffled())
        #expect(Set(ordered.map(\.id)) == Set(rows.map(\.id)))
        #expect(ordered.count == rows.count)
    }
}
