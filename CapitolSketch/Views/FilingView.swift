import SwiftUI
import DisclosureKit

/// A route to a whole filing, by its ID. Registered as a `navigationDestination`
/// wherever `DisclosureDetailView` can appear.
struct FilingRoute: Hashable {
    let id: String
}

/// One Periodic Transaction Report, with all of its transactions together.
///
/// The filing — not the row — is the unit a member actually submits. This screen is
/// pure grouping of records already in the feed: the same rows shown on the feed and on
/// the member's page, gathered by their shared `filingID`, identical for every reader.
struct FilingView: View {
    let filingID: String

    @Environment(TradeStore.self) private var store

    private var rows: [Trade] { store.trades(inFiling: filingID) }
    private var lead: Trade? { rows.first }
    private var member: Member? { lead.flatMap { store.member(id: $0.memberID) } }

    var body: some View {
        List {
            if let lead {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if let member {
                            NavigationLink(value: member) {
                                Text(member.name)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Ink.accent)
                            }
                        } else {
                            Text(lead.memberName).font(.title3.weight(.semibold))
                        }
                        Text("Filed \(lead.disclosedDate.mediumLabel)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("\(rows.count) transaction\(rows.count == 1 ? "" : "s")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Ink.card)
                }

                if let url = lead.documentURL {
                    Section {
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

                        ShareLink(
                            item: url,
                            subject: Text("\(lead.memberName) — House disclosure"),
                            message: Text("US House Periodic Transaction Report, filing \(filingID)")
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share this filing").fontWeight(.medium)
                                Spacer()
                            }
                            .foregroundStyle(Ink.accent)
                        }
                        .listRowBackground(Ink.card)
                    } footer: {
                        Text("Every field below is transcribed from the source PDF — US House "
                             + "Clerk, filing \(filingID), public domain. Check anything that "
                             + "matters against it.")
                    }
                }

                Section {
                    ForEach(rows) { trade in
                        NavigationLink(value: trade) {
                            DisclosureRow(trade: trade, showsMember: false)
                        }
                        .disclosureRowChrome()
                    }
                } header: {
                    Text("Transactions")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Copy.rangesOnly)
                        Text(Copy.lagBanner)
                    }
                    .padding(.top, 4)
                }
            } else {
                Section {
                    Text("This filing is not in the loaded snapshot.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Ink.card)
                }
            }
        }
        .listStyle(.insetGrouped)
        .gazetteChrome()
        .navigationTitle("Filing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
