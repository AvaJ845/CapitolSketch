import SwiftUI
import DisclosureKit

/// A ticker paired with how many times it appears — used by the "most traded" strips.
struct TickerCount: Identifiable, Hashable {
    let ticker: String
    let count: Int
    var id: String { ticker }
}

/// How the Members list is ordered. Both orders show the same members.
enum MemberSort: String, CaseIterable, Identifiable {
    case activity, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .activity: return "Most active"
        case .name: return "Name (A–Z)"
        }
    }
}

/// Facets for the Members list — the same kinds the Feed filter offers, so the two
/// screens stay consistent. Navigation over data already in hand: nothing is fetched.
struct MemberFilter: Equatable {
    var parties: Set<Party> = []
    var chambers: Set<Chamber> = []
    var states: Set<String> = []

    var isActive: Bool { !parties.isEmpty || !chambers.isEmpty || !states.isEmpty }
    var activeCount: Int { parties.count + chambers.count + states.count }

    func keeps(_ member: Member) -> Bool {
        if !parties.isEmpty && !parties.contains(member.party) { return false }
        if !chambers.isEmpty && !chambers.contains(member.chamber) { return false }
        if !states.isEmpty && !states.contains(member.state) { return false }
        return true
    }
}

struct MembersView: View {
    @Environment(TradeStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var sort = MemberSort.activity
    @State private var filter = MemberFilter()
    @State private var showingFilters = false

    private var rows: [(member: Member, count: Int)] {
        var all = store.membersByActivity()
        if sort == .name {
            all.sort { $0.member.name < $1.member.name }
        }
        if filter.isActive {
            all = all.filter { filter.keeps($0.member) }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.member.name.lowercased().contains(q) || $0.member.state.lowercased() == q }
    }

    private var availableStates: [String] {
        Set(store.members.map(\.state)).sorted()
    }

    private var availableChambers: [Chamber] {
        guard store.isMultiChamber else { return [] }
        return Chamber.allCases.filter { store.feed.chambersCovered.contains($0) }
    }

    private var availableParties: [Party] {
        let present = Set(store.members.map(\.party)).subtracting([.unknown])
        return Party.allCases.filter { $0 != .unknown && present.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Order", selection: $sort) {
                        ForEach(MemberSort.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Member order")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                Section {
                    ForEach(rows, id: \.member.id) { row in
                        NavigationLink(value: row.member) {
                            memberRow(row)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(row.member.name), "
                                + (row.member.party == .unknown ? "" : "\(row.member.party.label), ")
                                + "\(row.member.chamber.label) \(row.member.seat), "
                                + "\(row.count) disclosed trade\(row.count == 1 ? "" : "s")"
                            )
                        }
                        .disclosureRowChrome()
                    }
                } header: {
                    Text(filter.isActive
                         ? "\(rows.count) of \(store.members.count) members"
                         : "\(rows.count) members with disclosed trades")
                } footer: {
                    Text("Counts are disclosed transactions in the loaded filing years, not portfolio size.")
                }
            }
            .listStyle(.insetGrouped)
            .gazetteChrome()
            .navigationTitle("Members")
            .searchable(text: $query, prompt: "Name or state")
            .navigationDestination(for: Member.self) { MemberDetailView(member: $0) }
            .navigationDestination(for: Trade.self) { DisclosureDetailView(trade: $0) }
            .navigationDestination(for: FilingRoute.self) { FilingView(filingID: $0.id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFilters = true } label: {
                        FilterToolbarLabel(activeCount: filter.activeCount)
                    }
                    .accessibilityLabel(filter.isActive
                                        ? "Filters, \(filter.activeCount) active"
                                        : "Filters")
                }
            }
            .sheet(isPresented: $showingFilters) {
                MemberFilterSheet(
                    filter: $filter,
                    availableParties: availableParties,
                    availableChambers: availableChambers,
                    availableStates: availableStates
                )
                .presentationDetents([.medium, .large])
                .tint(Ink.accent)
            }
        }
    }

    /// One member. Monogram, name and seat beside the trade count normally; at the
    /// accessibility text sizes the count drops below the name so the name keeps the
    /// full row width instead of being broken mid-word.
    @ViewBuilder
    private func memberRow(_ row: (member: Member, count: Int)) -> some View {
        let name = Text(row.member.name).font(.body.weight(.medium))
        let seatText = [row.member.party.short, row.member.chamber.label, row.member.seat]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let seat = Text(seatText)
            .font(.caption)
            .foregroundStyle(.secondary)
        let count = Text("\(row.count)")
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)

        HStack(spacing: 12) {
            MonogramView(name: row.member.name)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    name
                    seat
                    count
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    name
                    seat
                }
                Spacer(minLength: 8)
                count
            }
        }
    }
}

/// The Members facet sheet. Same shape as the Feed's `FilterSheet` — a checklist per
/// facet, a Reset that leaves the search text alone, a Done that dismisses.
private struct MemberFilterSheet: View {
    @Binding var filter: MemberFilter
    var availableParties: [Party] = []
    var availableChambers: [Chamber] = []
    var availableStates: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if availableChambers.count > 1 {
                    Section("Chamber") {
                        ForEach(availableChambers) { chamber in
                            toggleRow(chamber.label, isOn: filter.chambers.contains(chamber)) {
                                toggle(chamber, in: &filter.chambers)
                            }
                        }
                    }
                }

                if !availableParties.isEmpty {
                    Section("Party") {
                        ForEach(availableParties) { party in
                            toggleRow(party.label, isOn: filter.parties.contains(party)) {
                                toggle(party, in: &filter.parties)
                            }
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
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { filter = MemberFilter() }
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

struct MemberDetailView: View {
    let member: Member
    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist

    private var trades: [Trade] {
        store.trades(forMember: member.id).sorted { $0.sortDate > $1.sortDate }
    }

    private var buys: Int { trades.filter { $0.txType.isAcquisition }.count }
    private var sells: Int { trades.count - buys }

    private var topTickers: [TickerCount] {
        var counts: [String: Int] = [:]
        for ticker in trades.compactMap(\.ticker) {
            counts[ticker, default: 0] += 1
        }
        var ranked: [TickerCount] = []
        ranked.reserveCapacity(counts.count)
        for (ticker, count) in counts {
            ranked.append(TickerCount(ticker: ticker, count: count))
        }
        ranked.sort { (a: TickerCount, b: TickerCount) -> Bool in
            if a.count != b.count { return a.count > b.count }
            return a.ticker < b.ticker
        }
        return Array(ranked.prefix(8))
    }

    /// "Democrat · House · CA-31", skipping any part that is unknown.
    private var identityLine: String {
        [member.party == .unknown ? "" : member.party.label, member.chamber.label, member.seat]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        List {
            Section {
                Text(identityLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel(identityLine)
            }

            Section {
                StatStrip(items: [
                    ("Trades", "\(trades.count)"),
                    ("Bought", "\(buys)"),
                    ("Sold", "\(sells)"),
                ])
                .listRowBackground(Ink.card)
            }

            if MemberActivityStrip.isWorthShowing(trades) {
                Section("Filing activity") {
                    MemberActivityStrip(trades: trades)
                        .padding(.vertical, 4)
                        .listRowBackground(Ink.card)
                }
            }

            if !topTickers.isEmpty {
                Section("Most traded") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(topTickers) { item in
                                NavigationLink {
                                    TickerDetailView(ticker: item.ticker)
                                } label: {
                                    TickerChip(ticker: item.ticker, count: item.count)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            if !member.committees.isEmpty {
                Section {
                    ForEach(member.committees, id: \.self) { committee in
                        Text(committee)
                            .font(.callout)
                            .listRowBackground(Ink.card)
                    }
                } header: {
                    Text("Committees")
                } footer: {
                    Text("Full-committee membership, from the public congress-legislators "
                         + "project as of the date this snapshot was built — not as of any "
                         + "trade below. It is public and changes between Congresses.")
                }
            }

            Section {
                Button {
                    // First watch or follow: treat everything already public as seen, so
                    // the reader is not buried in a backlog of alerts.
                    watchlist.toggleFollow(member.id, markingSeenIn: store.trades)
                } label: {
                    Label(
                        watchlist.isFollowing(member.id)
                            ? "Following \(member.name)"
                            : "Follow \(member.name)",
                        systemImage: watchlist.isFollowing(member.id) ? "bell.fill" : "bell"
                    )
                }
                .listRowBackground(Ink.card)
            } footer: {
                Text("Following a member only decides when you get a notification. "
                     + "It stays on this phone.")
            }

            Section {
                if trades.isEmpty {
                    Text("No disclosed transaction for this member in the loaded filings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Ink.card)
                } else {
                    ForEach(trades.prefix(300)) { trade in
                        NavigationLink(value: trade) {
                            DisclosureRow(trade: trade, showsMember: false)
                        }
                        .disclosureRowChrome()
                        .disclosureRowActions(for: trade, store: store, watchlist: watchlist)
                    }
                }
            } header: {
                Text("Disclosed transactions")
            } footer: {
                TruncationNote(shown: 300, total: trades.count)
            }
        }
        .listStyle(.insetGrouped)
        .gazetteChrome()
        .sensoryFeedback(.selection, trigger: watchlist.isFollowing(member.id))
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
