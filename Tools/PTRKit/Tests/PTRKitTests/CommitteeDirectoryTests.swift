import Foundation
import Testing
@testable import PTRKit

/// The offline floor: a machine with no warm cache and no network still produces
/// committee data from the copy checked in under `Sources/PTRKit/ReferenceData/`,
/// and says so in the report.
@Suite("CommitteeDirectory offline fallback")
struct CommitteeDirectoryTests {

    /// A session whose every request fails, standing in for "no network".
    private static func offlineSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AlwaysFailingProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("No cache, no network → roster comes from the checked-in copy")
    func fallsBackToBundledCopy() async throws {
        let emptyCache = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptrkit-test-\(UUID().uuidString)")

        let (roster, report) = await CommitteeDirectory.load(
            cacheDirectory: emptyCache, force: true, session: Self.offlineSession()
        )

        let roster2 = try #require(roster)
        #expect(!roster2.byBioguide.isEmpty)
        #expect(roster2.committeeCount > 15)
        #expect(Set(report.filesFromBundle) == [
            "committees-current.json", "committee-membership-current.json",
        ])
        #expect(report.filesFailed.isEmpty)

        // A verbatim, recognisable full-committee name is present.
        let names = Set(roster2.byBioguide.values.flatMap { $0 })
        #expect(names.contains("House Committee on Armed Services"))
    }

    @Test("A warm, fresh cache is preferred over the bundled copy")
    func prefersFreshCache() async throws {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptrkit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        // Seed the cache with the bundled bytes so "fresh cache" and "bundled" differ only
        // in provenance, then confirm the loader reports cache, not bundle.
        for name in ["committees-current.json", "committee-membership-current.json"] {
            let bundled = try #require(CommitteeDirectory.bundledCopy(named: name))
            try bundled.write(to: cache.appendingPathComponent(name))
        }

        let (roster, report) = await CommitteeDirectory.load(
            cacheDirectory: cache, force: false, session: Self.offlineSession()
        )

        #expect(roster != nil)
        #expect(report.filesFromBundle.isEmpty)
    }
}

private final class AlwaysFailingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
