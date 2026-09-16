import Foundation
import PDFKit
import Testing
@testable import DisclosureKit

/// Real President Donald J. Trump OGE Form 278-T filings, trimmed to the one or two
/// pages that reproduce a specific, diagnosed OCR failure (both now fixed) and checked
/// in — the same reasoning `Fixture` and `SenateFixture` give: pinned to what real
/// primary-source PDFs actually do, not to whatever the parser happened to produce the
/// day it was written.
///
/// Both were pulled from whitehouse.gov/disclosures while hardening `OGE278TParser`
/// against real filings beyond the hand-built ones in `OGE278TParserTests`. Each is
/// trimmed from the original multi-page filing (page count noted below) down to the
/// cover page plus the one transaction page that reproduces the bug, to keep a scanned,
/// image-only PDF out of the repo at its original 20–30 MB size.
enum WhiteHouseFixture: String {
    /// The full filing (`President-Donald-J.-Trump-Periodic-Transaction-Report-08.12.26`,
    /// 34 pages) originally yielded zero trades: its cover page prints no "OGE Received:
    /// M/D/YYYY" line at all — unlike the filings `OGE278TParserTests` was first built
    /// against — only a certifying official's digital-signature block reading "…Date:
    /// 2026.08.20 16:24:34 -04'00'". `OGE278TParser` now falls back to that date when no
    /// "OGE Received" line is found, which is what recovers this filing's rows.
    /// Trimmed to page 1 (cover) + page 18 (one of ~30 transaction pages, ~40 rows).
    case missingOGEReceived = "trump-missing-oge-received.2026-08-12"

    /// The full filing (`President-Donald-J.-Trump-Periodic-Transaction-Report-0.6.25.26-2`,
    /// 37 pages, 321 of ~350 rows parse cleanly) has several rows where Vision drops the
    /// date's first `/` (`5/14/2026` read as `5114/2026`). That row's own anchor pattern
    /// originally failed to match at all — `OGE278TParser` required two literal slashes —
    /// so the row was buffered as an unmatched line and folded into the *next* row's
    /// description instead of being recognized as its own transaction: row 225 (ISHARES
    /// U.S. TREASURY) was lost, and its remnants landed in row 226's (JOHNSON & JOHNSON)
    /// `asset` string. `OGE278TParser` now also matches a date with the first slash
    /// fused into the day (`5114` → re-split `51/14`), so row 225 is recognized as its
    /// own row again — its date still doesn't survive the split (`51` is not a valid
    /// month), so it is reported "unreadable" rather than merged into a neighbor, which
    /// is the fix: attributed to itself, wrong date and all, never to another row. Row
    /// 226's own date is separately wrong for an unrelated reason (a `6`→`8` OCR
    /// misread, `2026`→`2028`), caught by the existing `Trade.hasImpossibleDate` flag
    /// rather than anything specific to this parser.
    /// Trimmed to page 1 (cover) + page 8 (the ISHARES/JOHNSON rows).
    case dateSlashMerge = "trump-date-slash-merge.2026-06-25"

    var document: PDFDocument {
        guard let url = Bundle.module.url(
            forResource: rawValue, withExtension: "pdf", subdirectory: "Fixtures/whitehouse"
        ), let doc = PDFDocument(url: url) else {
            fatalError("missing White House fixture \(rawValue).pdf")
        }
        return doc
    }

    func filing(disclosedDate: CalendarDate? = nil) -> OGE278TFilingRef {
        OGE278TFilingRef(
            filerName: "President Donald J. Trump",
            position: "President of the United States of America",
            filingID: rawValue,
            disclosedDate: disclosedDate
        )
    }

    func parse(disclosedDate: CalendarDate? = nil) -> OGE278TParser.ParseResult {
        let lines = OGE278TOCR.lines(from: document)
        return OGE278TParser.parse(lines: lines, filing: filing(disclosedDate: disclosedDate))
    }
}

@Suite("OGE 278-T parser against real White House filings")
struct WhiteHouseFixtureTests {

    @Test("FIXED — with no \"OGE Received\" line, the OGE certifying official's signature date recovers the filing")
    func missingOGEReceivedFallsBackToCertificationDate() {
        // This cover page prints no "OGE Received" line at all (confirmed against the
        // real filing) — only "KEITH SONDERLING Digitally signed by KEITH SONDERLING …
        // Date: 2026.08.20 16:24:34 -04'00'" in the certification block. Originally this
        // meant every row in the filing was skipped; `OGE278TParser` now falls back to
        // that signature date, reported rather than passed off as the real received date.
        let result = WhiteHouseFixture.missingOGEReceived.parse()
        #expect(result.trades.count > 15)
        #expect(result.trades.allSatisfy { $0.disclosedDate == CalendarDate(iso: "2026-08-20") })
        #expect(result.warnings.contains {
            $0.contains("no \"OGE Received\" line found") && $0.contains("2026-08-20")
        })
    }

    @Test("Explicitly supplying the disclosed date (as seedgen could, from the index page) is preferred over both")
    func explicitDisclosedDateWins() {
        let result = WhiteHouseFixture.missingOGEReceived.parse(disclosedDate: CalendarDate(iso: "2026-08-23"))
        #expect(result.trades.count > 15)
        #expect(result.trades.allSatisfy { $0.disclosedDate == CalendarDate(iso: "2026-08-23") })
        #expect(!result.warnings.contains { $0.contains("OGE Received") })
    }

    @Test("FIXED — a date missing its first slash is now its own (unreadable-date) row, not folded into its neighbor")
    func dateSlashMergeNoLongerMergesRows() {
        let result = WhiteHouseFixture.dateSlashMerge.parse(disclosedDate: CalendarDate(iso: "2026-06-29"))
        #expect(result.trades.count > 10)

        // Row 225 (ISHARES U.S. TREASURY) still never becomes a trade — its fused date
        // (`5114/2026` → `51/14/2026`) has no valid month — but it no longer drags row
        // 226 down with it, and it is reported, not silently dropped.
        #expect(!result.trades.contains { $0.asset.contains("ISHARES U.S. TREASURY") })
        #expect(result.warnings.contains { $0.contains("unreadable date \"5114/2026\"") })

        // Row 226 (JOHNSON & JOHNSON) is now a clean row on its own.
        let johnson = result.trades.first { $0.asset.contains("JOHNSON & JOHNSON") }
        #expect(johnson?.asset == "JOHNSON & JOHNSON")
        #expect(johnson?.amount.kind == .range)

        // Its date is separately wrong for an unrelated reason (a `6`→`8` misread), still
        // caught by the general mechanism every trade already carries.
        #expect(johnson?.hasImpossibleDate == true)
    }

    @Test("Every row on the sampled page that does anchor-match cleanly is unaffected by the fix")
    func dateSlashMergeDoesNotSpreadBeyondTheOneRow() {
        let result = WhiteHouseFixture.dateSlashMerge.parse(disclosedDate: CalendarDate(iso: "2026-06-29"))
        let cleanRow = result.trades.first { $0.asset == "ZOETIS INC" }
        #expect(cleanRow?.txType == .sell)
        #expect(cleanRow?.txDate == CalendarDate(iso: "2026-05-11"))
        #expect(cleanRow?.amount.label == "$15,001 – $50,000")
        #expect(cleanRow?.hasImpossibleDate == false)
    }
}
