#if SEEDGEN
import Foundation
import Testing
@testable import DisclosureKit

/// The Senate eFD search prints only a name, and the crosswalk carries every historical
/// namesake. These pin the two fixes that make `resolve(last:first:chamber:)` land on the
/// sitting senator: stripping a generational suffix, and ignoring a member whose last
/// term ended before the filing window.
@Suite("Senate name resolution")
struct SenateNameResolutionTests {

    static let directory = MemberDirectory(entries: [
        // Sitting senators.
        MemberDirectory.Entry(bioguideID: "M000355", last: "McConnell", first: "Mitch",
                              state: "KY", district: nil, chamber: .senate,
                              nickname: "Mitch", lastTermEndYear: 2027),
        MemberDirectory.Entry(bioguideID: "K000383", last: "King", first: "Angus",
                              state: "ME", district: nil, chamber: .senate,
                              lastTermEndYear: 2029),
        MemberDirectory.Entry(bioguideID: "K000393", last: "Kennedy", first: "John",
                              state: "LA", district: nil, chamber: .senate,
                              lastTermEndYear: 2029),
        MemberDirectory.Entry(bioguideID: "B001327", last: "Begich", first: "Nicholas",
                              state: "AK", district: nil, chamber: .senate,
                              lastTermEndYear: 2031),
        // Long-gone Senate namesakes from the historical file.
        MemberDirectory.Entry(bioguideID: "K000105", last: "Kennedy", first: "John",
                              state: "MA", district: nil, chamber: .senate,
                              lastTermEndYear: 1963),
        MemberDirectory.Entry(bioguideID: "K000106", last: "Kennedy", first: "Edward",
                              state: "MA", district: nil, chamber: .senate,
                              lastTermEndYear: 2009),
        MemberDirectory.Entry(bioguideID: "K000107", last: "King", first: "William",
                              state: "AL", district: nil, chamber: .senate,
                              lastTermEndYear: 1853),
    ])

    @Test("A ', Jr.' suffix in the surname column still resolves")
    func suffixInLast() {
        #expect(Self.directory.resolve(last: "McConnell, Jr.", first: "A. Mitchell",
                                       chamber: .senate, servingInOrAfter: 2025)
                == .resolved("M000355"))
        #expect(Self.directory.resolve(last: "King, Jr.", first: "Angus S",
                                       chamber: .senate, servingInOrAfter: 2025)
                == .resolved("K000383"))
    }

    @Test("A trailing suffix in the forename column resolves")
    func suffixSplitAcross() {
        // eFD occasionally gives "Nicholas Begich" / "III".
        #expect(Self.directory.resolve(last: "III", first: "Nicholas Begich",
                                       chamber: .senate, servingInOrAfter: 2025)
                == .resolved("B001327"))
    }

    @Test("A historical namesake is ignored once the serving-year filter is applied")
    func historicalNamesakeDropped() {
        // Three Senate Kennedys in the crosswalk; only one is serving now.
        #expect(Self.directory.resolve(last: "Kennedy", first: "John N",
                                       chamber: .senate, servingInOrAfter: 2025)
                == .resolved("K000393"))
        // Without the filter it is ambiguous — the fix is load-bearing, not cosmetic.
        if case .resolved = Self.directory.resolve(last: "Kennedy", first: "John",
                                                   chamber: .senate) {
            Issue.record("expected ambiguity without the serving-year filter")
        }
    }

    @Test("A clean current name is unaffected")
    func cleanNameStillWorks() {
        #expect(Self.directory.resolve(last: "King", first: "Angus",
                                       chamber: .senate, servingInOrAfter: 2025)
                == .resolved("K000383"))
    }
}
#endif
