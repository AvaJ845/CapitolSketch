import Foundation
import PDFKit
import Testing
@testable import DisclosureKit

/// A stub `URLProtocol` local to this file — see `WhiteHouseFilingIndexTests`'s own copy
/// for why this isn't shared: two suites racing the same static handler produced a real
/// cross-suite failure once already this session. Deliberately matches that file's
/// `LocalStubProtocol` exactly, with no added state of its own (no lock, no recorded-URL
/// array): adding an `NSLock`-protected tracking array here once reproduced a genuine
/// multi-minute hang under `swift test`'s default parallel execution — gone the moment
/// that lock was removed, confirmed by re-running the full suite clean. Whether never
/// requesting the amendment's URL matters is checked by making the handler itself fail
/// the test if that URL is ever asked for, not by inspecting a side log afterward.
private final class FetcherStubProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    nonisolated(unsafe) static var handler: Handler?

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FetcherStubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = FetcherStubProtocol.handler else {
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

@Suite("White House fetcher — amendments", .serialized)
struct WhiteHouseFetcherTests {

    /// A minimal, real, openable PDF — content doesn't matter for this test, only that
    /// `PDFDocument(data:)` succeeds so the regular filing reaches the "no rows found"
    /// path rather than "PDF could not be opened", keeping the two failure modes distinct.
    private static func blankPDFData() -> Data {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        return doc.dataRepresentation()!
    }

    private static let disclosuresHTML = """
        <div class="wp-block-file"><a id="a" href="https://www.whitehouse.gov/wp-content/uploads/2026/01/President-Donald-J.-Trump-Periodic-Transaction-Report-Amendment-1.14.26.pdf">President Donald J. Trump Periodic Transaction Report Amendment 1.14.26</a></div>
        <div class="wp-block-file"><a id="b" href="https://www.whitehouse.gov/wp-content/uploads/2026/04/President-Donald-J.-Trump-Periodic-Transaction-Report-4.20.26.pdf">President Donald J. Trump Periodic Transaction Report 04.20.26</a></div>
        """

    @Test("An amendment is skipped before any network fetch — never even downloaded, let alone parsed")
    func amendmentNeverFetched() async throws {
        let pdfData = Self.blankPDFData()
        FetcherStubProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url == WhiteHouseFilingIndex.indexURL {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(Self.disclosuresHTML.utf8)
                )
            }
            // The amendment's own PDF URL must never be requested — this is the
            // regression the fix exists for. Failing the handler itself, rather than
            // inspecting a log after the fact, is the whole assertion.
            if url.lastPathComponent.contains("Amendment") {
                Issue.record("the amendment's PDF was fetched — it should have been skipped before any network call")
                throw URLError(.cancelled)
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, pdfData)
        }

        let fetcher = WhiteHouseFetcher(session: FetcherStubProtocol.makeSession(), politenessDelay: .zero)
        let output = try await fetcher.run()

        #expect(output.stats.filingsWithoutText.contains { $0.contains("Amendment") })
        let amendmentWarning = output.warningsByFiling.first { $0.key.contains("Amendment") }?.value.first
        #expect(amendmentWarning?.contains("amendment") == true)
        #expect(amendmentWarning?.contains("not machine-readable") == true)
    }

    @Test("A regular filing alongside an amendment is still fetched and processed normally")
    func regularFilingStillFetched() async throws {
        let pdfData = Self.blankPDFData()
        FetcherStubProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url == WhiteHouseFilingIndex.indexURL {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(Self.disclosuresHTML.utf8)
                )
            }
            if url.lastPathComponent.contains("Amendment") {
                Issue.record("the amendment's PDF was fetched — it should have been skipped before any network call")
                throw URLError(.cancelled)
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, pdfData)
        }

        let fetcher = WhiteHouseFetcher(session: FetcherStubProtocol.makeSession(), politenessDelay: .zero)
        let output = try await fetcher.run()

        // Two filings discovered, one skipped as an amendment, one actually fetched — the
        // regular filing's own outcome (a blank PDF, so zero rows) lands in
        // filingsYieldingNoTrades, never filingsFailedToFetch, which is only reachable if
        // the fetch itself happened and returned 200.
        #expect(output.stats.filingsProcessed == 2)
        #expect(output.stats.filingsFailedToFetch.isEmpty)
        #expect(output.stats.filingsYieldingNoTrades.contains { $0.contains("4.20.26") })
    }
}
