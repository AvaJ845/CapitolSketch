// Cabinet-secretary OGE 278-T fetch + parse. The shipping app is House/Senate/Executive-
// only via the bundled seed and no app or widget code path reaches any type in this
// file; it is compiled only for `seedgen` and the DisclosureKit test target, both of
// which define SEEDGEN — the same treatment `WhiteHouseFetcher.swift` gets, for the same
// reason: build-time-only ingestion.
#if SEEDGEN && canImport(PDFKit)
import Foundation
import PDFKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches and parses Periodic Transaction Reports for the 15 executive departments'
/// secretaries (Attorney General for Justice), via `OGEDisclosureIndex` for discovery and
/// `OGE278TNativeParser` for extraction.
///
/// **Build-time only** — same reasoning as `WhiteHouseFetcher`. Unlike that fetcher, this
/// one needs no OCR: every filing sampled while building this was filed through
/// Integrity.gov and carries an embedded text layer, read directly with
/// `PDFDocument.string`.
public struct CabinetFetcher: Sendable {
    private let session: URLSession
    private let politenessDelay: Duration

    public init(
        session: URLSession = OGEDisclosureIndex.makeSession(),
        politenessDelay: Duration = .milliseconds(300)
    ) {
        self.session = session
        self.politenessDelay = politenessDelay
    }

    public func run(
        limit: Int? = nil,
        onProgress: (@Sendable (_ done: Int, _ total: Int, _ trades: Int) -> Void)? = nil
    ) async throws -> PTRFetcher.Output {
        let allRows = try await OGEDisclosureIndex.fetchAllRows(session: session)
        var rows = OGEDisclosureIndex.cabinetDepartmentRows(in: allRows)
            .filter { $0.type.localizedCaseInsensitiveContains("278 Transaction") }
        if let limit, rows.count > limit { rows = Array(rows.prefix(limit)) }

        var trades: [Trade] = []
        var stats = ParseStats()
        var warnings: [String: [String]] = [:]
        var membersByID: [String: Member] = [:]

        for (offset, row) in rows.enumerated() {
            stats.filingsProcessed += 1
            let filingID = "cabinet-\(row.documentURL.deletingPathExtension().lastPathComponent)"

            do {
                let (data, response) = try await session.data(from: row.documentURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    stats.filingsFailedToFetch.append(filingID)
                    onProgress?(offset + 1, rows.count, trades.count)
                    try? await Task.sleep(for: politenessDelay)
                    continue
                }
                guard let doc = PDFDocument(data: data), let text = doc.string else {
                    stats.filingsWithoutText.append(filingID)
                    warnings[filingID] = ["PDF could not be opened or had no text layer"]
                    onProgress?(offset + 1, rows.count, trades.count)
                    try? await Task.sleep(for: politenessDelay)
                    continue
                }

                guard let disclosedDate = row.docDate else {
                    stats.filingsFailedToFetch.append(filingID)
                    warnings[filingID] = ["no docDate from the OGE index — skipped rather than dated wrong"]
                    onProgress?(offset + 1, rows.count, trades.count)
                    try? await Task.sleep(for: politenessDelay)
                    continue
                }

                let filing = OGE278TNativeFilingRef(
                    filerName: displayName(from: row.name),
                    position: row.title,
                    filingID: filingID,
                    disclosedDate: disclosedDate,
                    documentURL: row.documentURL
                )
                let lines = text.components(separatedBy: .newlines)
                let result = OGE278TNativeParser.parse(lines: lines, filing: filing)

                if !result.warnings.isEmpty { warnings[filingID] = result.warnings }
                if result.trades.isEmpty {
                    stats.filingsYieldingNoTrades.append(filingID)
                } else {
                    trades.append(contentsOf: result.trades)
                    stats.tradesParsed += result.trades.count
                    if let memberID = result.trades.first?.memberID, membersByID[memberID] == nil {
                        membersByID[memberID] = Member(
                            id: memberID, bioguideID: nil, name: filing.filerName,
                            state: "", district: nil, chamber: .executive
                        )
                    }
                }
            } catch {
                stats.filingsFailedToFetch.append(filingID)
                warnings[filingID] = ["fetch failed: \(error.localizedDescription)"]
            }

            onProgress?(offset + 1, rows.count, trades.count)
            try? await Task.sleep(for: politenessDelay)
        }

        return PTRFetcher.Output(
            trades: trades,
            members: membersByID.values.sorted { $0.name < $1.name },
            stats: stats,
            warningsByFiling: warnings
        )
    }

    /// "Bondi, Pam" → "Pam Bondi" — the index lists filers "Last, First", every other
    /// chamber's `memberName` reads "First Last".
    private func displayName(from lastFirst: String) -> String {
        let parts = lastFirst.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2 else { return lastFirst }
        return "\(parts[1]) \(parts[0])"
    }
}
#endif
