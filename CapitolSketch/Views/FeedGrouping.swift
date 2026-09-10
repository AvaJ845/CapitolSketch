import Foundation
import DisclosureKit

/// Splits an already-ordered feed into time buckets so a long list has structure to
/// scroll past instead of four hundred undifferentiated cards.
///
/// This is pure grouping of rows already in hand — the same rows, the same order, just
/// with headers. Nothing is selected, ranked or reworded. Which date is grouped on
/// follows the feed's own sort: the transaction date for "Recent trades", the disclosure
/// date for "Just disclosed", so the header always names the thing the reader sorted by.
enum FeedGrouping {

    struct Group: Identifiable {
        let id: Int
        let title: String
        let trades: [Trade]
    }

    /// - Parameters:
    ///   - trades: the feed slice to show, already in display order.
    ///   - sort: the active feed order — decides which date is grouped on.
    ///   - today: injectable for tests.
    static func groups(
        for trades: [Trade],
        sort: FeedSort,
        today: CalendarDate = .today()
    ) -> [Group] {
        guard !trades.isEmpty else { return [] }

        let dateOf: (Trade) -> CalendarDate = { trade in
            switch sort {
            case .recent: return trade.sortDate
            case .justDisclosed: return trade.disclosedDate
            }
        }

        // A leading "Past 7 days" bucket, then one bucket per calendar month. The recent
        // bucket earns its keep for "Just disclosed" (what was just filed); for "Recent
        // trades" the 45-day lag usually leaves it empty, and an empty bucket is dropped.
        let recentCutoffOrdinal = today.monthOrdinal
        var recent: [Trade] = []
        var byMonth: [Int: [Trade]] = [:]
        var monthOrder: [Int] = []

        for trade in trades {
            let date = dateOf(trade)
            let daysAgo = date.days(to: today)
            if (0...6).contains(daysAgo) {
                recent.append(trade)
            } else {
                let key = date.monthOrdinal
                if byMonth[key] == nil {
                    byMonth[key] = []
                    monthOrder.append(key)
                }
                byMonth[key]?.append(trade)
            }
        }

        var out: [Group] = []
        if !recent.isEmpty {
            out.append(Group(id: recentCutoffOrdinal + 1, title: "Past 7 days", trades: recent))
        }
        for key in monthOrder {
            guard let rows = byMonth[key], let first = rows.first else { continue }
            let date = dateOf(first)
            out.append(Group(id: key, title: date.monthLabel, trades: rows))
        }
        return out
    }
}
