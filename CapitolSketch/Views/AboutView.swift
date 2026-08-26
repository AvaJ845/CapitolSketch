import SwiftUI
import UserNotifications
import DisclosureKit

struct AboutView: View {
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(AppearanceStore.self) private var appearance

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var appearance = appearance
        NavigationStack {
            List {
                Section {
                    DisclosureLagNote()
                        .listRowInsets(.init(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .listRowBackground(Color.clear)
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance.preference) {
                        ForEach(AppearanceStore.Preference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Appearance")
                }

                Section("What this app is") {
                    principle("lock.shield", Copy.privateByDefault)
                    principle("clock.arrow.circlepath", Copy.historyNotHeadlines)
                    principle("arrow.left.and.right", Copy.rangesOnly)
                    principle("bell.badge", Copy.oneAlert)
                    principle("calendar", Copy.updatedDaily)
                }

                Section("Alerts") {
                    Toggle("Notify me about watchlist trades", isOn: Binding(
                        get: { watchlist.notificationsEnabled },
                        set: { newValue in
                            watchlist.notificationsEnabled = newValue
                            if newValue {
                                Task {
                                    _ = await AlertService.requestAuthorization()
                                    notificationStatus = await AlertService.authorizationStatus()
                                }
                            }
                        }
                    ))

                    if watchlist.notificationsEnabled && notificationStatus == .denied {
                        Label(
                            "Notifications are turned off for this app in Settings.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Section("Data") {
                    labeled("Transactions", store.trades.count.formatted())
                    labeled("Members", store.members.count.formatted())
                    labeled("Snapshot taken",
                            store.feed.generatedAt == .distantPast
                            ? "—"
                            : store.feed.generatedAt.formatted(date: .abbreviated, time: .shortened))

                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack {
                            Text("Check for new filings")
                            Spacer()
                            if store.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(store.isRefreshing)

                    if let summary = store.lastRefreshSummary {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }

                    if let error = store.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://disclosures-clerk.house.gov/PublicDisclosure")!) {
                        Label("House Clerk disclosure portal", systemImage: "building.columns")
                    }
                    Link(destination: URL(string: "https://fd.house.gov/reference/asset-type-codes.aspx")!) {
                        Label("Asset type code reference", systemImage: "book")
                    }
                } header: {
                    Text("Source")
                } footer: {
                    Text(store.feed.source.isEmpty
                         ? "US House Clerk — Periodic Transaction Reports."
                         : store.feed.source)
                }

                Section("Important") {
                    Text(Copy.noAdvice)
                        .font(.callout)
                }

                Section {
                    Text("""
                    **House only in v1.** Senate disclosures live on a separate portal that \
                    requires a session cookie, so they are not covered yet.

                    **Some filings are scanned paper and yield nothing.** \(store.stats.coverageNote) \
                    Those transactions are missing here entirely.

                    **Amounts are ranges.** The form asks for a bracket, so a bracket is all \
                    anyone has. Check any figure against the original PDF before you rely on it.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Known gaps")
                }
            }
            .navigationTitle("Settings")
            .task { notificationStatus = await AlertService.authorizationStatus() }
        }
    }

    private func principle(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
        .labelStyle(.titleAndIcon)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
