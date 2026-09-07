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
/// Electronic reports parse now; paper reports are recorded as incomplete, with their
/// scanned-page count, until the OCR + spatial-parser path (`SENATE.md`) lands.
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
        // eFD prints only a name; the crosswalk holds every historical namesake. A filer
        // has to have been serving during (or just before) the window this run covers.
        let servingYear = since.year

        for (offset, row) in rows.enumerated() {
            stats.filingsProcessed += 1
            let (memberID, bioguide) = resolveMember(row, servingInOrAfter: servingYear)
            // Use the crosswalk's common name on both the member record and every trade,
            // falling back to the eFD name when the filer did not resolve.
            let displayName = canonicalName(bioguide) ?? row.fullName
            let ref = SenateFilingRef(
                uuid: row.uuid, memberName: displayName, memberID: memberID,
                filedOn: row.filedOn, isPaper: row.isPaper, isAmendment: row.isAmendment
            )

            if row.isPaper {
                // Coverage-honest: a paper filing yields no transactions yet. Fetch the
                // report page anyway to record how many scanned pages it has — the input
                // the OCR + spatial-parser work in SENATE.md will consume.
                stats.filingsWithoutText.append(row.uuid)
                var note = "paper filing — scanned page images; not yet parsed"
                if let url = ref.documentURL,
                   let (data, response) = try? await session.data(from: url),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let html = String(data: data, encoding: .utf8) {
                    let pages = SenatePaperReport.imageURLs(fromHTML: html).count
                    if pages > 0 { note = "paper filing — \(pages) scanned page(s); not yet parsed" }
                }
                warnings[row.uuid] = [note]
                onProgress?(offset + 1, rows.count, trades.count)
                try? await Task.sleep(for: politenessDelay)
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
                    id: memberID, bioguideID: bioguide, name: displayName,
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

    private func resolveMember(
        _ row: SenateFilingRow, servingInOrAfter year: Int
    ) -> (id: String, bioguide: String?) {
        let fallback = MemberDirectory.fallbackID(
            last: row.last, first: row.first, state: "", district: nil
        )
        guard let directory else { return (fallback, nil) }
        switch directory.resolve(
            last: row.last, first: row.first, chamber: .senate, servingInOrAfter: year
        ) {
        case let .resolved(bio): return (bio, bio)
        case .ambiguous, .notFound: return (fallback, nil)
        }
    }

    private func stateFor(_ bioguide: String?) -> String? {
        guard let bioguide, let directory else { return nil }
        return directory.entries.first { $0.bioguideID == bioguide }?.state
    }

    /// "Mitch McConnell" from the crosswalk — its `first` is already the name the member
    /// goes by, not necessarily the legal forename.
    private func canonicalName(_ bioguide: String?) -> String? {
        guard let bioguide, let directory,
              let e = directory.entries.first(where: { $0.bioguideID == bioguide })
        else { return nil }
        return "\(e.first) \(e.last)"
    }
}
#endif // SEEDGEN
