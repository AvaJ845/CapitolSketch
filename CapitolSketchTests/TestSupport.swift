import Foundation
import DisclosureKit
@testable import CapitolSketch

// Compact builders for the app-target unit tests. The parser's own fixtures live in
// DisclosureKit; these tests exercise the presentation and navigation logic that sits
// above the model, so a hand-built `Trade` / `Member` is enough and keeps each case
// readable.

extension CalendarDate {
    /// `CalendarDate("2026-07-24")`. Traps on a malformed string — it is a test literal.
    init(_ iso: String) {
        guard let parsed = CalendarDate(iso: iso) else {
            fatalError("bad CalendarDate literal \(iso)")
        }
        self = parsed
    }
}

enum Build {
    static func amount(
        _ kind: DisclosedAmount.Kind,
        low: Int = 0,
        high: Int = 0
    ) -> DisclosedAmount {
        DisclosedAmount(
            kind: kind,
            lowCents: low,
            highCents: kind == .range ? high : low,
            label: DisclosedAmount.makeLabel(
                kind: kind, lowCents: low, highCents: kind == .range ? high : low
            )
        )
    }

    /// A range bracket in whole dollars.
    static func range(_ lowDollars: Int, _ highDollars: Int) -> DisclosedAmount {
        amount(.range, low: lowDollars * 100, high: highDollars * 100)
    }

    static func trade(
        id: String = UUID().uuidString,
        memberID: String = "M000001",
        memberName: String = "Pat Sample",
        owner: TradeOwner = .self,
        asset: String = "Acme Corp (ACME) [ST]",
        ticker: String? = "ACME",
        assetType: String? = "ST",
        type: TradeType = .buy,
        tx: CalendarDate = CalendarDate("2026-06-01"),
        disclosed: CalendarDate = CalendarDate("2026-06-20"),
        amount: DisclosedAmount = Build.range(1_001, 15_000),
        filingDescription: String? = nil,
        filingID: String = "F1",
        warnings: [String] = []
    ) -> Trade {
        Trade(
            id: id, memberID: memberID, memberName: memberName, owner: owner,
            asset: asset, ticker: ticker, assetType: assetType, txType: type,
            txDate: tx, disclosedDate: disclosed, amount: amount,
            filingDescription: filingDescription, filingID: filingID,
            documentURL: nil, warnings: warnings
        )
    }

    static func member(
        id: String = "M000001",
        bioguideID: String? = "M000001",
        name: String = "Pat Sample",
        state: String = "CA",
        district: String? = "12",
        chamber: Chamber = .house,
        committees: [String] = [],
        party: Party = .democrat
    ) -> Member {
        Member(
            id: id, bioguideID: bioguideID, name: name, state: state,
            district: district, chamber: chamber, committees: committees, party: party
        )
    }

    /// A `WatchlistStore` backed by a throwaway defaults suite, isolated per test.
    @MainActor
    static func watchlist() -> WatchlistStore {
        let suite = "test.watchlist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return WatchlistStore(defaults: defaults)
    }
}
