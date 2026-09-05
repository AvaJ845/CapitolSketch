import AppIntents
import WidgetKit
import DisclosureKit

// App Shortcuts and the intents behind them. These live in the app target only — an
// `AppShortcutsProvider` belongs to exactly one target, and the widget extension has no
// reason to carry the watchlist-mutating intents.
//
// Everything here is on-device. No parameter of any intent causes a network request or
// leaves the phone. The watchlist writes go straight through the App Group defaults
// (`SharedContainer`), the same store the app and widget already read; nothing is
// transmitted and no fetch varies with it.

// MARK: - Watchlist intents

struct AddTickerToWatchlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Ticker to Watchlist"
    static let description = IntentDescription(
        "Adds a ticker symbol to your on-device watchlist. The list never leaves this phone."
    )
    /// Pure local write — no need to bring the app forward.
    static let openAppWhenRun = false

    @Parameter(title: "Ticker", requestValueDialog: "Which ticker symbol?")
    var ticker: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let symbol = SharedContainer.addTicker(ticker) else {
            throw $ticker.needsValueError("That doesn't look like a ticker symbol.")
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Added \(symbol) to your watchlist.")
    }
}

struct FollowMemberIntent: AppIntent {
    static let title: LocalizedStringResource = "Follow a Member"
    static let description = IntentDescription(
        "Follows a House member, matched by name against the loaded filings, so a new disclosure from them alerts you. The list never leaves this phone."
    )
    /// Pure local write — no need to bring the app forward.
    static let openAppWhenRun = false

    @Parameter(title: "Member name", requestValueDialog: "Which House member?")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let resolved = SharedContainer.followMember(matching: name) else {
            throw $name.needsValueError("I couldn't match that to a House member in the loaded filings.")
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Following \(resolved). Alerts stay on this phone.")
    }
}

struct OpenWatchlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Watchlist"
    static let description = IntentDescription("Opens the Watchlist tab.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedContainer.defaults.set("watchlist", forKey: SharedContainer.Key.pendingRoute)
        return .result()
    }
}

struct CheckForNewFilingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Check for New Filings"
    static let description = IntentDescription(
        "Opens the app and asks the House Clerk for any filings published since the last check."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedContainer.defaults.set("refresh", forKey: SharedContainer.Key.pendingRoute)
        return .result()
    }
}

struct ShowTickerIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Ticker"
    static let description = IntentDescription("Opens every disclosed transaction in one ticker.")
    static let openAppWhenRun = true

    @Parameter(title: "Ticker", requestValueDialog: "Which ticker symbol?")
    var ticker: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let symbol = SharedContainer.normalizedTicker(ticker)
        guard !symbol.isEmpty else {
            throw $ticker.needsValueError("That doesn't look like a ticker symbol.")
        }
        SharedContainer.defaults.set("ticker:\(symbol)", forKey: SharedContainer.Key.pendingRoute)
        return .result()
    }
}

// MARK: - App Shortcuts

struct CapitolSketchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTickerToWatchlistIntent(),
            phrases: [
                "Add a ticker to \(.applicationName)",
                "Add a ticker to my \(.applicationName) watchlist",
            ],
            shortTitle: "Add Ticker",
            systemImageName: "bell.badge"
        )
        AppShortcut(
            intent: FollowMemberIntent(),
            phrases: [
                "Follow a member in \(.applicationName)",
                "Follow a House member with \(.applicationName)",
            ],
            shortTitle: "Follow Member",
            systemImageName: "bell.badge"
        )
        AppShortcut(
            intent: OpenWatchlistIntent(),
            phrases: [
                "Open my \(.applicationName) watchlist",
                "Show my \(.applicationName) watchlist",
            ],
            shortTitle: "Open Watchlist",
            systemImageName: "star"
        )
        AppShortcut(
            intent: CheckForNewFilingsIntent(),
            phrases: [
                "Check \(.applicationName) for new filings",
                "Refresh \(.applicationName)",
            ],
            shortTitle: "Check for New Filings",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: ShowTickerIntent(),
            phrases: [
                "Show a ticker in \(.applicationName)",
                "Look up a ticker on \(.applicationName)",
            ],
            shortTitle: "Show Ticker",
            systemImageName: "list.bullet"
        )
    }
}
