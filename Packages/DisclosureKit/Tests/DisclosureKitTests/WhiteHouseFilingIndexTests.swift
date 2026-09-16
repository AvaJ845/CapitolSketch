import Foundation
import Testing
@testable import DisclosureKit

/// `WhiteHouseFilingIndex.parse` against a fixture built from the disclosures page's real
/// markup (`<div class="wp-block-file"><a id="…" href="…pdf">Link Text</a></div>`,
/// confirmed against the live page before writing this), so no network is needed to pin
/// the scraping behavior.
@Suite("White House disclosures index — parsing")
struct WhiteHouseFilingIndexTests {

    static let fixture = """
        <div class="wp-block-file"><a id="wp-block-file--media-1" \
        href="https://www.whitehouse.gov/wp-content/uploads/2026/05/President-Donald-J.-Trump-Periodic-Transaction-Report-05.08.26-1.pdf">President Donald J. Trump Periodic Transaction Report 05.08.26 (1)</a></div>
        <div class="wp-block-file"><a id="wp-block-file--media-2" \
        href="https://www.whitehouse.gov/wp-content/uploads/2026/01/President-Donald-J.-Trump-Periodic-Transaction-Report-Amendment-1.14.26.pdf">President Donald J. Trump Periodic Transaction Report Amendment 1.14.26</a></div>
        <div class="wp-block-file"><a id="wp-block-file--media-3" \
        href="https://www.whitehouse.gov/wp-content/uploads/2025/12/President-Donald-J.-Trump-2025-Annual-Report.pdf">President Donald J. Trump 2025 Annual Report</a></div>
        <div class="wp-block-file"><a id="wp-block-file--media-4" \
        href="https://www.whitehouse.gov/wp-content/uploads/2026/04/Kenny-Stephen-Periodic-Transaction-Report-04.03.25-1.pdf">Kenny Stephen Periodic Transaction Report 04.03.25 (1)</a></div>
        <div class="wp-block-file"><a id="wp-block-file--media-5" \
        href="https://www.whitehouse.gov/wp-content/uploads/2026/04/President-Donald-J.-Trump-Periodic-Transaction-Report-4.20.26.pdf">President Donald J. Trump Periodic Transaction Report 04.20.26</a></div>
        """

    @Test("Keeps only the President's PTR links: excludes staff PTRs and the President's own annual report")
    func filtersToPresidentialPTRs() {
        let rows = WhiteHouseFilingIndex.parse(
            Self.fixture, matchingFilerNamed: WhiteHouseFilingIndex.presidentialFilerPattern
        )
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.filerName == "President Donald J. Trump" })
        #expect(!rows.contains { $0.linkText.contains("Annual Report") })
        #expect(!rows.contains { $0.linkText.contains("Kenny Stephen") })
    }

    @Test("Newest filing first, by the date parsed from the link text")
    func sortsNewestFirst() {
        let rows = WhiteHouseFilingIndex.parse(
            Self.fixture, matchingFilerNamed: WhiteHouseFilingIndex.presidentialFilerPattern
        )
        #expect(rows.map(\.filedOn) == [
            CalendarDate(iso: "2026-05-08"),
            CalendarDate(iso: "2026-04-20"),
            CalendarDate(iso: "2026-01-14"),
        ])
    }

    @Test("An amendment is flagged, a plain filing is not")
    func flagsAmendments() {
        let rows = WhiteHouseFilingIndex.parse(
            Self.fixture, matchingFilerNamed: WhiteHouseFilingIndex.presidentialFilerPattern
        )
        #expect(rows.first { $0.filedOn == CalendarDate(iso: "2026-01-14") }?.isAmendment == true)
        #expect(rows.first { $0.filedOn == CalendarDate(iso: "2026-04-20") }?.isAmendment == false)
    }

    @Test("Each PDF URL appears once even if the page linked it twice")
    func dedupesByURL() {
        let rows = WhiteHouseFilingIndex.parse(
            Self.fixture + "\n" + Self.fixture, matchingFilerNamed: WhiteHouseFilingIndex.presidentialFilerPattern
        )
        #expect(rows.count == 3)
    }

    @Test("A future filer pattern (e.g. a new administration) still matches, since the pattern has no name in it")
    func nameAgnosticPattern() {
        let futureAdmin = Self.fixture.replacingOccurrences(
            of: "President Donald J. Trump", with: "President Jane Q. Public"
        )
        let rows = WhiteHouseFilingIndex.parse(
            futureAdmin, matchingFilerNamed: WhiteHouseFilingIndex.presidentialFilerPattern
        )
        #expect(rows.allSatisfy { $0.filerName == "President Jane Q. Public" })
    }

    @Test("No PTR links on the page yields an empty list, not a crash")
    func emptyPage() {
        #expect(WhiteHouseFilingIndex.parse(
            "<html><body>Nothing here</body></html>",
            matchingFilerNamed: WhiteHouseFilingIndex.presidentialFilerPattern
        ).isEmpty)
    }
}

/// `WhiteHouseFilingIndex.fetchFilings`'s HTTP wiring. Uses its own `URLProtocol` stub
/// rather than the shared `StubURLProtocol` — that type's handler is global mutable
/// state, and `FetchTests` (a separate suite) also drives it; two suites racing the same
/// static handler produced a cross-suite failure (`FetchTests`'s handler answering this
/// suite's request) the one time both ran in the same `swift test` invocation. A private,
/// per-file stub sidesteps that instead of trying to serialize suites that share nothing
/// else.
private final class LocalStubProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    nonisolated(unsafe) static var handler: Handler?

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LocalStubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = LocalStubProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("White House disclosures index — fetch", .serialized)
struct WhiteHouseFilingIndexFetchTests {

    @Test("A 200 response is parsed for the President's filings")
    func fetchesAndParses() async throws {
        LocalStubProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(WhiteHouseFilingIndexTests.fixture.utf8))
        }
        let rows = try await WhiteHouseFilingIndex.fetchFilings(session: LocalStubProtocol.makeSession())
        #expect(rows.count == 3)
    }

    @Test("A non-2xx response throws badStatus rather than returning an empty list silently")
    func badStatusThrows() async {
        LocalStubProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        await #expect(throws: WhiteHouseFilingIndex.IndexError.self) {
            _ = try await WhiteHouseFilingIndex.fetchFilings(session: LocalStubProtocol.makeSession())
        }
    }
}
