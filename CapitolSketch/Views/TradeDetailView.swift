import SwiftUI
import DisclosureKit

/// One filing row in full.
///
/// This is the canonical view of a disclosure, and it is identical for every reader.
/// A notification tapped from the watchlist lands here, on the same screen someone who
/// browsed to it from the feed sees — nothing on this screen is selected, reordered or
/// annotated because of what the reader happens to own.
struct DisclosureDetailView: View {
    let trade: Trade

    @Environment(WatchlistStore.self) private var watchlist
    @Environment(TradeStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    private var filingRowCount: Int { store.trades(inFiling: trade.filingID).count }

    /// The ticker and the buy/sell badge. Side by side normally; stacked once Dynamic
    /// Type reaches the accessibility sizes, where the two together overflow the card
    /// and the badge's capsule distorts — the same treatment `DisclosureRow` gives them.
    @ViewBuilder
    private var symbolAndDirection: some View {
        let symbol = Text(trade.displaySymbol)
            .font(.title2.weight(.bold).monospaced())
            .fixedSize(horizontal: false, vertical: true)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                DirectionBadge(type: trade.txType)
                symbol
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                symbol
                DirectionBadge(type: trade.txType)
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    symbolAndDirection
                    Text(trade.cleanAssetName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    AmountView(amount: trade.amount)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
                .listRowBackground(Ink.card)
            } footer: {
                Text(Copy.rangesOnly)
            }

            Section {
                if let url = trade.documentURL {
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("View the source filing").fontWeight(.medium)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(Ink.accent)
                    }
                    .listRowBackground(Ink.card)

                    // The only growth loop the North Star allows: hand someone the public
                    // record itself. The payload is the Clerk's PDF link and nothing about
                    // who is sharing it or what they watch.
                    ShareLink(
                        item: url,
                        subject: Text("\(trade.memberName) — \(trade.displaySymbol) disclosure"),
                        message: Text("US House Periodic Transaction Report, filing \(trade.filingID)")
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share this filing").fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundStyle(Ink.accent)
                    }
                    .listRowBackground(Ink.card)
                }
            } footer: {
                Text("Every field below is transcribed from the source PDF — US House Clerk, "
                     + "filing \(trade.filingID), public domain. Check anything that matters "
                     + "against it.")
            }

            Section("The filing") {
                row("Member", trade.memberName)
                // Body weight, same as every other value. Whose account traded is a fact,
                // not a footnote.
                row("Account", trade.owner.label)
                row("Transaction date", trade.txDate.mediumLabel)
                row("Disclosed", trade.disclosedDate.mediumLabel)

                if trade.hasImpossibleDate {
                    Label(
                        Copy.datesAsFiled,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                        .foregroundStyle(Ink.lag)
                } else {
                    HStack {
                        Text("Gap").foregroundStyle(.secondary)
                        Spacer()
                        Text(trade.disclosureGapPhrase.replacingOccurrences(
                            of: "disclosed ", with: ""
                        ))
                        .foregroundStyle(trade.isLateFiling ? Ink.lag : .primary)
                        .multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
                }

                if let code = trade.assetType {
                    row("Asset type", trade.assetTypeName.map { "\($0) (\(code))" } ?? code)
                }
            }

            if let description = trade.filingDescription, !description.isEmpty {
                Section("Description on the filing") {
                    Text(description)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !trade.warnings.isEmpty {
                Section {
                    ForEach(trade.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("What the parser was unsure about")
                } footer: {
                    Text("Carried through from parsing rather than discarded, so you can "
                         + "check it against the original.")
                }
            }

            if filingRowCount > 1 {
                Section {
                    NavigationLink(value: FilingRoute(id: trade.filingID)) {
                        Label(
                            "See the full filing — \(filingRowCount) transactions",
                            systemImage: "doc.on.doc"
                        )
                    }
                    .listRowBackground(Ink.card)
                } footer: {
                    Text("This member disclosed several transactions in one filing.")
                }
            }

            if trade.ticker != nil || store.member(id: trade.memberID) != nil {
                Section {
                    if let ticker = trade.ticker {
                        Button {
                            watchlist.toggle(ticker, markingSeenIn: store.trades)
                        } label: {
                            Label(
                                watchlist.contains(ticker)
                                    ? "Stop watching \(ticker)"
                                    : "Watch \(ticker)",
                                systemImage: watchlist.contains(ticker) ? "bell.fill" : "bell"
                            )
                        }
                        .listRowBackground(Ink.card)
                    }

                    if let member = store.member(id: trade.memberID) {
                        Button {
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
                    }

                    if let ticker = trade.ticker {
                        NavigationLink {
                            TickerDetailView(ticker: ticker)
                        } label: {
                            Label("Every disclosure in \(ticker)", systemImage: "list.bullet")
                        }
                        .listRowBackground(Ink.card)
                    }
                } footer: {
                    Text("Watching a ticker or following a member only decides when you get "
                         + "a notification. Both stay on this phone.")
                }
            }

        }
        .listStyle(.insetGrouped)
        .gazetteChrome()
        .navigationTitle("Disclosure")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// Every disclosed transaction in one ticker, across all members.
struct TickerDetailView: View {
    let ticker: String

    @Environment(TradeStore.self) private var store
    @Environment(WatchlistStore.self) private var watchlist

    private var trades: [Trade] { store.trades(forTicker: ticker) }

    var body: some View {
        List {
            Section {
                StatStrip(items: [
                    ("Disclosures", "\(trades.count)"),
                    ("Bought", "\(trades.filter { $0.txType == .buy }.count)"),
                    ("Sold", "\(trades.filter { $0.txType != .buy }.count)"),
                    ("Members", "\(Set(trades.map(\.memberID)).count)"),
                ])
                .listRowBackground(Ink.card)
            } footer: {
                Text("Counts of disclosed transactions, not of shares or dollars. The form "
                     + "reports neither.")
            }

            Section {
                Button {
                    watchlist.toggle(ticker, markingSeenIn: store.trades)
                } label: {
                    Label(
                        watchlist.contains(ticker) ? "Stop watching" : "Watch this ticker",
                        systemImage: watchlist.contains(ticker) ? "bell.fill" : "bell"
                    )
                }
                .listRowBackground(Ink.card)
            }

            Section {
                if trades.isEmpty {
                    Text("No disclosed transaction mentions this ticker in the loaded filings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Ink.card)
                } else {
                    ForEach(trades.prefix(300)) { trade in
                        NavigationLink(value: trade) { DisclosureRow(trade: trade) }
                            .disclosureRowChrome()
                    }
                }
            } header: {
                Text("Disclosures")
            } footer: {
                TruncationNote(shown: 300, total: trades.count)
            }
        }
        .listStyle(.insetGrouped)
        .gazetteChrome()
        .navigationTitle(ticker)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Trade.self) { DisclosureDetailView(trade: $0) }
        .navigationDestination(for: Member.self) { MemberDetailView(member: $0) }
        .navigationDestination(for: FilingRoute.self) { FilingView(filingID: $0.id) }
    }
}
