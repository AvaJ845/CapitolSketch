import SwiftUI

/// Civic document palette. Navy is the accent; orange is reserved for data-quality
/// (late filings, date typos) and is never used to mean buy versus sell.
enum Ink {
    /// Icon A navy.
    static let navy = Color(red: 11 / 255, green: 31 / 255, blue: 58 / 255)
    /// Warm paper from the sketch icon.
    static let paper = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)

    /// Honesty / lag. Never buy/sell. Adaptive so it clears WCAG AA as *text* on both
    /// the paper and the dark card: a deeper rust on light, the warmer sketch orange on
    /// dark (where a deep rust would itself be too low-contrast).
    static let lag = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 240 / 255, green: 160 / 255, blue: 112 / 255, alpha: 1)
            : UIColor(red: 173 / 255, green: 74 / 255, blue: 30 / 255, alpha: 1)
    })

    /// Interactive tint — links, buttons, selection. Navy reads well on paper but is
    /// almost invisible on the dark canvas, so dark mode gets a legible civic blue that
    /// still clears WCAG AA as link text on the card.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.46, green: 0.66, blue: 0.92, alpha: 1)
            : UIColor(red: 11 / 255, green: 31 / 255, blue: 58 / 255, alpha: 1)
    })

    /// Faint tint behind chips and pull-quotes. Defined per appearance because a flat
    /// low-opacity navy vanishes on the dark canvas.
    static let chipFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 1, blue: 1, alpha: 0.10)
            : UIColor(red: 11 / 255, green: 31 / 255, blue: 58 / 255, alpha: 0.07)
    })

    static let chipStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 1, blue: 1, alpha: 0.22)
            : UIColor(red: 11 / 255, green: 31 / 255, blue: 58 / 255, alpha: 0.20)
    })

    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.065, blue: 0.085, alpha: 1)
            : UIColor(red: 244 / 255, green: 239 / 255, blue: 230 / 255, alpha: 1)
    })

    /// Card surface. On dark it is lifted well clear of the canvas so grouped sections
    /// read as distinct cards rather than a single flat field.
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1)
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
