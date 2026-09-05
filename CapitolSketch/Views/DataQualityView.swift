import SwiftUI
import DisclosureKit

/// The app's honesty about its own gaps, as a screen instead of a paragraph.
///
/// Every figure here is aggregated from the feed currently loaded. There is no score,
/// no grade, no "health" gauge — each row is a count and a plain sentence saying what it
/// means. Orange is used only where the rest of the app uses it: a data-quality signal.
struct DataQualityView: View {
    @Environment(TradeStore.self) private var store

    private var trades: [Trade] { store.trades }
    private var stats: ParseStats { store.stats }
    private var lag: DisclosureLagStats { trades.disclosureLagStats }

    private var ocrRecoveredCount: Int {
        trades.filter { t in t.warnings.contains { $0.contains("recovered by OCR") } }.count
    }
    private var impossibleDateCount: Int {
        trades.filter(\.hasImpossibleDate).count
    }

    private var filingYears: String {
        let years = store.feed.indexYears.sorted()
        guard let first = years.first, let last = years.last else { return "—" }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }

    var body: some View {
        List {
            Section {
                statRow(trades.count.formatted(),
                        "Disclosed transactions in the loaded filings.")
                statRow(store.members.count.formatted(),
                        "House members with at least one disclosed transaction here.")
                statRow(filingYears, "Filing years covered by this snapshot.")
                if let generatedAt = store.generatedAt {
                    statRow(generatedAt.formatted(date: .abbreviated, time: .shortened),
                            "When this data was assembled · \(DataAgeLine.age(of: generatedAt)).")
                }
            } header: {
                Text("The snapshot")
            }

            Section {
                statRow("\(lag.medianDays) days", "Median gap between a transaction and its disclosure.")
                statRow("\(lag.meanDays) days", "Mean gap, across \(lag.count.formatted()) transactions with usable dates.")
                statRow("\(lag.overFortyFiveCount.formatted()) · \(lag.overFortyFivePercent)%",
                        "Disclosed more than 45 days after the transaction — the STOCK Act limit.")
                ForEach(lag.buckets) { bucket in
                    HStack {
                        Text(bucket.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(bucket.count.formatted()).monospacedDigit()
                    }
                    .font(.callout)
                }
            } header: {
                Text("Disclosure lag")
            } footer: {
                Text("Buckets count transactions by how long after the trade they were disclosed. "
                     + "Transactions with an impossible date are left out and counted below.")
            }

            Section {
                statRow(percentRow(stats.filingsWithoutText.count, of: stats.filingsProcessed),
                        "Photographs of paper with no text layer; those transactions are missing here.")
            } header: {
                Text("Scanned paper")
            }

            Section {
                statRow(ocrRecoveredCount.formatted(),
                        "Transactions read by OCR from a scan — lower-confidence; check against the PDF.")
            } header: {
                Text("OCR-recovered")
            }

            Section {
                statRow(impossibleDateCount.formatted(),
                        "A transaction dated after its own filing, almost always a mistyped year; shown as filed.")
            } header: {
                Text("Impossible dates")
            }

            Section {
                statRow(stats.filingsYieldingNoTrades.count.formatted(),
                        "Filings with readable text but no rows the parser matched — a bug on our side.")
            } header: {
                Text("Parser misses")
            }

            Section {
                statRow(store.lastClerkContact.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "—",
                        "The last time a refresh reached the House Clerk with a good response.")
                if store.clerkContactIsStale {
                    StaleContactNote(lastContact: store.lastClerkContact)
                }
            } header: {
                Text("Last reached the Clerk")
            }

            Section {
                Link(destination: URL(string: "https://disclosures-clerk.house.gov/PublicDisclosure")!) {
                    Label("House Clerk disclosure portal", systemImage: "building.columns")
                }
                .listRowBackground(Ink.card)
            } footer: {
                Text("Every figure on this screen is counted from the data currently loaded. "
                     + "Check anything that matters against the source.")
            }
        }
        .listStyle(.insetGrouped)
        .gazetteChrome()
        .navigationTitle("About this data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .listRowBackground(Ink.card)
        .accessibilityElement(children: .combine)
    }

    private func percentRow(_ n: Int, of total: Int) -> String {
        guard total > 0 else { return "\(n.formatted())" }
        let pct = Int((Double(n) / Double(total) * 100).rounded())
        return "\(n.formatted()) · \(pct)% of \(total.formatted())"
    }
}
