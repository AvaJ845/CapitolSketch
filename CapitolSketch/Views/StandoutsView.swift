import SwiftUI
import DisclosureKit

/// Navigation route to the Standouts screen.
struct StandoutsRoute: Hashable {}

/// Factual superlatives over the loaded snapshot — the biggest brackets, the latest
/// filings, the most widely held, and a few other edges.
///
/// Nothing here is scored, ranked "overall", or recommended. Each section is its own
/// short list, ordered only by the fact that put a row on it, and every row names that
/// fact in plain language. The lists are identical for every reader: the watchlist and
/// the followed-members list take no part.
struct StandoutsView: View {
    @Environment(TradeStore.self) private var store

    /// Section render order. `widelyHeld` is drawn from `store.widelyHeld`; the rest from
    /// `store.standouts`.
    private enum Row: CaseIterable {
        case topBracket, filedLate, widelyHeld, newPosition, offPattern, rareTrader, memberLargest

        var title: String {
            switch self {
            case .topBracket: return "Largest brackets"
            case .filedLate: return "Filed latest"
            case .widelyHeld: return "Traded by the most members"
            case .newPosition: return "New positions"
            case .offPattern: return "Off pattern"
            case .rareTrader: return "Rare traders"
            case .memberLargest: return "Each member's largest"
            }
        }

        var footer: String {
            switch self {
            case .topBracket:
                return "Trades placed in the form's highest dollar brackets. The bracket is the only figure disclosed."
            case .filedLate:
                return "Disclosed more than 45 days after the trade — the STOCK Act's limit. Longest gap first."
            case .widelyHeld:
                return "Tickers in the most members' filings this snapshot — a count of filers, not shares or dollars."
            case .newPosition:
                return "A member's first disclosed trade in this ticker, disclosed in the last 30 days of this snapshot."
            case .offPattern:
                return "A single-stock trade by a member whose disclosed history is mostly funds."
            case .rareTrader:
                return "Every disclosed trade by a member who has disclosed three or fewer."
            case .memberLargest:
                return "The single largest bracket each member disclosed."
            }
        }

        var category: Standout.Category? {
            switch self {
            case .topBracket: return .topBracket
            case .filedLate: return .filedLate
            case .newPosition: return .newPosition
            case .offPattern: return .offPattern
            case .rareTrader: return .rareTrader
            case .memberLargest: return .memberLargest
            case .widelyHeld: return nil
            }
        }

        /// Most rules cap at 10; the two one-row-per-member rules can afford 15.
        var cap: Int { (self == .memberLargest || self == .rareTrader) ? 15 : 10 }
    }

    private func standouts(for row: Row) -> [Standout] {
        guard let category = row.category else { return [] }
        return store.standouts[category] ?? []
    }

    private var isEmpty: Bool {
        store.widelyHeld.isEmpty && Row.allCases.allSatisfy { standouts(for: $0).isEmpty }
    }

    var body: some View {
        Group {
            if store.standoutsLoading {
                ProgressView("Reading the snapshot…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                EmptyStateView(
                    icon: "text.magnifyingglass",
                    title: "Nothing stands out yet",
                    message: "The snapshot is too small."
                )
            } else {
                list
            }
        }
        .navigationTitle("Standouts")
        .navigationBarTitleDisplayMode(.inline)
    }

    #if DEBUG
    /// Screenshot QA only: `-qa-standouts-anchor=filedLate` scrolls to that section on
    /// appear, since the simulator cannot be scrolled from the command line.
    private var qaAnchor: String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("-qa-standouts-anchor=") }?
            .replacingOccurrences(of: "-qa-standouts-anchor=", with: "")
    }
    #endif

    private var list: some View {
        ScrollViewReader { proxy in
            listBody
            #if DEBUG
                .onAppear {
                    guard let qaAnchor,
                          let row = StandoutsView.Row.allCases.first(where: { "\($0)" == qaAnchor })
                    else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation { proxy.scrollTo(row, anchor: .top) }
                    }
                }
            #endif
        }
    }

    private var listBody: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The edges of this snapshot — the biggest brackets, the latest "
                         + "filings, the most widely held. Nothing here is ranked better "
                         + "or worse.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Copy.noAdvice)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .combine)
            }

            ForEach(Row.allCases, id: \.self) { row in
                section(for: row)
                    .id(row)
            }
        }
        .listStyle(.insetGrouped)
        .gazetteChrome()
    }

    @ViewBuilder
    private func section(for row: Row) -> some View {
        if row == .widelyHeld {
            if !store.widelyHeld.isEmpty {
                let shown = Array(store.widelyHeld.prefix(row.cap))
                Section {
                    ForEach(shown) { item in
                        NavigationLink {
                            TickerDetailView(ticker: item.ticker)
                        } label: {
                            WidelyHeldRow(item: item)
                        }
                        .disclosureRowChrome()
                    }
                    MoreRow(remaining: store.widelyHeld.count - shown.count)
                } header: {
                    Text(row.title)
                } footer: {
                    Text(row.footer)
                }
            }
        } else {
            let rows = standouts(for: row)
            if !rows.isEmpty {
                let shown = Array(rows.prefix(row.cap))
                Section {
                    ForEach(shown) { standout in
                        NavigationLink {
                            DisclosureDetailView(trade: standout.trade)
                        } label: {
                            StandoutRow(standout: standout)
                        }
                        .disclosureRowChrome()
                    }
                    MoreRow(remaining: rows.count - shown.count)
                } header: {
                    Text(row.title)
                } footer: {
                    Text(row.footer)
                }
            }
        }
    }
}

// MARK: - Rows

/// One standout trade: the reason tag on its own line, then the same fields
/// `DisclosureRow` shows, condensed. The accessibility layout is the real one — every
/// field its own line — and the compact layout only pairs the badge and symbol back onto
/// a shared line once there is room.
private struct StandoutRow: View {
    let standout: Standout

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAX: Bool { typeSize.isAccessibilitySize }
    private var trade: Trade { standout.trade }

    /// Orange only for the genuine data-quality tag. Every other reason is neutral.
    private var reasonTint: Color {
        standout.category == .filedLate ? Ink.lag : .secondary
    }

    /// The amount line repeats the reason for `topBracket` (where the reason *is* the
    /// bracket), so it is dropped when they would say the same thing.
    private var showsAmountLine: Bool { trade.amount.label != standout.reason }

    var body: some View {
        VStack(alignment: .leading, spacing: isAX ? 10 : 6) {
            reasonChip

            Text(trade.memberName)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            identity

            if showsAmountLine {
                Text(trade.amount.label)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(trade.timingSentence)
                .font(.caption)
                .foregroundStyle(trade.hasImpossibleDate ? Ink.lag : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(trade.memberName), \(trade.txType.verb) \(trade.displaySymbol), "
            + "\(trade.amount.accessibleDescription). Surfaced because: \(standout.reason)"
        )
    }

    /// The reason, as its own line. A capsule at normal sizes; a wrapping rounded tag once
    /// Dynamic Type reaches the accessibility sizes, where a fixed-size capsule would run
    /// off the card.
    @ViewBuilder
    private var reasonChip: some View {
        if isAX {
            Text(standout.reason)
                .font(.caption2.weight(.medium))
                .foregroundStyle(reasonTint == .secondary
                                 ? AnyShapeStyle(.secondary) : AnyShapeStyle(reasonTint))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            FlowRow(spacing: 6) {
                TagChip(text: standout.reason, tint: reasonTint)
            }
        }
    }

    @ViewBuilder
    private var identity: some View {
        let symbol = HStack(alignment: .firstTextBaseline, spacing: 6) {
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
            }
        }

        if isAX {
            VStack(alignment: .leading, spacing: 8) {
                DirectionBadge(type: trade.txType)
                symbol
            }
        } else {
            HStack(spacing: 8) {
                DirectionBadge(type: trade.txType)
                symbol
                Spacer(minLength: 0)
            }
        }
    }
}

/// A widely-held ticker: the symbol and a count of filers. Taps through to the ticker's
/// full disclosure list, not to a single trade.
private struct WidelyHeldRow: View {
    let item: WidelyHeldTicker

    @Environment(\.dynamicTypeSize) private var typeSize

    private var ticker: some View {
        Text(item.ticker)
            .font(.body.weight(.semibold).monospaced())
            .foregroundStyle(.primary)
    }

    private var count: some View {
        Text("\(item.memberCount) members")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    ticker
                    count
                }
            } else {
                HStack(spacing: 12) {
                    ticker
                    Spacer(minLength: 8)
                    count
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.ticker), disclosed by \(item.memberCount) members. "
            + "Surfaced because: among the most widely held this snapshot."
        )
    }
}

/// The honest "and N more like this" tail row, shown only when a list is truncated.
private struct MoreRow: View {
    let remaining: Int

    var body: some View {
        if remaining > 0 {
            Text("and \(remaining) more like this")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("and \(remaining) more like this")
        }
    }
}
