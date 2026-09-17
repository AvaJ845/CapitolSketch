import Foundation
import UniformTypeIdentifiers
import CoreTransferable
import DisclosureKit

/// Turns the currently loaded snapshot into a CSV file for research and journalism use —
/// the "hand someone the public record itself" growth loop `ShareLink`'s own comment in
/// `FilingView.swift` and `TradeDetailView.swift` already names as the only kind of
/// sharing this app does.
///
/// Every caveat the app already shows inline stays a column here too: `warnings`,
/// `hasImpossibleDate`, `disclosureLagDays`, `isAmendment`. An export that looked cleaner
/// than the app itself would be a quiet act of exactly the fabrication this app refuses
/// everywhere else — a reader who only sees the CSV must be able to notice the same
/// things a reader of the app would.
enum CSVExport {
    private static let columns = [
        "member_name", "chamber", "party", "owner", "transaction_type", "asset",
        "ticker", "asset_type", "transaction_date", "disclosed_date",
        "disclosure_lag_days", "has_impossible_date", "amount_label",
        "amount_low_cents", "amount_high_cents", "is_amendment", "warnings",
        "filing_id", "source_url",
    ]

    /// Builds the file off the main actor — 14,000+ rows of string assembly is cheap in
    /// absolute terms but has no reason to compete with a frame render, the same
    /// reasoning `TradeStore.recomputeStandouts()` already applies to its own passes.
    static func make(
        trades: [Trade],
        chamberFor: @escaping (Trade) -> Chamber?,
        partyFor: @escaping (Trade) -> Party?
    ) async -> Data {
        await Task.detached(priority: .utility) {
            var lines = [columns.joined(separator: ",")]
            lines.reserveCapacity(trades.count + 1)
            for t in trades {
                let fields: [String] = [
                    t.memberName,
                    chamberFor(t)?.label ?? "",
                    partyFor(t)?.label ?? "",
                    t.owner.label,
                    t.txType.verb,
                    t.cleanAssetName,
                    t.ticker ?? "",
                    t.assetType ?? "",
                    t.txDate.iso,
                    t.disclosedDate.iso,
                    String(t.disclosureLagDays),
                    String(t.hasImpossibleDate),
                    t.amount.label,
                    String(t.amount.lowCents),
                    String(t.amount.highCents),
                    String(t.isAmendment),
                    t.warnings.joined(separator: "; "),
                    t.filingID,
                    t.documentURL?.absoluteString ?? "",
                ]
                lines.append(fields.map(csvField).joined(separator: ","))
            }
            return Data(lines.joined(separator: "\n").utf8)
        }.value
    }

    /// Quotes a field only when it needs it, and escapes an embedded quote by doubling it
    /// — RFC 4180. A `warnings` string is the one column routinely long enough, or with
    /// enough embedded punctuation, to need this.
    private static func csvField(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    fileprivate static func fileName(generatedAt: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = generatedAt.map(formatter.string(from:)) ?? "snapshot"
        return "capitolsketch-disclosures-\(stamp).csv"
    }
}

/// A `ShareLink` item that generates the CSV lazily, only when the reader actually taps
/// Share — not on every appearance of the Data Quality screen. Lookup dictionaries
/// (rather than closures) keep this a plain `Sendable` value, since `Transferable`
/// content crosses actor boundaries to wherever the share sheet actually runs.
struct SnapshotCSVExport: Transferable {
    let trades: [Trade]
    let chamberByMemberID: [String: Chamber]
    let partyByMemberID: [String: Party]
    let generatedAt: Date?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            await CSVExport.make(
                trades: export.trades,
                chamberFor: { export.chamberByMemberID[$0.memberID] },
                partyFor: { export.partyByMemberID[$0.memberID] }
            )
        }
        .suggestedFileName { export in
            CSVExport.fileName(generatedAt: export.generatedAt)
        }
    }
}
