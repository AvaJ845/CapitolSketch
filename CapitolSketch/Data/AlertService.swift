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
            content.title = "\(trades.count) new disclosures on your watchlist"
            // Name the tickers the reader supplied; fall back to the members they follow
            // when a hit came from a follow and carries no ticker. Either way, no
            // commentary — nothing a reader could mistake for a recommendation.
            let symbols = Set(trades.compactMap(\.ticker)).sorted()
            let labels = symbols.isEmpty
                ? Set(trades.map(\.memberName)).sorted()
                : symbols
            content.body = labels.prefix(4).joined(separator: ", ")
                + (labels.count > 4 ? " and \(labels.count - 4) more" : "")
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

    /// A weekly local notification restating the snapshot's own headline — the same
    /// plain-language fact `StandoutsView` leads with, `Standouts.headline(in:)`, never
    /// anything computed just for this. No server, no `BGTaskScheduler`: the trigger is a
    /// fixed weekly calendar alarm, and the *content* is only ever as fresh as the last
    /// time this device recomputed it — the same "no fetch here" honesty every other
    /// on-device-only feature in this app already carries. Called every time the feed's
    /// headline changes, so the next scheduled firing reflects whatever the reader's
    /// device last saw, not what it saw the day this was turned on.
    ///
    /// A fixed identifier (`weeklyDigest`) means adding a request replaces the pending
    /// one rather than stacking a second alarm.
    static func scheduleWeeklyDigest(headline: String?) async {
        guard let headline, await authorizationStatus() == .authorized else {
            await cancelWeeklyDigest()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "This week in disclosures"
        content.body = headline
        content.sound = .default

        // Monday, 9:00 AM local time, repeating. `DateComponents.weekday` is 1-indexed
        // from Sunday, so 2 is Monday.
        var when = DateComponents()
        when.weekday = 2
        when.hour = 9
        when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)

        let request = UNNotificationRequest(
            identifier: "weeklyDigest", content: content, trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelWeeklyDigest() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["weeklyDigest"])
    }
}
