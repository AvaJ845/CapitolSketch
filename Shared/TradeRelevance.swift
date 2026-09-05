import DisclosureKit

extension Trade {
    /// Whether this public disclosure is one the reader has locally asked to be told
    /// about: its ticker is on the watchlist, **or** the member who filed it is followed.
    ///
    /// This is the single place the "which filings are relevant to this reader" test
    /// lives, shared by the app (`WatchlistStore`, `TradeStore`, the alert scan) and the
    /// widget entry builder. It only decides *when to surface* a record. It never changes
    /// the record: every field handed on is the same public filing every other reader
    /// sees. Both inputs are device-local and neither reaches any network call.
    ///
    /// `watchedTickers` is expected already upper-cased.
    func isWatchlistRelevant(watchedTickers: Set<String>, followedMembers: Set<String>) -> Bool {
        if let symbol = ticker?.uppercased(), watchedTickers.contains(symbol) { return true }
        return followedMembers.contains(memberID)
    }
}
