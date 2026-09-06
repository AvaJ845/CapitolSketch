import SwiftUI
import DisclosureKit

/// The three dollar floors offered by the "Minimum size" filter, in cents.
enum BracketFloor: Int, CaseIterable, Hashable, Identifiable {
    case m1 = 100_000_000, m5 = 500_000_000, m50 = 5_000_000_000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .m1: return "$1M+"
        case .m5: return "$5M+"
        case .m50: return "$50M+"
        }
    }
}

/// Filters applied to the main feed.
struct TradeFilter: Equatable {
    var search = ""
    var types: Set<TradeType> = []
    var owners: Set<TradeOwner> = []
    /// Two-letter state codes of the members whose filings to show. Navigation over data
    /// already in the feed — the state comes from `Member`, resolved by the caller.
    var states: Set<String> = []
    var optionsOnly = false
    var lateOnly = false
    /// Keep only trades whose bracket floor is at least this, or an open-ended bracket.
    var minBracket: BracketFloor? = nil
    /// Keep only the trades the `offPattern` standout rule surfaced.
    var offPatternOnly = false

    var isActive: Bool {
        !types.isEmpty || !owners.isEmpty || !states.isEmpty
            || optionsOnly || lateOnly || minBracket != nil || offPatternOnly
    }

    var activeCount: Int {
        types.count + owners.count + states.count
            + (optionsOnly ? 1 : 0) + (lateOnly ? 1 : 0)
            + (minBracket != nil ? 1 : 0) + (offPatternOnly ? 1 : 0)
    }

    /// - Parameters:
    ///   - stateOf: maps a member ID to their two-letter state code.
    ///   - offPatternIDs: the trade ids the `offPattern` standout rule surfaced, used
    ///     only when `offPatternOnly` is set. Passed in the same way as `stateOf` so the
    ///     filter stays free of any dependency on the store.
    func apply(
        to trades: [Trade],
        stateOf: (String) -> String?,
        offPatternIDs: Set<String> = []
    ) -> [Trade] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return trades.filter { t in
            if !types.isEmpty && !types.contains(t.txType) { return false }
            if !owners.isEmpty && !owners.contains(t.owner) { return false }
            if !states.isEmpty {
                guard let s = stateOf(t.memberID), states.contains(s) else { return false }
            }
            if optionsOnly && !t.isOption { return false }
            if lateOnly && !t.isLateFiling { return false }
            if let floor = minBracket,
               !(t.amount.kind == .atLeast || t.amount.lowCents >= floor.rawValue) {
                return false
            }
            if offPatternOnly && !offPatternIDs.contains(t.id) { return false }
            if !q.isEmpty {
                let haystack = "\(t.memberName) \(t.ticker ?? "") \(t.asset)".lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }
}

/// Every disclosure in the loaded filing years, newest first.
///
/// This is the whole public data set, in one order, for everybody. Nothing here is
/// selected, ranked or reworded according to what the reader holds.
struct FeedView: View {
    @Environment(TradeStore.self) private var store

    @State private var filter = TradeFilter()
    @State private var showingFilters = false
    @State private var path = NavigationPath()

    /// Ids the `offPattern` rule surfaced, from the store's already-computed standouts —
    /// so the "off pattern" filter needs no compute of its own here.
    private var offPatternIDs: Set<String> {
        Set((store.standouts[.offPattern] ?? []).map(\.trade.id))
    }

    private var results: [Trade] {
        filter.apply(
            to: store.trades,
            stateOf: { store.member(id: $0)?.state },
            offPatternIDs: offPatternIDs
        )
    }

    /// Distinct member states present in the feed, for the filter sheet.
    private var availableStates: [String] {
        Set(store.members.map(\.state)).sorted()
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.isLoading {
                    ProgressView("Loading filings…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.trades.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "No filings loaded",
                        message: store.lastError ?? "The bundled filings could not be read."
                    )
                } else if results.isEmpty {
                    EmptyStateView(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "No matches",
                        message: "Try clearing the search or the filters."
                    )
                } else {
                    List {
                        Section {
                            masthead
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        Section {
                            ForEach(results.prefix(400)) { trade in
                                NavigationLink(value: trade) {
                                    DisclosureRow(trade: trade)
                                }
                                .disclosureRowChrome()
                            }
                        } footer: {
                            VStack(alignment: .leading, spacing: 8) {
                                if results.count > 400 {
                                    Text("Search to narrow it down.")
                                }
                                Text(Copy.historyNotHeadlines)
                                Text(Copy.rangesOnly)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .gazetteChrome()
                }
            }
            .navigationTitle("Disclosures")
            .searchable(text: $filter.search, prompt: "Member, ticker, or company")
            .navigationDestination(for: Trade.self) { DisclosureDetailView(trade: $0) }
            .navigationDestination(for: Member.self) { MemberDetailView(member: $0) }
            .navigationDestination(for: FilingRoute.self) { FilingView(filingID: $0.id) }
            .navigationDestination(for: StandoutsRoute.self) { _ in StandoutsView() }
            .refreshable { await store.refresh(force: true) }
            .onChange(of: store.pendingStandoutsRoute) { _, pending in
                guard pending else { return }
                if !path.isEmpty { path = NavigationPath() }
                path.append(StandoutsRoute())
                store.pendingStandoutsRoute = false
            }
            .task {
                // The deep link (or the QA launch arg) can land before this view is on
                // screen, and before RootView has consumed the launch arguments.
                let wantsStandouts = store.pendingStandoutsRoute
                    || ProcessInfo.processInfo.arguments.contains("-route-standouts")
                if wantsStandouts {
                    store.pendingStandoutsRoute = false
                    try? await Task.sleep(for: .milliseconds(350))
                    if path.isEmpty { path.append(StandoutsRoute()) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        FilterToolbarLabel(activeCount: filter.activeCount)
                    }
                    .accessibilityLabel(filter.isActive
                                        ? "Filters, \(filter.activeCount) active"
                                        : "Filters")
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(filter: $filter, availableStates: availableStates)
                    .presentationDetents([.medium, .large])
                    .tint(Ink.accent)
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(results.count.formatted()) transactions")
                    .font(.title3.weight(.semibold).monospacedDigit())
                // The list is capped at 400 rows; say so here rather than only in a footer
                // the reader may never scroll to, so the rest are known to exist.
                if results.count > 400 {
                    Text("Showing 400 of \(results.count.formatted())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DataAgeLine(generatedAt: store.generatedAt)
                if store.clerkContactIsStale {
                    StaleContactNote(lastContact: store.lastClerkContact)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            NavigationLink(value: StandoutsRoute()) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "rectangle.stack")
                        .imageScale(.medium)
                    Text("Standouts in this snapshot")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Ink.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
            .accessibilityLabel("Standouts in this snapshot")
            .accessibilityHint("The edges of this snapshot — biggest brackets, latest filings, most widely held")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FilterToolbarLabel: View {
    let activeCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: activeCount > 0
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
        }
    }
}

private struct FilterSheet: View {
    @Binding var filter: TradeFilter
    var availableStates: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Direction") {
                    ForEach(TradeType.allCases, id: \.self) { type in
                        toggleRow(type.verb, isOn: filter.types.contains(type)) {
                            toggle(type, in: &filter.types)
                        }
                    }
                }

                Section("Whose account") {
                    ForEach(TradeOwner.allCases, id: \.self) { owner in
                        toggleRow(owner.label, isOn: filter.owners.contains(owner)) {
                            toggle(owner, in: &filter.owners)
                        }
                    }
                }

                if !availableStates.isEmpty {
                    Section("State") {
                        ForEach(availableStates, id: \.self) { state in
                            toggleRow(state, isOn: filter.states.contains(state)) {
                                toggle(state, in: &filter.states)
                            }
                        }
                    }
                }

                Section {
                    Picker("Minimum size", selection: $filter.minBracket) {
                        Text("None").tag(BracketFloor?.none)
                        ForEach(BracketFloor.allCases) { floor in
                            Text(floor.label).tag(BracketFloor?.some(floor))
                        }
                    }
                } footer: {
                    Text("Keeps trades whose disclosed bracket starts at or above this, "
                         + "plus every open-ended top bracket.")
                }

                Section {
                    Toggle("Options only", isOn: $filter.optionsOnly)
                    Toggle("Filed late (over 45 days)", isOn: $filter.lateOnly)
                    Toggle("Off the member's usual pattern", isOn: $filter.offPatternOnly)
                } footer: {
                    Text("The STOCK Act requires disclosure within 45 days of the "
                         + "transaction. \"Off the member's usual pattern\" shows single-stock "
                         + "trades by members whose disclosed history is mostly funds.")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        let q = filter.search
                        filter = TradeFilter()
                        filter.search = q
                    }
                    .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Ink.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}
