import Foundation
import CoreSpotlight
import DisclosureKit

/// Makes members and frequently-traded tickers findable from the system Spotlight
/// search, and turns a tap on one of those results into an in-app route.
///
/// **On-device only.** `CSSearchableItem` indexes locally by default — nothing here
/// opts into public or CloudKit indexing — and every field written is already public
/// in the bundled feed (a member's name and seat, a ticker and how often it was
/// disclosed). The watchlist and the follow list take no part in this: the index is
/// the same for every reader, exactly like the feed itself.
enum SpotlightIndex {

    static let memberDomain = "members"
    static let tickerDomain = "tickers"
    private static let memberPrefix = "member:"
    private static let tickerPrefix = "ticker:"
    /// Records the snapshot the index was last built from, so a relaunch on the same
    /// data does no work.
    private static let stampKey = "spotlightIndexedSnapshot"
    /// A ticker earns an entry once at least this many disclosures name it — a lone
    /// mention is noise in a search result list.
    private static let minTickerDisclosures = 3
    private static let maxTickers = 400

    /// Rebuilds the index when the snapshot has changed. Cheap and idempotent otherwise.
    static func rebuild(
        members: [Member],
        tickers: [(ticker: String, count: Int)],
        snapshotDate: Date
    ) async {
        guard CSSearchableIndex.isIndexingAvailable(), snapshotDate != .distantPast else { return }
        let stamp = ISO8601DateFormatter().string(from: snapshotDate)
        guard SharedContainer.defaults.string(forKey: stampKey) != stamp else { return }

        var items: [CSSearchableItem] = []
        items.reserveCapacity(members.count + maxTickers)

        for member in members {
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = member.name
            let seat = "\(member.chamber.label) · \(member.seat)"
            attributes.contentDescription = member.party == .unknown
                ? "\(seat) · disclosed trades"
                : "\(member.party.label) · \(seat) · disclosed trades"
            attributes.keywords =
                [member.name, member.state, member.chamber.label, "Congress", "disclosure"]
                + member.committees
            items.append(CSSearchableItem(
                uniqueIdentifier: memberPrefix + member.id,
                domainIdentifier: memberDomain,
                attributeSet: attributes
            ))
        }

        for entry in tickers where entry.count >= minTickerDisclosures {
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = entry.ticker
            attributes.contentDescription =
                "\(entry.count) disclosed transaction\(entry.count == 1 ? "" : "s") in the loaded filings"
            attributes.keywords = [entry.ticker, "ticker", "stock", "Congress"]
            items.append(CSSearchableItem(
                uniqueIdentifier: tickerPrefix + entry.ticker,
                domainIdentifier: tickerDomain,
                attributeSet: attributes
            ))
            if items.count >= members.count + maxTickers { break }
        }

        let index = CSSearchableIndex.default()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                index.deleteSearchableItems(withDomainIdentifiers: [memberDomain, tickerDomain]) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                index.indexSearchableItems(items) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            SharedContainer.defaults.set(stamp, forKey: stampKey)
            #if DEBUG
            print("[Spotlight] indexed \(items.count) items "
                  + "(\(members.count) members) for snapshot \(stamp)")
            #endif
        } catch {
            #if DEBUG
            print("[Spotlight] index rebuild failed: \(error)")
            #endif
        }
    }

    /// Where a tapped Spotlight result should land.
    enum Route: Equatable {
        case member(id: String)
        case ticker(String)
    }

    /// Reads the route out of the continuation activity a Spotlight tap hands the app.
    /// Returns `nil` for anything that is not one of ours, so a crafted activity routes
    /// nowhere.
    static func route(for activity: NSUserActivity) -> Route? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }
        if identifier.hasPrefix(memberPrefix) {
            let id = String(identifier.dropFirst(memberPrefix.count))
            return id.isEmpty ? nil : .member(id: id)
        }
        if identifier.hasPrefix(tickerPrefix) {
            let symbol = String(identifier.dropFirst(tickerPrefix.count))
            return symbol.isEmpty ? nil : .ticker(symbol)
        }
        return nil
    }
}
