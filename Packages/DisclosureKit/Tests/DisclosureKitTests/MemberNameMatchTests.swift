import Foundation
import Testing
@testable import DisclosureKit

@Suite("Matching a spoken name to a member")
struct MemberNameMatchTests {

    private func member(_ id: String, _ name: String) -> Member {
        Member(id: id, bioguideID: nil, name: name, state: "CA", district: "11", chamber: .house)
    }

    private var roster: [Member] {
        [
            member("P000197", "Nancy Pelosi"),
            member("K000389", "Ro Khanna"),
            member("S001193", "Adam Smith"),
            member("S001204", "Christopher Smith"),
        ]
    }

    @Test("exact name resolves")
    func exact() {
        #expect(matchMemberName("Nancy Pelosi", in: roster)?.id == "P000197")
    }

    @Test("case and surrounding whitespace are ignored")
    func caseAndWhitespace() {
        #expect(matchMemberName("  nAnCy   pelosi  ", in: roster)?.id == "P000197")
    }

    @Test("a unique prefix resolves")
    func uniquePrefix() {
        #expect(matchMemberName("Pelo", in: roster)?.id == "P000197")
        #expect(matchMemberName("ro kh", in: roster)?.id == "K000389")
    }

    @Test("an ambiguous prefix returns nil rather than guess between two people")
    func ambiguousPrefix() {
        // Two different Smiths — no honest single answer.
        #expect(matchMemberName("Smith", in: [
            member("S001193", "Smith Adam"),
            member("S001204", "Smith Chris"),
        ]) == nil)
    }

    @Test("substring fallback matches a surname mid-name")
    func substringFallback() {
        #expect(matchMemberName("pelosi", in: roster)?.id == "P000197")
        #expect(matchMemberName("khanna", in: roster)?.id == "K000389")
    }

    @Test("an ambiguous substring returns nil")
    func ambiguousSubstring() {
        #expect(matchMemberName("smith", in: roster) == nil)
    }

    @Test("no match returns nil")
    func noMatch() {
        #expect(matchMemberName("Alexandria Ocasio-Cortez", in: roster) == nil)
    }

    @Test("empty or whitespace-only query returns nil")
    func emptyQuery() {
        #expect(matchMemberName("", in: roster) == nil)
        #expect(matchMemberName("   ", in: roster) == nil)
    }

    @Test("repeated rows for the same person are not ambiguity")
    func samePersonNotAmbiguous() {
        let dupes = [
            member("P000197", "Nancy Pelosi"),
            member("P000197", "Nancy Pelosi"),
        ]
        #expect(matchMemberName("Pelosi", in: dupes)?.id == "P000197")
    }

    @Test("an exact match wins over a longer name it is a prefix of")
    func exactBeatsPrefix() {
        let r = [member("A", "Sam Rivera"), member("B", "Sam Riveras")]
        #expect(matchMemberName("Sam Rivera", in: r)?.id == "A")
    }
}
