import Foundation

/// A row of the House Clerk's annual filing index.
public struct FilingIndexRow: Hashable, Sendable {
    public let last: String
    public let first: String
    public let suffix: String
    /// "P" is a Periodic Transaction Report; the rest are annual reports, candidate
    /// filings, extensions, and terminations.
    public let filingType: String
    public let stateDst: String
    public let year: Int
    public let filedOn: CalendarDate?
    public let docID: String

    public var fullName: String {
        [first, last, suffix]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public var state: String { String(stateDst.prefix(2)) }

    public var district: String? {
        let d = String(stateDst.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? nil : d
    }

    public var isPeriodicTransactionReport: Bool { filingType == "P" }

    public var documentURL: URL? {
        houseDocumentURL(year: year, docID: docID)
    }
}

/// Builds the Clerk PDF URL for a filing, or nil when the document ID is not the plain
/// alphanumeric token the Clerk publishes. The scheme, host and path are fixed here;
/// guarding the one interpolated field stops a garbled or hostile index row from
/// pointing the "View the source filing" link anywhere other than a Clerk PDF.
func houseDocumentURL(year: Int, docID: String) -> URL? {
    guard !docID.isEmpty, docID.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
    return URL(string: "https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/\(year)/\(docID).pdf")
}

/// Reads the House Clerk's annual bulk filing index.
///
/// The Clerk publishes the index as both a ZIP and a plain tab-separated `.txt` at the
/// same path. Using the `.txt` directly means no archive reader and no `Process`, so the
/// identical code runs in the Mac CLI and on iOS.
///
/// # Threat model for every network read in this file
///
/// The app's whole claim is "this is the public record", so a network attacker or a
/// compromised CDN that could substitute a fabricated filing is the interesting threat.
/// The defences, and their deliberate limits:
///
/// - **Transport.** Every URL here is `https://disclosures-clerk.house.gov`, hard-coded,
///   scheme included. App Transport Security is locked in `Info.plist`
///   (`NSAllowsArbitraryLoads: false`, no exception domains), so the OS refuses a
///   downgrade to HTTP or to a TLS version below 1.2 and enforces the certificate chain.
/// - **No certificate pinning, on purpose.** The Clerk sits behind a rotating
///   government-managed certificate and (at times) a commercial CDN; pinning a leaf or
///   intermediate we do not control would turn a routine cert rotation into a dead app
///   in the field, which for a civic-record reader is the worse failure. The bar is
///   therefore "valid publicly-trusted TLS to the real hostname", not "this exact key".
/// - **What a successful MITM still cannot do.** The watchlist never takes part in any
///   request (see `IncrementalRefresher`), so there is nothing user-specific to steal on
///   the wire. Substituted *content* is the residual risk, and it is mitigated by
///   surface rather than by crypto: every screen shows the data's age, every row links
///   back to the source PDF on the same locked origin, and the parser reports rather
///   than invents (`ParseStats`, per-row warnings).
/// - **Resource bounds.** Responses are size-capped (`maxResponseBytes`) so a hostile or
///   broken server cannot exhaust memory, and the per-run download count is capped by
///   the caller (`IncrementalRefresher.maxDownloads`).
public enum FilingIndex {

    /// Hard ceiling on any single index response. The real file is a few MB; anything
    /// past this is a broken or hostile server and is refused rather than buffered.
    static let maxResponseBytes = 64 * 1024 * 1024

    public static func textURL(year: Int) -> URL {
        URL(string: "https://disclosures-clerk.house.gov/public_disc/financial-pdfs/\(year)FD.txt")!
    }

    /// Parses the tab-separated index. Public so tests can run without the network.
    public static func parse(_ raw: String, fallbackYear: Int) -> [FilingIndexRow] {
        let cleaned = raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var rows: [FilingIndexRow] = []
        for (n, line) in cleaned.components(separatedBy: "\n").enumerated() {
            if n == 0 { continue } // header
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let f = line.components(separatedBy: "\t")
            guard f.count >= 9 else { continue }

            // Column 0 is the name prefix (title); nothing downstream reads it, so it
            // is parsed past rather than stored.
            let year = Int(f[6].trimmingCharacters(in: .whitespaces)) ?? fallbackYear
            rows.append(FilingIndexRow(
                last: f[1].trimmingCharacters(in: .whitespaces),
                first: f[2].trimmingCharacters(in: .whitespaces),
                suffix: f[3].trimmingCharacters(in: .whitespaces),
                filingType: f[4].trimmingCharacters(in: .whitespaces),
                stateDst: f[5].trimmingCharacters(in: .whitespaces),
                year: year,
                filedOn: CalendarDate(formStyle: f[7]),
                docID: f[8].trimmingCharacters(in: .whitespaces)
            ))
        }
        return rows
    }

    /// How a `fetchWithContact` call actually reached the Clerk. Lets a caller tell
    /// "the Clerk confirmed this data" apart from "the Clerk was unreachable, so this is
    /// the last copy we hold" — a distinction the plain rows cannot carry, and the one
    /// P0-3 surfaces so a silent freeze does not read as the normal disclosure lag.
    public enum ClerkContact: Sendable, Equatable {
        /// HTTP 200 — the Clerk served the file.
        case fresh
        /// HTTP 304 — the Clerk confirmed the on-disk copy is still current.
        case notModified
        /// The Clerk could not be reached, or returned something unexpected; the rows
        /// came from the on-disk cache.
        case servedFromCache(Reason)

        public enum Reason: Sendable, Equatable {
            /// Transport failure — offline, DNS, TLS, timeout.
            case offline
            /// A response arrived but was not a clean 2xx/304.
            case badStatus(Int)
            /// The body was larger than `maxResponseBytes`.
            case tooLarge
            /// The body was not valid UTF-8.
            case undecodable

            /// A response arrived from the host but was not something we would accept —
            /// distinct from never reaching it at all.
            public var isUnexpectedResponse: Bool { self != .offline }
        }

        /// True only for a genuine good exchange with the Clerk (200 or a legitimate 304).
        public var reachedClerk: Bool {
            switch self {
            case .fresh, .notModified: return true
            case .servedFromCache: return false
            }
        }
    }

    /// Downloads the index for a year.
    ///
    /// The Clerk regenerates these files daily, so a cached copy is revalidated with the
    /// server rather than trusted because it exists. An earlier version of this skipped
    /// the request entirely whenever the file was already on disk, which meant the feed
    /// silently stopped growing after the first run.
    public static func fetch(
        year: Int,
        cacheDirectory: URL?,
        session: URLSession = .shared
    ) async throws -> [FilingIndexRow] {
        try await fetchWithContact(
            year: year, cacheDirectory: cacheDirectory, session: session
        ).rows
    }

    /// `fetch`, plus how the Clerk was actually reached. Falls back to the on-disk cache
    /// on any error or unexpected response, exactly as `fetch` does; throws only when
    /// there is no cache to fall back to.
    public static func fetchWithContact(
        year: Int,
        cacheDirectory: URL?,
        session: URLSession = .shared
    ) async throws -> (rows: [FilingIndexRow], contact: ClerkContact) {
        let url = textURL(year: year)
        let cacheFile = cacheDirectory?.appendingPathComponent("\(year)FD.txt")
        let etagFile = cacheDirectory?.appendingPathComponent("\(year)FD.etag")

        func cachedRows() -> [FilingIndexRow]? {
            guard let cacheFile,
                  let cached = try? String(contentsOf: cacheFile, encoding: .utf8)
            else { return nil }
            return parse(cached, fallbackYear: year)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Revalidate instead of re-downloading when the Clerk hasn't regenerated it.
        if let etagFile, let tag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(tag.trimmingCharacters(in: .whitespacesAndNewlines),
                             forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse

            if http?.statusCode == 304 {
                if let rows = cachedRows() { return (rows, .notModified) }
                // A 304 with nothing on disk to confirm is a broken exchange, not contact.
                throw IndexError.badStatus(304, year)
            }
            guard let http, (200..<300).contains(http.statusCode) else {
                let code = http?.statusCode ?? -1
                if let rows = cachedRows() { return (rows, .servedFromCache(.badStatus(code))) }
                throw IndexError.badStatus(code, year)
            }
            // `URLSession.data` has already buffered the body, so this bounds what gets
            // decoded, parsed and cached — three more copies — rather than the socket
            // read itself. A transport-level bound would mean streaming, which is not
            // worth it against a TLS-authenticated government host.
            guard data.count <= maxResponseBytes else {
                if let rows = cachedRows() { return (rows, .servedFromCache(.tooLarge)) }
                throw IndexError.tooLarge(year, data.count)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                if let rows = cachedRows() { return (rows, .servedFromCache(.undecodable)) }
                throw IndexError.undecodable(year)
            }
            if let cacheFile {
                try? FileManager.default.createDirectory(
                    at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? text.write(to: cacheFile, atomically: true, encoding: .utf8)
                if let etagFile, let tag = http.value(forHTTPHeaderField: "ETag") {
                    try? tag.write(to: etagFile, atomically: true, encoding: .utf8)
                }
            }
            return (parse(text, fallbackYear: year), .fresh)
        } catch let error as IndexError {
            throw error
        } catch {
            // Offline: fall back to whatever is cached rather than failing outright.
            if let rows = cachedRows() { return (rows, .servedFromCache(.offline)) }
            throw error
        }
    }

    public enum IndexError: LocalizedError {
        case badStatus(Int, Int)
        case undecodable(Int)
        case tooLarge(Int, Int)

        public var errorDescription: String? {
            switch self {
            case let .badStatus(code, year): return "index \(year): HTTP \(code)"
            case let .undecodable(year): return "index \(year): not valid UTF-8"
            case let .tooLarge(year, bytes): return "index \(year): response too large (\(bytes) bytes)"
            }
        }
    }

    /// Filing years that should be covered as of `today`.
    ///
    /// Disclosures for December trades land the following January, so the previous year
    /// stays relevant well into the new one. Defaulting to the current year alone meant
    /// the pipeline would produce a nearly empty feed every January 1st.
    public static func relevantYears(asOf today: CalendarDate = .today()) -> [Int] {
        [today.year - 1, today.year]
    }
}
