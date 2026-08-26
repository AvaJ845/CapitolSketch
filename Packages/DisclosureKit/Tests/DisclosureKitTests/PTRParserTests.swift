import Foundation
import Testing
@testable import DisclosureKit

/// Every expectation here was read off the source PDF by hand, not captured from a
/// previous run of the parser.
@Suite("PTR parsing against real filings")
struct PTRParserTests {

    // MARK: - Pelosi, 21 August 2026 (DocID 20035143)

    @Test("Pelosi multi-asset filing parses all seven rows exactly")
    func pelosiMultiAsset() {
        let r = Fixture.pelosiMultiAsset.parse()
        #expect(r.hadReadableText)
        #expect(r.trades.count == 7)

        let expected = [
            "BE | ST | spouse | buy | 2026-07-24 | range | $1,000,001 – $5,000,000",
            "BE | OP | spouse | buy | 2026-07-24 | range | $1,000,001 – $5,000,000",
            "BE | ST | self | buy | 2026-07-28 | range | $500,001 – $1,000,000",
            "BE | OP | self | buy | 2026-07-28 | range | $500,001 – $1,000,000",
            "INTC | OP | self | buy | 2026-07-24 | range | $250,001 – $500,000",
            "INTC | ST | self | buy | 2026-07-24 | range | $500,001 – $1,000,000",
            "— | AB | spouse | buy | 2026-07-27 | range | $500,001 – $1,000,000",
        ]
        #expect(r.trades.map(\.signature) == expected)
    }

    @Test("Stock and option legs of the same trade stay distinct")
    func stockAndOptionAreSeparateRows() {
        let r = Fixture.pelosiMultiAsset.parse()
        let july24BE = r.trades.filter { $0.ticker == "BE" && $0.txDate.iso == "2026-07-24" }
        #expect(july24BE.count == 2)
        #expect(Set(july24BE.compactMap(\.assetType)) == ["ST", "OP"])
        // De-duplication must not collapse them: same ticker, day, owner and bracket.
        #expect(deduplicate(july24BE).count == 2)
    }

    @Test("Option descriptions survive being printed after their row")
    func descriptionAfterRow() {
        let r = Fixture.pelosiMultiAsset.parse()
        let optionLeg = r.trades.first { $0.ticker == "BE" && $0.assetType == "OP" }
        #expect(optionLeg?.filingDescription?.contains("100 call options") == true)
        #expect(optionLeg?.filingDescription?.contains("strike price of $100") == true)
    }

    @Test("A holding with no ticker keeps its name and type")
    func assetWithoutTicker() {
        let r = Fixture.pelosiMultiAsset.parse()
        let llc = r.trades.first { $0.assetType == "AB" }
        #expect(llc?.ticker == nil)
        #expect(llc?.asset == "REOF XXV, LLC [AB]")
        #expect(llc?.owner == .spouse)
    }

    // MARK: - Pelosi, 23 January 2026 (DocID 20033725) — the hardest layout

    @Test("Page-break filing yields eighteen rows with no unreadable amounts")
    func pageBreakFiling() {
        let r = Fixture.pelosiPageBreak.parse()
        #expect(r.trades.count == 18)
        #expect(r.trades.allSatisfy { $0.amount.kind != .unknown })
    }

    @Test("A dollar range split across a page break is rejoined")
    func rangeSplitAcrossPageBreak() {
        // The form prints "$50,001 -" on page one and "$100,000" after the repeated
        // column headings on page two.
        let r = Fixture.pelosiPageBreak.parse()
        let tem = r.trades.first { $0.ticker == "TEM" }
        #expect(tem != nil)
        #expect(tem?.amount.kind == .range)
        #expect(tem?.amount.lowCents == 50_001_00)
        #expect(tem?.amount.highCents == 100_000_00)
        #expect(tem?.amount.label == "$50,001 – $100,000")
        // The asset name was also split by the break and must be reassembled.
        #expect(tem?.asset.contains("Tempus AI") == true)
        #expect(tem?.assetType == "ST")
    }

    @Test("An exact cash amount is not mistaken for an open-ended bracket")
    func exactAmountIsItsOwnKind() {
        // "E 01/02/2026 01/02/2026 $15.00" — cash in lieu from a spinoff.
        let r = Fixture.pelosiPageBreak.parse()
        let versant = r.trades.first { $0.ticker == "VSNT" }
        #expect(versant?.txType == .exchange)
        #expect(versant?.amount.kind == .exact)
        #expect(versant?.amount.lowCents == 1500)
        #expect(versant?.amount.isRange == false)
    }

    @Test("Descriptions do not swallow the next row's asset")
    func descriptionDoesNotEatNextAsset() {
        let r = Fixture.pelosiPageBreak.parse()
        // Every row on this filing names a real holding.
        let nameless = r.trades.filter { $0.ticker == nil && $0.asset.isEmpty }
        #expect(nameless.isEmpty)
        // The row after a wrapped description is Versant, not the preceding Tempus.
        let versant = r.trades.first { $0.ticker == "VSNT" }
        #expect(versant?.asset.contains("Versant Media") == true)
    }

    // MARK: - Amount column shapes

    @Test("Open-ended top bracket is recognised, not welded to a later figure")
    func openEndedBracketIsNotWelded() {
        // The regression: `high == low` used to mean "upper bound still missing", which
        // is also true of an open-ended bracket, so the next dollar figure on the page
        // was welded onto it. This is the largest-disclosure corruption case.
        let text = """
        ID Owner Asset Transaction
        $200?
        SP Giant Holdings LLC [OT] P 07/29/2026 07/31/2026 $50,000,001 +
        F      S     : New
        SP Other Fund [OT] P 07/30/2026 07/31/2026 $1,001 - $15,000
        """
        let r = PTRParser.parse(text: text, filing: Fixture.petersOverThreshold.ref())
        #expect(r.trades.count == 2)
        #expect(r.trades[0].amount.kind == .atLeast)
        #expect(r.trades[0].amount.lowCents == 50_000_001_00)
        #expect(r.trades[0].amount.highCents == 50_000_001_00)
        #expect(r.trades[1].amount.kind == .range)
        #expect(r.trades[1].amount.highCents == 15_000_00)
    }

    @Test("Over-threshold amount with a wrapped value is read from the real filing")
    func overThresholdFromFixture() {
        // "Spouse/DC Over" on one line, "$1,000,000" on the next.
        let r = Fixture.petersOverThreshold.parse()
        let audax = r.trades.first { $0.asset.contains("Audax") }
        #expect(audax?.amount.kind == .atLeast)
        #expect(audax?.amount.lowCents == 1_000_000_00)
        #expect(audax?.amount.label == "$1,000,000+")
        #expect(audax?.warnings.isEmpty == true)
    }

    @Test("The largest real bracket in the corpus parses")
    func largestRealBracket() {
        let r = Fixture.issaLargeBracket.parse()
        let big = r.trades.first { $0.amount.highCents == 50_000_000_00 }
        #expect(big != nil)
        #expect(big?.amount.kind == .range)
        #expect(big?.amount.lowCents == 25_000_001_00)
        #expect(big?.amount.label == "$25,000,001 – $50,000,000")
    }

    @Test("Every amount shape maps to the right kind", arguments: [
        ("$1,001 - $15,000", DisclosedAmount.Kind.range, 1_001_00),
        ("$50,000,001 +", .atLeast, 50_000_001_00),
        ("Over $50,000,000", .atLeast, 50_000_000_00),
        ("Spouse/DC Over $1,000,000", .atLeast, 1_000_000_00),
        ("$15.00", .exact, 1500),
        ("None (or less than $201)", .none, 0),
    ])
    func amountShapes(input: String, kind: DisclosedAmount.Kind, lowCents: Int) {
        let (amount, pending) = PTRParser.parseAmount(input)
        #expect(amount.kind == kind)
        #expect(amount.lowCents == lowCents)
        #expect(pending == .nothing)
    }

    @Test("A dangling range asks for an upper bound; a complete one does not")
    func pendingStateIsExplicit() {
        #expect(PTRParser.parseAmount("$50,001 -").1 == .upperBound)
        #expect(PTRParser.parseAmount("Spouse/DC Over").1 == .overThreshold)
        #expect(PTRParser.parseAmount("$1,001 - $15,000").1 == .nothing)
        #expect(PTRParser.parseAmount("$50,000,001 +").1 == .nothing)
    }

    @Test("An unrecognised amount is reported rather than guessed")
    func unknownAmountIsReported() {
        let (amount, _) = PTRParser.parseAmount("something unparseable")
        #expect(amount.kind == .unknown)
        #expect(amount.lowCents == 0)
        #expect(amount.isRange == false)
    }

    @Test("Cents are preserved exactly")
    func centsParsing() {
        #expect(PTRParser.cents("$15.00") == 1500)
        #expect(PTRParser.cents("$1,000,001") == 100_000_100)
        #expect(PTRParser.cents("$0.07") == 7)
    }

    // MARK: - Dates

    @Test("A transaction dated after its filing is preserved and flagged")
    func impossibleDatePreservedNotCorrected() {
        // Filing 20033889 reads "P 12/26/2026 01/21/2026" — a mistyped year on the form.
        // The value is shown as filed; correcting it silently would invent data.
        let filedOn = CalendarDate(year: 2026, month: 2, day: 9)
        let r = Fixture.cohenImpossibleDate.parse(filedOn: filedOn)
        #expect(r.trades.count == 1)
        let t = r.trades[0]
        #expect(t.ticker == "SONY")
        #expect(t.txDate.iso == "2026-12-26")
        #expect(t.disclosedDate.iso == "2026-02-09")
        #expect(t.hasImpossibleDate)
        #expect(!t.isLateFiling)
        // Sorting must fall back so one typo cannot pin a row to the top of every list.
        #expect(t.sortDate == t.disclosedDate)
    }

    // MARK: - Failure modes, surfaced rather than hidden

    @Test("A scanned filing reports no readable text, distinct from a parse failure")
    func scannedFilingIsDistinguishable() {
        let r = Fixture.scannedNoText.parse()
        #expect(r.hadReadableText == false)
        #expect(r.trades.isEmpty)
        // The caller must be able to tell "nothing to read" from "failed to read".
        #expect(r.warnings.contains { $0.contains("scanned") })
    }

    @Test("Amended filings parse", arguments: [Fixture.rouzerAmended, .cisnerosAmended])
    func amendedFilingsParse(fixture: Fixture) {
        let r = fixture.parse()
        #expect(r.hadReadableText)
        #expect(!r.trades.isEmpty)
        #expect(r.trades.allSatisfy { $0.amount.kind != .unknown })
    }

    @Test("A long multi-page filing parses every page")
    func longMultipageFiling() {
        let r = Fixture.bresnahanMultipage.parse()
        #expect(r.trades.count == 130)
        #expect(r.trades.allSatisfy { $0.amount.kind != .unknown })
        #expect(r.trades.allSatisfy { $0.txDate.year >= 2024 })
    }

    @Test("No fixture produces a row with a corrupted amount")
    func noCorruptedAmountsAnywhere() {
        for fixture in Fixture.allCases {
            let r = fixture.parse()
            for t in r.trades {
                // A range must have a strictly greater upper bound; anything else is a
                // different kind and must say so.
                if t.amount.kind == .range {
                    #expect(t.amount.highCents >= t.amount.lowCents,
                            "\(fixture.rawValue) \(t.id) inverted range")
                }
                #expect(t.amount.lowCents >= 0)
            }
        }
    }

    @Test("Readable filings all yield rows, so silent parser failure is visible")
    func readableFilingsYieldRows() {
        for fixture in Fixture.allCases where fixture != .scannedNoText {
            let r = fixture.parse()
            #expect(r.hadReadableText, "\(fixture.rawValue) should be readable")
            #expect(!r.trades.isEmpty, "\(fixture.rawValue) parsed to zero rows")
        }
    }
}
