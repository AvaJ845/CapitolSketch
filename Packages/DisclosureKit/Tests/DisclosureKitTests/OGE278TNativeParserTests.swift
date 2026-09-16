import Foundation
import PDFKit
import Testing
@testable import DisclosureKit

/// Real text-native OGE Form 278-T filings (filed via Integrity.gov), checked in trimmed
/// to size — both are already tiny (a few KB, 3 pages) since this source has no scanned
/// images to carry. Pinned the same way `Fixture` and `WhiteHouseFixture` are: to what
/// real primary-source PDFs actually contain.
enum NativeOGEFixture: String {
    case bondi = "bondi-doj-attorney-general.2025-05-05"
    case warsh = "warsh-federal-reserve.2026-08-06"

    var lines: [String] {
        guard let url = Bundle.module.url(
            forResource: rawValue, withExtension: "pdf", subdirectory: "Fixtures/oge-native"
        ), let doc = PDFDocument(url: url) else {
            fatalError("missing OGE native fixture \(rawValue).pdf")
        }
        return (doc.string ?? "").components(separatedBy: .newlines)
    }
}

@Suite("OGE 278-T native-text parser")
struct OGE278TNativeParserTests {

    static func filing(disclosedDate: CalendarDate = CalendarDate(iso: "2026-01-01")!) -> OGE278TNativeFilingRef {
        OGE278TNativeFilingRef(
            filerName: "Test Official", position: "Test Position",
            filingID: "native-test", disclosedDate: disclosedDate
        )
    }

    @Test("A single-line amount and a wrapped two-line amount both parse to the same range shape")
    func parsesSingleAndWrappedAmounts() {
        let lines = [
            "1 Trump Media & Technology Group Sale 04/02/2025 No $1,000,001 -",
            "$5,000,000",
            "2 THSDFS LLC - Series 58 Sale 07/14/2026 No $15,001 - $50,000",
        ]
        let result = OGE278TNativeParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 2)
        #expect(result.trades[0].amount.label == "$1,000,001 – $5,000,000")
        #expect(result.trades[1].amount.label == "$15,001 – $50,000")
        #expect(result.warnings.isEmpty)
    }

    @Test("Boilerplate lines around the table are never mistaken for rows")
    func ignoresBoilerplate() {
        let lines = [
            "# DESCRIPTION TYPE DATE NOTIFICATION",
            "AMOUNT",
            "RECEIVED OVER",
            "30 DAYS AGO",
            "1 Trump Media & Technology Group Sale 04/02/2025 No $1,000,001 - $5,000,000",
            "Endnotes",
            "Summary of Contents",
            "The 278-T discloses purchases, sales, or exchanges of securities in excess of $1,000.",
            "Bondi, Pam - Page 2",
        ]
        let result = OGE278TNativeParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
    }

    @Test("Row numbers must strictly increase, so a stray digit elsewhere is never read as a new row")
    func strictlyIncreasingRowNumbers() {
        let lines = [
            "1 First Holding Sale 04/02/2025 No $1,001 - $15,000",
            "2 Second Holding Purchase 04/03/2025 Yes $15,001 - $50,000",
        ]
        let result = OGE278TNativeParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.map(\.id) == ["native-test-1", "native-test-2"])
    }

    @Test("Purchase, sale, and exchange all map to the right trade type")
    func mapsAllThreeTypes() {
        let lines = [
            "1 A Sale 01/01/2026 No $1,001 - $15,000",
            "2 B Purchase 01/02/2026 No $1,001 - $15,000",
            "3 C Exchange 01/03/2026 No $1,001 - $15,000",
        ]
        let result = OGE278TNativeParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.map(\.txType) == [.sell, .buy, .exchange])
    }

    @Test("No transaction rows at all is reported, not silently empty")
    func emptyIsReported() {
        let result = OGE278TNativeParser.parse(lines: ["nothing here"], filing: Self.filing())
        #expect(result.trades.isEmpty)
        #expect(result.warnings.contains { $0.contains("no transaction rows") })
    }

    // MARK: - Real fixtures

    @Test("Real filing: Bondi (DOJ) — 2 clean rows, no warnings")
    func bondiFixture() {
        let result = OGE278TNativeParser.parse(
            lines: NativeOGEFixture.bondi.lines,
            filing: OGE278TNativeFilingRef(
                filerName: "Pam Bondi", position: "Attorney General",
                filingID: "bondi-test", disclosedDate: CalendarDate(iso: "2025-05-05")!
            )
        )
        #expect(result.trades.count == 2)
        #expect(result.trades.allSatisfy { $0.warnings.isEmpty })
        #expect(result.trades[0].amount.label == "$1,000,001 – $5,000,000")
        #expect(result.trades[1].asset == "Trump Media & Technology Group Warrants")
        #expect(result.warnings.isEmpty)
    }

    @Test("Real filing: Warsh (Federal Reserve) — 5 clean rows, mixing wrapped and unwrapped amounts")
    func warshFixture() {
        let result = OGE278TNativeParser.parse(
            lines: NativeOGEFixture.warsh.lines,
            filing: OGE278TNativeFilingRef(
                filerName: "Kevin Warsh", position: "Chairman, Federal Reserve",
                filingID: "warsh-test", disclosedDate: CalendarDate(iso: "2026-08-06")!
            )
        )
        #expect(result.trades.count == 5)
        #expect(result.trades.allSatisfy { $0.warnings.isEmpty })
        #expect(result.trades.allSatisfy { $0.txType == .sell })
        #expect(result.warnings.isEmpty)
    }
}
