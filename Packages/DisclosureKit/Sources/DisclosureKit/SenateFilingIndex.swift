import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One row of the Senate eFD Periodic Transaction Report search.
public struct SenateFilingRow: Hashable, Sendable {
    public let first: String
    public let last: String
    public let uuid: String
    public let isPaper: Bool
    public let isAmendment: Bool
    public let filedOn: CalendarDate?

    public var fullName: String {
        [first, last].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Queries efdsearch.senate.gov for Periodic Transaction Reports.
///
/// **Build-time only.** The app never calls this — Senate coverage ships baked into the
/// seed. The reasons, per the design review: the portal sits behind a CSRF "prohibition
/// agreement" gate plus Akamai bot management, so a `seedgen` run on a residential
/// connection is a far more reliable place to do it than every reader's phone; and there
/// is no bulk index, so a full pass is one HTTP round-trip per filing, which is
/// `seedgen`'s job, not an on-device refresh's.
///
/// The request pattern still carries no user data — same public search, same filters,
/// for the machine that builds the snapshot.
public enum SenateFilingIndex {

    public static let root = URL(string: "https://efdsearch.senate.gov")!
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public enum IndexError: LocalizedError {
        case blocked(Int)
        case noCSRFToken
        case badJSON

        public var errorDescription: String? {
            switch self {
            case let .blocked(code): return "efdsearch returned HTTP \(code) — likely bot-blocked"
            case .noCSRFToken: return "could not read the CSRF token from the agreement page"
            case .badJSON: return "the report search returned something other than the expected JSON"
            }
        }
    }

    /// All PTRs filed on or after `since`, newest first.
    ///
    /// - Parameter pageSize: rows per request; the API caps somewhere near 100.
    public static func fetchPTRs(
        since: CalendarDate,
        pageSize: Int = 100,
        politenessDelay: Duration = .milliseconds(700),
        session: URLSession = SenateFilingIndex.makeSession()
    ) async throws -> [SenateFilingRow] {
        let token = try await acceptAgreement(session: session)

        var rows: [SenateFilingRow] = []
        var offset = 0
        while true {
            let page = try await queryReports(
                offset: offset, length: pageSize, since: since, token: token, session: session
            )
            if page.isEmpty { break }
            rows.append(contentsOf: page)
            offset += pageSize
            if page.count < pageSize { break }
            try? await Task.sleep(for: politenessDelay)
        }
        return rows
    }

    // MARK: - Session

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    // MARK: - Handshake

    /// GET the agreement page, POST `prohibition_agreement=1`, return the session CSRF
    /// token (the value the search endpoint wants in its form body).
    private static func acceptAgreement(session: URLSession) async throws -> String {
        let home = root.appending(path: "/search/home/")
        let (data, response) = try await session.data(from: home)
        try check(response)

        guard let html = String(data: data, encoding: .utf8),
              let formToken = firstMatch(
                in: html, pattern: #"name="csrfmiddlewaretoken"\s+value="([^"]+)""#
              )
        else { throw IndexError.noCSRFToken }

        var post = URLRequest(url: home)
        post.httpMethod = "POST"
        post.setValue(home.absoluteString, forHTTPHeaderField: "Referer")
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = formEncoded([
            "csrfmiddlewaretoken": formToken,
            "prohibition_agreement": "1",
        ])
        _ = try await session.data(for: post)

        let cookieToken = session.configuration.httpCookieStorage?
            .cookies(for: root)?
            .first { $0.name == "csrftoken" || $0.name == "csrf" }?
            .value
        return cookieToken ?? formToken
    }

    // MARK: - DataTables query

    private static func queryReports(
        offset: Int, length: Int, since: CalendarDate, token: String, session: URLSession
    ) async throws -> [SenateFilingRow] {
        let url = root.appending(path: "/search/report/data/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(root.appending(path: "/search/").absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.httpBody = formEncoded([
            "draw": "1",
            "start": String(offset),
            "length": String(length),
            "report_types": "[11]",           // 11 = Periodic Transaction Report
            "filer_types": "[]",
            "submitted_start_date": "\(String(format: "%02d/%02d/%04d", since.month, since.day, since.year)) 00:00:00",
            "submitted_end_date": "",
            "candidate_state": "",
            "senator_state": "",
            "office_id": "",
            "first_name": "",
            "last_name": "",
            "csrfmiddlewaretoken": token,
        ])

        let (data, response) = try await session.data(for: request)
        try check(response)

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["data"] as? [[Any]]
        else { throw IndexError.badJSON }

        return raw.compactMap(row(from:))
    }

    /// A search row is `[first, last, displayName, linkHTML, filedDate]`.
    static func row(from raw: [Any]) -> SenateFilingRow? {
        guard raw.count >= 5,
              let first = raw[0] as? String,
              let last = raw[1] as? String,
              let linkHTML = raw[3] as? String,
              let filed = raw[4] as? String
        else { return nil }

        guard let match = firstMatch(
            in: linkHTML, pattern: #"/search/view/(ptr|paper)/([0-9a-f-]{36})/"#, group: 2
        ) else { return nil }
        let kind = firstMatch(in: linkHTML, pattern: #"/search/view/(ptr|paper)/"#, group: 1) ?? "ptr"

        return SenateFilingRow(
            first: first.trimmingCharacters(in: .whitespaces),
            last: last.trimmingCharacters(in: .whitespaces),
            uuid: match,
            isPaper: kind == "paper",
            isAmendment: linkHTML.localizedCaseInsensitiveContains("amendment"),
            filedOn: CalendarDate(formStyle: filed)
        )
    }

    // MARK: - Helpers

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw IndexError.blocked(http.statusCode) }
    }

    private static func formEncoded(_ pairs: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = pairs.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func firstMatch(
        in text: String, pattern: String, group: Int = 1
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[range])
    }
}
