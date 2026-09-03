import Foundation

/// How a transaction is identified, independent of where it sat in its filing.
///
/// The old identifier was the row's position: `"\(docID)-3"`. That made every id after
/// a change fragile — a parser fix that added, dropped or reordered one row in a filing
/// renumbered every row below it. `seenRowIDs` and the watchlist notification
/// identifiers are built on this id, so a renumber silently re-alerted a reader about
/// disclosures they had already been shown.
///
/// Keying on the fields that actually define the transaction removes that: fixing how
/// row 3 parses leaves rows 4+ with the ids they already had.

/// The content of a transaction, as a string — the same fields `deduplicate` compares,
/// minus the member (constant within one filing). Two rows that are "the same
/// disclosure" produce the same fingerprint, and de-duplication then keeps one.
func transactionFingerprint(_ t: Trade) -> String {
    [
        t.ticker ?? t.asset,
        t.assetType ?? "",
        t.txType.rawValue,
        t.txDate.iso,
        String(t.amount.lowCents),
        String(t.amount.highCents),
        t.owner.rawValue,
    ].joined(separator: "|")
}

/// Replaces each trade's provisional id with a `filingID`-scoped, content-derived one.
///
/// A filing that lists the same transaction twice — which happens — would collide; the
/// duplicates get a deterministic `-2`, `-3` suffix in parse order, and de-duplication
/// drops them downstream regardless.
func withStableIDs(_ trades: [Trade], filingID: String) -> [Trade] {
    var counts: [String: Int] = [:]
    return trades.map { trade in
        let base = "\(filingID)-\(fnv1a64Hex(transactionFingerprint(trade)))"
        let seen = counts[base, default: 0]
        counts[base] = seen + 1
        return trade.withID(seen == 0 ? base : "\(base)-\(seen + 1)")
    }
}

/// FNV-1a, 64-bit, as 16 lowercase hex digits. Deterministic across processes and
/// platforms — `Swift.Hasher` is seeded randomly per run and cannot be used for an id
/// that has to survive being written to disk and compared on a later launch.
func fnv1a64Hex(_ string: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return String(format: "%016llx", hash)
}
