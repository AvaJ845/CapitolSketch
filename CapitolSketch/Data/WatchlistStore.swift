import Foundation
import Observation
import DisclosureKit

/// The user's watched tickers, plus the bookkeeping needed to tell what is new.
///
/// **This list never leaves the device.** It is not transmitted as a set, as a hash, as a
/// count, or one ticker at a time, and no request the app makes varies with it. That is a
/// deliberate legal position as much as a privacy one: the app publishes the same public
/// filings to every reader and merely decides locally when to tap someone on the
/// shoulder. Sending the list — or fetching content selected by it — would turn an
/// impersonal publication into individualised advice.
///
/// "New" is tracked by remembering which rows have already been surfaced rather than by
/// timestamp. Filings arrive in bursts and are routinely backdated, so a date cursor
/// would silently skip disclosures that landed out of order.
@MainActor
@Observable
final class WatchlistStore {

    private let defaults: UserDefaults

    private(set) var tickers: Set<String> = []
    private(set) var seenRowIDs: Set<String> = []

    /// The identifier scheme the current build writes. Bumped when `Trade.id` changed
    /// from a row position to a content hash.
    private static let rowIDScheme = "content-v1"
    /// True when `seenRowIDs` was loaded from an older identifier scheme and has to be
    /// rebased against the feed before "new since you last looked" can mean anything.
    private var needsRowIDRebase = false

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: SharedContainer.Key.notifyEnabled) }
    }

    /// Defaults to the shared container so the widget reads the same list without the
    /// list ever being copied anywhere else.
    init(defaults: UserDefaults = SharedContainer.defaults) {
        self.defaults = defaults
        tickers = Set(defaults.stringArray(forKey: SharedContainer.Key.tickers) ?? [])
        seenRowIDs = Set(defaults.stringArray(forKey: SharedContainer.Key.seenRowIDs) ?? [])
        notificationsEnabled = defaults.bool(forKey: SharedContainer.Key.notifyEnabled)

        let storedScheme = defaults.string(forKey: SharedContainer.Key.rowIDScheme)
        // A fresh install has no stored ids and nothing to rebase — just stamp the
        // scheme. An install carrying ids from the old scheme has to wait for the feed.
        needsRowIDRebase = storedScheme != Self.rowIDScheme && !seenRowIDs.isEmpty
        if seenRowIDs.isEmpty {
            defaults.set(Self.rowIDScheme, forKey: SharedContainer.Key.rowIDScheme)
        }
    }

    /// One-time fix-up after `Trade.id` changed schemes: treat every disclosure already
    /// in the feed as seen, exactly as a first-time watchlist setup does, so the switch
    /// does not fire an alert for every filing the reader had already been shown.
    func rebaseSeenRowIDsIfNeeded(against trades: [Trade]) {
        guard needsRowIDRebase, !trades.isEmpty else { return }
        seenRowIDs = Set(trades.map(\.id))
        needsRowIDRebase = false
        defaults.set(Self.rowIDScheme, forKey: SharedContainer.Key.rowIDScheme)
        persistSeen()
    }

    var sortedTickers: [String] { tickers.sorted() }
    var isEmpty: Bool { tickers.isEmpty }
    var count: Int { tickers.count }

    func contains(_ ticker: String) -> Bool {
        tickers.contains(Self.normalize(ticker))
    }

    /// Longest symbol the feed can hold is the parser's `[A-Z][A-Z0-9.\-]{0,6}`, so
    /// anything past a small margin is a paste accident, not a ticker.
    static let maxTickerLength = 12

    func add(_ ticker: String) {
        let t = Self.normalize(ticker)
        guard !t.isEmpty, t.count <= Self.maxTickerLength else { return }
        tickers.insert(t)
        persistTickers()
    }

    func remove(_ ticker: String) {
        tickers.remove(Self.normalize(ticker))
        persistTickers()
    }

    func toggle(_ ticker: String) {
        contains(ticker) ? remove(ticker) : add(ticker)
    }

    func removeAll() {
        tickers.removeAll()
        persistTickers()
    }

    private static func normalize(_ ticker: String) -> String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Watchlist matches that have not been surfaced yet, most recently disclosed first.
    ///
    /// This chooses *when to notify*. It does not choose what the reader then sees: the
    /// rows handed back are whole, unmodified public records.
    func unseenMatches(in trades: [Trade]) -> [Trade] {
        guard !tickers.isEmpty else { return [] }
        return trades
            .filter { trade in
                guard let s = trade.ticker?.uppercased(), tickers.contains(s) else { return false }
                return !seenRowIDs.contains(trade.id)
            }
            .sorted { $0.disclosedDate > $1.disclosedDate }
    }

    func markSeen(_ trades: [Trade]) {
        guard !trades.isEmpty else { return }
        seenRowIDs.formUnion(trades.map(\.id))
        persistSeen()
    }

    /// Called the first time a ticker is watched, so the reader is not buried in alerts
    /// about disclosures that were already public before they asked.
    func markAllSeen(in trades: [Trade]) {
        seenRowIDs.formUnion(trades.map(\.id))
        persistSeen()
    }

    private func persistTickers() {
        defaults.set(tickers.sorted(), forKey: SharedContainer.Key.tickers)
    }

    private func persistSeen() {
        // Bound the stored history so it cannot grow without limit. Each id begins with
        // its filing id, and House filing ids climb over time, so trimming to the
        // lexicographically highest keeps the most recent filings rather than an
        // arbitrary sample — which would let an old disclosure re-notify years later.
        if seenRowIDs.count > 20_000 {
            seenRowIDs = Set(seenRowIDs.sorted().suffix(10_000))
        }
        defaults.set(Array(seenRowIDs), forKey: SharedContainer.Key.seenRowIDs)
    }
}
