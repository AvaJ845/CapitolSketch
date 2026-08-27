import SwiftUI
import DisclosureKit

@main
struct CapitolSketchApp: App {
    @State private var store = TradeStore()
    @State private var watchlist = WatchlistStore()
    @State private var appearance = AppearanceStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(watchlist)
                .environment(appearance)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Ink.accent)
                .task { store.seedSharedContainerIfNeeded() }
        }
    }
}

struct RootView: View {
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: TabID = .feed

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
        .task {
            applyLaunchTabIfNeeded()
            await checkForWatchlistAlerts()
        }
        .onOpenURL { url in
            switch url.host {
            case "watchlist": selection = .watchlist
            case "members": selection = .members
            case "settings", "about": selection = .about
            default: selection = .feed
            }
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

    /// Simulator verification: `simctl launch … -tab-watchlist` / `-tab-settings`.
    private func applyLaunchTabIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-seed-watchlist") {
            for ticker in ["NVDA", "AAPL", "MSFT", "BE"] { watchlist.add(ticker) }
            watchlist.markAllSeen(in: store.trades)
        }
        if args.contains("-tab-watchlist") { selection = .watchlist }
        else if args.contains("-tab-settings") { selection = .about }
        else if args.contains("-tab-members") { selection = .members }
        else if args.contains("-tab-feed") { selection = .feed }
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
