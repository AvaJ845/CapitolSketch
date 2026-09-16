import SwiftUI
import UserNotifications
import DisclosureKit

struct AboutView: View {
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(AppearanceStore.self) private var appearance
    @Environment(AppIconStore.self) private var appIcon

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// Screenshot QA only (`-route-dataquality`): push "About this data" on launch. A
    /// launch argument like `-demo-filing`, so the App Store screenshot set can be shot
    /// from the same Release build (see AppStore/METADATA.md §6).
    @State private var routeToDataQuality = false

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
                    labeled("People", store.members.count.formatted())
                    labeled("Snapshot taken",
                            store.feed.generatedAt == .distantPast
                            ? "—"
                            : store.feed.generatedAt.formatted(date: .abbreviated, time: .shortened))

                    labeled("Last reached the Clerk",
                            store.lastClerkContact.map {
                                $0.formatted(date: .abbreviated, time: .shortened)
                            } ?? "—")

                    if store.clerkContactIsStale {
                        Text("Haven't reached the House Clerk in over a week — the list above is "
                             + "the last data downloaded, not necessarily the newest on file.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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

                    NavigationLink {
                        DataQualityView()
                    } label: {
                        Label("About this data", systemImage: "list.bullet.rectangle.portrait")
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
                    Text(knownGapsCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Ink.card)
                } header: {
                    Text("Known gaps")
                }

                Section {
                    HStack {
                        Text("Version").foregroundStyle(.secondary)
                        Spacer()
                        Text(Self.appVersion).monospacedDigit()
                    }
                    .font(.callout)
                    .listRowBackground(Ink.card)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("App version \(Self.appVersion)")
                } footer: {
                    Text("The app version is separate from the data — how old the filings "
                         + "are is on \u{201C}About this data.\u{201D}")
                }
            }
            .listStyle(.insetGrouped)
            .gazetteChrome()
            .navigationTitle("Settings")
            .task { notificationStatus = await AlertService.authorizationStatus() }
            .navigationDestination(isPresented: $routeToDataQuality) { DataQualityView() }
            .task {
                if ProcessInfo.processInfo.arguments.contains("-route-dataquality") {
                    try? await Task.sleep(for: .milliseconds(400))
                    routeToDataQuality = true
                }
            }
        }
    }

    /// "1.1.0 (5)" — the marketing version and the build, straight from the bundle so it
    /// can never drift from what was actually shipped.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return build == short ? short : "\(short) (\(build))"
    }

    private var coversSenate: Bool { store.feed.chambersCovered.contains(.senate) }
    private var coversExecutive: Bool { store.feed.chambersCovered.contains(.executive) }

    /// The "Known gaps" copy adapts to what the snapshot covers — House alone, House and
    /// Senate, or either of those plus the President — naming each source that is
    /// actually present rather than assuming the only possible addition to House is
    /// Senate.
    private var knownGapsCopy: String {
        let scope: String
        switch (coversSenate, coversExecutive) {
        case (false, false):
            scope = """
            **House only in this version.** Senate disclosures live on a separate portal \
            that requires a session cookie, so they are not covered yet.
            """
        case (true, false):
            scope = """
            **The full Congress, with a lag.** House trades come from the Clerk's bulk \
            index; Senate trades are pulled from the eFD portal when this snapshot is \
            built. Both are already weeks old — members have 45 days to disclose.
            """
        case (false, true):
            scope = """
            **House, plus the President.** House trades come from the Clerk's bulk \
            index; the President's trades come from the White House's own public \
            disclosures page. Both are already weeks old — the same 45-day disclosure \
            window applies to the executive branch too.
            """
        case (true, true):
            scope = """
            **The full Congress, plus the President.** House trades come from the \
            Clerk's bulk index, Senate trades from the eFD portal, and the President's \
            trades from the White House's own public disclosures page. All of it is \
            already weeks old — the same 45-day disclosure window applies across the \
            board.
            """
        }

        var paperNotes: [String] = []
        if coversSenate {
            paperNotes.append("Senate paper filings, whose amounts are hand-marked and cannot be read reliably")
        }
        if coversExecutive {
            paperNotes.append("the President's filings, which are scanned and recovered by on-device text recognition, flagged lower-confidence")
        }
        let paper = paperNotes.isEmpty
            ? """
            **Some filings are scanned paper.** \(store.stats.coverageNote) Scans are run \
            through OCR; whatever it recovers is shown but flagged lower-confidence, and \
            the rest are still missing here — open the source PDF.
            """
            : """
            **Some filings are scanned paper.** \(store.stats.coverageNote) This includes \
            \(paperNotes.joined(separator: " and ")) — counted here and shown as missing \
            or flagged, the same treatment an unreadable House scan gets. Open the source \
            filing for those.
            """
        return """
        \(scope)

        \(paper)

        **Amounts are ranges.** The form asks for a bracket, so a bracket is all anyone \
        has. Check any figure against the original filing before you rely on it.
        """
    }

    /// "House" / "House & Senate" / "House & Executive" / "House, Senate & Executive" —
    /// whichever sources are actually in the loaded snapshot.
    private var chamberSummaryLabel: String {
        switch (coversSenate, coversExecutive) {
        case (false, false): return "House"
        case (true, false): return "House & Senate"
        case (false, true): return "House & Executive"
        case (true, true): return "House, Senate & Executive"
        }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CapitolSketch")
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text("Congress trade disclosures")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(chamberSummaryLabel) · public record")
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
            iconSwatch(option)
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

    @ViewBuilder
    private func iconSwatch(_ option: AppIconStore.Option) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Group {
            if let preview = option.preview {
                preview.resizable()
            } else {
                option.background.overlay {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(option.mark)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Ink.hairline, lineWidth: 0.5) }
    }
}
