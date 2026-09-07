#if canImport(Vision)
import Foundation
import Testing
@testable import DisclosureKit

/// Pins the Senate paper-OCR finding: Vision recovers the *printed* text on the scanned
/// carbon form — filer, dates, asset names — but not the hand-drawn `X` that carries the
/// dollar amount. So paper filings are located and their pages counted, but not turned
/// into transactions. See `SENATE.md`.
@Suite("Senate paper OCR — recovers text, not amounts")
struct SenatePaperOCRTests {

    private static func page(_ name: String) -> Data {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "gif",
            subdirectory: "Fixtures/senate/paper-blumenthal-pages"
        ), let data = try? Data(contentsOf: url) else {
            fatalError("missing Senate paper fixture \(name).gif")
        }
        return data
    }

    @Test("Recovers transaction dates and asset text from the scanned pages")
    func recoversPrintedText() {
        let pages = SenatePaperOCR.recognise(gifPages: [Self.page("page-2"), Self.page("page-3")])
        #expect(!pages.isEmpty)

        let text = pages.flatMap(\.lines).joined(separator: "\n")
        // Dates are printed and come through (OCR spelling varies: "7/8/26", "718/26").
        #expect(text.range(of: #"\d{1,2}/\d{1,2}/\d{2}"#, options: .regularExpression) != nil)
        // The asset column carries the ticker inside the name; Vision reads it.
        #expect(text.uppercased().contains("TKNO"))
        // The filer's name is printed in the header.
        #expect(text.contains("Blumenthal"))
    }

    @Test("Does not recover a usable amount for the transaction rows")
    func doesNotRecoverAmounts() {
        let pages = SenatePaperOCR.recognise(gifPages: [Self.page("page-2")])
        let lines = pages.flatMap(\.lines)

        // A transaction row is one that carries a date. None of them should also carry a
        // resolvable dollar bracket — the amount is an unread X in a column. If this ever
        // starts passing with a real bracket, revisit the paper parser in SENATE.md.
        let datedRows = lines.filter {
            $0.range(of: #"\d{1,2}/\d{1,2}/\d{2}"#, options: .regularExpression) != nil
        }
        let rowsWithABracket = datedRows.filter {
            $0.range(of: #"\$\s?\d{1,3},\d{3}\s?[-–]\s?\$?\s?\d"#, options: .regularExpression) != nil
        }
        #expect(rowsWithABracket.isEmpty)
    }
}
#endif
