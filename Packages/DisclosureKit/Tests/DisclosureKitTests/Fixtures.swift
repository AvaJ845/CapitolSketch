import Foundation
import Testing
@testable import DisclosureKit

/// Real filings checked into the repo, so parser behaviour is pinned to primary sources
/// rather than to whatever the parser happened to produce on the day it was written.
enum Fixture: String, CaseIterable {
    case pelosiMultiAsset = "pelosi-multi-asset.2026.20035143"
    case pelosiPageBreak = "pelosi-pagebreak-exact.2026.20033725"
    case cohenImpossibleDate = "cohen-impossible-date.2026.20033889"
    case petersOverThreshold = "peters-over-threshold.2026.20035191"
    case issaLargeBracket = "issa-25m-bracket.2025.20030181"
    case cisnerosAmended = "cisneros-amended-multipage.2025.20031022"
    case rouzerAmended = "rouzer-amended.2026.20033759"
    case millerExactCents = "miller-exact-cents.2025.20030236"
    case scannedNoText = "scanned-no-text.2025.8220731"
    case bresnahanMultipage = "bresnahan-multipage.2025.20024346"

    var docID: String { rawValue.components(separatedBy: ".")[2] }
    var year: Int { Int(rawValue.components(separatedBy: ".")[1]) ?? 0 }

    var url: URL {
        guard let u = Bundle.module.url(
            forResource: rawValue, withExtension: "pdf", subdirectory: "Fixtures"
        ) else {
            fatalError("missing fixture \(rawValue).pdf")
        }
        return u
    }

    /// A filing reference standing in for the index row that would accompany the PDF.
    func ref(filedOn: CalendarDate? = nil) -> FilingRef {
        FilingRef(
            docID: docID, year: year, memberName: "Fixture Member",
            memberID: "x-fixture", filedOn: filedOn
        )
    }

    func parse(filedOn: CalendarDate? = nil) -> ParseResult {
        PTRParser.parse(pdfAt: url, filing: ref(filedOn: filedOn))
    }
}

/// Wraps a hand-built array of trades in a `TradeFeed` so rules that take a whole feed
/// can be exercised without parsing a PDF. Members are synthesised from the distinct
/// `memberID`s present.
func makeFeed(_ trades: [Trade]) -> TradeFeed {
    let members = Set(trades.map(\.memberID)).sorted().map {
        Member(id: $0, bioguideID: $0, name: $0, state: "CA", district: "1", chamber: .house)
    }
    return TradeFeed(
        generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
        indexYears: [2026], source: "test",
        members: members, trades: trades,
        stats: ParseStats(filingsProcessed: 1, tradesParsed: trades.count)
    )
}

extension Trade {
    /// Compact form used in assertions: what a human would read off the form.
    var signature: String {
        [
            ticker ?? "—",
            assetType ?? "—",
            owner.rawValue,
            txType.rawValue,
            txDate.iso,
            amount.kind.rawValue,
            amount.label,
        ].joined(separator: " | ")
    }
}
