import Foundation

/// Files and preferences the app and the widget both read.
///
/// The suite is an App Group so a widget timeline can see the same feed and the same
/// ticker list the app is looking at. Keys are deliberately product-name-free: a rename
/// must not force a data migration.
enum SharedContainer {

    static let appGroupID = "group.com.avaresearch.capitolsketch"

    enum Key {
        static let tickers = "watchlistTickers"
        static let seenRowIDs = "seenRowIDs"
        static let notifyEnabled = "notificationsEnabled"
        static let appearance = "appearance"
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
}
