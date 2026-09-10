import Foundation
import Testing
import DisclosureKit
@testable import CapitolSketch

/// `WatchlistStore` decides *when to surface* a filing — never what it says. These pin
/// the ticker/follow bookkeeping and the "new since you last looked" logic, including
/// the first-watch guard that keeps a new user from being buried in a backlog.
@MainActor
@Suite("Watchlist store")
struct WatchlistStoreTests {

    @Test("Tickers are normalised to upper case and de-duplicated")
    func normalise() {
        let w = Build.watchlist()
        w.add(" nvda ")
        w.add("NVDA")
        #expect(w.tickers == ["NVDA"])
        #expect(w.contains("nvda"))
    }

    @Test("A paste accident longer than the max ticker length is rejected")
    func rejectsOverlongSymbol() {
        let w = Build.watchlist()
        w.add(String(repeating: "A", count: WatchlistStore.maxTickerLength + 1))
        #expect(w.tickers.isEmpty)
    }

    @Test("isEmpty is true only with no watched ticker and no followed member")
    func isEmpty() {
        let w = Build.watchlist()
        #expect(w.isEmpty)
        w.follow("M000001")
        #expect(!w.isEmpty)
        w.unfollow("M000001")
        #expect(w.isEmpty)
    }

    @Test("unseenMatches surfaces a watched ticker and a followed member, newest disclosure first")
    func unseenMatches() {
        let w = Build.watchlist()
        w.add("NVDA")
        w.follow("M000002")

        let hitTicker = Build.trade(id: "nv", memberID: "M000009", ticker: "NVDA",
                                    disclosed: CalendarDate("2026-06-01"))
        let hitMember = Build.trade(id: "mem", memberID: "M000002", ticker: "ZZZZ",
                                    disclosed: CalendarDate("2026-06-10"))
        let miss = Build.trade(id: "no", memberID: "M000009", ticker: "AAPL",
                               disclosed: CalendarDate("2026-06-20"))

        let unseen = w.unseenMatches(in: [hitTicker, hitMember, miss])
        #expect(unseen.map(\.id) == ["mem", "nv"])
    }

    @Test("A row already marked seen is not surfaced again")
    func seenRowsExcluded() {
        let w = Build.watchlist()
        w.add("NVDA")
        let a = Build.trade(id: "a", ticker: "NVDA", disclosed: CalendarDate("2026-06-01"))
        let b = Build.trade(id: "b", ticker: "NVDA", disclosed: CalendarDate("2026-06-05"))
        w.markSeen([a])
        #expect(w.unseenMatches(in: [a, b]).map(\.id) == ["b"])
    }

    @Test("The first watch marks the existing backlog seen so it does not all alert at once")
    func firstWatchGuard() {
        let w = Build.watchlist()
        let backlog = [
            Build.trade(id: "old1", ticker: "NVDA"),
            Build.trade(id: "old2", ticker: "NVDA"),
        ]
        w.toggle("NVDA", markingSeenIn: backlog)
        #expect(w.contains("NVDA"))
        #expect(w.unseenMatches(in: backlog).isEmpty)

        // A filing that lands *after* the first watch still surfaces.
        let fresh = Build.trade(id: "new", ticker: "NVDA", disclosed: CalendarDate("2026-12-01"))
        #expect(w.unseenMatches(in: backlog + [fresh]).map(\.id) == ["new"])
    }

    @Test("A second watch does not re-trigger the backlog guard")
    func secondWatchNoGuard() {
        let w = Build.watchlist()
        w.toggle("NVDA", markingSeenIn: [])
        let existing = Build.trade(id: "aapl", ticker: "AAPL")
        w.toggle("AAPL", markingSeenIn: [existing])
        // The guard only fires on the very first watch/follow, so this AAPL row stays new.
        #expect(w.unseenMatches(in: [existing]).map(\.id) == ["aapl"])
    }

    @Test("Watched tickers and follows persist through the shared defaults")
    func persistence() {
        let suite = "test.watchlist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = WatchlistStore(defaults: defaults)
        first.add("NVDA")
        first.follow("M000007")

        let reloaded = WatchlistStore(defaults: defaults)
        #expect(reloaded.tickers == ["NVDA"])
        #expect(reloaded.followedMemberIDs == ["M000007"])
    }
}
