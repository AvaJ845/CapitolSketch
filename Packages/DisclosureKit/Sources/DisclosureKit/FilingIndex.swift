import Foundation

/// A row of the House Clerk's annual filing index.
public struct FilingIndexRow: Hashable, Sendable {
    public let prefix: String
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
public enum FilingIndex {

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

            let year = Int(f[6].trimmingCharacters(in: .whitespaces)) ?? fallbackYear
            rows.append(FilingIndexRow(
                prefix: f[0],
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
        let url = textURL(year: year)
        let cacheFile = cacheDirectory?.appendingPathComponent("\(year)FD.txt")
        let etagFile = cacheDirectory?.appendingPathComponent("\(year)FD.etag")

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

            if http?.statusCode == 304, let cacheFile,
               let cached = try? String(contentsOf: cacheFile, encoding: .utf8) {
                return parse(cached, fallbackYear: year)
            }
            guard let http, (200..<300).contains(http.statusCode) else {
                throw IndexError.badStatus(http?.statusCode ?? -1, year)
            }
            guard let text = String(data: data, encoding: .utf8) else {
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
            return parse(text, fallbackYear: year)
        } catch {
            // Offline: fall back to whatever is cached rather than failing outright.
            if let cacheFile, let cached = try? String(contentsOf: cacheFile, encoding: .utf8) {
                return parse(cached, fallbackYear: year)
            }
            throw error
        }
    }

    public enum IndexError: LocalizedError {
        case badStatus(Int, Int)
        case undecodable(Int)

        public var errorDescription: String? {
            switch self {
            case let .badStatus(code, year): return "index \(year): HTTP \(code)"
            case let .undecodable(year): return "index \(year): not valid UTF-8"
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
