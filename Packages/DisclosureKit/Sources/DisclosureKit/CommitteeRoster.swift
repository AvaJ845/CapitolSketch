import Foundation

/// Turns the `unitedstates/congress-legislators` committee files into a plain
/// Bioguide-ID → committee-names map.
///
/// This is the tested half of committee ingestion, the same split `MemberDirectory` has
/// with `LegislatorDirectory`: the PTRKit `CommitteeDirectory` only fetches, caches and
/// decodes the two JSON files, then hands the bytes here.
///
/// It lists full committees only. Subcommittee rows in the membership file are keyed by
/// the parent's THOMAS id followed by the subcommittee's (`SSAF15`), so any key that is
/// not itself a full-committee id is skipped. Names are used exactly as the source writes
/// them — no trimming, no house style — so the app shows the official name and nothing is
/// an editorial judgement. Nothing here is matched against a traded company either; that
/// mapping would be editorial and is deliberately absent.
public struct CommitteeRoster: Sendable, Equatable {

    /// Bioguide ID → sorted, de-duplicated full-committee display names.
    public let byBioguide: [String: [String]]

    /// Number of distinct full committees seen, for a coverage line.
    public let committeeCount: Int

    public init(byBioguide: [String: [String]], committeeCount: Int) {
        self.byBioguide = byBioguide
        self.committeeCount = committeeCount
    }

    public var membersMapped: Int { byBioguide.count }
    public var assignmentCount: Int { byBioguide.values.reduce(0) { $0 + $1.count } }

    // MARK: - Decoding

    private struct CommitteeRecord: Decodable {
        let name: String
        let thomas_id: String
    }

    private struct MembershipEntry: Decodable {
        let bioguide: String?
    }

    /// - Parameters:
    ///   - committeesJSON: `committees-current.json` — the array of full committees.
    ///   - membershipJSON: `committee-membership-current.json` — THOMAS id → member rows.
    public static func fromCongressLegislators(
        committeesJSON: Data, membershipJSON: Data
    ) throws -> CommitteeRoster {
        let committees = try JSONDecoder().decode([CommitteeRecord].self, from: committeesJSON)
        let membership = try JSONDecoder()
            .decode([String: [MembershipEntry]].self, from: membershipJSON)

        // THOMAS id → official name, full committees only, verbatim from the source.
        var nameByID: [String: String] = [:]
        for c in committees where !c.thomas_id.isEmpty {
            nameByID[c.thomas_id] = c.name.trimmingCharacters(in: .whitespaces)
        }

        var sets: [String: Set<String>] = [:]
        for (key, rows) in membership {
            // A key that is not itself a full-committee id is a subcommittee (parent id
            // + subcommittee id, e.g. `SSAF15`) — skip it.
            guard let committeeName = nameByID[key] else { continue }
            for row in rows {
                guard let bio = row.bioguide, !bio.isEmpty else { continue }
                sets[bio, default: []].insert(committeeName)
            }
        }

        let byBioguide = sets.mapValues { $0.sorted() }
        return CommitteeRoster(byBioguide: byBioguide, committeeCount: nameByID.count)
    }
}
