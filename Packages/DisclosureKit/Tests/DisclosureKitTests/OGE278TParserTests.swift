import Foundation
import Testing
@testable import DisclosureKit

/// `OGE278TParser` against hand-built lines shaped like `VisionText.lines` output for the
/// three real President Donald J. Trump 278-T filings pulled while building this (a
/// municipal-bond-and-corporate-note portfolio, no tickers, no owner column) — see
/// `_private` notes for the source PDFs. These are plain strings, not OCR output, so the
/// suite runs without Vision and pins the row grammar independently of recognition
/// accuracy.
@Suite("OGE 278-T parser")
struct OGE278TParserTests {

    static func filing(disclosedDate: CalendarDate? = CalendarDate(iso: "2026-04-23")) -> OGE278TFilingRef {
        OGE278TFilingRef(
            filerName: "President Donald J. Trump",
            position: "President of the United States of America",
            filingID: "wh-2026-04-20",
            disclosedDate: disclosedDate
        )
    }

    @Test("Parses purchase, sale, and exchange rows, including a real range and a 'No' notification flag")
    func parsesRows() {
        let lines = [
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
            "3  LOWER COLO RIV AUTH 5% DUE 05/15/35  purchase  3/4/2026  Yes  $1,000,001 - $5,000,000",
            "4  TEXAS WTR DEV BRD ST RVLNG FD REV B/E 4.00 % Due Aug 1, 2036  purchase  3/18/2026  No  $15,001 - $50,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 3)
        #expect(result.trades.map(\.txType) == [.sell, .buy, .buy])
        #expect(result.trades[0].asset == "ARLINGTON TEX INDPT 5% DUE 02/15/31")
        #expect(result.trades[0].amount.label == "$500,001 – $1,000,000")
        #expect(result.trades[0].amount.kind == .range)
        #expect(result.trades[2].txDate == CalendarDate(iso: "2026-03-18"))
        #expect(result.trades.allSatisfy { $0.ticker == nil && $0.assetType == nil && $0.owner == .self })
        #expect(result.trades.allSatisfy { $0.disclosedDate == CalendarDate(iso: "2026-04-23") })
        #expect(result.warnings.isEmpty)
    }

    @Test("A description containing digits and punctuation does not confuse the row anchor")
    func complexDescription() {
        let lines = [
            "62  AMERICAN HONDA FIN NTS 04.450% 010831 DTD010826 FC070826 CALL@MW+15BP YTM = 4.295 UNSOLICITED ACCRUE  purchase  3/3/2026  Yes  $250,001 - $500,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
        #expect(result.trades[0].asset.hasPrefix("AMERICAN HONDA FIN NTS"))
        #expect(result.trades[0].amount.label == "$250,001 – $500,000")
    }

    @Test("Reads the disclosed date from an 'OGE Received' line when the filing ref carries none")
    func recoversReceivedDateFromLines() {
        let lines = [
            "OGE Received: 4/23/2026",
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing(disclosedDate: nil))
        #expect(result.trades.first?.disclosedDate == CalendarDate(iso: "2026-04-23"))
    }

    @Test("Falls back to the OGE certifying official's digital-signature date when no 'OGE Received' line exists")
    func fallsBackToCertificationDate() {
        let lines = [
            "KEITH SONDERLING Digitally signed by KEITH SONDERLING  8/20/26",
            "-Date: 2026.08.20 16:24:34 -04'00",
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing(disclosedDate: nil))
        #expect(result.trades.first?.disclosedDate == CalendarDate(iso: "2026-08-20"))
        #expect(result.warnings.contains {
            $0.contains("no \"OGE Received\" line found") && $0.contains("2026-08-20")
        })
    }

    @Test("An explicit 'OGE Received' line is preferred over the certification-date fallback when both are present")
    func explicitReceivedDateBeatsFallback() {
        let lines = [
            "OGE Received: 4/23/2026",
            "-Date: 2026.04.24 08:37:12 -04'00",
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing(disclosedDate: nil))
        #expect(result.trades.first?.disclosedDate == CalendarDate(iso: "2026-04-23"))
        #expect(!result.warnings.contains { $0.contains("certifying official") })
    }

    @Test("The certification-date line is never folded into a row's description")
    func certificationDateLineIsBoilerplate() {
        let lines = [
            "-Date: 2026.08.20 16:24:34 -04'00",
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing(disclosedDate: nil))
        #expect(result.trades.first?.asset == "ARLINGTON TEX INDPT 5% DUE 02/15/31")
    }

    @Test("No disclosed date anywhere: rows are skipped and reported, never dated wrong")
    func noDisclosedDateSkipsRows() {
        let lines = ["1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000"]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing(disclosedDate: nil))
        #expect(result.trades.isEmpty)
        #expect(result.warnings.contains { $0.contains("no \"OGE Received\" date") })
    }

    @Test("A line with no recognizable row anchor is ignored, not misread as a transaction")
    func ignoresNonRowLines() {
        let lines = [
            "OGE Form 278-T (Updated February 2024)",
            "Filer's Name",
            "Donald J Trump",
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
    }

    @Test("Vision's bare-S-for-dollar-sign and period-for-thousands-comma misreads are corrected")
    func normalizesOCRAmountNoise() {
        // Real OCR output observed against a sample filing: a bare "S" where the form
        // prints "$", and "." where it prints ",", sometimes both in the same amount.
        let lines = [
            "14  BLACK BELT ENERGY GAS DIST AL GAS PJ 6 SER B B/E 4.00 % Due Oct 1, 2052  purchase  3/10/2026  Yes  S500,001 - $1,000,000",
            "18  MINIDOKA JEROME CNTY ID JT SCH DIST 331  purchase  3/9/2026  Yes  S1.000.001 - S5.000.000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 2)
        #expect(result.trades[0].amount.label == "$500,001 – $1,000,000")
        #expect(result.trades[0].amount.kind == .range)
        #expect(result.trades[1].amount.label == "$1,000,001 – $5,000,000")
        #expect(result.trades[1].amount.kind == .range)
        #expect(result.warnings.isEmpty)
    }

    @Test("A dollar sign OCR'd as a bare digit is left unreadable rather than guessed at")
    func ambiguousDigitForDollarSignStaysUnknown() {
        // "$500,001" misread as "5500,001" is indistinguishable from a genuine
        // "$500,001" bracket that lost its sign a different way — correctness here
        // means flagging it, not picking one.
        let lines = ["1  SOME BOND DESCRIPTION  purchase  3/9/2026  Yes  5500,001 -51,000,000"]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.first?.amount.kind == .unknown)
        #expect(result.warnings.contains { $0.contains("amount unreadable") })
    }

    @Test("An unreadable amount still yields the row, flagged unknown rather than dropped")
    func unreadableAmountIsKeptAndFlagged() {
        let lines = ["1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  garbled text here"]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
        #expect(result.trades[0].amount.kind == .unknown)
        #expect(result.warnings.contains { $0.contains("amount unreadable") })
    }

    @Test("Every trade's id is unique per row number within a filing")
    func idsAreUniquePerRow() {
        let lines = [
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
            "2  ENERGY NORTHWES 3.503% DUE 07/01/26 XTRO TAXBL  sale  3/6/2026  Yes  $1,000,001 - $5,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(Set(result.trades.map(\.id)).count == 2)
    }

    @Test("A description that wraps onto its own OCR line is folded into the row instead of lost")
    func mergesWrappedDescription() {
        // Real shape observed against a sample filing: the two-line description cell
        // and the single-line type/date/amount cell land in different vertical bands, so
        // VisionText.lines returns them as two separate lines.
        let lines = [
            "2  ENERGY NORTHWES 3.503% DUE 07/01/26",
            "XTRO TAXBL",
            "sale  3/6/2026  Yes  $1,000,001 - $5,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
        #expect(result.trades[0].asset == "ENERGY NORTHWES 3.503% DUE 07/01/26 XTRO TAXBL")
        #expect(result.trades[0].amount.label == "$1,000,001 – $5,000,000")
        #expect(!result.warnings.contains { $0.contains("description was empty") })
    }

    @Test("A recoverable fused date (missing slash, 3 digits) is re-split and parses correctly")
    func recoverableFusedDate() {
        // "514/2026" for "5/14/2026" — a single-digit month fused to the day, still
        // unambiguous to re-split.
        let lines = ["11  INVESCO GGQ TR  sale  514/2026  No  $250,001 - $500,000"]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
        #expect(result.trades[0].txDate == CalendarDate(iso: "2026-05-14"))
        #expect(result.warnings.isEmpty)
    }

    @Test("An unrecoverable fused date (4 digits, no valid month) is its own unreadable row, not merged into the next one")
    func unrecoverableFusedDateStaysItsOwnRow() {
        // Real shape observed against a sample filing: "5114/2026" for "5/14/2026" splits
        // to month "51", which is not a valid month — the row is attributed to itself as
        // unreadable, not folded into whichever row happens to come next.
        let lines = [
            "225  ISHARES U.S. TREASURY  sale  5114/2026  No  $15,001 - $50,000",
            "226  JOHNSON & JOHNSON  sale  5/14/2026  No  $500,001 - $1,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
        #expect(result.trades[0].asset == "JOHNSON & JOHNSON")
        #expect(result.warnings.contains { $0.contains("unreadable date \"5114/2026\"") })
    }

    @Test("Reprinted page furniture between rows is never folded into a description")
    func boilerplateBetweenRowsIsIgnored() {
        let lines = [
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
            "OGE Form 278-T (Updated February 2024)",
            "Filer's Name",
            "Donald J Trump  Page 6 of 8",
            "Transactions",
            "Description  TypeDate  Days Ago",
            "131  SAN JACINTO TX CMNTY CLG BE/R/ 5 DUE 021532  purchase  03/27/2026  No  $100,001 - $250,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 2)
        #expect(result.trades[1].asset == "SAN JACINTO TX CMNTY CLG BE/R/ 5 DUE 021532")
    }

    @Test("A header line OCR mangles past recognition still costs only a cosmetic prefix, never the numbers")
    func unrecognizedBoilerplateStaysCosmeticOnly() {
        // "Received Over 30 Days Ago" as Vision actually read it once, real filing: the
        // boilerplate matcher does not catch this specific garbling, so it is folded in
        // as if it were description text — undesirable, but the date/type/amount, which
        // matter far more than the description string, are unaffected.
        let lines = [
            "acelved Over 3  Notlficatio",
            "131  SAN JACINTO TX CMNTY CLG BE/R/ 5 DUE 021532  purchase  03/27/2026  No  $100,001 - $250,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
        #expect(result.trades[0].asset.hasSuffix("SAN JACINTO TX CMNTY CLG BE/R/ 5 DUE 021532"))
        #expect(result.trades[0].txDate == CalendarDate(iso: "2026-03-27"))
        #expect(result.trades[0].amount.label == "$100,001 – $250,000")
    }

    @Test("A run of unmatched lines longer than a real wrapped description is discarded, not welded on")
    func longUnmatchedRunIsDiscarded() {
        let lines = [
            "line one", "line two", "line three", "line four", "line five",
            "1  ARLINGTON TEX INDPT 5% DUE 02/15/31  sale  3/6/2026  Yes  $500,001 - $1,000,000",
        ]
        let result = OGE278TParser.parse(lines: lines, filing: Self.filing())
        #expect(result.trades.count == 1)
        #expect(!result.trades[0].asset.contains("line one"))
        #expect(result.warnings.contains { $0.contains("discarded") })
    }

    @Test("No transaction rows at all is reported, not silently empty")
    func emptyLinesWarns() {
        let result = OGE278TParser.parse(lines: ["Nothing to see here"], filing: Self.filing())
        #expect(result.trades.isEmpty)
        #expect(result.warnings.contains { $0.contains("no transaction rows") })
    }
}
