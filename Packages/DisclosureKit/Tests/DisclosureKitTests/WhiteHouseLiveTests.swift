import Foundation
@testable import DisclosureKit
import Testing

/// Hits whitehouse.gov/disclosures/ for real. Disabled in the normal run — it is network-
/// dependent and the page's own markup could change without notice. Run it by hand
/// (`swift test --filter "disclosures page is reachable"`) before a seed regeneration to
/// confirm the scrape still finds real filings.
@Suite("White House disclosures — live", .disabled("network; run manually before regenerating the seed"))
struct WhiteHouseLiveTests {

    @Test("disclosures page is reachable: at least one President PTR comes back, dated and linked")
    func reachable() async throws {
        let rows = try await WhiteHouseFilingIndex.fetchFilings()
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.filerName.hasPrefix("President") })
        #expect(rows.allSatisfy { $0.documentURL.absoluteString.hasSuffix(".pdf") })
        #expect(rows.contains { $0.filedOn != nil })
    }
}
