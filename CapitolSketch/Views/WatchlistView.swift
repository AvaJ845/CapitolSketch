import SwiftUI
import DisclosureKit

/// The user's own tickers, and every disclosed trade touching them.
struct WatchlistView: View {
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist

    @State private var showingAdd = false
    @State private var newMatches: [Trade] = []

    private var matches: [Trade] {
        store.trades(matching: watchlist.tickers)
            .sorted { $0.disclosedDate > $1.disclosedDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if watchlist.isEmpty {
                    EmptyStateView(
                        icon: "star",
                        title: "Watch your own holdings",
                        message: "Add the tickers you own and this tab will show you every time a House member discloses a trade in them."
                    )
                } else {
                    List {
                        Section {
                            tickerChips
                        }

                        if !newMatches.isEmpty {
                            Section("New since you last looked") {
                                ForEach(newMatches) { trade in
                                    NavigationLink(value: trade) { DisclosureRow(trade: trade) }
                                }
                            }
                        }

                        Section("\(matches.count.formatted()) disclosed trades") {
                            if matches.isEmpty {
                                Text("No House member has disclosed a trade in these tickers.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(matches.prefix(300)) { trade in
                                    NavigationLink(value: trade) { DisclosureRow(trade: trade) }
                                }
                            }
                        }

                        Section {
                            DisclosureLagNote()
                                .listRowInsets(.init(top: 4, leading: 8, bottom: 4, trailing: 8))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Watchlist")
            .navigationDestination(for: Trade.self) { DisclosureDetailView(trade: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add ticker")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddTickerView().presentationDetents([.large])
            }
            .task { refreshNewMatches() }
            .onChange(of: watchlist.tickers) { refreshNewMatches() }
        }
    }

    private var tickerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(watchlist.sortedTickers, id: \.self) { ticker in
                    NavigationLink {
                        TickerDetailView(ticker: ticker)
                    } label: {
                        HStack(spacing: 5) {
                            Text(ticker).font(.subheadline.weight(.semibold))
                            Text("\(store.trades(forTicker: ticker).count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            watchlist.remove(ticker)
                        } label: {
                            Label("Remove \(ticker)", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    /// Surfaces unseen matches, then marks them seen so the section clears next visit.
    private func refreshNewMatches() {
        let unseen = watchlist.unseenMatches(in: store.trades)
        newMatches = Array(unseen.prefix(50))
        watchlist.markSeen(unseen)
    }
}

/// Ticker picker driven by what actually appears in the filings.
struct AddTickerView: View {
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var suggestions: [(ticker: String, count: Int)] {
        let all = store.knownTickers
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return Array(all.prefix(60)) }
        return all.filter { $0.ticker.hasPrefix(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty && !suggestions.contains(where: { $0.ticker == query.uppercased() }) {
                    Section {
                        Button {
                            add(query)
                        } label: {
                            Label("Add \"\(query.uppercased())\" anyway", systemImage: "plus.circle")
                        }
                    } footer: {
                        Text("No filing mentions this ticker yet. You'll be alerted if one does.")
                    }
                }

                Section(query.isEmpty ? "Most traded in the House" : "Matches") {
                    ForEach(suggestions, id: \.ticker) { item in
                        Button {
                            add(item.ticker)
                        } label: {
                            HStack {
                                Text(item.ticker).font(.body.weight(.medium))
                                Spacer()
                                Text("\(item.count) trades")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if watchlist.contains(item.ticker) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Add Ticker")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search ticker")
            .textInputAutocapitalization(.characters)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }

    private func add(_ ticker: String) {
        let wasEmpty = watchlist.isEmpty
        watchlist.add(ticker)
        // Don't fire a backlog of alerts for disclosures that were already public
        // when the user first set up their watchlist.
        if wasEmpty { watchlist.markAllSeen(in: store.trades) }
        dismiss()
    }
}
