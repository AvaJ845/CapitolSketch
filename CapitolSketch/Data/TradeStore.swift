import Foundation
import Observation
import WidgetKit
import DisclosureKit

/// Loads the disclosure feed and derives everything the UI reads from it.
///
/// The app ships a snapshot in its bundle, so first launch is instant and works offline.
/// Refreshing asks the House Clerk's own public index which filings have appeared since
/// and reads only those — the same index and the same PDFs for every reader. There is no
/// server in between and nothing about the reader is sent anywhere.
@MainActor
@Observable
final class TradeStore {

    private(set) var feed: TradeFeed = .empty {
        didSet { trades = feed.trades }
    }

    /// Newest first. The feed is stored sorted, so this is not re-sorted per view.
    private(set) var trades: [Trade] = []

    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// What the last refresh actually did, in words, for display.
    private(set) var lastRefreshSummary: String?

    var members: [Member] { feed.members }
    var stats: ParseStats { feed.stats }

    /// When the data in hand was assembled. Every screen that shows filings shows this.
    var generatedAt: Date? {
        feed.generatedAt == .distantPast ? nil : feed.generatedAt
    }

    init() {
        load()
    }

    // MARK: - Loading

    /// Prefers whichever copy was generated most recently: a refresh the app has already
    /// merged, or the snapshot it shipped with. A build newer than the cache wins, which
    /// is what makes shipping an updated seed work.
    private func load() {
        let candidates = [
            SharedContainer.feedFile,
            SharedContainer.localFeedFile,
            Bundle.main.url(forResource: "seed-filings", withExtension: "json"),
        ]
        .compactMap { $0 }
        .compactMap { Self.decode(contentsOf: $0) }
        .filter { $0.schemaVersion == TradeFeed.currentSchemaVersion }

        guard let newest = candidates.max(by: { $0.generatedAt < $1.generatedAt }) else {
            feed = .empty
            lastError = "The bundled filings could not be read."
            return
        }
        feed = newest
    }

    // MARK: - Refreshing

    /// Reads the Clerk's index and parses any filings the snapshot has never seen.
    ///
    /// The watchlist takes no part in this. Which index is read, which PDFs are fetched
    /// and the order they are fetched in depend only on what the snapshot already holds
    /// and on today's date, so every device issues the same requests.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        let current = feed
        let outcome = await IncrementalRefresher.refresh(
            seed: current,
            cacheDirectory: SharedContainer.directory
        )

        lastRefreshSummary = outcome.report.summary
        if let first = outcome.report.failures.first, outcome.report.addedTrades == 0 {
            lastError = first
        }

        guard let updated = outcome.feed else { return }
        feed = updated
        persist(updated)
        // The widget reads the shared copy, so it is reloaded only when there is
        // genuinely something new to show.
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persist(_ feed: TradeFeed) {
        let (encoder, _) = TradeFeed.makeCoder()
        guard let data = try? encoder.encode(feed) else { return }
        let destination = SharedContainer.feedFile ?? SharedContainer.localFeedFile
        try? data.write(to: destination, options: .atomic)
    }

    /// Makes the shipped snapshot visible to the widget on first launch, so a widget
    /// added before any refresh still has real filings to show.
    func seedSharedContainerIfNeeded() {
        guard let shared = SharedContainer.feedFile else { return }
        let existing = Self.decode(contentsOf: shared)
        guard existing == nil || existing!.generatedAt < feed.generatedAt else { return }
        persist(feed)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Derived views of the data

    func trades(forMember id: String) -> [Trade] {
        trades.filter { $0.memberID == id }
    }

    func trades(forTicker ticker: String) -> [Trade] {
        let t = ticker.uppercased()
        return trades.filter { $0.ticker?.uppercased() == t }
    }

    func member(id: String) -> Member? {
        members.first { $0.id == id }
    }

    /// Every ticker in the feed, most disclosed first — powers watchlist search.
    var knownTickers: [(ticker: String, count: Int)] {
        Dictionary(grouping: trades.compactMap(\.ticker), by: { $0.uppercased() })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count == $1.count ? $0.ticker < $1.ticker : $0.count > $1.count }
    }

    /// Filings touching any watched ticker.
    ///
    /// This is navigation, not personalisation: each row is the same public record every
    /// other reader sees, shown in full. Nothing here rewrites, ranks or annotates a
    /// filing according to what the reader happens to hold.
    func trades(matching watchlist: Set<String>) -> [Trade] {
        guard !watchlist.isEmpty else { return [] }
        let upper = Set(watchlist.map { $0.uppercased() })
        return trades.filter { t in
            guard let s = t.ticker?.uppercased() else { return false }
            return upper.contains(s)
        }
    }

    /// Members ordered by how much they have disclosed, for the Members tab.
    func membersByActivity() -> [(member: Member, count: Int)] {
        let counts = Dictionary(grouping: trades, by: \.memberID).mapValues(\.count)
        return members
            .map { ($0, counts[$0.id] ?? 0) }
            .sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
    }

    // MARK: - Decoding

    static func decode(contentsOf url: URL) -> TradeFeed? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let (_, decoder) = TradeFeed.makeCoder()
        return try? decoder.decode(TradeFeed.self, from: data)
    }
}
