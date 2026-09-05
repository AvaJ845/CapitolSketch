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

    /// Disclosure-lag facts for the "About the data" screen: the spread between when a
    /// transaction happened and when it was disclosed, across every row that carries a
    /// usable pair of dates. Rows with an impossible date (transaction after filing) are
    /// left out — their lag is not a real number — and counted separately by the caller.
    ///
    /// These are plain descriptive statistics of the loaded feed. No score, no grade,
    /// nothing is called good or bad.
    var disclosureLagStats: DisclosureLagStats {
        let lags = compactMap { $0.hasImpossibleDate ? nil : $0.disclosureLagDays }
            .sorted()
        return DisclosureLagStats(sortedLags: lags)
    }
}

/// Median / mean / bucket breakdown of disclosure lag in days. Value type so it is
/// testable without a view.
public struct DisclosureLagStats: Sendable, Equatable {

    public struct Bucket: Sendable, Equatable, Identifiable {
        public let label: String
        public let count: Int
        public var id: String { label }
    }

    /// Rows that contributed a usable lag.
    public let count: Int
    public let medianDays: Int
    public let meanDays: Int
    /// The STOCK Act allows 45 days. Rows past that.
    public let overFortyFiveCount: Int
    public let buckets: [Bucket]

    /// Share of `count` that came in over the 45-day limit, 0–100.
    public var overFortyFivePercent: Int {
        guard count > 0 else { return 0 }
        return Int((Double(overFortyFiveCount) / Double(count) * 100).rounded())
    }

    /// - Parameter sortedLags: lag in days, ascending.
    public init(sortedLags lags: [Int]) {
        count = lags.count
        guard !lags.isEmpty else {
            medianDays = 0
            meanDays = 0
            overFortyFiveCount = 0
            buckets = Self.emptyBuckets
            return
        }
        let mid = lags.count / 2
        medianDays = lags.count.isMultiple(of: 2)
            ? Int((Double(lags[mid - 1] + lags[mid]) / 2).rounded())
            : lags[mid]
        meanDays = Int((Double(lags.reduce(0, +)) / Double(lags.count)).rounded())
        overFortyFiveCount = lags.filter { $0 > 45 }.count
        buckets = [
            Bucket(label: "7 days or fewer", count: lags.filter { $0 <= 7 }.count),
            Bucket(label: "8 to 30 days", count: lags.filter { $0 >= 8 && $0 <= 30 }.count),
            Bucket(label: "31 to 45 days", count: lags.filter { $0 >= 31 && $0 <= 45 }.count),
            Bucket(label: "46 to 90 days", count: lags.filter { $0 >= 46 && $0 <= 90 }.count),
            Bucket(label: "More than 90 days", count: lags.filter { $0 > 90 }.count),
        ]
    }

    private static let emptyBuckets: [Bucket] = [
        "7 days or fewer", "8 to 30 days", "31 to 45 days", "46 to 90 days", "More than 90 days",
    ].map { Bucket(label: $0, count: 0) }
}
