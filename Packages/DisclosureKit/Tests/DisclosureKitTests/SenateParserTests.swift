import Foundation
import Testing
@testable import DisclosureKit

/// Real efdsearch.senate.gov report pages, checked in so the parser is pinned to the
/// actual eFD layout rather than to whatever it produced the day it was written.
enum SenateFixture: String {
    case coons = "electronic-coons.5a76ceb6"
    case tuberville = "electronic-tuberville.57cf1745"
    case wyden = "electronic-wyden.5ecc9b5c"
    case paper = "paper-blumenthal.ec20cd93"

    var html: String {
        guard let url = Bundle.module.url(
            forResource: rawValue, withExtension: "html", subdirectory: "Fixtures/senate"
        ), let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("missing Senate fixture \(rawValue).html")
        }
        return text
    }

    func ref(paper: Bool = false) -> SenateFilingRef {
        SenateFilingRef(
            uuid: rawValue.components(separatedBy: ".").last ?? rawValue,
            memberName: "Fixture Senator", memberID: "x-fixture",
            filedOn: CalendarDate(year: 2026, month: 8, day: 28),
            isPaper: paper
        )
    }
}

@Suite("Senate PTR parsing against real eFD pages")
struct SenateParserTests {

    @Test("A single-transaction spouse filing parses with owner, bracket and description")
    func coonsSingleRow() {
        let r = SenatePTRParser.parse(reportHTML: SenateFixture.coons.html, filing: SenateFixture.coons.ref())
        #expect(r.hadReadableText)
        #expect(r.trades.count == 1)
        let t = try! #require(r.trades.first)
        #expect(t.owner == .spouse)
        #expect(t.txType == .partialSell)
        #expect(t.txDate == CalendarDate(year: 2026, month: 8, day: 7))
        #expect(t.amount.kind == .range)
        #expect(t.amount.lowCents == 100_001_00)
        #expect(t.amount.highCents == 250_000_00)
        #expect(t.asset.contains("Gore"))
        #expect(!t.asset.contains("Company:"))          // the inline sub-blocks are stripped
        #expect(t.filingDescription?.contains("Advanced materials") == true)
        #expect(t.ticker == nil)                        // "--"
        #expect(t.documentURL?.absoluteString.contains("/search/view/ptr/") == true)
    }

    @Test("A multi-row filing keeps every transaction, in order, with real values")
    func tubervilleMultiRow() {
        let r = SenatePTRParser.parse(
            reportHTML: SenateFixture.tuberville.html, filing: SenateFixture.tuberville.ref()
        )
        #expect(r.trades.count == 5)
        #expect(r.warnings.isEmpty)
        // Ids are filing-scoped and content-derived, not row positions.
        #expect(r.trades.allSatisfy { $0.id.hasPrefix("57cf1745-") })
        #expect(Set(r.trades.map(\.id)).count == 5)
        #expect(r.trades.allSatisfy { $0.owner == .self })
        #expect(r.trades.allSatisfy { $0.assetType == "ST" })
        #expect(r.trades.allSatisfy { $0.amount.kind == .range })
        #expect(r.trades.allSatisfy { $0.ticker != nil })
        #expect(r.trades.allSatisfy { !$0.asset.isEmpty && !$0.asset.contains("Company:") })
        // The filing mixes buys and partial sells — the parser must not flatten that.
        #expect(Set(r.trades.map(\.txType)) == [.buy, .partialSell])
        #expect(r.trades.contains { $0.ticker == "AAPL" })
    }

    @Test("An in-kind exchange with a stray ticker token does not crash the ticker column")
    func wydenExchange() {
        let r = SenatePTRParser.parse(reportHTML: SenateFixture.wyden.html, filing: SenateFixture.wyden.ref())
        #expect(r.trades.count == 1)
        let t = try! #require(r.trades.first)
        #expect(t.txType == .exchange)
        // "-- AMCR" — the "--" is dropped, the symbol-shaped token is kept.
        #expect(t.ticker == "AMCR")
        #expect(t.amount.kind == .range)
    }

    @Test("A paper filing has no electronic table and says so")
    func paperHasNoTable() {
        let r = SenatePTRParser.parse(reportHTML: SenateFixture.paper.html, filing: SenateFixture.paper.ref(paper: true))
        #expect(r.trades.isEmpty)
        #expect(r.hadReadableText == false)
        #expect(r.warnings.contains { $0.contains("no transaction table") })
    }

    @Test("The search-index JSON row parser reads UUIDs, paper vs electronic, and amendments")
    func indexRowParsing() throws {
        let url = try #require(Bundle.module.url(
            forResource: "report-index", withExtension: "json", subdirectory: "Fixtures/senate"
        ))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let raw = try #require(object?["data"] as? [[Any]])
        #expect(!raw.isEmpty)

        let rows = raw.compactMap(SenateFilingIndex.row(from:))
        #expect(rows.count == raw.count)
        #expect(rows.contains { $0.isPaper })                    // Blumenthal
        #expect(rows.contains { !$0.isPaper })                   // most of them
        #expect(rows.contains { $0.isAmendment })                // "(Amendment 1)"
        #expect(rows.allSatisfy { $0.uuid.count == 36 })
        #expect(rows.allSatisfy { $0.filedOn != nil })
    }
}
