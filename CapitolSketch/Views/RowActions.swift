import SwiftUI
import DisclosureKit

/// Swipe actions for a disclosure row: watch the ticker (trailing) or follow the member
/// (leading), whichever the row has.
///
/// This only toggles a device-local alert preference — the same thing the buttons on the
/// detail screen do. It never changes what the reader sees: the row, and the filing it
/// opens, are the same public record for everyone. Both edges use the plain navy tint,
/// never a green/red "positive/negative" colour.
extension View {
    @ViewBuilder
    func disclosureRowActions(
        for trade: Trade,
        store: TradeStore,
        watchlist: WatchlistStore
    ) -> some View {
        self
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let ticker = trade.ticker {
                    Button {
                        watchlist.toggle(ticker, markingSeenIn: store.trades)
                    } label: {
                        Label(
                            watchlist.contains(ticker) ? "Unwatch \(ticker)" : "Watch \(ticker)",
                            systemImage: watchlist.contains(ticker) ? "bell.slash" : "bell"
                        )
                    }
                    .tint(Ink.accent)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if let member = store.member(id: trade.memberID) {
                    Button {
                        watchlist.toggleFollow(member.id, markingSeenIn: store.trades)
                    } label: {
                        Label(
                            watchlist.isFollowing(member.id) ? "Unfollow" : "Follow",
                            systemImage: watchlist.isFollowing(member.id) ? "bell.slash" : "bell.badge"
                        )
                    }
                    .tint(Ink.accent)
                }
            }
    }
}
