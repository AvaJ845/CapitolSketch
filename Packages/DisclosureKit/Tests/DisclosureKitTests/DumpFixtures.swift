import Foundation
import Testing
@testable import DisclosureKit

/// Not an assertion — a development aid that prints what the parser sees, so expected
/// values can be checked against the source PDFs by hand.
@Suite(.disabled("development aid; enable manually when adding a fixture"))
struct DumpFixtures {
    @Test func dumpAll() {
        for f in Fixture.allCases {
            let r = f.parse()
            print("\n════ \(f.rawValue)  readable=\(r.hadReadableText)  rows=\(r.trades.count)")
            if !r.warnings.isEmpty { print("  file warnings: \(r.warnings)") }
            for t in r.trades {
                print("  [\(t.id)] \(t.signature)")
                print("       asset: \(t.asset)")
                if let d = t.filingDescription { print("       desc : \(d)") }
                if !t.warnings.isEmpty { print("       WARN : \(t.warnings)") }
            }
        }
    }
}
