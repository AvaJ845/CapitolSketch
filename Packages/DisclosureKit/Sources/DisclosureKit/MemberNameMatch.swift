import Foundation

/// Resolves a free-text name — the phrase a reader speaks to Siri or types into a
/// Shortcut — to exactly one `Member` of the loaded feed.
///
/// The tiers run most-to-least specific: an exact name, then a name that starts with
/// the query, then a name that merely contains it. Matching is case- and
/// whitespace-insensitive.
///
/// Ambiguity is reported, never guessed. If a tier matches more than one distinct
/// person the function returns `nil` rather than pick one — the same contract
/// `MemberDirectory.resolve` follows. The caller (`FollowMemberIntent`) then asks the
/// reader to be more specific instead of silently following the wrong member. Repeated
/// entries for the *same* person (same `id`) do not count as ambiguity.
///
/// - Returns: the single matching member, or `nil` for an empty query, no match, or an
///   ambiguous one.
public func matchMemberName(_ query: String, in members: [Member]) -> Member? {
    let q = normalizeForMatch(query)
    guard !q.isEmpty else { return nil }

    let indexed = members.map { (member: $0, name: normalizeForMatch($0.name)) }

    for tier: (String) -> Bool in [
        { $0 == q },
        { $0.hasPrefix(q) },
        { $0.contains(q) },
    ] {
        let hits = indexed.filter { tier($0.name) }
        let distinct = Set(hits.map(\.member.id))
        if distinct.count == 1 { return hits.first?.member }
        if distinct.count > 1 { return nil } // ambiguous — do not guess
    }
    return nil
}

/// Lower-cased, edge-trimmed, and with every internal run of whitespace collapsed to a
/// single space — so "  nAnCy   pelosi " and "Nancy Pelosi" compare equal.
private func normalizeForMatch(_ s: String) -> String {
    s.lowercased()
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}
