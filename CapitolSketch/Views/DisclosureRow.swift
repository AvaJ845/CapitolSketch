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
        VStack(alignment: .leading, spacing: isAX ? 10 : 8) {
            identity
            assetName
            attribution
            AmountView(amount: trade.amount, showsKindCaption: isAX)
            timing
            flags
        }
        .padding(.vertical, isAX ? 6 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trade.accessibleSummary)
    }

    @ViewBuilder
    private var identity: some View {
        if isAX {
            VStack(alignment: .leading, spacing: 8) {
                DirectionBadge(type: trade.txType)
                symbolAndCode
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                DirectionBadge(type: trade.txType)
                symbolAndCode
                Spacer(minLength: 0)
            }
        }
    }

    private var symbolAndCode: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(trade.displaySymbol)
                .font(.body.weight(.semibold).monospaced())
                .foregroundStyle(.primary)
                .lineLimit(isAX ? nil : 1)

            if let code = trade.assetType {
                Text(code)
                    .font(.caption2.weight(.semibold).monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(trade.assetTypeName ?? code)
            }
        }
    }

    private var assetName: some View {
        Text(trade.cleanAssetName)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(isAX ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Owner is body weight, not a muted chip. Whose account traded is part of the fact.
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

    private var timing: some View {
        Text(trade.timingSentence)
            .font(.caption)
            .foregroundStyle(trade.hasImpossibleDate ? Ink.lag : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var flags: some View {
        let items = flagItems
        if !items.isEmpty {
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
            out.append(("Filed late", "clock.badge.exclamationmark", Ink.lag))
        }
        if trade.hasImpossibleDate {
            out.append(("Date as filed", "exclamationmark.triangle", Ink.lag))
        }
        return out
    }
}

/// `↑ Bought` / `↓ Sold`.
///
/// Deliberately not green/red. Bought is a filled navy capsule; Sold is an outline of
/// the same ink. Colour still carries no P&L meaning — fill versus stroke is the
/// distinction, and the word plus arrow each carry the whole meaning on their own.
struct DirectionBadge: View {
    let type: TradeType
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isFilled: Bool { type == .buy }

    var body: some View {
        Text(type.directionLabel)
            .font(typeSize.isAccessibilitySize ? .body.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isFilled ? Ink.badgeOnFill : Ink.badgeFill)
            .background(isFilled ? Ink.badgeFill : Color.clear, in: Capsule())
            .overlay {
                if !isFilled {
                    Capsule().strokeBorder(Ink.badgeFill, lineWidth: 1.2)
                }
            }
            .accessibilityLabel(type.directionPhrase)
    }
}

/// Chips that wrap onto as many lines as they need.
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
