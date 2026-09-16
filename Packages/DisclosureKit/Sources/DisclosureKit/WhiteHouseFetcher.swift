// White House OGE 278-T fetch + parse. The shipping app is House/Senate-only and no app
// or widget code path reaches any type in this file; it is compiled only for `seedgen`
// and the DisclosureKit test target, both of which define SEEDGEN — the same treatment
// `SenateFetcher.swift` gets, for the same reason: build-time-only ingestion.
#if SEEDGEN && canImport(Vision) && canImport(PDFKit)
import Foundation
import PDFKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches and parses every President Periodic Transaction Report the White House has
/// posted, via `WhiteHouseFilingIndex` for discovery and `OGE278TOCR` + `OGE278TParser`
/// for extraction.
///
/// **Build-time only** — same reasoning as `SenateFetcher`: a few filings a month, no
/// case for hitting whitehouse.gov from every reader's phone. Every filing found is
/// currently the President's; a future Vice President filer would need its own
/// `filerNamePattern` passed to `WhiteHouseFilingIndex.fetchFilings` and its own call
/// through this same fetcher — not a change to this type.
public struct WhiteHouseFetcher: Sendable {
    private let session: URLSession
    private let politenessDelay: Duration

    public init(
        session: URLSession = WhiteHouseFilingIndex.makeSession(),
        politenessDelay: Duration = .milliseconds(700)
    ) {
        self.session = session
        self.politenessDelay = politenessDelay
    }

    public func run(
        limit: Int? = nil,
        onProgress: (@Sendable (_ done: Int, _ total: Int, _ trades: Int) -> Void)? = nil
    ) async throws -> PTRFetcher.Output {
        var rows = try await WhiteHouseFilingIndex.fetchFilings(session: session)
        if let limit, rows.count > limit { rows = Array(rows.prefix(limit)) }

        var trades: [Trade] = []
        var stats = ParseStats()
        var warnings: [String: [String]] = [:]
        var membersByID: [String: Member] = [:]

        for (offset, row) in rows.enumerated() {
            stats.filingsProcessed += 1
            let filingID = "wh-\(row.documentURL.deletingPathExtension().lastPathComponent)"

            do {
                let (data, response) = try await session.data(from: row.documentURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    stats.filingsFailedToFetch.append(filingID)
                    onProgress?(offset + 1, rows.count, trades.count)
                    try? await Task.sleep(for: politenessDelay)
                    continue
                }
                guard let doc = PDFDocument(data: data) else {
                    stats.filingsWithoutText.append(filingID)
                    warnings[filingID] = ["PDF could not be opened"]
                    onProgress?(offset + 1, rows.count, trades.count)
                    try? await Task.sleep(for: politenessDelay)
                    continue
                }

                let lines = OGE278TOCR.lines(from: doc)
                let filing = OGE278TFilingRef(
                    filerName: row.filerName,
                    position: "President of the United States of America",
                    filingID: filingID,
                    disclosedDate: nil,
                    documentURL: row.documentURL,
                    isAmendment: row.isAmendment
                )
                let result = OGE278TParser.parse(lines: lines, filing: filing)

                if !result.warnings.isEmpty { warnings[filingID] = result.warnings }
                if result.trades.isEmpty {
                    stats.filingsYieldingNoTrades.append(filingID)
                } else {
                    trades.append(contentsOf: result.trades)
                    stats.tradesParsed += result.trades.count
                    if let memberID = result.trades.first?.memberID, membersByID[memberID] == nil {
                        membersByID[memberID] = Member(
                            id: memberID, bioguideID: nil, name: row.filerName,
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
}
#endif
