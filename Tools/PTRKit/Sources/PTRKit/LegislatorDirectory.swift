import Foundation
import DisclosureKit

/// Build-time loader for the Bioguide crosswalk that `MemberDirectory` resolves against.
///
/// The Clerk's index carries no member identifier — only a printed name and a seat. The
/// `congress-legislators` dataset is the public, maintained crosswalk from name and seat
/// to Bioguide ID, so identity is resolved once here, on a Mac, and baked into the seed.
///
/// It deliberately does not ship to the device. The two files together are tens of
/// megabytes, and the seed already carries the answer for every filer it saw, so an
/// on-device refresh reads `TradeFeed.nameToMemberID` instead of downloading this.
///
/// Matching itself lives in `DisclosureKit.MemberDirectory`, which is the tested copy.
/// This type only fetches, caches and decodes.
public enum LegislatorDirectory {

    /// Current members alone miss anyone who left mid-period but still had to file, so
    /// the historical file is loaded too.
    public static let sources: [(name: String, primary: URL, mirror: URL)] = [
        source("legislators-current.json"),
        source("legislators-historical.json"),
    ]

    private static func source(_ file: String) -> (String, URL, URL) {
        (
            file,
            URL(string: "https://unitedstates.github.io/congress-legislators/\(file)")!,
            URL(string: "https://raw.githubusercontent.com/unitedstates/congress-legislators/main/\(file)")!
        )
    }

    public static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60

    public struct LoadReport: Sendable {
        public var entries = 0
        public var filesLoaded: [String] = []
        public var filesFailed: [String] = []
    }

    /// Loads every crosswalk file into one directory, caching each to disk.
    ///
    /// A missing file degrades the result rather than failing the run: fewer members
    /// resolve to a Bioguide ID and the rest keep a fallback key, which the seed reports.
    /// Returns nil only when nothing at all could be read, so the caller can say so
    /// instead of silently shipping a seed keyed entirely on names.
    public static func load(
        cacheDirectory: URL,
        maxAge: TimeInterval = defaultMaxAge,
        force: Bool = false,
        session: URLSession = .shared
    ) async -> (directory: MemberDirectory?, report: LoadReport) {
        var report = LoadReport()
        var entries: [MemberDirectory.Entry] = []

        for (name, primary, mirror) in sources {
            guard let data = await fetch(
                name: name, urls: [primary, mirror],
                cacheDirectory: cacheDirectory, maxAge: maxAge, force: force, session: session
            ) else {
                report.filesFailed.append(name)
                continue
            }
            do {
                entries += try MemberDirectory.fromCongressLegislators(data).entries
                report.filesLoaded.append(name)
            } catch {
                report.filesFailed.append("\(name): \(error.localizedDescription)")
            }
        }

        report.entries = entries.count
        return (entries.isEmpty ? nil : MemberDirectory(entries: entries), report)
    }

    /// Returns the file's bytes, preferring a fresh cache, then the network, then a
    /// stale cache. A week-old crosswalk is still overwhelmingly correct, and is a far
    /// better answer than no identity at all.
    private static func fetch(
        name: String,
        urls: [URL],
        cacheDirectory: URL,
        maxAge: TimeInterval,
        force: Bool,
        session: URLSession
    ) async -> Data? {
        let path = cacheDirectory.appendingPathComponent(name)
        let modified = (try? FileManager.default.attributesOfItem(atPath: path.path))
            .flatMap { $0[.modificationDate] as? Date }
        let fresh = modified.map { Date().timeIntervalSince($0) <= maxAge } ?? false

        if !force, fresh, let data = try? Data(contentsOf: path) { return data }

        for url in urls {
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  !data.isEmpty
            else { continue }
            try? FileManager.default.createDirectory(
                at: cacheDirectory, withIntermediateDirectories: true
            )
            try? data.write(to: path, options: .atomic)
            return data
        }

        return try? Data(contentsOf: path)
    }
}
