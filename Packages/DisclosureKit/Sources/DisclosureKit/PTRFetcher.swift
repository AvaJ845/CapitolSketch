import Foundation

/// Downloads and parses Periodic Transaction Reports.
///
/// Shared by the build-time Mac CLI (which walks whole years) and the app (which fetches
/// only filings newer than the bundled seed), so both run byte-identical parsing logic.
public struct PTRFetcher: Sendable {

    public struct Progress: Sendable {
        public let completed: Int
        public let total: Int
        public let tradesSoFar: Int
    }

    public struct Output: Sendable {
        public var trades: [Trade]
        public var members: [Member]
        public var stats: ParseStats
        /// Per-filing warnings, keyed by document ID. Surfaced, never swallowed.
        public var warningsByFiling: [String: [String]]
    }

    private let session: URLSession
    private let concurrency: Int
    private let cacheDirectory: URL?
    /// Identity decisions the seed already made, consulted before the directory.
    ///
    /// The app has no crosswalk on device and should not download one. A filer the seed
    /// already names must resolve to the same ID here, or a refreshed row would appear
    /// as a second copy of a member the app already lists.
    private let nameToMemberID: [String: String]

    public init(
        session: URLSession = .shared,
        concurrency: Int = 4,
        cacheDirectory: URL? = nil,
        nameToMemberID: [String: String] = [:]
    ) {
        self.session = session
        self.concurrency = max(1, concurrency)
        self.cacheDirectory = cacheDirectory
        self.nameToMemberID = nameToMemberID
    }

    /// Fetches and parses the given filings.
    public func run(
        filings: [FilingIndexRow],
        directory: MemberDirectory?,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async -> Output {
        let knownNames = nameToMemberID
        var trades: [Trade] = []
        var membersByID: [String: Member] = [:]
        var stats = ParseStats()
        var warnings: [String: [String]] = [:]

        var index = 0
        while index < filings.count {
            let end = min(index + concurrency, filings.count)
            let batch = Array(filings[index..<end])
            index = end

            let results = await withTaskGroup(
                of: (FilingIndexRow, ParseResult).self
            ) { group -> [(FilingIndexRow, ParseResult)] in
                for filing in batch {
                    group.addTask {
                        let ref = makeRef(for: filing, directory: directory, knownNames: knownNames)
                        guard let data = await fetchPDF(for: filing) else {
                            return (filing, ParseResult(
                                trades: [], hadReadableText: false,
                                warnings: ["download failed"]
                            ))
                        }
                        #if canImport(PDFKit)
                        return (filing, PTRParser.parse(pdfData: data, filing: ref))
                        #else
                        return (filing, ParseResult(
                            trades: [], hadReadableText: false,
                            warnings: ["PDFKit unavailable on this platform"]
                        ))
                        #endif
                    }
                }
                var out: [(FilingIndexRow, ParseResult)] = []
                for await r in group { out.append(r) }
                return out
            }

            for (filing, result) in results {
                stats.filingsProcessed += 1
                if !result.warnings.isEmpty { warnings[filing.docID] = result.warnings }

                if result.warnings.contains("download failed") {
                    stats.filingsFailedToFetch.append(filing.docID)
                } else if result.trades.isEmpty {
                    if result.hadReadableText && !result.recoveredByOCR {
                        // An embedded text layer, but no rows recognised — a parser failure.
                        stats.filingsYieldingNoTrades.append(filing.docID)
                    } else {
                        // A scan: no text layer, and OCR either failed or could not be
                        // structured into rows. Still missing, not a parser bug.
                        stats.filingsWithoutText.append(filing.docID)
                    }
                } else {
                    trades.append(contentsOf: result.trades)
                    stats.tradesParsed += result.trades.count
                    let member = makeMember(for: filing, directory: directory, knownNames: knownNames)
                    membersByID[member.id] = member
                }
            }

            onProgress?(Progress(
                completed: stats.filingsProcessed, total: filings.count, tradesSoFar: trades.count
            ))
        }

        return Output(
            trades: trades,
            members: membersByID.values.sorted { $0.name < $1.name },
            stats: stats,
            warningsByFiling: warnings
        )
    }

    /// Ceiling on a single PDF. A House PTR is tens to a few hundred KB; the largest
    /// multi-hundred-page filings are a handful of MB. Past this is a broken or hostile
    /// server — see the threat model on `FilingIndex`.
    static let maxPDFBytes = 64 * 1024 * 1024

    private func fetchPDF(for filing: FilingIndexRow) async -> Data? {
        let cached = cacheDirectory?
            .appendingPathComponent("ptr-\(filing.year)-\(filing.docID).pdf")
        if let cached, let data = try? Data(contentsOf: cached) { return data }
        // `filing.documentURL` is `houseDocumentURL`, which pins scheme + host and only
        // interpolates a docID it has checked is bare alphanumerics.
        guard let url = filing.documentURL else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= Self.maxPDFBytes else { return nil }
            if let cached {
                try? FileManager.default.createDirectory(
                    at: cached.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                // Atomic: a crash mid-write must not leave a truncated PDF that the
                // cache check above would then hand back forever without re-fetching.
                try? data.write(to: cached, options: .atomic)
            }
            return data
        } catch {
            return nil
        }
    }
}

/// Builds the identifier and display fields for a filing's member.
func resolveMemberID(
    for filing: FilingIndexRow,
    directory: MemberDirectory?,
    knownNames: [String: String] = [:]
) -> (id: String, bioguide: String?) {
    // A name the seed already resolved wins outright, so a device refresh can never
    // file the same member under a second identifier.
    if let known = knownNames[filing.fullName] {
        return (known, MemberDirectory.isBioguideID(known) ? known : nil)
    }
    guard let directory else {
        return (MemberDirectory.fallbackID(
            last: filing.last, first: filing.first,
            state: filing.state, district: filing.district
        ), nil)
    }
    switch directory.resolve(
        last: filing.last, first: filing.first,
        state: filing.state, district: filing.district
    ) {
    case let .resolved(bio):
        return (bio, bio)
    case .ambiguous, .notFound:
        // Never collapse two people into one ID on a guess.
        return (MemberDirectory.fallbackID(
            last: filing.last, first: filing.first,
            state: filing.state, district: filing.district
        ), nil)
    }
}

func makeRef(
    for filing: FilingIndexRow, directory: MemberDirectory?, knownNames: [String: String] = [:]
) -> FilingRef {
    FilingRef(
        docID: filing.docID,
        year: filing.year,
        memberName: filing.fullName,
        memberID: resolveMemberID(
            for: filing, directory: directory, knownNames: knownNames
        ).id,
        filedOn: filing.filedOn
    )
}

func makeMember(
    for filing: FilingIndexRow, directory: MemberDirectory?, knownNames: [String: String] = [:]
) -> Member {
    let resolved = resolveMemberID(for: filing, directory: directory, knownNames: knownNames)
    return Member(
        id: resolved.id,
        bioguideID: resolved.bioguide,
        name: filing.fullName,
        state: filing.state,
        district: filing.district,
        // v1 reads the House index only. Stated plainly in the UI rather than implied.
        chamber: .house
    )
}

/// Removes restatements. Amended filings repeat transactions already disclosed.
///
/// An amendment that restates a transaction with every fingerprint field unchanged
/// (confirmed against a real one — House docID 20033759, which added only a "Comments"
/// annotation and a row ID Congress does not print on the un-amended original) collapses
/// here, into whichever copy appeared first — the seed's own row when this runs inside
/// `FeedBuilder.merge`, so an already-shown trade keeps its filing ID and link rather
/// than silently swapping to the amendment's on every refresh. An amendment that changes
/// a fingerprint field (a corrected date or bracket) does *not* collide here — nothing in
/// any source this app reads says which earlier row such a correction replaces, so
/// guessing that link is not attempted; both rows survive as two disclosures. See
/// `possibleDuplicateAmendments(in:)` for surfacing that residual case instead of hiding it.
public func deduplicate(_ trades: [Trade]) -> [Trade] {
    var seen = Set<String>()
    var out: [Trade] = []
    for t in trades {
        // The member, plus the fields that define the transaction. Asset type is in the
        // fingerprint: a stock buy and a call-option buy on the same ticker, same day,
        // in the same bracket are two distinct disclosures. This is the same key the
        // row's content id is built from, so "same id" and "gets de-duplicated" agree.
        let key = t.memberID + "|" + transactionFingerprint(t)
        if seen.insert(key).inserted { out.append(t) }
    }
    return out
}

/// A looser identity than `transactionFingerprint` — ticker, asset type, transaction
/// type, owner and the *transaction* date, but not the amount, which is what a bracket
/// correction actually changes.
///
/// The transaction date stays in this key deliberately, even though a correction could
/// in principle change it too — a first version of this excluded it and, run against the
/// real production feed, flagged 255 rows, nearly all of them ordinary same-ticker
/// repeat trading (a senator dollar-cost-averaging into the same ETF every few days is
/// indistinguishable from a correction once the date is dropped from the key). Keeping
/// the date makes this precise rather than merely cautious: two rows that claim to be
/// the exact same day's transaction but disagree on the amount is a real, narrow signal;
/// "this member traded this ticker more than once" is not.
private func correctionIdentity(_ t: Trade) -> String {
    [t.memberID, (t.ticker ?? t.asset).uppercased(), t.assetType ?? "",
     t.txType.rawValue, t.owner.rawValue, t.txDate.iso].joined(separator: "|")
}

/// Rows `deduplicate(_:)` could not resolve because their full fingerprint genuinely
/// differs — the amount changed — but that still share a member, ticker, asset type,
/// transaction type, owner and transaction *date* with another surviving row, where at
/// least one of the group is flagged `isAmendment`.
///
/// This is the case `deduplicate(_:)`'s own doc comment names and does not attempt to
/// fix: an amendment correcting a fingerprint field has no stated link, in any source
/// this app reads, to the specific row it corrects, so both survive as separate
/// disclosures — one of them likely stale or an outright duplicate of real-world intent,
/// but which one is not something to guess at. Called after de-duplication, over the
/// feed's full trade list, so it can be surfaced (a `seedgen` log line today; a UI
/// affordance would be a separate, larger change) rather than silently trusted either way.
public func possibleDuplicateAmendments(in dedupedTrades: [Trade]) -> [Trade] {
    Dictionary(grouping: dedupedTrades, by: correctionIdentity)
        .values
        .filter { group in group.count > 1 && group.contains(where: \.isAmendment) }
        .flatMap { $0 }
        .sorted { $0.id < $1.id }
}
