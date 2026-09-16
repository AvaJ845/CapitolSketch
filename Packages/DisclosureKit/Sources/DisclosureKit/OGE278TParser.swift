import Foundation

/// Identifies the OGE Form 278-T filing a set of transactions came from. One filing is
/// one document; `disclosedDate` and `filerName` are document-level facts, the same
/// division `FilingRef` (House) and `SenateFilingRef` draw.
public struct OGE278TFilingRef: Hashable, Sendable {
    public let filerName: String
    public let position: String?
    public let filingID: String
    /// The date OGE recorded receiving the filing — printed once, near the bottom of the
    /// cover page, as "OGE Received: M/D/YYYY". This is the disclosure-lag anchor, not
    /// the filer's own signature date a line above it (the two are routinely a few days
    /// apart in the real filings this was built against).
    public let disclosedDate: CalendarDate?
    public let documentURL: URL?
    public let isAmendment: Bool

    public init(
        filerName: String, position: String? = nil, filingID: String,
        disclosedDate: CalendarDate?, documentURL: URL? = nil, isAmendment: Bool = false
    ) {
        self.filerName = filerName
        self.position = position
        self.filingID = filingID
        self.disclosedDate = disclosedDate
        self.documentURL = documentURL
        self.isAmendment = isAmendment
    }
}

/// Turns the text of an OGE Form 278-T (Executive Branch Periodic Transaction Report)
/// into structured trades.
///
/// The form OGE publishes is a scanned, ruled table — see `OGE278TOCR` for why every
/// filing sampled while building this had `/Image` XObjects and no embedded text layer,
/// unlike the House and Senate electronic PTRs. The table's own columns are `#`,
/// `Description`, `Type`, `Date`, `Notification Received Over 30 Days Ago`, `Amount` —
/// no ticker column (every transaction sampled was a municipal bond or corporate note,
/// identified only by its printed description) and no owner column (SP/DC/JT), so every
/// trade here is attributed to the filer, `.self`, until a sample with a spousal holding
/// says otherwise.
///
/// Like `PTRParser`, this does not attempt to reconstruct table columns by position —
/// `VisionText.lines` joins every fragment on a line left to right regardless of which
/// cell it belongs to, so column boundaries are not recoverable from whitespace alone.
/// Instead it anchors on the one sequence that cannot appear inside a free-text
/// description: `purchase|sale|exchange`, a date, then `Yes` or `No`. Everything before
/// that on the line is the row number and description; everything after is the amount.
public enum OGE278TParser {

    public struct ParseResult: Sendable {
        public var trades: [Trade]
        public var warnings: [String]

        public init(trades: [Trade] = [], warnings: [String] = []) {
            self.trades = trades
            self.warnings = warnings
        }
    }

    // MARK: - Patterns

    /// A transaction row's unambiguous tail: type word, one date, the notification flag,
    /// then the amount as everything remaining. Description text realistically never
    /// contains this exact sequence — it is bond coupons and maturity dates, not the
    /// words "purchase almost certainly followed immediately by a bare M/D/YYYY and a
    /// lone Yes or No".
    ///
    /// The date alternative also accepts a date missing its first `/` — `5114/2026` for
    /// `5/14/2026` — a real Vision misread (see `WhiteHouseFixture.dateSlashMerge`).
    /// Losing that slash used to make the whole row invisible to this anchor, so the row
    /// got folded into the *next* row's description instead of being recognized as its
    /// own event. `normalizedDateCandidate` re-splits the fused digits before the date is
    /// validated, and an unrecoverable split (as with this exact example — `51/14` has no
    /// valid month) still surfaces as "unreadable date" rather than a merge, which is the
    /// point: the row is attributed to itself, wrong date and all, not to its neighbor.
    private static let rowAnchor = try! NSRegularExpression(
        pattern: #"(?i)\b(purchase|sale|exchange)\s+(\d{1,2}/\d{1,2}/\d{2,4}|\d{3,4}/\d{2,4})\s+(Yes|No)\b\s*(.*)$"#
    )

    /// A date with its first `/` missing: `\d{3,4}` (month+day fused) then the surviving
    /// `/year`.
    private static let fusedSlashDate = try! NSRegularExpression(
        pattern: #"^(\d{3,4})/(\d{2,4})$"#
    )

    private static let leadingRowNumber = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,4})\s+(.*)$"#, options: [.dotMatchesLineSeparators]
    )

    /// "OGE Received: 4/23/2026" — printed once on the cover page, outside the
    /// transaction table.
    private static let ogeReceived = try! NSRegularExpression(
        pattern: #"(?i)OGE\s+Received:?\s*(\d{1,2}/\d{1,2}/\d{2,4})"#
    )

    private static let pageMarker = try! NSRegularExpression(
        pattern: #"(?i)Page\s+\d+\s+of\s+\d+"#
    )

    /// Reprinted page furniture — the form's own header, the column headings, and the
    /// legal boilerplate on the final page — none of which is part of any row's
    /// description. Matched loosely (substring, case-insensitive) because OCR mangles
    /// these unpredictably (`"acelved Over 3  Notlficatio"` for "Received Over 30 Days
    /// Ago" was an actual observed reading); a false-negative here just means a stray
    /// fragment of header text gets glued onto the next row's description, which is a
    /// cosmetic wart, not a wrong number — the amount and date columns are unaffected.
    private static let boilerplateMarkers = [
        "OGE Form 278-T", "Instructions", "public form", "account num",
        "Filer's Name", "Filer's Information", "Transactions", "Notification",
        "Days Ago", "Received Over", "Summary of Contents", "Privacy Act",
        "U.S.C", "C.F.R", "Office of Government Ethics", "Executive Branch Personnel",
    ]

    // MARK: - Entry point

    /// Parses every OCR'd line of a filing (cover page and transaction pages together —
    /// only lines matching `rowAnchor` are read as transactions, so page order does not
    /// matter). `filing.disclosedDate` is used when given; otherwise this looks for an
    /// "OGE Received" line among `lines` itself.
    ///
    /// A row whose description wraps onto a second printed line splits across two OCR
    /// lines too, because `VisionText.lines` bands fragments by vertical position and a
    /// two-line description cell does not share a band with the single-line type/date/
    /// amount cell beside it (both observed against real filings — see
    /// `OGE278TParserTests`). Non-anchor lines are buffered as the description-in-progress
    /// and folded into the next anchor line, rather than read as their own event or
    /// silently dropped.
    public static func parse(lines: [String], filing: OGE278TFilingRef) -> ParseResult {
        var trades: [Trade] = []
        var warnings: [String] = []

        let disclosedDate: CalendarDate?
        if let explicit = filing.disclosedDate ?? ogeReceivedDate(in: lines) {
            disclosedDate = explicit
        } else if let fallback = ogeCertificationDate(in: lines) {
            // Some filings' cover pages print no "OGE Received" line at all — observed
            // against a real filing while hardening this parser (see
            // `WhiteHouseFixture.missingOGEReceived`). The OGE certifying official's own
            // digital-signature date is the next best per-document date on the page: in
            // every filing sampled that has both, the two are a day or so apart, never
            // more — close enough to date the filing by, not close enough to call it the
            // received date outright, so the substitution is reported rather than silent.
            disclosedDate = fallback
            warnings.append(
                "no \"OGE Received\" line found — used the OGE certifying official's "
                + "digital-signature date (\(fallback.iso)) instead, which can be a day "
                + "or so off from the actual received date"
            )
        } else {
            disclosedDate = nil
            warnings.append("no \"OGE Received\" date found — trades were skipped rather than dated wrong")
        }

        var rowCount = 0
        var pendingDescriptionLines: [String] = []
        for line in lines {
            guard let match = rowAnchor.firstMatch(in: line, range: line.nsRange) else {
                if !isBoilerplate(line) {
                    pendingDescriptionLines.append(line)
                    // A real row's description never spans more than a couple of printed
                    // lines. A longer run means something upstream (page layout, a missed
                    // anchor) broke the one-buffer-per-row assumption; better to drop the
                    // stale fragments and say so than silently weld unrelated text onto
                    // whatever row happens to close the buffer next.
                    if pendingDescriptionLines.count > 4 {
                        warnings.append(
                            "discarded \(pendingDescriptionLines.count) unmatched lines before "
                            + "a row could be found for them: \"\(pendingDescriptionLines.first ?? "")…\""
                        )
                        pendingDescriptionLines.removeAll()
                    }
                }
                continue
            }
            rowCount += 1
            guard let disclosedDate else { continue }

            let typeWord = line.substring(match, 1)?.lowercased() ?? ""
            let dateStr = line.substring(match, 2) ?? ""
            let tail = line.substring(match, 4) ?? ""
            let ownHead = String(line[..<Range(match.range(at: 1), in: line)!.lowerBound])
            let head = (pendingDescriptionLines + [ownHead]).joined(separator: " ")
            pendingDescriptionLines.removeAll()

            guard let txDate = CalendarDate(formStyle: normalizedDateCandidate(dateStr)) else {
                warnings.append("row \(rowCount): unreadable date \"\(dateStr)\" — skipped")
                continue
            }
            guard let txType = tradeType(for: typeWord) else {
                warnings.append("row \(rowCount): unrecognized type \"\(typeWord)\" — skipped")
                continue
            }

            let (number, description) = splitLeadingNumber(head)
            let (amount, pending) = PTRParser.parseAmount(normalizeAmountText(tail))
            if pending != .nothing {
                warnings.append("row \(number ?? "?"): amount continued past its own line — recorded as unknown")
            }
            if amount.kind == .unknown {
                warnings.append("row \(number ?? "?"): amount unreadable: \"\(tail)\"")
            }
            if description.isEmpty {
                warnings.append("row \(number ?? "?"): description was empty — kept anyway")
            }

            trades.append(Trade(
                id: "\(filing.filingID)-\(number ?? String(rowCount))",
                memberID: MemberDirectory.fallbackID(
                    last: filing.filerName, first: "", state: "", district: nil
                ),
                memberName: filing.filerName,
                owner: .self,
                asset: description,
                ticker: nil,
                assetType: nil,
                txType: txType,
                txDate: txDate,
                disclosedDate: disclosedDate,
                amount: amount,
                filingDescription: filing.position,
                filingID: filing.filingID,
                documentURL: filing.documentURL
            ))
        }

        if rowCount == 0 {
            warnings.append("no transaction rows recognized in this filing's OCR text")
        }
        return ParseResult(trades: trades, warnings: warnings)
    }

    // MARK: - Helpers

    /// Re-inserts a date's missing first `/`, if `rowAnchor` matched the fused form: the
    /// digits before the surviving slash are split as month + day, one digit of month for
    /// a 3-digit fusion (`514` → `5/14`) and two for a 4-digit one (`5114` → `51/14`).
    /// Passed through unchanged when it is already well-formed. The split is a guess, not
    /// a recovery — `CalendarDate(formStyle:)` still rejects an out-of-range result (a
    /// 4-digit fusion very often produces an impossible month, as in the real case this
    /// was built against), which is the intended outcome: report it unreadable rather
    /// than invent a date.
    private static func normalizedDateCandidate(_ raw: String) -> String {
        guard let match = fusedSlashDate.firstMatch(in: raw, range: raw.nsRange),
              let fused = raw.substring(match, 1), let year = raw.substring(match, 2)
        else { return raw }
        let splitIndex = fused.index(fused.endIndex, offsetBy: -2)
        return "\(fused[..<splitIndex])/\(fused[splitIndex...])/\(year)"
    }

    private static func tradeType(for word: String) -> TradeType? {
        switch word {
        case "purchase": return .buy
        case "sale": return .sell
        case "exchange": return .exchange
        default: return nil
        }
    }

    /// Splits "37   HOUSTON CNTY AL BRD..." into `("37", "HOUSTON CNTY AL BRD...")`. A
    /// row missing its leading number (an OCR miss on a single glyph) still yields the
    /// description, just with no row number for the id and warnings to key on.
    private static func splitLeadingNumber(_ head: String) -> (number: String?, description: String) {
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        guard let match = leadingRowNumber.firstMatch(in: trimmed, range: trimmed.nsRange),
              let number = trimmed.substring(match, 1), let rest = trimmed.substring(match, 2)
        else { return (nil, trimmed) }
        return (number, rest.trimmingCharacters(in: .whitespaces))
    }

    /// Vision reads this column's `$` as a bare `S` often enough, and its thousands
    /// comma as a period occasionally, to be worth correcting before `PTRParser`'s
    /// amount grammar (which wants a literal `$` and comma-grouped digits) ever sees it.
    /// Both fixes are unambiguous within an amount string specifically: nothing in a
    /// dollar-bracket label is legitimately a decimal point, and a bare `S` immediately
    /// before a digit has no other reading. Left alone: a `$` OCR'd as a bare `5` (also
    /// observed) is genuinely ambiguous against a real `$50,001`-style bracket, so that
    /// one is not guessed at — it surfaces as an "amount unreadable" warning instead.
    private static let bareDollarS = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])S(?=\d)"#)

    private static func normalizeAmountText(_ text: String) -> String {
        let sFixed = bareDollarS.stringByReplacingMatches(
            in: text, range: text.nsRange, withTemplate: "\\$"
        )
        // A period between digit groups where a thousands comma belongs: "5.000.000" →
        // "5,000,000". Lookaround rather than capturing the surrounding digits, so two
        // adjacent groups (a millions-scale bracket) both get fixed instead of the second
        // one losing its shared boundary digit to the first match.
        return sFixed.replacingOccurrences(
            of: #"(?<=\d)\.(?=\d{3}\b)"#, with: ",", options: .regularExpression
        )
    }

    /// True for reprinted page furniture that must never be folded into a row's
    /// description: the form header, column headings, the filer's name banner, an "OGE
    /// Received" line or a certifying official's signature date (both already read
    /// separately), or the legal boilerplate on the last page.
    private static func isBoilerplate(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if pageMarker.firstMatch(in: trimmed, range: trimmed.nsRange) != nil { return true }
        if ogeReceived.firstMatch(in: trimmed, range: trimmed.nsRange) != nil { return true }
        if certificationDate.firstMatch(in: trimmed, range: trimmed.nsRange) != nil { return true }
        if boilerplateMarkers.contains(where: { trimmed.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        return trimmed.localizedCaseInsensitiveContains("Description")
            && trimmed.localizedCaseInsensitiveContains("Type")
    }

    /// "OGE Received: 4/23/2026", read exactly as the form prints it.
    private static func ogeReceivedDate(in lines: [String]) -> CalendarDate? {
        for line in lines {
            if let match = ogeReceived.firstMatch(in: line, range: line.nsRange),
               let raw = line.substring(match, 1), let date = CalendarDate(formStyle: raw) {
                return date
            }
        }
        return nil
    }

    /// The digital-signature timestamp in the "U.S. Office of Government Ethics
    /// Certification" block — Adobe's standard `…Date: 2026.08.20 16:24:34 -04'00'`
    /// format, distinctive enough not to appear anywhere else on the form. Used only when
    /// `ogeReceivedDate` finds nothing.
    private static let certificationDate = try! NSRegularExpression(
        pattern: #"Date:\s*(\d{4})\.(\d{1,2})\.(\d{1,2})"#
    )

    private static func ogeCertificationDate(in lines: [String]) -> CalendarDate? {
        for line in lines {
            guard let match = certificationDate.firstMatch(in: line, range: line.nsRange),
                  let y = line.substring(match, 1), let m = line.substring(match, 2),
                  let d = line.substring(match, 3)
            else { continue }
            return CalendarDate(iso: "\(y)-\(m)-\(d)")
        }
        return nil
    }
}
