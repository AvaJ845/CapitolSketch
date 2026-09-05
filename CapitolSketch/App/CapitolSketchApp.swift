import SwiftUI
import UserNotifications
import DisclosureKit

@main
struct CapitolSketchApp: App {
    @State private var store = TradeStore()
    @State private var watchlist = WatchlistStore()
    @State private var appearance = AppearanceStore()
    @State private var appIcon = AppIconStore()
    @State private var notifications = NotificationCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(watchlist)
                .environment(appearance)
                .environment(appIcon)
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selection: Section = .feed
    @State private var routedTrade: Trade?
    @State private var splitVisibility: NavigationSplitViewVisibility = .automatic
    /// When the scene last became active and actually ran the refresh + alert scan.
    /// A quick app-switch flurry (Control Center, notification banner, share sheet)
    /// should not re-run either every time.
    @State private var lastForegroundWork: Date = .distantPast

    /// The four top-level areas. On iPhone these are tabs; on iPad they are the sidebar.
    enum Section: Hashable, CaseIterable {
        case feed, watchlist, members, about

        var title: String {
            switch self {
            case .feed: return "Trades"
            case .watchlist: return "Watchlist"
            case .members: return "Members"
            case .about: return "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .feed: return "list.bullet.rectangle"
            case .watchlist: return "star"
            case .members: return "person.3"
            case .about: return "gearshape"
            }
        }
    }

    private var watchlistBadge: Int {
        watchlist.unseenMatches(in: store.trades).count
    }

    var body: some View {
        layout
            .tint(Ink.accent)
            .sheet(item: $routedTrade) { trade in
                NavigationStack {
                    DisclosureDetailView(trade: trade)
                        .navigationDestination(for: Trade.self) { DisclosureDetailView(trade: $0) }
                        .navigationDestination(for: Member.self) { MemberDetailView(member: $0) }
                        .navigationDestination(for: FilingRoute.self) { FilingView(filingID: $0.id) }
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { routedTrade = nil }
                            }
                        }
                }
                .environment(store)
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
                watchlist.rebaseSeenRowIDsIfNeeded(against: store.trades)
                seedWatchlistIfRequested()
                routeToFiling(notifications.pendingRowID)
                openDemoFilingIfRequested()
                Task { await checkForWatchlistAlerts() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // Clearing the badge is free and expected every time the app opens.
                Task { await AlertService.clearBadge() }
                // The refresh (30-min network throttle) and the alert scan are not:
                // skip both entirely if the app was only backgrounded for a moment.
                let now = Date()
                guard now.timeIntervalSince(lastForegroundWork) > 60 else { return }
                lastForegroundWork = now
                Task {
                    await store.refresh()
                    await checkForWatchlistAlerts()
                }
            }
    }

    // MARK: - Layout

    /// iPhone (and narrow iPad multitasking) get the tab bar; a regular-width iPad gets
    /// a sidebar so the four areas stay visible and the window's width is actually used.
    @ViewBuilder
    private var layout: some View {
        if horizontalSizeClass == .compact {
            tabLayout
        } else {
            sidebarLayout
        }
    }

    private var tabLayout: some View {
        TabView(selection: $selection) {
            ForEach(Section.allCases, id: \.self) { section in
                Tab(section.title, systemImage: section.symbol, value: section) {
                    view(for: section)
                }
                .badge(section == .watchlist ? watchlistBadge : 0)
            }
        }
    }

    private var sidebarLayout: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List(selection: sidebarSelection) {
                ForEach(Section.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(section == .watchlist ? watchlistBadge : 0)
                        .tag(Optional(section))
                }
            }
            .navigationTitle("CapitolSketch")
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            view(for: selection)
        }
    }

    /// `List` single-selection on iOS wants an optional binding; the app always has a
    /// section selected, so a nil selection is treated as "no change".
    private var sidebarSelection: Binding<Section?> {
        Binding(get: { selection }, set: { if let new = $0 { selection = new } })
    }

    @ViewBuilder
    private func view(for section: Section) -> some View {
        switch section {
        case .feed: FeedView()
        case .watchlist: WatchlistView()
        case .members: MembersView()
        case .about: AboutView()
        }
    }

    // MARK: - Routing

    /// `capitolsketch://` deep links. A hostile link can only pick a tab or ask for a
    /// filing by id; the id is used solely as an equality match against rows already in
    /// the loaded feed (`routeToFiling`), so an unknown or crafted id navigates nowhere
    /// and nothing is parsed, written or escalated.
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
        // Follow one well-known member so the Watchlist screenshot shows both halves.
        if let member = store.members.first(where: { $0.name == "Nancy Pelosi" })
            ?? store.members.first {
            watchlist.follow(member.id)
        }
        watchlist.markAllSeen(in: store.trades)
    }

    /// `-demo-filing` opens a representative disclosure for App Store captures: the most
    /// recent trade that has a ticker and a filing description, so the detail screen is
    /// shown full rather than sparse.
    private func openDemoFilingIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-demo-filing"),
              routedTrade == nil,
              let trade = store.trades.first(where: {
                  $0.ticker != nil && !($0.filingDescription ?? "").isEmpty && !$0.hasImpossibleDate
              })
        else { return }
        routedTrade = trade
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
