import SwiftUI

/// Civic document palette. Navy is the accent; orange is reserved for data-quality
/// (late filings, date typos) and is never used to mean buy versus sell.
enum Ink {
    /// Icon A navy.
    static let navy = Color(red: 11 / 255, green: 31 / 255, blue: 58 / 255)
    /// Warm paper from the sketch icon.
    static let paper = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    /// Honesty / lag. Never buy/sell.
    static let lag = Color(red: 224 / 255, green: 122 / 255, blue: 61 / 255)

    static let accent = navy

    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
            : UIColor(red: 244 / 255, green: 239 / 255, blue: 230 / 255, alpha: 1)
    })

    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1)
            : UIColor.white
    })

    static let hairline = Color.primary.opacity(0.10)

    /// Filled direction badge (Bought).
    static let badgeFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 244 / 255, green: 239 / 255, blue: 230 / 255, alpha: 1)
            : UIColor(red: 11 / 255, green: 31 / 255, blue: 58 / 255, alpha: 1)
    })

    static let badgeOnFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 11 / 255, green: 31 / 255, blue: 58 / 255, alpha: 1)
            : UIColor.white
    })
}

extension View {
    /// Paper canvas, navy tint, inset grouped lists.
    func gazetteChrome() -> some View {
        self
            .tint(Ink.accent)
            .scrollContentBackground(.hidden)
            .background(Ink.canvas)
    }

    func disclosureRowChrome() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
            .listRowBackground(Ink.card)
            .listRowSeparatorTint(Ink.hairline)
            .navigationLinkIndicatorVisibility(.hidden)
    }
}
