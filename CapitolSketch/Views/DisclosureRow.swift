import SwiftUI
import DisclosureKit

/// One disclosed transaction, showing all nine fields the filing states.
///
/// Laid out for AX5 first and condensed from there. Designing the dense case first and
/// scaling it up is how finance apps end up shipping truncated tickers and clipped
/// amounts at large text sizes, because the compact layout's assumptions — that a label
/// and its value fit on one line — stop holding and there is nowhere left to go. Here the
/// accessibility layout is the real one: every field is its own line, nothing truncates,
/// and the compact layout is the same order of fields with a few pairs allowed back onto
/// shared lines once there is provably room.
struct DisclosureRow: View {
    let trade: Trade
    /// Member-scoped lists already name the member in the title.
    var showsMember = true

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: isAX ? 10 : 6) {
            identity
            assetName
            attribution
            AmountView(amount: trade.amount, showsKindCaption: isAX)
            timing
            flags
        }
        .padding(.vertical, isAX ? 6 : 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Nine fields would otherwise be nine VoiceOver stops per row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trade.accessibleSummary)
    }

    // MARK: - Direction, ticker, asset-type code

    /// At AX5 these stack; below it they share a line only because the ticker and the
    /// two-letter code are both short by construction.
    @ViewBuilder
    private var identity: some View {
        if isAX {
            VStack(alignment: .leading, spacing: 8) {
                DirectionBadge(type: trade.txType)
                symbolAndCode
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DirectionBadge(type: trade.txType)
                symbolAndCode
                Spacer(minLength: 0)
            }
        }
    }

    private var symbolAndCode: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(trade.displaySymbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(isAX ? nil : 1)

            if let code = trade.assetType {
                // The bare code is what the filing prints, so it is shown as printed.
                Text(code)
                    .font(.caption2.weight(.semibold).monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(trade.assetTypeName ?? code)
            }
        }
    }

    // MARK: - Asset

    private var assetName: some View {
        Text(trade.cleanAssetName)
            .font(.subheadline)
            .foregroundStyle(.primary)
            // Asset names on the form run long and carry the meaning. At accessibility
            // sizes nothing is clipped; below it two lines are allowed before eliding.
            .lineLimit(isAX ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Member and owner

    /// Owner is body weight, not a muted chip. Whose account traded is part of the fact,
    /// and greying it out would quietly editorialise: a large share of the best-known
    /// trades in this data are spouse-owned.
    @ViewBuilder
    private var attribution: some View {
        let owner = Text(trade.owner.label).font(.subheadline).foregroundStyle(.primary)

        if isAX {
            VStack(alignment: .leading, spacing: 4) {
                if showsMember {
                    Text(trade.memberName).font(.subheadline.weight(.medium))
                }
                owner
            }
        } else if showsMember {
            HStack(spacing: 5) {
                Text(trade.memberName).font(.subheadline.weight(.medium))
                Text("·").foregroundStyle(.tertiary)
                owner
            }
            .lineLimit(1)
        } else {
            owner
        }
    }

    // MARK: - Dates

    /// Both dates and the gap between them, in words. Subtracting two dates is work the
    /// reader should not have to do to notice that a trade is two months old.
    private var timing: some View {
        Text(trade.timingSentence)
            .font(.caption)
            .foregroundStyle(trade.hasImpossibleDate ? .orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Flags

    @ViewBuilder
    private var flags: some View {
        let items = flagItems
        if !items.isEmpty {
            // At AX5 chips cannot sit side by side, so they wrap down the page.
            FlowRow(spacing: 6) {
                ForEach(items, id: \.text) { flag in
                    TagChip(text: flag.text, systemImage: flag.symbol, tint: flag.tint)
                }
            }
        }
    }

    private var flagItems: [(text: String, symbol: String, tint: Color)] {
        var out: [(String, String, Color)] = []
        if trade.isOption {
            out.append(("Option", "function", .secondary))
        }
        if trade.isLateFiling {
            out.append(("Filed late", "clock.badge.exclamationmark", .orange))
        }
        if trade.hasImpossibleDate {
            // A real filer typo. Being faithful to the form is the correct behaviour, so
            // the value stands and the flag explains it.
            out.append(("Date as filed", "exclamationmark.triangle", .orange))
        }
        return out
    }
}

/// `↑ Bought` / `↓ Sold`.
///
/// Deliberately monochrome. Green means gain and red means loss everywhere else on the
/// reader's phone, and buying is not a gain — it is a direction. The arrow and the word
/// each carry the whole meaning independently, so the badge still reads correctly under
/// Increase Contrast, Smart Invert, Reduce Transparency and for a reader who cannot
/// separate red from green at all. Colour is left to do nothing here rather than given a
/// hue that would have to mean something.
struct DirectionBadge: View {
    let type: TradeType

    var body: some View {
        Text(type.directionLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: Capsule())
            .foregroundStyle(.primary)
            .accessibilityLabel(type.directionPhrase)
    }
}

/// Chips that wrap onto as many lines as they need.
///
/// `HStack` would push them off the edge at accessibility sizes, and a `ScrollView` would
/// hide them behind a gesture nobody knows to make.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
