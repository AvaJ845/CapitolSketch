import Foundation
import Testing
@testable import DisclosureKit

/// Pins the security-relevant behaviour of the network layer, using `StubURLProtocol`
/// so nothing here touches the real Clerk. These cover the guards added in the
/// "response bounds" security pass: an oversized or hostile response must never be
/// buffered, parsed, or allowed to masquerade as fresh data, and a cached copy must be
/// revalidated rather than trusted because it exists.
@Suite("Fetch layer", .serialized)
struct FetchTests {

    // A minimal but real Clerk index: header row, then three Periodic Transaction
    // Reports. `\t`-separated, ≥ 9 columns, filing type "P".
    static func indexText(year: Int, docIDs: [String]) -> String {
        var lines = ["Prefix\tLast\tFirst\tSuffix\tFilingType\tStateDst\tYear\tFilingDate\tDocID"]
        for (i, id) in docIDs.enumerated() {
            lines.append("Hon.\tMember\(i)\tFirst\(i)\t\tP\tCA0\(i)\t\(year)\t8/0\(i + 1)/\(year)\t\(id)")
        }
        return lines.joined(separator: "\n")
    }

    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fetchtests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func seed(filingID: String) -> TradeFeed {
        let trade = Trade(
            id: "\(filingID)-seed", memberID: "x-seed", memberName: "Seed Member",
            owner: .self, asset: "SEED", ticker: "SEED", assetType: "ST", txType: .buy,
            txDate: CalendarDate(iso: "2026-07-01")!, disclosedDate: CalendarDate(iso: "2026-07-10")!,
            amount: DisclosedAmount(kind: .range, lowCents: 100_100, highCents: 1_500_000,
                                    label: "$1,001 - $15,000"),
            filingDescription: nil, filingID: filingID, documentURL: nil
        )
        return FeedBuilder.make(
            trades: [trade],
            members: [Member(id: "x-seed", bioguideID: nil, name: "Seed Member",
                             state: "CA", district: "1", chamber: .house)],
            stats: ParseStats(filingsProcessed: 1, tradesParsed: 1),
            indexYears: [2026]
        )
    }

    // MARK: - 1. Oversized index response

    @Test("An index response past the size cap is refused, not buffered")
    func oversizedIndexWithNoCacheThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.ok(for: request), Data(count: FilingIndex.maxResponseBytes + 1))
        }

        do {
            _ = try await FilingIndex.fetch(
                year: 2026, cacheDirectory: nil, session: StubURLProtocol.makeSession()
            )
            Issue.record("expected a throw")
        } catch let error as FilingIndex.IndexError {
            guard case .tooLarge(let year, let bytes) = error else {
                Issue.record("expected .tooLarge, got \(error)")
                return
            }
            #expect(year == 2026)
            #expect(bytes == FilingIndex.maxResponseBytes + 1)
        } catch {
            Issue.record("expected FilingIndex.IndexError, got \(error)")
        }
    }

    @Test("An oversized index response falls back to the on-disk cache when one exists")
    func oversizedIndexFallsBackToCache() async throws {
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        let cached = Self.indexText(year: 2026, docIDs: ["20000001"])
        try cached.write(to: cache.appendingPathComponent("2026FD.txt"),
                         atomically: true, encoding: .utf8)

        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.ok(for: request), Data(count: FilingIndex.maxResponseBytes + 1))
        }

        let rows = try await FilingIndex.fetch(
            year: 2026, cacheDirectory: cache, session: StubURLProtocol.makeSession()
        )
        #expect(rows.map(\.docID) == ["20000001"])
    }

    // MARK: - 2. Oversized PDF

    @Test("A PDF past the size cap is dropped as a fetch failure and never parsed")
    func oversizedPDFCountsAsFailure() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.ok(for: request), Data(count: PTRFetcher.maxPDFBytes + 1))
        }

        let filing = FilingIndexRow(
            last: "Member", first: "First", suffix: "", filingType: "P",
            stateDst: "CA01", year: 2026, filedOn: CalendarDate(iso: "2026-08-01"),
            docID: "20000042"
        )
        let fetcher = PTRFetcher(session: StubURLProtocol.makeSession())
        let output = await fetcher.run(filings: [filing], directory: nil)

        #expect(output.trades.isEmpty)
        #expect(output.stats.tradesParsed == 0)
        #expect(output.stats.filingsFailedToFetch == ["20000042"])
        // Never handed to the parser: it would have landed in one of these instead.
        #expect(output.stats.filingsYieldingNoTrades.isEmpty)
        #expect(output.stats.filingsWithoutText.isEmpty)
        #expect(StubURLProtocol.recordedURLs == [
            URL(string: "https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2026/20000042.pdf")!
        ])
    }

    // MARK: - 3. HTTP 304

    @Test("A 304 revalidation returns the cached rows and still makes the request")
    func notModifiedUsesCacheButRevalidates() async throws {
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        let cached = Self.indexText(year: 2026, docIDs: ["20000100", "20000101"])
        try cached.write(to: cache.appendingPathComponent("2026FD.txt"),
                         atomically: true, encoding: .utf8)
        try "\"etag-abc\"".write(to: cache.appendingPathComponent("2026FD.etag"),
                                 atomically: true, encoding: .utf8)

        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            // The request must carry the stored validator — not a blind cache read.
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"etag-abc\"")
            return (StubURLProtocol.response(for: request, status: 304), Data())
        }

        let rows = try await FilingIndex.fetch(
            year: 2026, cacheDirectory: cache, session: StubURLProtocol.makeSession()
        )
        #expect(rows.map(\.docID) == ["20000100", "20000101"])
        #expect(StubURLProtocol.recordedURLs == [FilingIndex.textURL(year: 2026)])
    }

    // MARK: - 4. Non-2xx

    @Test("A 500 throws badStatus, and falls back to cache when one exists")
    func serverErrorIsBadStatusWithCacheFallback() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.response(for: request, status: 500), Data("upstream error".utf8))
        }

        // No cache: the specific error case surfaces.
        do {
            _ = try await FilingIndex.fetch(
                year: 2026, cacheDirectory: nil, session: StubURLProtocol.makeSession()
            )
            Issue.record("expected a throw")
        } catch let error as FilingIndex.IndexError {
            guard case .badStatus(let code, let year) = error else {
                Issue.record("expected .badStatus, got \(error)")
                return
            }
            #expect(code == 500)
            #expect(year == 2026)
        }

        // Cache present: the last good copy is served rather than failing outright.
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        try Self.indexText(year: 2026, docIDs: ["20000200"])
            .write(to: cache.appendingPathComponent("2026FD.txt"), atomically: true, encoding: .utf8)

        let rows = try await FilingIndex.fetch(
            year: 2026, cacheDirectory: cache, session: StubURLProtocol.makeSession()
        )
        #expect(rows.map(\.docID) == ["20000200"])
    }

    // MARK: - 5. Cached PDF short-circuits the network

    @Test("A cached PDF is returned with zero network requests")
    func cachedPDFMakesNoRequest() async throws {
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }

        // A real fixture PDF, dropped in at the path PTRFetcher caches to.
        let pdf = try Data(contentsOf: Fixture.pelosiMultiAsset.url)
        try pdf.write(to: cache.appendingPathComponent("ptr-2026-20035143.pdf"))

        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            Issue.record("no request should be made when the PDF is cached: \(request.url as Any)")
            return (StubURLProtocol.response(for: request, status: 500), Data())
        }

        let filing = FilingIndexRow(
            last: "Pelosi", first: "Nancy", suffix: "", filingType: "P",
            stateDst: "CA11", year: 2026, filedOn: CalendarDate(iso: "2026-08-21"),
            docID: "20035143"
        )
        let fetcher = PTRFetcher(session: StubURLProtocol.makeSession(), cacheDirectory: cache)
        let output = await fetcher.run(filings: [filing], directory: nil)

        #expect(StubURLProtocol.recordedURLs.isEmpty)
        #expect(!output.trades.isEmpty)
        #expect(output.stats.filingsFailedToFetch.isEmpty)
    }

    // MARK: - 6. Watchlist-independence (executable invariant)

    @Test("The refresh request sequence depends only on the seed and the date, never the watchlist")
    func refreshRequestSequenceIsWatchlistIndependent() async {
        // The watchlist (`WatchlistStore`) lives in the app target and has no path into
        // DisclosureKit: `IncrementalRefresher.refresh` takes only
        // `seed / years / maxDownloads / concurrency / cacheDirectory / session` — there
        // is no watchlist, ticker, holdings, member or count parameter, and the body
        // reads no `UserDefaults`. This test proves the request sequence is a pure
        // function of the seed + calendar by capturing it twice under different ambient
        // watchlist state and asserting byte-for-byte equality.

        let index = Self.indexText(year: 2026, docIDs: ["30000001", "30000002", "30000003"])
        // The seed already has 30000001, so 30000002 and 30000003 are the new filings,
        // fetched newest-filed first.
        let expected: [URL] = [
            FilingIndex.textURL(year: 2026),
            URL(string: "https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2026/30000003.pdf")!,
            URL(string: "https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2026/30000002.pdf")!,
        ]

        func capture() async -> [URL] {
            StubURLProtocol.reset()
            let body = index
            StubURLProtocol.handler = { request in
                let url = request.url!
                if url.path.hasSuffix("2026FD.txt") {
                    return (StubURLProtocol.ok(for: request), Data(body.utf8))
                }
                // PDFs 404 — the URL is still recorded, which is all this test reads.
                return (StubURLProtocol.response(for: request, status: 404), Data())
            }
            _ = await IncrementalRefresher.refresh(
                seed: Self.seed(filingID: "30000001"),
                years: [2026],
                concurrency: 1,               // deterministic request ordering
                cacheDirectory: nil,
                session: StubURLProtocol.makeSession()
            )
            return StubURLProtocol.recordedURLs
        }

        // Baseline: nothing in the watchlist, nobody followed.
        UserDefaults.standard.removeObject(forKey: "watchlistTickers")
        UserDefaults.standard.removeObject(forKey: "followedMembers")
        let withoutWatchlist = await capture()
        #expect(withoutWatchlist == expected)

        // A fully-populated watchlist AND a populated followed-members list in ambient
        // storage must change nothing — neither is a parameter of the refresh, and the
        // refresher reads no `UserDefaults`.
        UserDefaults.standard.set(
            ["AAPL", "TSLA", "NVDA", "MSFT", "SEED", "GOOG"], forKey: "watchlistTickers"
        )
        UserDefaults.standard.set(
            ["P000197", "x-seed", "S000510", "R000619"], forKey: "followedMembers"
        )
        let withWatchlist = await capture()
        UserDefaults.standard.removeObject(forKey: "watchlistTickers")
        UserDefaults.standard.removeObject(forKey: "followedMembers")

        #expect(withWatchlist == withoutWatchlist)
        #expect(withWatchlist == expected)
    }
}

// P0-3: refresh liveness is reported separately from data age. `reachedClerk` is the
// seam the app and widget use to stamp "last reached the Clerk"; it must be true only
// on a genuine good exchange, and a suspicious response must be distinguishable from a
// plain offline run. Kept in the same `.serialized` suite as the fetch tests because
// they share `StubURLProtocol`'s global state.
extension FetchTests {

    static func runRefresh(
        handler: @escaping StubURLProtocol.Handler,
        seedFilingID: String = "40000001",
        cacheDirectory: URL? = nil
    ) async -> IncrementalRefresher.Report {
        StubURLProtocol.reset()
        StubURLProtocol.handler = handler
        let outcome = await IncrementalRefresher.refresh(
            seed: seed(filingID: seedFilingID),
            years: [2026],
            concurrency: 1,
            cacheDirectory: cacheDirectory,
            session: StubURLProtocol.makeSession()
        )
        return outcome.report
    }

    static var freshIndex: String { indexText(year: 2026, docIDs: ["40000001", "40000002"]) }

    @Test("A 200 on the index counts as reaching the Clerk")
    func healthyRefreshReachesClerk() async {
        let report = await Self.runRefresh {  request in
            let url = request.url!
            if url.path.hasSuffix("2026FD.txt") {
                return (StubURLProtocol.ok(for: request), Data(Self.freshIndex.utf8))
            }
            return (StubURLProtocol.response(for: request, status: 404), Data())
        }
        #expect(report.reachedClerk)
        #expect(!report.clerkReturnedUnexpected)
    }

    @Test("A legitimate 304 counts as reaching the Clerk")
    func notModifiedReachesClerk() async throws {
        let cache = FetchTests.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        try FetchTests.indexText(year: 2026, docIDs: ["40000001"])
            .write(to: cache.appendingPathComponent("2026FD.txt"), atomically: true, encoding: .utf8)
        try "\"v1\"".write(to: cache.appendingPathComponent("2026FD.etag"),
                           atomically: true, encoding: .utf8)

        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.response(for: request, status: 304), Data())
        }
        let (_, contact) = try await FilingIndex.fetchWithContact(
            year: 2026, cacheDirectory: cache, session: StubURLProtocol.makeSession()
        )
        #expect(contact == .notModified)
        #expect(contact.reachedClerk)

        // And through a full refresh.
        let report = await Self.runRefresh(
            handler: { request in (StubURLProtocol.response(for: request, status: 304), Data()) },
            seedFilingID: "40000001",
            cacheDirectory: cache
        )
        #expect(report.reachedClerk)
        #expect(!report.clerkReturnedUnexpected)
    }

    @Test("An oversized index response is reached-but-unexpected, not offline")
    func oversizedIndexIsUnexpected() async {
        let report = await Self.runRefresh {  request in
            (StubURLProtocol.ok(for: request), Data(count: FilingIndex.maxResponseBytes + 1))
        }
        #expect(!report.reachedClerk)
        #expect(report.clerkReturnedUnexpected)
        #expect(report.summary.contains("unexpected response"))
    }

    @Test("A 500 on the index is reached-but-unexpected, not offline")
    func serverErrorIsUnexpected() async {
        let report = await Self.runRefresh {  request in
            (StubURLProtocol.response(for: request, status: 500), Data("nope".utf8))
        }
        #expect(!report.reachedClerk)
        #expect(report.clerkReturnedUnexpected)
        #expect(report.summary.contains("unexpected response"))
    }

    @Test("A transport failure is plain offline, not an unexpected response")
    func offlineIsNotUnexpected() async {
        let report = await Self.runRefresh {  _ in throw URLError(.notConnectedToInternet) }
        #expect(!report.reachedClerk)
        #expect(!report.clerkReturnedUnexpected)
        #expect(report.summary.contains("Couldn't reach the House Clerk"))
    }

    @Test("fetchWithContact labels a 200 fresh and a cache fallback served-from-cache")
    func contactLabels() async throws {
        // 200
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.ok(for: request), Data(FetchTests.indexText(year: 2026, docIDs: ["1"]).utf8))
        }
        let fresh = try await FilingIndex.fetchWithContact(
            year: 2026, cacheDirectory: nil, session: StubURLProtocol.makeSession()
        )
        #expect(fresh.contact == .fresh)
        #expect(fresh.contact.reachedClerk)

        // 500 with a cache present -> served from cache, not reached
        let cache = FetchTests.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        try FetchTests.indexText(year: 2026, docIDs: ["2"])
            .write(to: cache.appendingPathComponent("2026FD.txt"), atomically: true, encoding: .utf8)
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            (StubURLProtocol.response(for: request, status: 503), Data())
        }
        let stale = try await FilingIndex.fetchWithContact(
            year: 2026, cacheDirectory: cache, session: StubURLProtocol.makeSession()
        )
        #expect(stale.contact == .servedFromCache(.badStatus(503)))
        #expect(!stale.contact.reachedClerk)
        #expect(stale.contact == .servedFromCache(.badStatus(503)))
        if case .servedFromCache(let reason) = stale.contact {
            #expect(reason.isUnexpectedResponse)
        }
    }
}
