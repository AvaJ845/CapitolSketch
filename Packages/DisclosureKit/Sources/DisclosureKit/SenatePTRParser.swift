// Senate eFD portal scraping / parsing. The shipping app is House-only and no app or
// widget code path reaches SenateFilingRef or SenatePTRParser; this file is compiled
// only for `seedgen` and the DisclosureKit test target, both of which define SEEDGEN.
// See P0-2 in the security review and `Package.swift`.
#if SEEDGEN
import Foundation

/// Identifies a Senate Periodic Transaction Report from efdsearch.senate.gov.
///
/// The Senate has no bulk index like the House Clerk's `{year}FD.txt`; a filing is a UUID
/// behind the eFD search, and it is either an *electronic* report (an HTML table this
/// parser reads) or a *paper* report (scanned page images that need OCR).
public struct SenateFilingRef: Hashable, Sendable {
    public let uuid: String
    public let memberName: String
    /// Bioguide ID when resolved against the crosswalk, otherwise a fallback slug.
    public let memberID: String
    public let filedOn: CalendarDate?
    public let isPaper: Bool
    public let isAmendment: Bool

    public init(
        uuid: String, memberName: String, memberID: String,
        filedOn: CalendarDate?, isPaper: Bool, isAmendment: Bool = false
    ) {
        self.uuid = uuid
        self.memberName = memberName
        self.memberID = memberID
        self.filedOn = filedOn
        self.isPaper = isPaper
        self.isAmendment = isAmendment
    }

    public var documentURL: URL? {
        URL(string: "https://efdsearch.senate.gov/search/view/\(isPaper ? "paper" : "ptr")/\(uuid)/")
    }
}

/// Reads the transaction table from a Senate **electronic** PTR report page.
///
/// The page is a Django template with exactly one `<table class="table table-striped">`
/// whose body holds one `<tr>` per transaction. Columns, in order:
///
///   # · Transaction Date · Owner · Ticker · Asset Name · Asset Type · Type · Amount · Comment
///
/// Dependency-free by design — this is build-time code (`seedgen`), and it is pinned to
/// checked-in fixtures so a layout change on efdsearch fails a test rather than shipping
/// silently wrong data. Paper PTRs go through `PTRParser` + OCR instead.
public enum SenatePTRParser {

    public static func parse(reportHTML html: String, filing: SenateFilingRef) -> ParseResult {
        guard let body = tableBody(in: html) else {
            return ParseResult(
                trades: [], hadReadableText: false,
                warnings: ["no transaction table found — the eFD layout may have changed"]
            )
        }

        var trades: [Trade] = []
        var warnings: [String] = []

        for (index, rawRow) in rows(in: body).enumerated() {
            let raw = rawCells(in: rawRow)
            let cells = raw.map(strip)
            guard cells.count >= 8 else {
                warnings.append("row \(index): expected at least 8 columns, found \(cells.count)")
                continue
            }

            guard let txDate = CalendarDate(formStyle: cells[1]) else {
                warnings.append("row \(index): unreadable transaction date '\(cells[1])'")
                continue
            }

            let owner = ownerFrom(cells[2])
            let ticker = tickerFrom(cells[3])
            let (assetName, inlineDescription) = assetFrom(rawCells: raw)
            let assetType = assetTypeCode(cells[5])
            let txType = txTypeFrom(cells[6])
            let (amount, _) = PTRParser.parseAmount(cells[7])
            let comment = cells.count > 8 ? cells[8] : ""

            let description = [inlineDescription, comment]
                .filter { !$0.isEmpty && $0 != "--" }
                .joined(separator: " · ")

            var rowWarnings: [String] = []
            if amount.kind == .unknown, !cells[7].isEmpty, cells[7] != "--" {
                rowWarnings.append("amount column not understood: \(cells[7])")
            }

            trades.append(Trade(
                id: "\(filing.uuid)-\(index)",   // provisional; replaced with a content id below
                memberID: filing.memberID,
                memberName: filing.memberName,
                owner: owner,
                asset: assetName,
                ticker: ticker,
                assetType: assetType,
                txType: txType,
                txDate: txDate,
                disclosedDate: filing.filedOn ?? txDate,
                amount: amount,
                filingDescription: description.isEmpty ? nil : description,
                filingID: filing.uuid,
                documentURL: filing.documentURL,
                warnings: rowWarnings
            ))
        }

        if trades.isEmpty {
            warnings.append("report table had no readable transaction rows")
        }
        return ParseResult(
            trades: withStableIDs(trades, filingID: filing.uuid),
            hadReadableText: true, warnings: warnings
        )
    }

    // MARK: - Field mapping

    private static func ownerFrom(_ raw: String) -> TradeOwner {
        switch raw.lowercased() {
        case let s where s.contains("spouse"): return .spouse
        case let s where s.contains("joint"): return .joint
        case let s where s.contains("dependent"): return .dependent
        default: return .self
        }
    }

    /// The ticker cell is `--` when there is none, and occasionally carries stray tokens
    /// for in-kind exchanges (`-- AMCR`). Keep only a token that looks like a symbol.
    private static func tickerFrom(_ raw: String) -> String? {
        let candidates = raw.replacingOccurrences(of: "--", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
        for token in candidates
        where token.range(of: #"^[A-Z][A-Z0-9.\-]{0,6}$"#, options: .regularExpression) != nil {
            return token
        }
        return nil
    }

    /// The asset-name cell holds the plain name, then optional
    /// `<div class="text-muted"><em>Company:</em> …</div>` and
    /// `<div class="text-muted"><em>Description:</em> …</div>` blocks. Work on the
    /// flattened text and cut at the first sub-label.
    private static func assetFrom(rawCells: [String]) -> (name: String, description: String) {
        guard rawCells.count > 4 else { return ("", "") }
        let full = strip(rawCells[4])

        let cut = [" Company:", " Description:", "Company:", "Description:"]
            .compactMap { full.range(of: $0)?.lowerBound }
            .min()
        let name = cut.map { String(full[..<$0]) }?.trimmingCharacters(in: .whitespaces) ?? full

        var description = ""
        if let range = full.range(of: "Description:") {
            description = String(full[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return (name.isEmpty ? full : name, description)
    }

    private static func assetTypeCode(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "stock": return "ST"
        case "non-public stock": return "PS"
        case let s where s.contains("option"): return "OP"
        case let s where s.contains("municipal"): return "GS"
        case let s where s.contains("corporate bond"), let s where s.contains("corporate security"):
            return "CS"
        case let s where s.contains("crypto"): return "CT"
        case let s where s.contains("etf") || s.contains("exchange traded") || s.contains("exchange-traded"):
            return "EF"
        case let s where s.contains("mutual fund"): return "MF"
        case "--", "": return nil
        default: return nil
        }
    }

    private static func txTypeFrom(_ raw: String) -> TradeType {
        let s = raw.lowercased()
        if s.contains("purchase") { return .buy }
        if s.contains("exchange") { return .exchange }
        if s.contains("partial") { return .partialSell }
        if s.contains("sale") || s.contains("sold") { return .sell }
        return .buy
    }

    // MARK: - HTML extraction (scoped to this one template)

    private static func tableBody(in html: String) -> Substring? {
        guard let table = html.range(
            of: #"<table[^>]*class="[^"]*table-striped[^"]*"[^>]*>"#, options: .regularExpression
        ),
        let open = html.range(of: "<tbody>", range: table.upperBound..<html.endIndex),
        let close = html.range(of: "</tbody>", range: open.upperBound..<html.endIndex)
        else { return nil }
        return html[open.upperBound..<close.lowerBound]
    }

    private static func rows(in body: Substring) -> [Substring] {
        slices(in: body, open: "<tr", close: "</tr>")
    }

    private static func rawCells(in row: Substring) -> [String] {
        slices(in: row, open: "<td", close: "</td>").map(String.init)
    }

    /// Every `open…>…close` span in `text`, returning the inner content.
    private static func slices(in text: Substring, open: String, close: String) -> [Substring] {
        var out: [Substring] = []
        var cursor = text.startIndex
        while let start = text.range(of: open, range: cursor..<text.endIndex),
              let gt = text.range(of: ">", range: start.upperBound..<text.endIndex),
              let end = text.range(of: close, range: gt.upperBound..<text.endIndex) {
            out.append(text[gt.upperBound..<end.lowerBound])
            cursor = end.upperBound
        }
        return out
    }

    private static func strip<S: StringProtocol>(_ s: S) -> String {
        var t = String(s).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&#35;", "#"), ("&lt;", "<"),
            ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ] {
            t = t.replacingOccurrences(of: entity, with: replacement)
        }
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif // SEEDGEN
