import Foundation
import Testing
import DisclosureKit
@testable import CapitolSketch

/// `FeedGrouping.groups` only adds section headers to a feed slice that is already in
/// display order. These pin that it never reorders, drops, or duplicates a row, and that
/// the header it writes names the date the reader sorted by.
@Suite("Feed month grouping")
struct FeedGroupingTests {

    private let today = CalendarDate("2026-06-15")

    @Test("An empty feed produces no groups")
    func empty() {
        #expect(FeedGrouping.groups(for: [], sort: .recent, today: today).isEmpty)
    }

    @Test("Rows are preserved, in order, across the groups")
    func preservesRowsAndOrder() {
        let trades = (0..<40).map { i in
            Build.trade(id: "t\(i)", tx: CalendarDate("2026-04-\(String(format: "%02d", (i % 28) + 1))"))
        }
        let flattened = FeedGrouping.groups(for: trades, sort: .recent, today: today)
            .flatMap(\.trades)
        #expect(flattened.map(\.id) == trades.map(\.id))
    }

    @Test("Recent transactions bucket by transaction month under .recent")
    func recentSortBucketsByTransactionMonth() {
        let april = Build.trade(id: "apr", tx: CalendarDate("2026-04-10"), disclosed: CalendarDate("2026-05-20"))
        let march = Build.trade(id: "mar", tx: CalendarDate("2026-03-02"), disclosed: CalendarDate("2026-04-15"))

        let groups = FeedGrouping.groups(for: [april, march], sort: .recent, today: today)
        #expect(groups.map(\.title) == ["April 2026", "March 2026"])
        #expect(groups.first?.trades.map(\.id) == ["apr"])
    }

    @Test("Just-disclosed groups on the filing date and leads with a Past 7 days bucket")
    func justDisclosedUsesDisclosureDateAndRecentBucket() {
        let fresh = Build.trade(id: "fresh", tx: CalendarDate("2026-01-05"), disclosed: CalendarDate("2026-06-12"))
        let older = Build.trade(id: "older", tx: CalendarDate("2026-02-01"), disclosed: CalendarDate("2026-04-03"))

        let groups = FeedGrouping.groups(for: [fresh, older], sort: .justDisclosed, today: today)
        #expect(groups.first?.title == "Past 7 days")
        #expect(groups.first?.trades.map(\.id) == ["fresh"])
        #expect(groups.last?.title == "April 2026")
    }

    @Test("An empty Past 7 days bucket is dropped, not rendered")
    func emptyRecentBucketDropped() {
        // Everything disclosed well over a week ago.
        let a = Build.trade(id: "a", disclosed: CalendarDate("2026-05-01"))
        let b = Build.trade(id: "b", disclosed: CalendarDate("2026-05-20"))
        let groups = FeedGrouping.groups(for: [a, b], sort: .justDisclosed, today: today)
        #expect(!groups.contains { $0.title == "Past 7 days" })
    }

    @Test("Group ids are unique so ForEach does not collapse two months")
    func uniqueGroupIDs() {
        let trades = [
            Build.trade(id: "jan", tx: CalendarDate("2026-01-10")),
            Build.trade(id: "feb", tx: CalendarDate("2026-02-10")),
            Build.trade(id: "mar", tx: CalendarDate("2026-03-10")),
        ]
        let ids = FeedGrouping.groups(for: trades, sort: .recent, today: today).map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
