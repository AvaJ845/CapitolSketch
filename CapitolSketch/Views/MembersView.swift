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
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.member.name).font(.body.weight(.medium))
                                    Text("\(row.member.chamber.label) · \(row.member.seat)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(row.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("\(rows.count) members with disclosed trades")
                } footer: {
                    Text("Counts are disclosed transactions in the loaded filing years, not portfolio size.")
                }
            }
            .navigationTitle("Members")
            .searchable(text: $query, prompt: "Name or state")
            .navigationDestination(for: Member.self) { MemberDetailView(member: $0) }
            .navigationDestination(for: Trade.self) { DisclosureDetailView(trade: $0) }
        }
    }
}

struct MemberDetailView: View {
    let member: Member
    @Environment(TradeStore.self) private var store

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
                HStack(spacing: 0) {
                    stat("Trades", "\(trades.count)")
                    Divider()
                    stat("Bought", "\(buys)")
                    Divider()
                    stat("Sold", "\(sells)")
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
                                    VStack(spacing: 2) {
                                        Text(item.ticker).font(.subheadline.weight(.semibold))
                                        Text("\(item.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section("Disclosed transactions") {
                ForEach(trades.prefix(300)) { trade in
                    NavigationLink(value: trade) {
                        DisclosureRow(trade: trade, showsMember: false)
                    }
                }
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
