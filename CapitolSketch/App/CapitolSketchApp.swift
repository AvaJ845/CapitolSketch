import SwiftUI
import UserNotifications
import DisclosureKit

@main
struct CapitolSketchApp: App {
    @State private var store = TradeStore()
    @State private var watchlist = WatchlistStore()
    @State private var appearance = AppearanceStore()
    @State private var notifications = NotificationCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(watchlist)
                .environment(appearance)
                .environment(notifications)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Ink.accent)
                .task {
                    UNUserNotificationCenter.current().delegate = notifications
                    await store.start()
                }
        }
    }
}

struct RootView: View {
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: TabID = .feed
    @State private var routedTrade: Trade?

    /// Not named `Tab` so it doesn't shadow SwiftUI's `Tab` view.
    enum TabID: Hashable { case feed, watchlist, members, about }

    private var watchlistBadge: Int {
        watchlist.unseenMatches(in: store.trades).count
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Trades", systemImage: "list.bullet.rectangle", value: TabID.feed) {
                FeedView()
            }

            Tab("Watchlist", systemImage: "star", value: TabID.watchlist) {
                WatchlistView()
            }
            .badge(watchlistBadge)

            Tab("Members", systemImage: "person.3", value: TabID.members) {
                MembersView()
            }

            Tab("Settings", systemImage: "gearshape", value: TabID.about) {
                AboutView()
            }
        }
        .tint(Ink.accent)
        .sheet(item: $routedTrade) { trade in
            NavigationStack {
                DisclosureDetailView(trade: trade)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { routedTrade = nil }
                        }
                    }
            }
            .environment(watchlist)
            .tint(Ink.accent)
        }
        .task { applyLaunchArguments() }
        .onOpenURL { handle(url: $0) }
        .onChange(of: notifications.pendingRowID) { _, id in routeToFiling(id) }
        .onChange(of: notifications.pendingDigest) { _, digest in
            if digest {
                selection = .watchlist
                notifications.clear()
            }
        }
        .onChange(of: store.isLoading) { _, loading in
            guard !loading else { return }
            // The feed loads off the main actor, so anything that needs trades — a
            // pending notification/widget tap, the first watchlist alert check, the
            // simulator seed — waits until it is in hand.
            seedWatchlistIfRequested()
            routeToFiling(notifications.pendingRowID)
            Task { await checkForWatchlistAlerts() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await AlertService.clearBadge()
                    await store.refresh()
                    await checkForWatchlistAlerts()
                }
            }
        }
    }

    private func handle(url: URL) {
        switch url.host {
        case "watchlist": selection = .watchlist
        case "members": selection = .members
        case "settings", "about": selection = .about
        case "filing":
            let id = url.pathComponents.last { $0 != "/" }
            routeToFiling(id)
        default: selection = .feed
        }
    }

    /// Opens a filing by row ID once the feed is available. Held pending if it is not.
    private func routeToFiling(_ id: String?) {
        guard let id else { return }
        guard let trade = store.trades.first(where: { $0.id == id }) else {
            // Feed still loading, or the row is not in this snapshot. Keep the pending
            // ID so `isLoading` finishing can retry; drop it if the feed is loaded.
            if !store.isLoading { notifications.clear() }
            return
        }
        routedTrade = trade
        notifications.clear()
    }

    /// Simulator verification: `simctl launch … -tab-watchlist` / `-tab-settings`.
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-tab-watchlist") { selection = .watchlist }
        else if args.contains("-tab-settings") { selection = .about }
        else if args.contains("-tab-members") { selection = .members }
        else if args.contains("-tab-feed") { selection = .feed }
    }

    /// `-seed-watchlist` fills the watchlist for screenshots. Runs after the feed loads
    /// so the seeded matches are marked seen instead of firing a wall of alerts.
    private func seedWatchlistIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-watchlist"),
              watchlist.isEmpty else { return }
        for ticker in ["NVDA", "AAPL", "MSFT", "BE"] { watchlist.add(ticker) }
        watchlist.markAllSeen(in: store.trades)
    }

    /// Notifies about watchlist hits the user hasn't seen. The Watchlist tab is what
    /// marks them seen, so opening it is what dismisses the alert state.
    private func checkForWatchlistAlerts() async {
        guard watchlist.notificationsEnabled else { return }
        let unseen = watchlist.unseenMatches(in: store.trades)
        guard !unseen.isEmpty else { return }
        await AlertService.notify(about: unseen)
    }
}
