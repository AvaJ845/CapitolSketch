// White House disclosures-page scraping. The shipping app is House/Senate-only and no
// app or widget code path reaches any type in this file; it is compiled only for
// `seedgen` and the DisclosureKit test target, both of which define SEEDGEN — the same
// treatment `SenateFetcher.swift` gets, for the same reason: build-time-only ingestion.
#if SEEDGEN
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One Periodic Transaction Report link found on the White House's own disclosures page.
///
/// `filerName` and `filedOn` are read from the link's visible text, not from the PDF —
/// they are what the page says about the filing, useful for discovery and ordering, but
/// not authoritative. The PDF itself (fetched from `documentURL`) is the source of
/// record for the actual transactions, the same division `SenateFilingRow` draws between
/// what the index row says and what the filing itself says.
public struct WhiteHouseFilingRow: Hashable, Sendable {
    public let filerName: String
    public let linkText: String
    public let documentURL: URL
    public let isAmendment: Bool
    /// Best-effort parse of the trailing `MM.DD.YY` (or `YYYY`) in the link text. `nil`
    /// when the text does not end in a recognizable date, which should not stop the
    /// filing from being surfaced — Phase 2's PDF parse is what actually matters.
    public let filedOn: CalendarDate?
}

/// Reads `whitehouse.gov/disclosures/` for Periodic Transaction Report filings.
///
/// **Build-time only** — the same reasoning as `SenateFilingIndex`: low volume (a
/// handful of filings a month), no case for polling this from every reader's phone.
///
/// Unlike the Clerk or Senate eFD, there is no documented bulk index or search API here.
/// `/disclosures/` is the same page a person reads in a browser — the White House's own
/// on-site search surfaces it as "Public Disclosures" — and as observed it lists every
/// filing back to the start of the administration on one page with no pagination (365
/// PDF links spanning March 2025 – August 2026 in a single GET). If the White House ever
/// paginates or restyles this page, `fetchFilings` will simply stop finding the filings
/// past whatever changed; that is a discovery gap for the caller to notice via its own
/// filing count, not something this type can detect on its own.
public enum WhiteHouseFilingIndex {

    public static let indexURL = URL(string: "https://www.whitehouse.gov/disclosures/")!

    /// Matches "President [Name] Periodic Transaction Report" link text, so an
    /// administration change does not require a code update. Annual (OGE Form 278e)
    /// filings and every other official's PTRs are present on the same page and are
    /// deliberately excluded here, not fetched and dropped later.
    public static let presidentialFilerPattern = #"^President\s+.+?\s+Periodic Transaction Report"#

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public enum IndexError: LocalizedError {
        case badStatus(Int)
        case undecodable

        public var errorDescription: String? {
            switch self {
            case let .badStatus(code): return "whitehouse.gov/disclosures: HTTP \(code)"
            case .undecodable: return "whitehouse.gov/disclosures: response was not valid UTF-8"
            }
        }
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    /// Every Periodic Transaction Report link on the disclosures page whose visible text
    /// matches `filerNamePattern` — the President's, by default.
    public static func fetchFilings(
        matchingFilerNamed filerNamePattern: String = presidentialFilerPattern,
        session: URLSession = WhiteHouseFilingIndex.makeSession()
    ) async throws -> [WhiteHouseFilingRow] {
        var request = URLRequest(url: indexURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndexError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw IndexError.undecodable }
        return parse(html, matchingFilerNamed: filerNamePattern)
    }

    /// Parses the page's `<a href="…pdf">Link Text</a>` file blocks and keeps only the
    /// ones whose link text matches `pattern`. Public so a test can run without the
    /// network. This reads what a browser would show — WordPress block markup, not a
    /// documented schema — so it is brittle by nature and worth re-checking if the White
    /// House ever restyles the page.
    public static func parse(
        _ html: String, matchingFilerNamed pattern: String
    ) -> [WhiteHouseFilingRow] {
        guard let anchorRegex = try? NSRegularExpression(
            pattern: #"<a\s+[^>]*href="([^"]+\.pdf)"[^>]*>([^<]+)</a>"#, options: [.caseInsensitive]
        ), let filerRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return [] }

        var seen = Set<URL>()
        var rows: [WhiteHouseFilingRow] = []
        for match in anchorRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard match.numberOfRanges == 3,
                  let urlRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html)
            else { continue }

            let linkText = decodeEntities(String(html[textRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard filerRegex.firstMatch(in: linkText, range: NSRange(linkText.startIndex..., in: linkText)) != nil
            else { continue }
            guard let url = URL(string: String(html[urlRange])), seen.insert(url).inserted else { continue }

            let filerName = linkText.components(separatedBy: "Periodic Transaction Report").first?
                .trimmingCharacters(in: .whitespaces) ?? linkText
            rows.append(WhiteHouseFilingRow(
                filerName: filerName,
                linkText: linkText,
                documentURL: url,
                isAmendment: linkText.localizedCaseInsensitiveContains("amendment"),
                filedOn: trailingDate(in: linkText)
            ))
        }
        // Newest first when a date parsed; undated rows (should not normally occur) sort
        // last rather than interleaving unpredictably.
        return rows.sorted { a, b in
            switch (a.filedOn, b.filedOn) {
            case let (l?, r?) where l != r: return l > r
            case (nil, .some): return false
            case (.some, nil): return true
            default: return a.linkText < b.linkText
            }
        }
    }

    // MARK: - Helpers

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The last `M(.M)?\.D(.D)?\.YY(YY)?` token in the text, as a `CalendarDate`. Link
    /// text observed in the wild is `MM.DD.YY` (e.g. "05.08.26 (1)"), consistent with the
    /// upload path's own `/YYYY/MM/` prefix.
    private static func trailingDate(in text: String) -> CalendarDate? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\.(\d{1,2})\.(\d{2,4})"#),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last
        else { return nil }
        return CalendarDate(formStyle: (1...3).map { group in
            (Range(match.range(at: group), in: text)).map { String(text[$0]) } ?? ""
        }.joined(separator: "/"))
    }
}
#endif // SEEDGEN
