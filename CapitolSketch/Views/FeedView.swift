import SwiftUI
import DisclosureKit

/// Filters applied to the main feed.
struct TradeFilter: Equatable {
    var search = ""
    var types: Set<TradeType> = []
    var owners: Set<TradeOwner> = []
    var optionsOnly = false
    var lateOnly = false

    var isActive: Bool { !types.isEmpty || !owners.isEmpty || optionsOnly || lateOnly }

    var activeCount: Int {
        types.count + owners.count + (optionsOnly ? 1 : 0) + (lateOnly ? 1 : 0)
    }

    func apply(to trades: [Trade]) -> [Trade] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return trades.filter { t in
            if !types.isEmpty && !types.contains(t.txType) { return false }
            if !owners.isEmpty && !owners.contains(t.owner) { return false }
            if optionsOnly && !t.isOption { return false }
            if lateOnly && !t.isLateFiling { return false }
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

    private var results: [Trade] { filter.apply(to: store.trades) }

    var body: some View {
        NavigationStack {
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
                                    Text("Showing the 400 most recent. Search to narrow it down.")
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
            .refreshable { await store.refresh(force: true) }
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
                FilterSheet(filter: $filter)
                    .presentationDetents([.medium, .large])
                    .tint(Ink.accent)
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(results.count.formatted()) transactions")
                .font(.title3.weight(.semibold).monospacedDigit())
            DataAgeLine(generatedAt: store.generatedAt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

                Section {
                    Toggle("Options only", isOn: $filter.optionsOnly)
                    Toggle("Filed late (over 45 days)", isOn: $filter.lateOnly)
                } footer: {
                    Text("The STOCK Act requires disclosure within 45 days of the transaction.")
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
