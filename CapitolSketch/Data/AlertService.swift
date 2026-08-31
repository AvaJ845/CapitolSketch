import Foundation
import UserNotifications
import DisclosureKit

/// Local notifications for watchlist hits.
///
/// The trigger is personal; the content is not. Which reader gets tapped on the shoulder
/// depends on the ticker list held on their device, but what they are then shown is the
/// filing exactly as published — the same member, direction, asset, bracket and dates
/// that every other reader of that filing sees. Nothing here interprets the filing
/// against the reader's holdings, ranks it for them, or suggests what to do about it.
///
/// Disclosures are already weeks old when they become public, so there is nothing a push
/// server could add. Everything below runs on the device and reaches no network.
enum AlertService {

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Posts one notification for a single filing, or a plain count when several land.
    ///
    /// The single-filing case restates the record and nothing else. The digest case names
    /// the tickers, which the reader supplied, and adds no commentary — deliberately, so
    /// that neither form contains anything a reader could mistake for a recommendation.
    static func notify(about trades: [Trade]) async {
        guard !trades.isEmpty else { return }
        guard await authorizationStatus() == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.badge = NSNumber(value: trades.count)

        // A stable identifier per filing (and one shared id for the digest) so that a
        // re-check before the reader opens the Watchlist tab replaces the pending
        // notification instead of stacking a fresh copy in Notification Center.
        let identifier: String

        if trades.count == 1, let only = trades.first {
            content.title = "\(only.memberName) \(only.txType.verb.lowercased()) \(only.displaySymbol)"
            // The bracket and the gap, both stated as the form states them.
            content.body = "\(only.amount.label) · \(only.disclosureGapPhrase)"
            content.userInfo = ["rowID": only.id]
            identifier = "watchlist-\(only.id)"
        } else {
            let symbols = Set(trades.compactMap(\.ticker)).sorted()
            content.title = "\(trades.count) new disclosures on your watchlist"
            content.body = symbols.prefix(4).joined(separator: ", ")
                + (symbols.count > 4 ? " and \(symbols.count - 4) more" : "")
            identifier = "watchlist-digest"
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func clearBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
