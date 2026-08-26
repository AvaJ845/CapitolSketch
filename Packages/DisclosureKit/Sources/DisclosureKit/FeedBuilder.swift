import Foundation

/// Assembles a feed from parsed filings, and folds a newer batch into an older one.
///
/// Shared deliberately between the build-time CLI and the app: the same filing has to
/// produce the same record in both places, or a trade already in the shipped snapshot
/// would appear a second time the moment a device refreshed.
public enum FeedBuilder {

    /// Newest transaction first, with a stable tiebreak so two runs order identically.
    ///
    /// Sorting is on `sortDate`, not `txDate`: a filing with a mistyped transaction year
    /// would otherwise pin one row to the top of every list forever.
    public static func sorted(_ trades: [Trade]) -> [Trade] {
        trades.sorted {
            $0.sortDate == $1.sortDate ? $0.id > $1.id : $0.sortDate > $1.sortDate
        }
    }

    public static func make(
        trades: [Trade],
        members: [Member],
        stats: ParseStats,
        indexYears: [Int],
        nameToMemberID: [String: String] = [:],
        generatedAt: Date = Date()
    ) -> TradeFeed {
        let rows = sorted(deduplicate(trades))
        var stats = stats
        stats.tradesParsed = rows.count
        return TradeFeed(
            generatedAt: generatedAt,
            indexYears: indexYears.sorted(),
            source: TradeFeed.houseClerkSource,
            chambersCovered: [.house],
            members: members.sorted { $0.name < $1.name },
            trades: rows,
            stats: stats,
            nameToMemberID: nameToMemberID
        )
    }

    /// Folds freshly parsed filings into an existing feed.
    ///
    /// The seed's rows are listed first so that when an amended filing restates a trade
    /// already disclosed, de-duplication keeps the original record and its filing ID
    /// rather than swapping in the amendment's.
    public static func merge(
        seed: TradeFeed,
        newTrades: [Trade],
        newMembers: [Member],
        newStats: ParseStats = ParseStats(),
        generatedAt: Date = Date()
    ) -> TradeFeed {
        var members: [String: Member] = [:]
        for m in seed.members { members[m.id] = m }
        // A member already in the seed keeps the seed's record, which carries the
        // Bioguide ID resolved against the full crosswalk at build time.
        for m in newMembers where members[m.id] == nil { members[m.id] = m }

        var names = seed.nameToMemberID
        for m in newMembers where names[m.name] == nil { names[m.name] = m.id }

        // Coverage accumulates. A scanned filing read on device is still a gap in the
        // data the reader is looking at, so it has to keep showing up in the count.
        var stats = seed.stats
        stats.filingsProcessed += newStats.filingsProcessed
        stats.filingsWithoutText += newStats.filingsWithoutText
        stats.filingsYieldingNoTrades += newStats.filingsYieldingNoTrades
        stats.filingsFailedToFetch += newStats.filingsFailedToFetch

        return make(
            trades: seed.trades + newTrades,
            members: Array(members.values),
            stats: stats,
            indexYears: seed.indexYears,
            nameToMemberID: names,
            generatedAt: generatedAt
        )
    }
}

extension TradeFeed {
    public static let houseClerkSource =
        "US House Clerk — Periodic Transaction Reports (disclosures-clerk.house.gov)"
}
