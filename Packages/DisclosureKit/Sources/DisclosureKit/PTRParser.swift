import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Identifies the filing a set of transactions came from.
public struct FilingRef: Hashable, Sendable {
    public let docID: String
    public let year: Int
    public let memberName: String
    public let memberID: String
    public let filedOn: CalendarDate?

    public init(
        docID: String, year: Int, memberName: String,
        memberID: String, filedOn: CalendarDate?
    ) {
        self.docID = docID
        self.year = year
        self.memberName = memberName
        self.memberID = memberID
        self.filedOn = filedOn
    }

    public var documentURL: URL? {
        URL(string: "https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/\(year)/\(docID).pdf")
    }
}

public struct ParseResult: Sendable {
    public var trades: [Trade]
    /// False when the PDF yielded no usable text at all — no embedded text layer and
    /// OCR of the page images also came back empty.
    public var hadReadableText: Bool
    /// True when the text came from optical character recognition of a scanned filing
    /// rather than an embedded text layer. Those rows are lower-confidence and say so.
    public var recoveredByOCR: Bool
    public var warnings: [String]

    public init(
        trades: [Trade], hadReadableText: Bool,
        recoveredByOCR: Bool = false, warnings: [String] = []
    ) {
        self.trades = trades
        self.hadReadableText = hadReadableText
        self.recoveredByOCR = recoveredByOCR
        self.warnings = warnings
    }
}

/// Turns the text of a House Periodic Transaction Report into structured trades.
///
/// PDFKit flattens the form's table into a stream of lines in which one logical row can
/// span several lines, columns arrive out of order, and a page break can land in the
/// middle of a dollar range. Rather than rebuilding the table, this anchors on the one
/// unambiguous pattern per row — transaction code, two dates — and attributes the
/// surrounding text to it using explicit parser state.
public enum PTRParser {

    // MARK: - Patterns

    /// Transaction code, trade date, notification date, then everything else as the tail.
    /// `S (partial)` precedes the bare `S` so the alternation prefers the longer match.
    private static let anchor = try! NSRegularExpression(
        pattern: #"(?:^|\s)(S \(partial\)|P|S|E)\s+(\d{1,2}/\d{1,2}/\d{2,4})\s+(\d{1,2}/\d{1,2}/\d{2,4})\s*(.*)$"#
    )

    private static let money = #"\$[\d,]+(?:\.\d{2})?"#

    /// A complete bracket: `$1,001 - $15,000`.
    private static let completeRange = try! NSRegularExpression(
        pattern: #"^\s*("# + money + #")\s*[-–]\s*("# + money + #")"#
    )
    /// A bracket whose upper bound has not arrived yet: `$50,001 -`.
    private static let danglingRange = try! NSRegularExpression(
        pattern: #"^\s*("# + money + #")\s*[-–]\s*$"#
    )
    /// The open-ended top bracket, written either as `$50,000,001 +` or as
    /// `Over $50,000,000`. The form also uses `Spouse/DC Over $1,000,000`, the reduced
    /// reporting standard for a spouse's or dependent child's assets.
    private static let openEnded = try! NSRegularExpression(
        pattern: #"^\s*("# + money + #")\s*\+"#
    )
    private static let overPrefixed = try! NSRegularExpression(
        pattern: #"(?i)\bOver\s*("# + money + #")"#
    )
    /// `Over` with its value wrapped onto the following line.
    private static let danglingOver = try! NSRegularExpression(pattern: #"(?i)\bOver\s*$"#)
    /// A lone exact figure, used for cash in lieu and similar.
    private static let exactAmount = try! NSRegularExpression(
        pattern: #"^\s*("# + money + #")\s*$"#
    )
    /// Any dollar figure anywhere in a line, for recovering a wrapped upper bound.
    private static let anyMoney = try! NSRegularExpression(pattern: money)

    private static let tickerAndType = try! NSRegularExpression(
        pattern: #"\(([A-Z][A-Z0-9.\-]{0,6})\)\s*\[([A-Z]{2,4})\]"#
    )
    private static let bareType = try! NSRegularExpression(pattern: #"\[([A-Z]{2,4})\]"#)
    /// A ticker in parentheses with its type code stranded on another line.
    private static let trailingTicker = try! NSRegularExpression(
        pattern: #"\(([A-Z][A-Z0-9.\-]{0,6})\)\s*$"#
    )
    /// A line consisting only of an asset-type code, orphaned by the layout.
    private static let onlyType = try! NSRegularExpression(pattern: #"^\s*\[([A-Z]{2,4})\]\s*$"#)

    /// Small-caps labels lose their lowercase glyphs: "DESCRIPTION:" becomes "D        :".
    private static let labelLine = try! NSRegularExpression(
        pattern: #"^\s*([A-Z])(\s{2,}[A-Z])*\s*:\s*(.*)$"#
    )
    private static let garbledHeading = try! NSRegularExpression(
        pattern: #"^\s*[A-Za-z](\s{2,}[A-Za-z])+\s*$"#
    )
    /// Owner codes, which the renderer sometimes repeats and sometimes puts on the
    /// line above the asset they belong to.
    private static let leadingOwners = try! NSRegularExpression(pattern: #"^\s*((?:SP|JT|DC)\s+)+"#)

    private static let boilerplatePrefixes = [
        "Filing ID #", "Name:", "Status:", "State/District:", "Initial Public Offering",
    ]
    private static let boilerplateContains = [
        "Clerk of the House of Representatives", "Legislative Resource Center",
    ]
    private static let tableEndPrefixes = [
        "* For the complete list", "I CERTIFY", "Digitally Signed", "my knowledge and belief",
    ]

    // MARK: - Entry points

    #if canImport(PDFKit)
    public static func parse(pdfAt url: URL, filing: FilingRef) -> ParseResult {
        guard let doc = PDFDocument(url: url) else {
            return ParseResult(trades: [], hadReadableText: false,
                               warnings: ["PDF could not be opened"])
        }
        return parse(document: doc, filing: filing)
    }

    public static func parse(pdfData data: Data, filing: FilingRef) -> ParseResult {
        guard let doc = PDFDocument(data: data) else {
            return ParseResult(trades: [], hadReadableText: false,
                               warnings: ["PDF could not be opened"])
        }
        return parse(document: doc, filing: filing)
    }

    /// Prefers the embedded text layer; falls back to OCR of the page images when the
    /// filing is a scan. About a fifth of House PTRs are filed as photographs of paper.
    private static func parse(document doc: PDFDocument, filing: FilingRef) -> ParseResult {
        if let text = doc.string, text.contains(where: { !$0.isWhitespace }) {
            return parse(text: text, filing: filing)
        }
        #if canImport(Vision)
        if let ocr = ocrText(from: doc), ocr.contains(where: { !$0.isWhitespace }) {
            var result = parse(text: ocr, filing: filing)
            result.recoveredByOCR = true
            result.warnings.insert(
                "text recovered by OCR from a scanned filing — check every field against the PDF",
                at: 0
            )
            result.trades = result.trades.map {
                var t = $0
                appendWarning("recovered by OCR", to: &t)
                return t
            }
            return result
        }
        #endif
        return ParseResult(trades: [], hadReadableText: false,
                           warnings: ["no extractable text (scanned filing)"])
    }
    #endif

    public static func parse(text: String, filing: FilingRef) -> ParseResult {
        let lines = normalize(text)
        let hasText = lines.contains { !$0.isEmpty }
        guard hasText else {
            return ParseResult(trades: [], hadReadableText: false,
                               warnings: ["no extractable text (scanned filing)"])
        }

        var state = State(filing: filing)
        var i = 0
        while i < lines.count {
            consume(lines, at: &i, state: &state)
        }
        state.finish()

        return ParseResult(
            trades: state.trades, hadReadableText: true, warnings: state.fileWarnings
        )
    }

    // MARK: - Normalisation

    /// The form's small-caps labels are padded with NUL bytes rather than spaces, so
    /// control characters are folded to spaces before any pattern is applied.
    private static func normalize(_ text: String) -> [String] {
        let folded = String(text.map { ch -> Character in
            if ch == "\n" || ch == "\r" { return "\n" }
            guard ch.unicodeScalars.count == 1, let s = ch.unicodeScalars.first else { return ch }
            return s.properties.generalCategory == .control ? " " : ch
        })
        return folded.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Parser state

    private struct State {
        let filing: FilingRef
        var trades: [Trade] = []
        var assetLines: [String] = []
        var pendingDescription: String?
        var descriptionOnLastTrade = false
        var continuingDescription = false
        var inTableHeader = false
        var inTable = false
        /// The row still waiting on a figure from a later line, and which figure it
        /// needs. Explicit state, so a completed row can never absorb a stray amount.
        var awaiting: (index: Int, kind: PendingAmount)?
        /// Owner codes seen on a line that was not itself an asset line.
        var pendingOwner: TradeOwner?
        var fileWarnings: [String] = []

        mutating func finish() {
            if let pending = awaiting {
                note(&trades[pending.index], Self.missingFigureWarning(pending.kind))
                fileWarnings.append("row \(pending.index) has an incomplete amount")
                awaiting = nil
            }
        }

        static func missingFigureWarning(_ kind: PendingAmount) -> String {
            switch kind {
            case .upperBound: return "upper bound of the dollar range was never found"
            case .overThreshold: return "threshold of the 'Over' amount was never found"
            case .nothing: return "amount incomplete"
            }
        }

        func note(_ trade: inout Trade, _ warning: String) {
            trade = Trade(
                id: trade.id, memberID: trade.memberID, memberName: trade.memberName,
                owner: trade.owner, asset: trade.asset, ticker: trade.ticker,
                assetType: trade.assetType, txType: trade.txType, txDate: trade.txDate,
                disclosedDate: trade.disclosedDate, amount: trade.amount,
                filingDescription: trade.filingDescription, filingID: trade.filingID,
                documentURL: trade.documentURL, warnings: trade.warnings + [warning]
            )
        }
    }

    // MARK: - Main loop

    private static func consume(_ lines: [String], at i: inout Int, state: inout State) {
        let raw = lines[i]
        defer { i += 1 }
        if raw.isEmpty { return }

        // Column headings span several lines and finish with the "$200?" cell. A page
        // break can interrupt a row, so this must not clear `awaitingUpperBound`.
        if raw.contains("ID Owner Asset") {
            state.inTableHeader = true
            state.inTable = false
            state.assetLines.removeAll()
            state.continuingDescription = false
            return
        }
        if state.inTableHeader {
            if raw.contains("$200?") {
                state.inTableHeader = false
                state.inTable = true
            }
            return
        }

        if tableEndPrefixes.contains(where: { raw.hasPrefix($0) }) {
            state.inTable = false
            state.assetLines.removeAll()
            state.pendingDescription = nil
            state.continuingDescription = false
            return
        }
        guard state.inTable else { return }

        if boilerplatePrefixes.contains(where: { raw.hasPrefix($0) }) { return }
        if boilerplateContains.contains(where: { raw.contains($0) }) { return }
        if raw == "Yes No" { return }
        if raw.range(of: #"^Page \d+ of \d+$"#, options: .regularExpression) != nil { return }

        // Owner codes are sometimes printed on the line above the asset they belong to,
        // and sometimes ahead of a label. Strip them but remember them.
        var line = raw
        if let m = leadingOwners.firstMatch(in: line, range: line.nsRange) {
            let codes = (line as NSString).substring(with: m.range)
            let rest = (line as NSString).substring(from: m.range.length)
                .trimmingCharacters(in: .whitespaces)
            // Keep the owner attached to asset text; only hoist it when what follows
            // is a label or the line is otherwise not asset content.
            if rest.isEmpty || labelLine.firstMatch(in: rest, range: rest.nsRange) != nil {
                state.pendingOwner = ownerFrom(codes)
                line = rest
                if line.isEmpty { return }
            }
        }

        // An orphaned asset-type code belongs to the row just emitted.
        if let m = onlyType.firstMatch(in: line, range: line.nsRange),
           let code = line.substring(m, 1),
           let last = state.trades.indices.last,
           state.trades[last].assetType == nil {
            applyAssetType(code, to: &state.trades[last])
            return
        }

        // A wrapped figure, only when a row is explicitly waiting for one. It may be
        // embedded in other text when a page break split the row.
        if let pending = state.awaiting,
           let m = anyMoney.firstMatch(in: line, range: line.nsRange),
           let amt = line.substring(m, 0) {
            switch pending.kind {
            case .upperBound:
                completeRange(of: &state.trades[pending.index], upperBound: amt)
            case .overThreshold:
                completeOver(of: &state.trades[pending.index], threshold: amt)
            case .nothing:
                break
            }
            let idx = pending.index
            state.awaiting = nil
            let remainder = ((line as NSString).replacingCharacters(in: m.range, with: " "))
                .trimmingCharacters(in: .whitespaces)
            guard !remainder.isEmpty else { return }

            // When a page break splits a row, the tail of its own asset name lands after
            // the anchor. If that row never got a ticker, this text is its name — not the
            // next row's — so claim it rather than handing it forward.
            let (ticker, type) = extractTickerAndType(remainder)
            if state.trades[idx].ticker == nil, ticker != nil {
                enrichAsset(of: &state.trades[idx], appending: remainder,
                            ticker: ticker, assetType: type)
            } else {
                state.assetLines.append(remainder)
            }
            return
        }

        // "FILING STATUS: New" / "DESCRIPTION: Purchased 10,000 shares."
        if let m = labelLine.firstMatch(in: line, range: line.nsRange),
           let initial = line.substring(m, 1) {
            let body = (line.substring(m, 3) ?? "").trimmingCharacters(in: .whitespaces)
            if initial == "D", !body.isEmpty {
                attachDescription(body, to: &state)
                state.continuingDescription = !endsSentence(body)
            } else {
                state.continuingDescription = false
            }
            return
        }

        if garbledHeading.firstMatch(in: line, range: line.nsRange) != nil { return }

        // A transaction row.
        if let m = anchor.firstMatch(in: line, range: line.nsRange) {
            emitTrade(line: line, match: m, state: &state)
            return
        }

        // A sentence fragment that the layout printed just before its own label. These
        // are description tails, not asset names.
        if isDescriptionFragment(lines, at: i, line: line) {
            state.pendingDescription = [state.pendingDescription, line]
                .compactMap { $0 }.joined(separator: " ")
            return
        }

        // A wrapped description runs until it ends a sentence — unless the next line is
        // plainly the start of the following row's asset, which the layout can place
        // mid-description. Without this the asset name is swallowed and the row loses
        // both its ticker and its name.
        if state.continuingDescription, !looksLikeAssetStart(line) {
            appendDescriptionContinuation(line, to: &state)
            if endsSentence(line) { state.continuingDescription = false }
            return
        }
        state.continuingDescription = false

        state.assetLines.append(line)
    }

    // MARK: - Row construction

    private static func emitTrade(line: String, match m: NSTextCheckingResult, state: inout State) {
        // A new row means an earlier row's missing figure will never arrive.
        if let pending = state.awaiting {
            state.note(&state.trades[pending.index], State.missingFigureWarning(pending.kind))
            state.awaiting = nil
        }

        // `m.range.location` is a UTF-16 offset, so slice with NSString rather than
        // `String.prefix`, which counts Characters and would misalign on any accented
        // name or en-dash that precedes the anchor.
        let head = (line as NSString).substring(to: m.range.location)
            .trimmingCharacters(in: .whitespaces)
        let assetText = trimToLastAsset(
            (state.assetLines + [head])
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        )

        let code = line.substring(m, 1) ?? "P"
        let tail = (line.substring(m, 4) ?? "").trimmingCharacters(in: .whitespaces)
        guard let txDate = CalendarDate(formStyle: line.substring(m, 2) ?? ""),
              let disclosed = CalendarDate(formStyle: line.substring(m, 3) ?? "")
        else {
            state.fileWarnings.append("unparseable dates on a transaction row")
            state.assetLines.removeAll()
            return
        }

        let (ownerFromAsset, cleanAsset) = splitOwner(assetText)
        let owner = ownerFromAsset ?? state.pendingOwner ?? .self
        let (ticker, assetType) = extractTickerAndType(cleanAsset)
        let (amount, pendingKind) = parseAmount(tail)

        var warnings: [String] = []
        if amount.kind == .unknown && pendingKind == .nothing && !tail.isEmpty {
            warnings.append("amount column not understood: \(tail)")
        }

        let trade = Trade(
            id: "\(state.filing.docID)-\(state.trades.count)",
            memberID: state.filing.memberID,
            memberName: state.filing.memberName,
            owner: owner,
            asset: tidy(cleanAsset),
            ticker: ticker,
            assetType: assetType,
            txType: txType(code),
            txDate: txDate,
            disclosedDate: state.filing.filedOn ?? disclosed,
            amount: amount,
            filingDescription: state.pendingDescription,
            filingID: state.filing.docID,
            documentURL: state.filing.documentURL,
            warnings: warnings
        )
        state.trades.append(trade)

        if pendingKind != .nothing {
            state.awaiting = (index: state.trades.count - 1, kind: pendingKind)
        }
        state.assetLines.removeAll()
        state.pendingDescription = nil
        state.pendingOwner = nil
        state.descriptionOnLastTrade = true
        state.continuingDescription = false
    }

    /// What, if anything, a row is still waiting for from a later line.
    enum PendingAmount: Equatable, Sendable {
        case nothing
        /// The upper bound of a bracket, after a dangling `-`.
        case upperBound
        /// The threshold of an `Over …` amount whose value wrapped.
        case overThreshold
    }

    /// Reads the amount column.
    ///
    /// Every shape the column can take is recognised explicitly. Anything unrecognised
    /// becomes `.unknown` and is reported, rather than being coerced into a number.
    static func parseAmount(_ tail: String) -> (DisclosedAmount, PendingAmount) {
        let t = tail.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return (.unknown(""), .nothing) }

        if t.lowercased().contains("none") || t.contains("less than $201") {
            return (.noneDisclosed, .nothing)
        }
        // "Over $X" is checked before the range forms so the word is never ignored.
        if let m = overPrefixed.firstMatch(in: t, range: t.nsRange), let v = t.substring(m, 1) {
            let low = cents(v)
            return (DisclosedAmount(
                kind: .atLeast, lowCents: low, highCents: low,
                label: DisclosedAmount.makeLabel(kind: .atLeast, lowCents: low, highCents: low)
            ), .nothing)
        }
        if danglingOver.firstMatch(in: t, range: t.nsRange) != nil {
            return (.unknown(t), .overThreshold)
        }
        if let m = completeRange.firstMatch(in: t, range: t.nsRange),
           let lo = t.substring(m, 1), let hi = t.substring(m, 2) {
            let low = cents(lo), high = cents(hi)
            return (DisclosedAmount(
                kind: .range, lowCents: low, highCents: high,
                label: DisclosedAmount.makeLabel(kind: .range, lowCents: low, highCents: high)
            ), .nothing)
        }
        if let m = openEnded.firstMatch(in: t, range: t.nsRange), let lo = t.substring(m, 1) {
            let low = cents(lo)
            return (DisclosedAmount(
                kind: .atLeast, lowCents: low, highCents: low,
                label: DisclosedAmount.makeLabel(kind: .atLeast, lowCents: low, highCents: low)
            ), .nothing)
        }
        if let m = danglingRange.firstMatch(in: t, range: t.nsRange), let lo = t.substring(m, 1) {
            let low = cents(lo)
            // Provisional: a range with an unknown top until the bound arrives.
            return (DisclosedAmount(
                kind: .range, lowCents: low, highCents: low,
                label: DisclosedAmount.makeLabel(kind: .range, lowCents: low, highCents: low)
            ), .upperBound)
        }
        if let m = exactAmount.firstMatch(in: t, range: t.nsRange), let v = t.substring(m, 1) {
            let c = cents(v)
            return (DisclosedAmount(
                kind: .exact, lowCents: c, highCents: c,
                label: DisclosedAmount.makeLabel(kind: .exact, lowCents: c, highCents: c)
            ), .nothing)
        }
        return (.unknown(t), .nothing)
    }

    private static func completeRange(of trade: inout Trade, upperBound: String) {
        let high = cents(upperBound)
        let low = trade.amount.lowCents
        // A "bound" below the low is not the missing upper bound.
        guard high > low else {
            var t = trade
            appendWarning("ignored an out-of-order upper bound \(upperBound)", to: &t)
            trade = t
            return
        }
        let amount = DisclosedAmount(
            kind: .range, lowCents: low, highCents: high,
            label: DisclosedAmount.makeLabel(kind: .range, lowCents: low, highCents: high)
        )
        trade = replacingAmount(trade, with: amount)
    }

    /// Completes an `Over …` amount whose threshold wrapped onto a later line.
    private static func completeOver(of trade: inout Trade, threshold: String) {
        let low = cents(threshold)
        let amount = DisclosedAmount(
            kind: .atLeast, lowCents: low, highCents: low,
            label: DisclosedAmount.makeLabel(kind: .atLeast, lowCents: low, highCents: low)
        )
        trade = replacingAmount(trade, with: amount)
    }

    // MARK: - Field extraction

    private static func splitOwner(_ text: String) -> (TradeOwner?, String) {
        guard let m = leadingOwners.firstMatch(in: text, range: text.nsRange) else {
            return (nil, text)
        }
        let codes = (text as NSString).substring(with: m.range)
        let rest = (text as NSString).substring(from: m.range.length)
        return (ownerFrom(codes), rest.trimmingCharacters(in: .whitespaces))
    }

    private static func ownerFrom(_ codes: String) -> TradeOwner {
        if codes.contains("SP") { return .spouse }
        if codes.contains("JT") { return .joint }
        if codes.contains("DC") { return .dependent }
        return .self
    }

    private static func extractTickerAndType(_ asset: String) -> (String?, String?) {
        if let m = tickerAndType.firstMatch(in: asset, range: asset.nsRange) {
            return (asset.substring(m, 1), asset.substring(m, 2))
        }
        // The type code can be stranded on its own line by the layout, leaving the
        // ticker alone at the end of the asset name.
        if let m = trailingTicker.firstMatch(in: asset, range: asset.nsRange) {
            return (asset.substring(m, 1), nil)
        }
        if let m = bareType.firstMatch(in: asset, range: asset.nsRange) {
            return (nil, asset.substring(m, 1))
        }
        return (nil, nil)
    }

    private static func applyAssetType(_ code: String, to trade: inout Trade) {
        trade = Trade(
            id: trade.id, memberID: trade.memberID, memberName: trade.memberName,
            owner: trade.owner, asset: trade.asset, ticker: trade.ticker,
            assetType: code, txType: trade.txType, txDate: trade.txDate,
            disclosedDate: trade.disclosedDate, amount: trade.amount,
            filingDescription: trade.filingDescription, filingID: trade.filingID,
            documentURL: trade.documentURL, warnings: trade.warnings
        )
    }

    /// Completes a row whose asset name was split by a page break.
    private static func enrichAsset(
        of trade: inout Trade, appending text: String, ticker: String?, assetType: String?
    ) {
        let merged = tidy([trade.asset, text].filter { !$0.isEmpty }.joined(separator: " "))
        trade = Trade(
            id: trade.id, memberID: trade.memberID, memberName: trade.memberName,
            owner: trade.owner, asset: merged, ticker: trade.ticker ?? ticker,
            assetType: trade.assetType ?? assetType, txType: trade.txType,
            txDate: trade.txDate, disclosedDate: trade.disclosedDate, amount: trade.amount,
            filingDescription: trade.filingDescription, filingID: trade.filingID,
            documentURL: trade.documentURL, warnings: trade.warnings
        )
    }

    private static func replacingAmount(_ trade: Trade, with amount: DisclosedAmount) -> Trade {
        Trade(
            id: trade.id, memberID: trade.memberID, memberName: trade.memberName,
            owner: trade.owner, asset: trade.asset, ticker: trade.ticker,
            assetType: trade.assetType, txType: trade.txType, txDate: trade.txDate,
            disclosedDate: trade.disclosedDate, amount: amount,
            filingDescription: trade.filingDescription, filingID: trade.filingID,
            documentURL: trade.documentURL, warnings: trade.warnings
        )
    }

    private static func appendWarning(_ w: String, to trade: inout Trade) {
        trade = Trade(
            id: trade.id, memberID: trade.memberID, memberName: trade.memberName,
            owner: trade.owner, asset: trade.asset, ticker: trade.ticker,
            assetType: trade.assetType, txType: trade.txType, txDate: trade.txDate,
            disclosedDate: trade.disclosedDate, amount: trade.amount,
            filingDescription: trade.filingDescription, filingID: trade.filingID,
            documentURL: trade.documentURL, warnings: trade.warnings + [w]
        )
    }

    // MARK: - Descriptions

    private static func attachDescription(_ text: String, to state: inout State) {
        if state.assetLines.isEmpty,
           let last = state.trades.indices.last,
           state.trades[last].filingDescription == nil {
            state.trades[last] = withDescription(state.trades[last], text)
            state.descriptionOnLastTrade = true
        } else {
            state.pendingDescription = [state.pendingDescription, text]
                .compactMap { $0 }.joined(separator: " ")
            state.descriptionOnLastTrade = false
        }
    }

    private static func appendDescriptionContinuation(_ text: String, to state: inout State) {
        if state.descriptionOnLastTrade, let last = state.trades.indices.last {
            let joined = [state.trades[last].filingDescription, text]
                .compactMap { $0 }.joined(separator: " ")
            state.trades[last] = withDescription(state.trades[last], joined)
        } else {
            state.pendingDescription = [state.pendingDescription, text]
                .compactMap { $0 }.joined(separator: " ")
        }
    }

    private static func withDescription(_ trade: Trade, _ text: String) -> Trade {
        Trade(
            id: trade.id, memberID: trade.memberID, memberName: trade.memberName,
            owner: trade.owner, asset: trade.asset, ticker: trade.ticker,
            assetType: trade.assetType, txType: trade.txType, txDate: trade.txDate,
            disclosedDate: trade.disclosedDate, amount: trade.amount,
            filingDescription: text, filingID: trade.filingID,
            documentURL: trade.documentURL, warnings: trade.warnings
        )
    }

    /// True when the next meaningful line is a description label, which means this line
    /// is the tail of that description printed out of order.
    private static func isDescriptionFragment(_ lines: [String], at i: Int, line: String) -> Bool {
        guard bareType.firstMatch(in: line, range: line.nsRange) == nil else { return false }
        guard anchor.firstMatch(in: line, range: line.nsRange) == nil else { return false }
        var j = i + 1
        while j < lines.count, lines[j].isEmpty { j += 1 }
        guard j < lines.count else { return false }
        var next = lines[j]
        if let m = leadingOwners.firstMatch(in: next, range: next.nsRange) {
            next = (next as NSString).substring(from: m.range.length)
        }
        guard let m = labelLine.firstMatch(in: next, range: next.nsRange),
              next.substring(m, 1) == "D" else { return false }
        return true
    }

    // MARK: - Helpers

    /// Whether a line reads as the beginning of an asset row rather than prose.
    /// Descriptions do contain parentheses ("(5,000 shares)"), but not all-caps tickers
    /// or bracketed asset-type codes.
    private static func looksLikeAssetStart(_ line: String) -> Bool {
        if bareType.firstMatch(in: line, range: line.nsRange) != nil { return true }
        if leadingOwners.firstMatch(in: line, range: line.nsRange) != nil { return true }
        if line.range(of: #"\([A-Z][A-Z0-9.\-]{0,6}\)"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func endsSentence(_ s: String) -> Bool {
        guard let last = s.trimmingCharacters(in: .whitespaces).last else { return true }
        return ".!?".contains(last)
    }

    /// Keeps only the final asset when a failed row left its name in the buffer.
    private static func trimToLastAsset(_ text: String) -> String {
        let marks = bareType.matches(in: text, range: text.nsRange)
        guard marks.count >= 2 else { return text }
        let cutoff = marks[marks.count - 2].range.upperBound
        let last = marks[marks.count - 1].range
        return (text as NSString)
            .substring(with: NSRange(location: cutoff, length: last.upperBound - cutoff))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func tidy(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func txType(_ code: String) -> TradeType {
        switch code {
        case "P": return .buy
        case "S": return .sell
        case "S (partial)": return .partialSell
        case "E": return .exchange
        default: return .buy
        }
    }

    /// `$1,000,001` and `$15.00` both become an exact number of cents.
    static func cents(_ s: String) -> Int {
        let cleaned = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = cleaned.split(separator: ".", maxSplits: 1)
        let whole = Int(parts.first ?? "0") ?? 0
        var frac = 0
        if parts.count == 2 {
            let digits = String(parts[1].prefix(2)).padding(toLength: 2, withPad: "0", startingAt: 0)
            frac = Int(digits) ?? 0
        }
        return whole * 100 + frac
    }
}

extension String {
    var nsRange: NSRange { NSRange(startIndex..., in: self) }

    /// Capture group `i`; group 0 is the whole match.
    func substring(_ match: NSTextCheckingResult, _ i: Int) -> String? {
        guard i < match.numberOfRanges else { return nil }
        let r = match.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (self as NSString).substring(with: r)
    }
}
