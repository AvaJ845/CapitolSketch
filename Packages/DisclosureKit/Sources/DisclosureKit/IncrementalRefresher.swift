import Foundation

/// Brings a shipped seed feed up to date from the House Clerk directly, on device.
///
/// There is no server in this app. The Clerk is the host: the app ships a snapshot built
/// at release time, and at runtime asks the Clerk's own index which filings have appeared
/// since, then reads only those PDFs. A full ingest is thousands of documents and is
/// never attempted here — that work belongs to `seedgen` on a Mac.
///
/// **The request pattern is identical for every user.** The index URL, the PDF URLs and
/// the order they are fetched in derive only from the shipped snapshot's contents and the
/// calendar. No watchlist, holding, ticker, member or any other user-held value takes
/// part in choosing what to fetch, and none is ever sent anywhere. Filtering by what a
/// reader owns happens strictly after the bytes are on the device, against data every
/// other reader received in exactly the same form. This is what keeps the app inside the
/// publisher's exclusion: the trigger may be personal, the content never is.
public enum IncrementalRefresher {

    public struct Report: Sendable, Equatable {
        /// PTR filings named by the Clerk's index across the requested years.
        public var indexedFilings = 0
        /// Filings in that index the snapshot had never seen.
        public var newFilings = 0
        /// PDFs actually fetched this run, after the per-refresh cap.
        public var downloaded = 0
        public var addedTrades = 0
        /// Filings that opened but hold no text layer — photographs of paper forms.
        public var scannedPaper = 0
        /// Anything that failed for another reason, with why.
        public var failures: [String] = []
        /// True when more new filings exist than this run was willing to fetch.
        public var moreRemaining = false

        /// True when at least one requested index year came back a clean HTTP 200 or a
        /// legitimate 304. Callers persist a "last reached the Clerk" timestamp only
        /// when this is true — never on an error, an over-cap body, or an offline run.
        public var reachedClerk = false
        /// True when the Clerk answered but with something we would not accept — a
        /// non-2xx status, an over-cap body, or undecodable bytes. Distinct from a
        /// plain offline run, and worth saying so: it can mean an outage or an attacker
        /// forcing a bad response to freeze the index behind the normal disclosure lag.
        public var clerkReturnedUnexpected = false

        /// Plain-language summary. The app never claims to be current without saying
        /// what "current" cost, so this is written to be shown, not just logged.
        public var summary: String {
            if addedTrades == 0 {
                if clerkReturnedUnexpected {
                    return "The Clerk returned an unexpected response; showing the last data downloaded."
                }
                if !reachedClerk && (!failures.isEmpty || indexedFilings == 0) {
                    return "Couldn't reach the House Clerk. Showing the filings already downloaded."
                }
            }
            if newFilings == 0 { return "No new filings since the last check." }
            if addedTrades == 0 {
                if downloaded > 0, scannedPaper < downloaded {
                    // Filings were read fine; they just restated trades already on file.
                    return "Checked \(downloaded) new filing\(downloaded == 1 ? "" : "s"); nothing to add."
                }
                return "\(newFilings) new filing\(newFilings == 1 ? "" : "s"), none readable."
            }
            var s = "Added \(addedTrades) transaction\(addedTrades == 1 ? "" : "s")"
            s += " from \(downloaded) filing\(downloaded == 1 ? "" : "s")."
            if scannedPaper > 0 { s += " \(scannedPaper) were scanned paper and yielded nothing." }
            if moreRemaining { s += " More remain; check again to continue." }
            return s
        }
    }

    public struct Outcome: Sendable {
        /// Nil when nothing changed, so a caller can skip persisting and re-rendering.
        public var feed: TradeFeed?
        public var report: Report

        public init(feed: TradeFeed?, report: Report) {
            self.feed = feed
            self.report = report
        }
    }

    /// - Parameters:
    ///   - seed: the feed currently in hand — bundled snapshot or a previous refresh.
    ///   - maxDownloads: hard ceiling on PDFs per run. A day of House filings is well
    ///     under this; the cap exists so a months-old build cannot turn one launch into
    ///     a thousand requests to a government file server.
    public static func refresh(
        seed: TradeFeed,
        years: [Int]? = nil,
        maxDownloads: Int = 60,
        concurrency: Int = 4,
        cacheDirectory: URL? = nil,
        session: URLSession = .shared
    ) async -> Outcome {
        var report = Report()
        let years = years ?? FilingIndex.relevantYears()

        // 1. What does the Clerk have? One public index, the same for every reader.
        var indexed: [FilingIndexRow] = []
        for year in years {
            do {
                let (rows, contact) = try await FilingIndex.fetchWithContact(
                    year: year, cacheDirectory: cacheDirectory, session: session
                )
                indexed += rows.filter(\.isPeriodicTransactionReport)
                if contact.reachedClerk { report.reachedClerk = true }
                if case let .servedFromCache(reason) = contact, reason.isUnexpectedResponse {
                    report.clerkReturnedUnexpected = true
                    report.failures.append("index \(year): the Clerk returned an unexpected response")
                }
            } catch {
                if case let FilingIndex.IndexError.badStatus(code, _) = error, code != -1 {
                    report.clerkReturnedUnexpected = true
                } else if case FilingIndex.IndexError.tooLarge = error {
                    report.clerkReturnedUnexpected = true
                } else if case FilingIndex.IndexError.undecodable = error {
                    report.clerkReturnedUnexpected = true
                }
                report.failures.append("index \(year): \(error.localizedDescription)")
            }
        }
        report.indexedFilings = indexed.count
        guard !indexed.isEmpty else { return Outcome(feed: nil, report: report) }

        // 2. Which of those is the snapshot missing? Compared by filing ID, not by date:
        //    filings arrive out of order and are routinely backdated.
        let known = Set(seed.trades.map(\.filingID))
        var fresh = indexed.filter { !known.contains($0.docID) }
        report.newFilings = fresh.count
        guard !fresh.isEmpty else { return Outcome(feed: nil, report: report) }

        // Newest filings first, so a capped run reads the most useful ones.
        fresh.sort { ($0.filedOn ?? .distantPast) > ($1.filedOn ?? .distantPast) }
        if fresh.count > maxDownloads {
            report.moreRemaining = true
            fresh = Array(fresh.prefix(maxDownloads))
        }

        // 3. Read them with the same parser and the same identity decisions the seed
        //    used. No crosswalk is downloaded on device: a filer the seed already names
        //    resolves from the seed's own name map, and a genuinely new filer keeps a
        //    fallback key rather than being dropped or guessed at.
        let fetcher = PTRFetcher(
            session: session,
            concurrency: concurrency,
            cacheDirectory: cacheDirectory,
            nameToMemberID: seed.nameToMemberID
        )
        let output = await fetcher.run(filings: fresh, directory: nil)

        report.downloaded = output.stats.filingsProcessed
        report.scannedPaper = output.stats.filingsWithoutText.count
        report.addedTrades = output.trades.count
        for id in output.stats.filingsFailedToFetch {
            report.failures.append("\(id): download failed")
        }
        for id in output.stats.filingsYieldingNoTrades {
            report.failures.append("\(id): readable but no rows matched")
        }

        guard !output.trades.isEmpty else { return Outcome(feed: nil, report: report) }

        let merged = FeedBuilder.merge(
            seed: seed,
            newTrades: output.trades,
            newMembers: output.members,
            newStats: output.stats
        )
        // De-duplication can absorb a row the seed already had under another filing.
        report.addedTrades = merged.trades.count - seed.trades.count
        return Outcome(feed: merged, report: report)
    }
}

extension CalendarDate {
    /// Sorts ahead of every real filing date, for rows the index left undated.
    static let distantPast = CalendarDate(year: 0, month: 1, day: 1)
}
