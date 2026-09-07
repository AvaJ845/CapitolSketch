import Foundation
import DisclosureKit

/// Build-time loader for public committee assignments, modelled on `LegislatorDirectory`.
///
/// It fetches the two `unitedstates/congress-legislators` committee files — the list of
/// current committees and the current membership roster — caches each to disk, and hands
/// the bytes to `DisclosureKit.CommitteeRoster`, which does the actual mapping and is the
/// tested copy.
///
/// A checked-in copy of both files lives in `Sources/PTRKit/ReferenceData/` as an offline
/// floor: a build with a network connection always prefers a fresh fetch, but a machine
/// that has never fetched them and has no network now still produces committee data
/// rather than silently dropping it. That copy is refreshed by committing a new one,
/// reviewed as a diff — the same discipline as the parser's PTR fixtures. The much larger
/// legislator crosswalk (~15 MB, mostly historical) is not vendored this way.
///
/// Like the Bioguide crosswalk this deliberately does not ship to the device: the
/// committee names are baked into the seed by `seedgen`, and an on-device refresh never
/// fetches them. A member the seed never saw keeps an empty committee list, which the
/// data-quality screen reports.
public enum CommitteeDirectory {

    public static let sources: [(name: String, primary: URL, mirror: URL)] = [
        source("committees-current.json"),
        source("committee-membership-current.json"),
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
        public var membersMapped = 0
        public var assignments = 0
        public var committees = 0
        public var filesLoaded: [String] = []
        public var filesFailed: [String] = []
        /// Files that came from the checked-in copy because the network and the cache
        /// both failed. The seed is still built, but from data that may be a Congress old.
        public var filesFromBundle: [String] = []
    }

    private struct FetchOutcome {
        let data: Data
        let fromBundle: Bool
    }

    /// Loads both files and returns the resulting roster, or `nil` when the mapping could
    /// not be built (either file unavailable, or a decode failure). A `nil` result means
    /// `seedgen` ships a seed with no committee data rather than failing the run — the
    /// same discipline as the crosswalk.
    public static func load(
        cacheDirectory: URL,
        maxAge: TimeInterval = defaultMaxAge,
        force: Bool = false,
        session: URLSession = .shared
    ) async -> (roster: CommitteeRoster?, report: LoadReport) {
        var report = LoadReport()
        var loaded: [String: Data] = [:]

        for (name, primary, mirror) in sources {
            guard let outcome = await fetch(
                name: name, urls: [primary, mirror],
                cacheDirectory: cacheDirectory, maxAge: maxAge, force: force, session: session
            ) else {
                report.filesFailed.append(name)
                continue
            }
            loaded[name] = outcome.data
            report.filesLoaded.append(name)
            if outcome.fromBundle { report.filesFromBundle.append(name) }
        }

        guard let committees = loaded["committees-current.json"],
              let membership = loaded["committee-membership-current.json"]
        else {
            return (nil, report)
        }

        do {
            let roster = try CommitteeRoster.fromCongressLegislators(
                committeesJSON: committees, membershipJSON: membership
            )
            report.membersMapped = roster.membersMapped
            report.assignments = roster.assignmentCount
            report.committees = roster.committeeCount
            return (roster.byBioguide.isEmpty ? nil : roster, report)
        } catch {
            report.filesFailed.append("decode: \(error.localizedDescription)")
            return (nil, report)
        }
    }

    /// Fresh cache, then network, then a stale cache, then the checked-in copy. The first
    /// three steps are identical to `LegislatorDirectory`; only the last is new, and it
    /// only fires when a machine has never fetched these files and has no network now.
    private static func fetch(
        name: String,
        urls: [URL],
        cacheDirectory: URL,
        maxAge: TimeInterval,
        force: Bool,
        session: URLSession
    ) async -> FetchOutcome? {
        let path = cacheDirectory.appendingPathComponent(name)
        let modified = (try? FileManager.default.attributesOfItem(atPath: path.path))
            .flatMap { $0[.modificationDate] as? Date }
        let fresh = modified.map { Date().timeIntervalSince($0) <= maxAge } ?? false

        if !force, fresh, let data = try? Data(contentsOf: path) {
            return FetchOutcome(data: data, fromBundle: false)
        }

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
            return FetchOutcome(data: data, fromBundle: false)
        }

        if let stale = try? Data(contentsOf: path) {
            return FetchOutcome(data: stale, fromBundle: false)
        }
        if let bundled = bundledCopy(named: name) {
            return FetchOutcome(data: bundled, fromBundle: true)
        }
        return nil
    }

    /// The copy checked into `Sources/PTRKit/ReferenceData/`. It is a floor, not a
    /// source: a build with a network connection always prefers a fresh fetch, and this
    /// file is refreshed by committing a new one, reviewed as a diff.
    static func bundledCopy(named name: String) -> Data? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(
            forResource: base, withExtension: ext, subdirectory: "ReferenceData"
        ) else { return nil }
        return try? Data(contentsOf: url)
    }
}
