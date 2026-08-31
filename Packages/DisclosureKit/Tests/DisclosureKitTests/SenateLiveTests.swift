import Foundation
@testable import DisclosureKit
import Testing

/// Hits efdsearch.senate.gov for real. Disabled in the normal run — it is slow (the
/// politeness delays), needs network, and depends on a government service being up. Run
/// it by hand (`swift test --filter "eFD is reachable"`) before a seed regeneration to
/// confirm the handshake still works and Akamai isn't blocking this machine.
@Suite("Senate eFD — live", .disabled("network; run manually before regenerating the seed"))
struct SenateLiveTests {

    @Test("eFD is reachable: handshake, pagination, and both filing types come back")
    func reachable() async throws {
        let since = CalendarDate(year: CalendarDate.today().year, month: 1, day: 1)
        let rows = try await SenateFilingIndex.fetchPTRs(since: since)
        #expect(rows.count > 20)
        #expect(rows.contains { !$0.isPaper })
        #expect(rows.allSatisfy { $0.uuid.count == 36 && $0.filedOn != nil })
    }
}
