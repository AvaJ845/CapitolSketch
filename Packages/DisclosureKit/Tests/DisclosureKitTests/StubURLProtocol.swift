import Foundation

/// A `URLProtocol` that answers every request from an in-test handler instead of the
/// network, and records the URL of every request it was asked to make.
///
/// Dependency-free and test-target-only. The fetch layer (`FilingIndex.fetch`,
/// `PTRFetcher`, `IncrementalRefresher.refresh`) all take an injectable `URLSession`;
/// hand them `StubURLProtocol.makeSession()` and set `StubURLProtocol.handler`.
///
/// Usage:
/// ```
/// StubURLProtocol.reset()
/// StubURLProtocol.handler = { request in
///     (StubURLProtocol.ok(for: request), Data("…".utf8))
/// }
/// let session = StubURLProtocol.makeSession()
/// … // exercise the code under test
/// #expect(StubURLProtocol.recordedURLs == [expectedURL])
/// ```
final class StubURLProtocol: URLProtocol {

    /// Everything the handler needs to build a reply. `URLRequest` is Sendable; the
    /// return tuple is (`HTTPURLResponse`, body). Throwing simulates a transport error.
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    // Shared mutable state, guarded by `lock`. `nonisolated(unsafe)` is the deliberate
    // opt-out: a URLProtocol is instantiated by URLSession on its own queue, so the
    // handler and the URL log are touched from a non-test thread.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _recordedURLs: [URL] = []

    static var handler: Handler? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    /// Every URL a request was started for, in order. The assertion surface for
    /// "which requests did this code actually make, and in what order".
    static var recordedURLs: [URL] {
        lock.withLock { _recordedURLs }
    }

    /// Clears the handler and the URL log. Call at the start of every test.
    static func reset() {
        lock.withLock {
            _handler = nil
            _recordedURLs = []
        }
    }

    private static func record(_ url: URL) {
        lock.withLock { _recordedURLs.append(url) }
    }

    /// A `URLSession` whose only protocol is this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    /// Convenience: an `HTTPURLResponse` for `request.url` with the given status and headers.
    static func response(
        for request: URLRequest, status: Int, headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://disclosures-clerk.house.gov/")!,
            statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
    }

    static func ok(for request: URLRequest, headers: [String: String] = [:]) -> HTTPURLResponse {
        response(for: request, status: 200, headers: headers)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        StubURLProtocol.record(url)

        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
