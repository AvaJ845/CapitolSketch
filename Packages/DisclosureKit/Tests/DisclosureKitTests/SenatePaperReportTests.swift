import Foundation
import Testing
@testable import DisclosureKit

/// The paper-report page carries the scanned filing as carousel GIFs. Locating them in
/// page order is the first step of the OCR path in `_private/SENATE.md`; parsing the images is not
/// done yet.
@Suite("Senate paper report image extraction")
struct SenatePaperReportTests {

    @Test("Every filingImage GIF is returned, in carousel (page) order")
    func extractsOrderedImageURLs() {
        let urls = SenatePaperReport.imageURLs(fromHTML: SenateFixture.paper.html)

        #expect(urls.map(\.lastPathComponent) == [
            "000000513.gif", "000000514.gif", "000000515.gif", "000000516.gif",
        ])
        #expect(urls.allSatisfy { $0.host == "efd-media-public.senate.gov" })
    }

    @Test("An electronic report page has no paper images")
    func electronicPageYieldsNothing() {
        #expect(SenatePaperReport.imageURLs(fromHTML: SenateFixture.coons.html).isEmpty)
    }

    @Test("Missing markup yields an empty list, not a crash")
    func emptyOnUnrecognisedHTML() {
        #expect(SenatePaperReport.imageURLs(fromHTML: "<html><body>no carousel</body></html>").isEmpty)
    }
}
