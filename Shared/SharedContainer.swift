import Foundation
import DisclosureKit

/// Files and preferences the app and the widget both read.
///
/// The suite is an App Group so a widget timeline can see the same feed and the same
/// ticker list the app is looking at. Keys are deliberately product-name-free: a rename
/// must not force a data migration.
enum SharedContainer {

    static let appGroupID = "group.com.avaresearch.capitolsketch"

    enum Key {
        static let tickers = "watchlistTickers"
        /// Bioguide-or-slug member IDs the reader has chosen to follow for filing
        /// alerts. Like `tickers`, this never leaves the device: it is not sent as a
        /// set, a hash, a count or one item, and no network request varies with it.
        /// Stored as a sorted `[String]`, read only by post-download code
        /// (`WatchlistStore`, the alert scan, the widget entry builder).
        static let followedMembers = "followedMembers"
        static let seenRowIDs = "seenRowIDs"
        static let notifyEnabled = "notificationsEnabled"
        static let appearance = "appearance"
        /// The app build the on-device feed cache was last written by. A build change
        /// means a new bundled snapshot that may carry parser or data fixes, so the
        /// cache is discarded rather than allowed to outrank it on timestamp alone.
        static let seedBuild = "seedBuildVersion"
        /// The scheme `seenRowIDs` were recorded under. Row identifiers moved from
        /// "<filing>-<row position>" to a content-derived hash; a stored value from the
        /// old scheme can never match the new feed, so it is rebased rather than left to
        /// re-surface every watched filing at once.
        static let rowIDScheme = "rowIDScheme"
        /// The last time a refresh genuinely reached the House Clerk with a good
        /// response (a 200 on the index, or a legitimate 304), as an ISO-8601 string.
        /// Written by the app and the widget, and only on real contact — never on an
        /// error, an offline run, or an over-cap response. Read to tell a silent index
        /// freeze apart from the normal 45-day disclosure lag.
        static let lastClerkContact = "lastClerkContact"
        /// A one-shot instruction left by an App Shortcut for the app to act on next
        /// time it is frontmost: `"watchlist"`, `"refresh"`, or `"ticker:SYMBOL"`. Set
        /// by an intent, consumed and cleared by `RootView`. Device-local; never sent.
        static let pendingRoute = "pendingIntentRoute"
    }

    // MARK: - Watchlist writes shared with a not-running app and the widget

    /// Longest symbol the feed can hold is the parser's `[A-Z][A-Z0-9.\-]{0,6}`, so
    /// anything past a small margin is a paste accident, not a ticker.
    static let maxTickerLength = 12

    static func normalizedTicker(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Adds a ticker to the shared watchlist, writing straight through the App Group
    /// defaults so a headless App Shortcut, a not-running app and the widget all see it.
    /// Returns the normalized symbol, or `nil` if it was not a plausible ticker.
    ///
    /// This is a device-local write. Nothing is transmitted, and no fetch varies with
    /// the list — see `WatchlistStore`.
    @discardableResult
    static func addTicker(_ raw: String) -> String? {
        let t = normalizedTicker(raw)
        guard !t.isEmpty, t.count <= maxTickerLength else { return nil }
        var current = defaults.stringArray(forKey: Key.tickers) ?? []
        let wasEmpty = current.isEmpty
        if !current.contains(t) {
            current.append(t)
            current.sort()
            defaults.set(current, forKey: Key.tickers)
        }
        // First-ever watched ticker: treat everything already public as seen, exactly as
        // the in-app first-time setup does, so opening the app does not fire a backlog of
        // alerts about disclosures that were public before the reader asked.
        if wasEmpty, (defaults.stringArray(forKey: Key.seenRowIDs) ?? []).isEmpty,
           let feed = currentFeed() {
            defaults.set(feed.trades.map(\.id), forKey: Key.seenRowIDs)
        }
        return t
    }

    /// Follows a House member by name, matched against the members in the last-downloaded
    /// feed (exact, then prefix, then substring, case-insensitive). Writes straight
    /// through the App Group defaults so a headless App Shortcut and a not-running app
    /// both see it. Returns the resolved member name, or `nil` if no match.
    ///
    /// Device-local write, same contract as `addTicker`: the follow list is never
    /// transmitted and no fetch varies with it — see `WatchlistStore`.
    @discardableResult
    static func followMember(matching rawName: String) -> String? {
        guard let feed = currentFeed(),
              let member = matchMemberName(rawName, in: feed.members)
        else { return nil }

        var current = defaults.stringArray(forKey: Key.followedMembers) ?? []
        let wasEmpty = current.isEmpty
            && (defaults.stringArray(forKey: Key.tickers) ?? []).isEmpty
        if !current.contains(member.id) {
            current.append(member.id)
            current.sort()
            defaults.set(current, forKey: Key.followedMembers)
        }
        // First-ever watch or follow: treat everything already public as seen, exactly as
        // the in-app first-time setup does, so opening the app does not fire a backlog.
        if wasEmpty, (defaults.stringArray(forKey: Key.seenRowIDs) ?? []).isEmpty {
            defaults.set(feed.trades.map(\.id), forKey: Key.seenRowIDs)
        }
        return member.name
    }

    /// Records that a refresh reached the Clerk with a good response, now.
    static func noteClerkContact(at date: Date = Date()) {
        defaults.set(ISO8601DateFormatter().string(from: date), forKey: Key.lastClerkContact)
    }

    /// When a refresh last reached the Clerk with a good response, if ever.
    static var lastClerkContact: Date? {
        guard let raw = defaults.string(forKey: Key.lastClerkContact) else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// App Group suite when the entitlement is honoured; otherwise the process defaults,
    /// so the app still works in a simulator that has not been signed.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Shared feed, written by the app (and by the widget after an incremental refresh).
    static var feedFile: URL? {
        directory?.appendingPathComponent("feed.json")
    }

    /// Process-local fallback used when the App Group container is unavailable.
    static var localFeedFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("feed.json")
    }

    /// The feed as last written to the App Group (or the process-local fallback). Used
    /// by headless code — the widget timeline and App Shortcuts — that has no live
    /// `TradeStore`. Returns `nil` before the app has ever seeded the shared copy.
    static func currentFeed() -> TradeFeed? {
        let (_, decoder) = TradeFeed.makeCoder()
        for url in [feedFile, localFeedFile].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let feed = try? decoder.decode(TradeFeed.self, from: data),
                  feed.schemaVersion == TradeFeed.currentSchemaVersion
            else { continue }
            return feed
        }
        return nil
    }
}
