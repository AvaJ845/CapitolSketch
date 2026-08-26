import DisclosureKit

extension TradeType {
    /// Unicode arrow. Colour is never used to mean buy or sell.
    var arrowGlyph: String {
        switch self {
        case .buy: return "↑"
        case .sell, .partialSell: return "↓"
        case .exchange: return "↔"
        }
    }

    /// `↑ Bought` / `↓ Sold`. The word is the meaning; the arrow repeats it.
    var directionLabel: String { "\(arrowGlyph) \(verb)" }
}
