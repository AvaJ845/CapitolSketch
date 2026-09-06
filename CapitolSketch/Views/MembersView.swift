import SwiftUI
import DisclosureKit

/// A ticker paired with how many times it appears — used by the "most traded" strips.
struct TickerCount: Identifiable, Hashable {
    let ticker: String
    let count: Int
    var id: String { ticker }
}

struct MembersView: View {
    @Environment(TradeStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""

    private var rows: [(member: Member, count: Int)] {
        let all = store.membersByActivity()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.member.name.lowercased().contains(q) || $0.member.state.lowercased() == q }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows, id: \.member.id) { row in
                        NavigationLink(value: row.member) {
                            memberRow(row)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(row.member.name), \(row.member.chamber.label) \(row.member.seat), "
                                + "\(row.count) disclosed trade\(row.count == 1 ? "" : "s")"
                            )
                        }
                        .disclosureRowChrome()
                    }
                } header: {
                    Text("\(rows.count) members with disclosed trades")
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
        }
    }

    /// One member. Monogram, name and seat beside the trade count normally; at the
    /// accessibility text sizes the count drops below the name so the name keeps the
    /// full row width instead of being broken mid-word.
    @ViewBuilder
    private func memberRow(_ row: (member: Member, count: Int)) -> some View {
        let name = Text(row.member.name).font(.body.weight(.medium))
        let seat = Text("\(row.member.chamber.label) · \(row.member.seat)")
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

    var body: some View {
        List {
            Section {
                StatStrip(items: [
                    ("Trades", "\(trades.count)"),
                    ("Bought", "\(buys)"),
                    ("Sold", "\(sells)"),
                ])
                .listRowBackground(Ink.card)
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
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
