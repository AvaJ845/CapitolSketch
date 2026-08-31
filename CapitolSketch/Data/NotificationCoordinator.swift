import Foundation
import UserNotifications
import Observation

/// Bridges a tapped watchlist notification back to a destination in the app.
///
/// The notification payload carries only the filing's row ID (or nothing, for the
/// digest). This turns that into observable routing state the root view can act on, so
/// tapping an alert lands on the same `DisclosureDetailView` a reader would have browsed
/// to — not just "the app, on whatever tab was last open".
@MainActor
@Observable
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {

    /// Set when a single-filing alert is tapped; the root view routes to that filing.
    var pendingRowID: String?
    /// Set when the multi-filing digest is tapped; the root view shows the Watchlist tab.
    var pendingDigest = false

    func clear() {
        pendingRowID = nil
        pendingDigest = false
    }

    private func apply(rowID: String?) {
        if let rowID {
            pendingRowID = rowID
        } else {
            pendingDigest = true
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rowID = response.notification.request.content.userInfo["rowID"] as? String
        Task { @MainActor [weak self] in self?.apply(rowID: rowID) }
        completionHandler()
    }
}
