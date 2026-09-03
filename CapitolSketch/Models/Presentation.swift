import Foundation
import DisclosureKit

// How the parsed record is worded on screen. The model itself carries no presentation,
// so every string a reader sees is defined once, here, and can be audited in one place.

extension DisclosedAmount {

    /// The amount as a single phrase, worded the way the form words it.
    ///
    /// The three shapes are genuinely different facts and are never collapsed into one
    /// number: a bracket is a bracket, an open-ended top bracket has no upper bound at
    /// all, and the rare exact figure is exact to the cent.
    var headline: String {
        switch kind {
        case .range: return "\(lowLabel) – \(highLabel)"
        // The form prints the top bracket as words, not as a numeric range with a
        // fabricated ceiling. There is no such thing as a `$50,000,001 +` filing here.
        case .atLeast: return "Over \(lowLabel)"
        case .exact: return lowLabel
        case .none: return Self.noneDisclosed.label
        case .unknown: return "Amount unreadable"
        }
    }

    /// What kind of number this is, said out loud, so the reader is never left to assume
    /// a bracket is a price.
    var kindCaption: String {
        switch kind {
        case .range: return "Disclosed range"
        case .atLeast: return "Open-ended bracket"
        case .exact: return "Exact amount"
        case .none: return "Below the reporting threshold"
        case .unknown: return "Not readable on the filing"
        }
    }

    /// Spoken form. VoiceOver should not read a dash as a hyphen in "1,001–15,000".
    var accessibleDescription: String {
        switch kind {
        case .range: return "Disclosed range, \(lowLabel) to \(highLabel)"
        case .atLeast: return "Open-ended bracket, over \(lowLabel)"
        case .exact: return "Exact amount, \(lowLabel)"
        case .none: return "None, or less than $201"
        case .unknown: return "Amount could not be read from the filing"
        }
    }
}

extension TradeType {
    /// Spoken direction for VoiceOver: `↑ Bought` / `↓ Sold`. The word carries the
    /// meaning; colour never does.
    var directionPhrase: String { directionLabel }
}

extension Trade {
    /// House asset-type codes, spelled out. The bare code is still shown next to it,
    /// because the code is what the filing says.
    var assetTypeName: String? {
        guard let assetType else { return nil }
        return Self.assetTypeNames[assetType]
    }

    static let assetTypeNames: [String: String] = [
        "ST": "Stock", "OP": "Option", "MF": "Mutual fund", "EF": "Exchange-traded fund",
        "GS": "Government security", "CS": "Corporate security", "AB": "Asset-backed",
        "OT": "Other", "CT": "Cryptocurrency", "HN": "Hedge fund", "OI": "Ownership interest",
        "PS": "Stock (private)", "RP": "Real property", "SA": "Stock appreciation right",
        "CO": "Collectible", "FA": "Farm", "IH": "Inheritance", "IR": "IRA",
        "TR": "Trust", "VA": "Variable annuity", "WU": "Whole life insurance",
    ]

    /// The two dates as one honest sentence. The gap is the point of the whole app, so
    /// it is stated in words rather than left for the reader to subtract.
    var timingSentence: String {
        "Traded \(txDate.mediumLabel) · \(disclosureGapPhrase)"
    }

    var accessibleSummary: String {
        var parts = [
            memberName,
            owner == .self ? "own account" : "\(owner.label) account",
            txType.verb,
            cleanAssetName,
        ]
        if let ticker { parts.append("ticker \(ticker)") }
        if let name = assetTypeName { parts.append(name) }
        parts.append(amount.accessibleDescription)
        parts.append("traded \(txDate.mediumLabel)")
        parts.append(hasImpossibleDate
            ? "the filing's dates are inconsistent and are shown as filed"
            : disclosureGapPhrase)
        return parts.joined(separator: ", ")
    }
}

extension CalendarDate {
    /// `24 Jul 2026`, formatted from the calendar fields so no time zone can shift it.
    var mediumLabel: String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let name = (1...12).contains(month) ? months[month - 1] : "\(month)"
        return "\(name) \(day), \(year)"
    }

}

