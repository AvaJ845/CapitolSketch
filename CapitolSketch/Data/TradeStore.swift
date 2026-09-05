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
    /// True until the bundled snapshot has been read off disk. The 4.6 MB feed is decoded
    /// on a background task, so the first frame renders a loading state rather than
    /// blocking the main actor at launch.
    private(set) var isLoading = true
    private(set) var lastError: String?
    /// What the last refresh actually did, in words, for display.
    private(set) var lastRefreshSummary: String?

    /// When the feed was last brought up to date this session. A foreground is not an
    /// instruction to re-hit the Clerk; an explicit pull-to-refresh or Settings tap is.
    private var lastRefreshAt: Date?
    private static let minimumRefreshInterval: TimeInterval = 30 * 60

    var members: [Member] { feed.members }
    var stats: ParseStats { feed.stats }

    /// When the data in hand was assembled. Every screen that shows filings shows this.
    var generatedAt: Date? {
        feed.generatedAt == .distantPast ? nil : feed.generatedAt
    }

    /// When a refresh last genuinely reached the House Clerk (a 200 on the index or a
    /// legitimate 304). Nil until the first successful contact. Surfaced separately from
    /// `generatedAt` so a silent index freeze — an outage, or a forced bad response —
    /// does not hide behind the normal 45-day disclosure lag.
    private(set) var lastClerkContact: Date? = SharedContainer.lastClerkContact

    /// True when the last successful Clerk contact is more than a week old, or there has
    /// never been one and the data itself is over a week old. The masthead and Settings
    /// say so, calmly, when this is true.
    var clerkContactIsStale: Bool {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        if let last = lastClerkContact { return last < cutoff }
        if let generatedAt { return generatedAt < cutoff }
        return false
    }

    init() {}

    // MARK: - Loading

    /// Reads the feed off disk, then makes the shipped snapshot visible to the widget.
    /// Called once from the app's root `.task`.
    func start() async {
        await load()
        seedSharedContainerIfNeeded()
        // The widget may have reached the Clerk since this process last ran.
        lastClerkContact = SharedContainer.lastClerkContact
    }

    /// Loads the feed, preferring whichever copy was generated most recently — a refresh
    /// the app already merged, or the snapshot it shipped with.
    ///
    /// The file read and JSON decode run off the main actor so launch is not blocked by
    /// the size of the snapshot.
    private func load() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.discardCacheIfBuildChanged()
            return Self.newestFeedOnDisk()
        }.value

        isLoading = false
        guard let loaded else {
            feed = .empty
            lastError = "The bundled filings could not be read."
            return
        }
        feed = loaded
    }

    /// A new app build ships a new bundled snapshot that may carry parser or data fixes.
    /// Its `generatedAt` predates any on-device refresh, so newest-wins would keep serving
    /// the stale cache. On a build change, drop the cache: the next refresh rebuilds it
    /// from the fresh snapshot.
    ///
    /// This runs in a detached task and can race a widget timeline that is writing
    /// `feed.json` at the same moment. Both writers are first-party and every write is
    /// atomic, so the worst case is one cycle with a missing or superseded feed file,
    /// which the next refresh (app or widget) rebuilds — there is no partial-file or
    /// cross-tenant exposure (an App Group is scoped to this app and its extension).
    nonisolated private static func discardCacheIfBuildChanged() {
        let defaults = SharedContainer.defaults
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        guard defaults.string(forKey: SharedContainer.Key.seedBuild) != build else { return }
        defaults.set(build, forKey: SharedContainer.Key.seedBuild)
        for url in [SharedContainer.feedFile, SharedContainer.localFeedFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func newestFeedOnDisk() -> TradeFeed? {
        [
            SharedContainer.feedFile,
            SharedContainer.localFeedFile,
            Bundle.main.url(forResource: "seed-filings", withExtension: "json"),
        ]
        .compactMap { $0 }
        .compactMap { decode(contentsOf: $0) }
        .filter { $0.schemaVersion == TradeFeed.currentSchemaVersion }
        .max(by: { $0.generatedAt < $1.generatedAt })
    }

    // MARK: - Refreshing

    /// Reads the Clerk's index and parses any filings the snapshot has never seen.
    ///
    /// The watchlist takes no part in this. Which index is read, which PDFs are fetched
    /// and the order they are fetched in depend only on what the snapshot already holds
    /// and on today's date, so every device issues the same requests.
    /// - Parameter force: `true` for an explicit user action (pull-to-refresh, the
    ///   Settings button). `false` — the default, used by the scene-activation hook —
    ///   is a no-op if the feed was refreshed within the last half hour, so flipping
    ///   between apps does not turn into a burst of requests to a government file server.
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let last = lastRefreshAt,
           Date().timeIntervalSince(last) < Self.minimumRefreshInterval {
            return
        }
        isRefreshing = true
        lastError = nil
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
        }

        let current = feed
        let outcome = await IncrementalRefresher.refresh(
            seed: current,
            cacheDirectory: SharedContainer.directory
        )

        lastRefreshSummary = outcome.report.summary
        if let first = outcome.report.failures.first, outcome.report.addedTrades == 0 {
            lastError = first
        }

        // Liveness is tracked apart from data age: stamp "last reached the Clerk" only
        // on a genuine good exchange (200 / legitimate 304), never on an error, an
        // offline run, or an over-cap response.
        if outcome.report.reachedClerk {
            SharedContainer.noteClerkContact()
            lastClerkContact = SharedContainer.lastClerkContact
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

    /// Filings touching any watched ticker or any followed member.
    ///
    /// This is navigation, not personalisation: each row is the same public record every
    /// other reader sees, shown in full. Nothing here rewrites, ranks or annotates a
    /// filing according to what the reader happens to hold. The relevance test itself
    /// lives in one place — `Trade.isWatchlistRelevant`.
    func trades(matching watchlist: Set<String>, followedBy followed: Set<String> = []) -> [Trade] {
        guard !watchlist.isEmpty || !followed.isEmpty else { return [] }
        let upper = Set(watchlist.map { $0.uppercased() })
        return trades.filter {
            $0.isWatchlistRelevant(watchedTickers: upper, followedMembers: followed)
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

    /// Decodes a feed file. The inputs are the app's own bundle resource and the App
    /// Group cache written only by this app and its widget (both first-party, the group
    /// is scoped to them) — not attacker-controlled — so there is no untrusted-input
    /// hardening here beyond the schema-version check the callers apply.
    nonisolated static func decode(contentsOf url: URL) -> TradeFeed? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let (_, decoder) = TradeFeed.makeCoder()
        return try? decoder.decode(TradeFeed.self, from: data)
    }
}
