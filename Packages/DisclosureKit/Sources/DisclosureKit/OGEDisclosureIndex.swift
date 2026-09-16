// OGE disclosure-database discovery. Build-time only (`seedgen` / the test target); the
// shipping app never runs this — same reasoning as `WhiteHouseFilingIndex`.
#if SEEDGEN
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One document listed in OGE's Presidential Nominee and Appointee Request System — the
/// public record of financial disclosures for every Presidentially-appointed,
/// Senate-confirmed (PAS) official government-wide, not just the President. `type` is
/// read from the site's own type label ("278 Transaction", "Annual (2026)", "Ethics
/// Agreement", …) and `documentURL` is only ever a direct, immediately downloadable PDF —
/// most records in this system are "Request this Document" placeholders that require
/// manually contacting OGE, which this fetches nothing for, since nothing here can be
/// automated past that point.
public struct OGEDisclosureRow: Hashable, Sendable {
    public let name: String
    public let agency: String
    public let title: String
    public let type: String
    /// The date OGE's own system recorded this document ("Date Added" in the site's own
    /// table) — read from the leading `yyyy-MM-dd` of the API's ISO timestamp. Used as
    /// the disclosed date directly; there is no separate "OGE Received" line to look for
    /// the way the scanned presidential filings need, since this value already comes
    /// from OGE's own record-keeping rather than something printed on the form.
    public let docDate: CalendarDate?
    public let documentURL: URL
}

/// Reads `extapps2.oge.gov`'s public disclosure database.
///
/// **Build-time only** — same reasoning as `WhiteHouseFilingIndex`: no case for hitting
/// this from every reader's phone.
///
/// Unlike `whitehouse.gov/disclosures` (one filer, one static page), this is a real
/// DataTables-backed REST endpoint behind the site's own search UI
/// (`www.oge.gov/web/oge.nsf/Officials Individual Disclosures Search Collection`) —
/// found by reading that page's own `<script>` block, not documented anywhere OGE
/// publishes. It answers a plain, unauthenticated GET with every row it holds — this
/// implementation fetches all of them in one page (`length` set to comfortably exceed
/// `recordsTotal`) rather than reverse-engineering the site's server-side search
/// parameters, since the whole response is a few MB and this only ever runs at build
/// time. As of the filing this was built against, `recordsTotal` was ~16,600 covering
/// every PAS position, not just Cabinet secretaries — callers filter down with
/// `cabinetDepartmentRows`.
public enum OGEDisclosureIndex {

    public static let apiURL = URL(string: "https://extapps2.oge.gov/201/Presiden.nsf/API.xsp/v2/rest")!

    /// Comfortably above the ~16,600 records observed; the API reports `recordsTotal` in
    /// its own response, so a caller that wants to confirm nothing was truncated can
    /// compare it against the row count returned.
    private static let pageLength = 30_000

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public enum IndexError: LocalizedError {
        case badStatus(Int)
        case badJSON

        public var errorDescription: String? {
            switch self {
            case let .badStatus(code): return "OGE disclosure API: HTTP \(code)"
            case .badJSON: return "OGE disclosure API: response was not the expected JSON shape"
            }
        }
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    private struct APIResponse: Decodable {
        struct Row: Decodable {
            let type: String
            let name: String
            let agency: String
            let title: String
            let docDate: String?
        }
        let recordsTotal: Int
        let data: [Row]
    }

    /// Only a row whose `type` field links straight to a `.pdf` — the site's own way of
    /// saying "public and downloadable now" as opposed to "Request this Document", a
    /// manual process with no automatable endpoint.
    private static let directPDFLink = try! NSRegularExpression(
        pattern: #"href='([^']+\.pdf)'>([^<]+)</a>"#
    )

    /// Every row in the database with a directly downloadable document. Rows behind
    /// "Request this Document" are silently excluded — there is nothing to fetch there.
    public static func fetchAllRows(session: URLSession = OGEDisclosureIndex.makeSession()) async throws -> [OGEDisclosureRow] {
        var request = URLRequest(url: apiURL)
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "draw", value: "1"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "length", value: String(pageLength)),
        ]
        request.url = components.url
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndexError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let parsed = try? JSONDecoder().decode(APIResponse.self, from: data) else {
            throw IndexError.badJSON
        }

        return parsed.data.compactMap { row -> OGEDisclosureRow? in
            guard let match = directPDFLink.firstMatch(in: row.type, range: row.type.nsRange),
                  let urlString = row.type.substring(match, 1),
                  let label = row.type.substring(match, 2),
                  let url = URL(string: urlString)
            else { return nil }
            let date = row.docDate.flatMap { CalendarDate(iso: String($0.prefix(10))) }
            return OGEDisclosureRow(
                name: row.name, agency: row.agency, title: row.title,
                type: label, docDate: date, documentURL: url
            )
        }
    }

    /// The 15 executive departments' heads — "Secretary" everywhere except the
    /// Department of Justice, whose head is styled "Attorney General". Matched against
    /// `agency` as a loose substring (the database spells the same department several
    /// different ways across administrations — "Department Of Agriculture" and
    /// "Department of Agriculture" are both real, observed strings — and `title` is
    /// matched by substring too, since some records append extra detail like "Secretary,
    /// United States Department of Justice").
    private static let cabinetDepartmentNames = [
        "agriculture", "commerce", "defense", "education", "energy",
        "health and human services", "homeland security", "housing and urban development",
        "interior", "justice", "labor", "state", "transportation", "treasury",
        "veterans affairs",
    ]

    /// Every row whose `agency` names one of the 15 executive departments and whose
    /// `title` is that department's own head (Secretary, or Attorney General for
    /// Justice) — matched by *prefix*, not substring, specifically so "Deputy
    /// Secretary", "Under Secretary" and "Assistant Secretary" (all real titles in this
    /// database, all containing the substring "secretary") are excluded. Deliberately
    /// not every Cabinet-*rank* position either (EPA, OMB, DNI, CIA, USTR, …), which is a
    /// different, broader question from "the departments."
    public static func cabinetDepartmentRows(in rows: [OGEDisclosureRow]) -> [OGEDisclosureRow] {
        rows.filter { row in
            let agency = row.agency.lowercased()
            guard agency.contains("department of") else { return false }
            guard cabinetDepartmentNames.contains(where: { agency.contains($0) }) else { return false }
            let title = row.title.trimmingCharacters(in: .whitespaces).lowercased()
            return title.hasPrefix("secretary") || title.hasPrefix("attorney general")
        }
    }
}
#endif
