import Foundation
import Testing
@testable import DisclosureKit

/// Committee assignments are baked into the seed as public facts: names on a member,
/// carried through a merge, never matched against a traded company. The field was added
/// additively — no schema bump — so these also pin that an older feed with no
/// `committees` key still decodes.
@Suite("Committee assignments")
struct CommitteeTests {

    // A miniature of the two `congress-legislators` files: two full committees, one with a
    // subcommittee, plus a membership roster that includes the subcommittee key.
    static let committeesJSON = Data("""
    [
      { "type": "house", "name": "House Committee on Armed Services", "thomas_id": "HSAS",
        "subcommittees": [ { "name": "Readiness", "thomas_id": "03" } ] },
      { "type": "house", "name": "House Committee on Appropriations", "thomas_id": "HSAP",
        "subcommittees": [] },
      { "type": "senate", "name": "Senate Committee on Finance", "thomas_id": "SSFI",
        "subcommittees": [] },
      { "type": "joint", "name": "Joint Economic Committee", "thomas_id": "JSEC",
        "subcommittees": [] }
    ]
    """.utf8)

    static let membershipJSON = Data("""
    {
      "HSAS": [
        { "name": "Rogers, Mike", "party": "majority", "rank": 1, "title": "Chair", "bioguide": "R000575" },
        { "name": "Smith, Adam", "party": "minority", "rank": 1, "bioguide": "S000510" }
      ],
      "HSAS03": [
        { "name": "Smith, Adam", "party": "minority", "rank": 1, "bioguide": "S000510" }
      ],
      "HSAP": [
        { "name": "Smith, Adam", "party": "minority", "rank": 4, "bioguide": "S000510" }
      ],
      "SSFI": [
        { "name": "Wyden, Ron", "party": "majority", "rank": 1, "bioguide": "W000779" }
      ],
      "JSEC": [
        { "name": "Wyden, Ron", "party": "majority", "rank": 2, "bioguide": "W000779" }
      ]
    }
    """.utf8)

    @Test("Maps bioguide to sorted, de-duped full-committee names and skips subcommittees")
    func mappingShape() throws {
        let roster = try CommitteeRoster.fromCongressLegislators(
            committeesJSON: Self.committeesJSON, membershipJSON: Self.membershipJSON
        )

        // Adam Smith sits on two full committees; the subcommittee key HSAS03 must not add
        // a third entry, and the two names come back sorted, verbatim from the source.
        #expect(roster.byBioguide["S000510"]
                == ["House Committee on Appropriations", "House Committee on Armed Services"])
        #expect(roster.byBioguide["R000575"] == ["House Committee on Armed Services"])
        // Both chambers, names exactly as the source writes them.
        #expect(roster.byBioguide["W000779"]
                == ["Joint Economic Committee", "Senate Committee on Finance"])

        #expect(roster.committeeCount == 4)
        #expect(roster.membersMapped == 3)
        #expect(roster.assignmentCount == 5)
    }

    @Test("A member on no committee is absent, not present with an empty list")
    func absentMember() throws {
        let roster = try CommitteeRoster.fromCongressLegislators(
            committeesJSON: Self.committeesJSON, membershipJSON: Self.membershipJSON
        )
        #expect(roster.byBioguide["X999999"] == nil)
    }

    // MARK: - The committees field

    static func member(committees: [String]) -> Member {
        Member(id: "S000510", bioguideID: "S000510", name: "Adam Smith",
               state: "WA", district: "9", chamber: .house, committees: committees)
    }

    static func feed(members: [Member], trades: [Trade] = []) -> TradeFeed {
        FeedBuilder.make(
            trades: trades, members: members,
            stats: ParseStats(filingsProcessed: 1, tradesParsed: trades.count),
            indexYears: [2025, 2026]
        )
    }

    @Test("Adding committees did not bump the schema version")
    func schemaVersionUnchanged() {
        #expect(TradeFeed.currentSchemaVersion == 2)
    }

    @Test("A feed whose members carry committees round-trips through its coder unchanged")
    func committeesRoundTrip() throws {
        let original = Self.feed(members: [Self.member(
            committees: ["House Committee on Appropriations", "House Committee on Armed Services"]
        )])
        let (encoder, decoder) = TradeFeed.makeCoder()
        let restored = try decoder.decode(TradeFeed.self, from: encoder.encode(original))

        #expect(restored.schemaVersion == 2)
        #expect(restored.members == original.members)
        #expect(restored.members.first?.committees
                == ["House Committee on Appropriations", "House Committee on Armed Services"])
    }

    // MARK: - Backward compatibility

    @Test("A member JSON written before the committees key decodes with an empty list")
    func decodesMemberWithoutCommitteesKey() throws {
        let older = Data("""
        { "id": "S000510", "bioguideID": "S000510", "name": "Adam Smith",
          "state": "WA", "district": "9", "chamber": "house" }
        """.utf8)
        let (_, decoder) = TradeFeed.makeCoder()
        let member = try decoder.decode(Member.self, from: older)
        #expect(member.committees.isEmpty)
        #expect(member.name == "Adam Smith")
    }

    // MARK: - Merge

    @Test("Merge keeps the seed member's committees; a genuinely new member has none")
    func mergeKeepsSeedCommittees() {
        let seed = Self.feed(members: [Self.member(committees: ["House Committee on Armed Services"])])

        // Same member, re-seen by an on-device refresh with no committee data, plus a
        // member the seed never had.
        let refreshedKnown = Member(id: "S000510", bioguideID: "S000510", name: "Adam Smith",
                                    state: "WA", district: "9", chamber: .house)
        let brandNew = Member(id: "x-doe-jane-tx-1", bioguideID: nil, name: "Jane Doe",
                              state: "TX", district: "1", chamber: .house)

        let merged = FeedBuilder.merge(
            seed: seed, newTrades: [], newMembers: [refreshedKnown, brandNew]
        )

        let smith = merged.members.first { $0.id == "S000510" }
        #expect(smith?.committees == ["House Committee on Armed Services"])
        let doe = merged.members.first { $0.id == "x-doe-jane-tx-1" }
        #expect(doe?.committees.isEmpty == true)
    }
}
