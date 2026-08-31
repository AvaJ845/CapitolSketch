import SwiftUI
import UserNotifications
import DisclosureKit

struct AboutView: View {
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(AppearanceStore.self) private var appearance
    @Environment(AppIconStore.self) private var appIcon

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var appearance = appearance
        NavigationStack {
            List {
                Section {
                    brandHeader
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    DisclosureLagNote()
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance.preference) {
                        ForEach(AppearanceStore.Preference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Appearance")
                    .listRowBackground(Ink.card)
                }

                if appIcon.supportsAlternateIcons {
                    Section("App icon") {
                        ForEach(AppIconStore.Option.allCases) { option in
                            Button {
                                Task { await appIcon.select(option) }
                            } label: {
                                iconRow(option)
                            }
                            .listRowBackground(Ink.card)
                        }
                        if let error = appIcon.lastError {
                            Text(error).font(.caption).foregroundStyle(Ink.lag)
                                .listRowBackground(Ink.card)
                        }
                    }
                }

                Section("What this app is") {
                    ForEach(Copy.principles) { item in
                        principle(item)
                            .listRowBackground(Ink.card)
                    }
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
                    .listRowBackground(Ink.card)

                    if watchlist.notificationsEnabled && notificationStatus == .denied {
                        Label(
                            "Notifications are turned off for this app in Settings.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(Ink.lag)
                        .listRowBackground(Ink.card)
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
                        Task { await store.refresh(force: true) }
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
                        Text(error).font(.caption).foregroundStyle(Ink.lag)
                    }
                }
                .listRowBackground(Ink.card)

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
                .listRowBackground(Ink.card)

                Section {
                    Text(Copy.noAdvice)
                        .font(.callout.weight(.medium))
                        .listRowBackground(Ink.card)
                } header: {
                    Text("Important")
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
                    .listRowBackground(Ink.card)
                } header: {
                    Text("Known gaps")
                }
            }
            .listStyle(.insetGrouped)
            .gazetteChrome()
            .navigationTitle("Settings")
            .task { notificationStatus = await AlertService.authorizationStatus() }
        }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CapitolSketch")
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text("Congress trade disclosures")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("House · public record")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func principle(_ item: Copy.Principle) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.body)
                .foregroundStyle(Ink.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func iconRow(_ option: AppIconStore.Option) -> some View {
        let selected = appIcon.current == option
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(option.background)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(option.mark)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Ink.hairline, lineWidth: 0.5)
                }
            Text(option.label).foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Ink.accent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
