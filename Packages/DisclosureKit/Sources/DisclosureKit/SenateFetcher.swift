// Senate eFD portal scraping. The shipping app is House-only and no app or widget code
// path reaches any type in this file; it is compiled only for `seedgen` and the
// DisclosureKit test target, both of which define SEEDGEN. See P0-2 in the security
// review and `Package.swift`.
#if SEEDGEN
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches and parses every Senate Periodic Transaction Report filed since a cutoff.
///
/// **Build-time only** — `seedgen` calls this on a Mac; the app never does. One CSRF
/// handshake, then the session is reused for the index query and every report fetch.
/// Electronic reports parse now; paper reports are recorded as missing until the OCR
/// path (`SENATE.md`, step 2) lands.
public struct SenateFetcher: Sendable {

    private let directory: MemberDirectory?
    private let politenessDelay: Duration

    public init(directory: MemberDirectory?, politenessDelay: Duration = .milliseconds(700)) {
        self.directory = directory
        self.politenessDelay = politenessDelay
    }

    public func run(
        since: CalendarDate,
        limit: Int? = nil,
        onProgress: (@Sendable (_ done: Int, _ total: Int, _ trades: Int) -> Void)? = nil
    ) async throws -> PTRFetcher.Output {
        let session = SenateFilingIndex.makeSession()
        var rows = try await SenateFilingIndex.fetchPTRs(
            since: since, politenessDelay: politenessDelay, session: session
        )
        if let limit, rows.count > limit { rows = Array(rows.prefix(limit)) }

        var trades: [Trade] = []
        var membersByID: [String: Member] = [:]
        var stats = ParseStats()
        var warnings: [String: [String]] = [:]

        for (offset, row) in rows.enumerated() {
            stats.filingsProcessed += 1
            let (memberID, bioguide) = resolveMember(row)
            let ref = SenateFilingRef(
                uuid: row.uuid, memberName: row.fullName, memberID: memberID,
                filedOn: row.filedOn, isPaper: row.isPaper, isAmendment: row.isAmendment
            )

            if row.isPaper {
                stats.filingsWithoutText.append(row.uuid)
                warnings[row.uuid] = ["paper filing — scanned page images; Senate OCR not yet implemented"]
                onProgress?(offset + 1, rows.count, trades.count)
                continue
            }

            let result: ParseResult
            do {
                guard let url = ref.documentURL else {
                    stats.filingsFailedToFetch.append(row.uuid); continue
                }
                let (data, response) = try await session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let html = String(data: data, encoding: .utf8)
                else { stats.filingsFailedToFetch.append(row.uuid); continue }
                result = SenatePTRParser.parse(reportHTML: html, filing: ref)
            } catch {
                stats.filingsFailedToFetch.append(row.uuid)
                warnings[row.uuid] = ["fetch failed: \(error.localizedDescription)"]
                continue
            }

            if !result.warnings.isEmpty { warnings[row.uuid] = result.warnings }

            if result.trades.isEmpty {
                stats.filingsYieldingNoTrades.append(row.uuid)
            } else {
                trades.append(contentsOf: result.trades)
                stats.tradesParsed += result.trades.count
                membersByID[memberID] = Member(
                    id: memberID, bioguideID: bioguide, name: row.fullName,
                    state: stateFor(bioguide) ?? "", district: nil, chamber: .senate
                )
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

    // MARK: - Identity

    private func resolveMember(_ row: SenateFilingRow) -> (id: String, bioguide: String?) {
        let fallback = MemberDirectory.fallbackID(
            last: row.last, first: row.first, state: "", district: nil
        )
        guard let directory else { return (fallback, nil) }
        switch directory.resolve(last: row.last, first: row.first, chamber: .senate) {
        case let .resolved(bio): return (bio, bio)
        case .ambiguous, .notFound: return (fallback, nil)
        }
    }

    private func stateFor(_ bioguide: String?) -> String? {
        guard let bioguide, let directory else { return nil }
        return directory.entries.first { $0.bioguideID == bioguide }?.state
    }
}
#endif // SEEDGEN
