import Foundation

/// Identifies the filing an `OGE278TNativeParser` result came from. Parallel to
/// `OGE278TFilingRef` (the scanned-presidential-filing path); kept separate because this
/// source always has a reliable `disclosedDate` from OGE's own record-keeping, never a
/// printed line to fall back on reading.
public struct OGE278TNativeFilingRef: Hashable, Sendable {
    public let filerName: String
    public let position: String?
    public let filingID: String
    public let disclosedDate: CalendarDate
    public let documentURL: URL?

    public init(
        filerName: String, position: String? = nil, filingID: String,
        disclosedDate: CalendarDate, documentURL: URL? = nil
    ) {
        self.filerName = filerName
        self.position = position
        self.filingID = filingID
        self.disclosedDate = disclosedDate
        self.documentURL = documentURL
    }
}

/// Turns the text of a *text-native* OGE Form 278-T into structured trades — the form
/// filed through Integrity.gov (OGE's electronic filing system) by senior officials
/// including Cabinet secretaries, as opposed to the scanned copies the President's office
/// posts to whitehouse.gov (see `OGE278TParser` for that path).
///
/// The two are the same form, read differently. `PDFDocument.string` groups this PDF's
/// text by visual line much the way Vision does for a scanned page, so a whole row —
/// number, description, type, date, notification, and the start of the amount — lands on
/// one line, confirmed against two real Cabinet-level filings while building this. The
/// one place a row still spans two lines is the amount itself: PDFKit wraps a dangling
/// `"$1,000,001 -"` onto its own following line exactly when the range doesn't fit on the
/// row's line, and the very next line is nothing but the missing upper bound (no row
/// number, no other text) — unlike the scanned path, this is completely predictable, so
/// it is completed rather than merely flagged.
public enum OGE278TNativeParser {

    public struct ParseResult: Sendable {
        public var trades: [Trade]
        public var warnings: [String]

        public init(trades: [Trade] = [], warnings: [String] = []) {
            self.trades = trades
            self.warnings = warnings
        }
    }

    /// A whole row: leading number, description, type, date, notification, then the
    /// amount as everything remaining on the line (which may be a dangling `"$X -"`).
    private static let rowAnchor = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,4})\s+(.*?)\s+(?i:(purchase|sale|exchange))\s+(\d{1,2}/\d{1,2}/\d{2,4})\s+(Yes|No)\s+(.*)$"#
    )

    /// The lone upper-bound continuation line: nothing but a dollar figure.
    private static let bareAmount = try! NSRegularExpression(pattern: #"^\s*\$[\d,]+(?:\.\d{2})?\s*$"#)

    public static func parse(lines: [String], filing: OGE278TNativeFilingRef) -> ParseResult {
        var trades: [Trade] = []
        var warnings: [String] = []
        var lastRowNumber = 0
        var i = 0

        while i < lines.count {
            let line = lines[i]
            guard let match = rowAnchor.firstMatch(in: line, range: line.nsRange),
                  let numberStr = line.substring(match, 1), let rowNumber = Int(numberStr),
                  rowNumber > lastRowNumber,
                  let description = line.substring(match, 2),
                  let typeWord = line.substring(match, 3)?.lowercased(),
                  let dateStr = line.substring(match, 4),
                  var amountText = line.substring(match, 6)
            else { i += 1; continue }

            guard let txDate = CalendarDate(formStyle: dateStr) else {
                warnings.append("row \(rowNumber): unreadable date \"\(dateStr)\" — skipped")
                i += 1
                continue
            }
            guard let txType = tradeType(for: typeWord) else {
                warnings.append("row \(rowNumber): unrecognized type \"\(typeWord)\" — skipped")
                i += 1
                continue
            }

            var linesConsumed = 1
            if amountText.hasSuffix("-"), i + 1 < lines.count,
               bareAmount.firstMatch(in: lines[i + 1], range: lines[i + 1].nsRange) != nil {
                amountText += " " + lines[i + 1].trimmingCharacters(in: .whitespaces)
                linesConsumed = 2
            }
            let (amount, pending) = PTRParser.parseAmount(amountText)

            var rowWarnings: [String] = []
            if pending != .nothing {
                rowWarnings.append("amount continued past where this parser looked for it — recorded as unknown")
            }
            if amount.kind == .unknown {
                rowWarnings.append("amount unreadable: \"\(amountText)\"")
            }
            let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
            if trimmedDescription.isEmpty {
                rowWarnings.append("description was empty — kept anyway")
            }
            for w in rowWarnings { warnings.append("row \(rowNumber): \(w)") }

            trades.append(Trade(
                id: "\(filing.filingID)-\(rowNumber)",
                memberID: MemberDirectory.fallbackID(
                    last: filing.filerName, first: "", state: "", district: nil
                ),
                memberName: filing.filerName,
                owner: .self,
                asset: trimmedDescription,
                ticker: nil,
                assetType: nil,
                txType: txType,
                txDate: txDate,
                disclosedDate: filing.disclosedDate,
                amount: amount,
                filingDescription: filing.position,
                filingID: filing.filingID,
                documentURL: filing.documentURL,
                warnings: rowWarnings
            ))

            lastRowNumber = rowNumber
            i += linesConsumed
        }

        if trades.isEmpty {
            warnings.append("no transaction rows recognized in this filing's text")
        }
        return ParseResult(trades: trades, warnings: warnings)
    }

    private static func tradeType(for word: String) -> TradeType? {
        switch word {
        case "purchase": return .buy
        case "sale": return .sell
        case "exchange": return .exchange
        default: return nil
        }
    }
}
