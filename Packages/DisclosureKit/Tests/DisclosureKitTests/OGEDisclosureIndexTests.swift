import Foundation
import Testing
@testable import DisclosureKit

@Suite("OGE disclosure index — parsing and filtering")
struct OGEDisclosureIndexTests {

    private func row(
        name: String, agency: String, title: String, type: String = "278 Transaction"
    ) -> OGEDisclosureRow {
        OGEDisclosureRow(name: name, agency: agency, title: title, type: type, docDate: nil, documentURL: URL(string: "https://x/y.pdf")!)
    }

    @Test("A department secretary is kept; an ambassador or board member at a non-Cabinet agency is not")
    func filtersToCabinetSecretaries() {
        let rows = [
            row(name: "Bondi, Pam", agency: "Department of Justice", title: "Attorney General"),
            row(name: "Hegseth, Pete", agency: "Department of Defense/Office of The Secretary", title: "Secretary"),
            row(name: "Toepfer, David", agency: "Department of Justice", title: "U.S. Attorney Ohio Northern District"),
            row(name: "Warsh, Kevin", agency: "Federal Reserve System Board of Governors", title: "Chairman and Member"),
            row(name: "Brown, Stanley", agency: "Department of State", title: "Ambassador to Guinea"),
        ]
        let filtered = OGEDisclosureIndex.cabinetDepartmentRows(in: rows)
        #expect(Set(filtered.map(\.name)) == ["Bondi, Pam", "Hegseth, Pete"])
    }

    @Test("KNOWN BUG, FIXED — a Deputy/Under/Assistant Secretary is not the department head")
    func excludesDeputyAndUnderSecretaries() {
        // Real titles observed in the OGE database — all contain the substring
        // "secretary", none of them are the department's own head. A naive `.contains`
        // match let 40 filers through where only ~19 should have qualified.
        let rows = [
            row(name: "Monaco, Lisa", agency: "Department of Justice", title: "Deputy Attorney General"),
            row(name: "Adeyemo, Wally", agency: "Department of The Treasury", title: "Deputy Secretary"),
            row(name: "MacGregor, Katharine", agency: "Department of The Interior", title: "Deputy Secretary"),
            row(name: "Someone, Under", agency: "Department of Labor", title: "Under Secretary"),
            row(name: "Someone, Assistant", agency: "Department of Energy", title: "Assistant Secretary"),
        ]
        #expect(OGEDisclosureIndex.cabinetDepartmentRows(in: rows).isEmpty)
    }

    @Test("The department's own head still matches, prefix or no trailing detail")
    func keepsTheActualSecretary() {
        let rows = [
            row(name: "Bondi, Pam", agency: "Department of Justice", title: "Attorney General, United States Department of Justice, Department of Justice -- Simple"),
            row(name: "Hegseth, Pete", agency: "Department of Defense/Office of The Secretary", title: "Secretary"),
        ]
        #expect(OGEDisclosureIndex.cabinetDepartmentRows(in: rows).count == 2)
    }

    @Test("Agency name capitalization varies across the index; matching is case-insensitive")
    func caseInsensitiveAgencyMatch() {
        let rows = [
            row(name: "Perdue, George E", agency: "Department Of Agriculture", title: "Secretary"),
            row(name: "Rollins, Brooke L", agency: "Department of Agriculture", title: "Secretary"),
        ]
        #expect(OGEDisclosureIndex.cabinetDepartmentRows(in: rows).count == 2)
    }

    @Test("A department head with a non-278-T document type is not excluded by cabinetDepartmentRows itself")
    func cabinetFilterDoesNotCareAboutDocumentType() {
        // Type filtering is `CabinetFetcher`'s job (it also requires "278 Transaction");
        // `cabinetDepartmentRows` answers only "is this person a department head."
        let rows = [row(name: "Rubio, Marco", agency: "Department of State", title: "Secretary", type: "Annual (2026)")]
        #expect(OGEDisclosureIndex.cabinetDepartmentRows(in: rows).count == 1)
    }

    @Test("A row whose type has no direct .pdf link (a 'Request this Document' placeholder) is dropped during parsing")
    func requestOnlyRowsAreExcludedAtParseTime() {
        // Exercised indirectly: fetchAllRows' own compactMap requires a `href='...pdf'`
        // match, which a "Request this Document" link (…OpenForm&Filer=X, no .pdf) fails.
        // This test pins the regex itself against both real shapes observed.
        let directLink = "<a href='https://extapps2.oge.gov/201/Presiden.nsf/PAS+Index/ABC/$FILE/Name-278T.pdf'>278 Transaction</a>"
        let requestOnly = "278 Transaction (<a href='https://extapps2.oge.gov/201/Presiden.nsf/201%20Request?OpenForm&Filer=Name'>Request this Document</a>)"
        let regex = try! NSRegularExpression(pattern: #"href='([^']+\.pdf)'>([^<]+)</a>"#)
        #expect(regex.firstMatch(in: directLink, range: directLink.nsRange) != nil)
        #expect(regex.firstMatch(in: requestOnly, range: requestOnly.nsRange) == nil)
    }
}
