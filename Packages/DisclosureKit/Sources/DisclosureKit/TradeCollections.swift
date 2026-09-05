import Foundation

/// Derived views over a set of trades that both the app and the build-time tools can
/// share, so a grouping or a statistic is computed one way everywhere.
public extension Sequence where Element == Trade {

    /// Every transaction row belonging to one filing (one Periodic Transaction Report).
    ///
    /// The filing — not the row — is the real civic unit: a member submits one PTR
    /// listing several transactions. This is a plain grouping of data already in the
    /// model; nothing is added or interpreted.
    func inFiling(_ filingID: String) -> [Trade] {
        filter { $0.filingID == filingID }
    }
}
