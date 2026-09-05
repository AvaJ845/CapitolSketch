import SwiftUI
import DisclosureKit

/// Small tag used for data-quality flags and secondary facts.
///
/// Orange is reserved for "something about this filing's own dates is off". No colour in
/// the app encodes buy versus sell.
struct TagChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.fill.quaternary, in: Capsule())
        .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .fixedSize()
    }
}

/// Consistent empty state across tabs.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Ink.accent)
            }
        }
    }
}

/// The 45-day window, restated as a pull-quote rather than a banner dump.
struct DisclosureLagNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Ink.lag
                .frame(width: 3)
            Text(Copy.lagBanner)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.lag.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The age of the data in hand, shown wherever filings are.
struct DataAgeLine: View {
    let generatedAt: Date?

    var body: some View {
        Group {
            if let generatedAt {
                Text("Filings as of \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
                     + " · \(Self.age(of: generatedAt))")
            } else {
                Text("No filings loaded.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    static func age(of date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<0: return "dated in the future"
        case 0: return "downloaded today"
        case 1: return "1 day old"
        default: return "\(days) days old"
        }
    }
}

/// Refresh liveness, shown only when the app hasn't reached the House Clerk in over a
/// week. Deliberately calm — this is a data-quality note, not an alarm: `.caption2`
/// secondary text with a thin `Ink.lag` rule and no fill, so it reads as "here is a
/// caveat" rather than "something is broken".
struct StaleContactNote: View {
    let lastContact: Date?

    private var message: String {
        if let lastContact {
            let when = lastContact.formatted(.dateTime.month(.abbreviated).day())
            return "Haven't reached the House Clerk since \(when) — showing the last data downloaded."
        }
        return "Haven't reached the House Clerk yet — showing the data this version shipped with."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Ink.lag
                .frame(width: 2)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Initials in a navy disc. Used on the members list so rows have a face without photos.
struct MonogramView: View {
    let name: String

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    private var initials: String {
        let parts = name.split(separator: " ").filter { !$0.hasSuffix(".") }
        let letters = parts.suffix(2).compactMap { $0.first }
        let s = String(letters).uppercased()
        return s.isEmpty ? "—" : s
    }

    var body: some View {
        Text(initials)
            .font(.caption.weight(.semibold))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .foregroundStyle(Ink.badgeOnFill)
            .frame(width: size, height: size)
            .background(Ink.badgeFill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Three or four headline numbers. A single row normally; a wrapping grid once Dynamic
/// Type reaches the accessibility sizes, where four cells across would clip.
struct StatStrip: View {
    let items: [(label: String, value: String)]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        cell(item)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        cell(item).frame(maxWidth: .infinity)
                        if index < items.count - 1 {
                            Divider().frame(height: 28)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ item: (label: String, value: String)) -> some View {
        VStack(spacing: 4) {
            Text(item.value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(item.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label): \(item.value)")
    }
}

/// Honest note for a list that is showing only the first `shown` of `total` rows, so the
/// rest are known to exist rather than silently dropped. Matches the feed masthead's
/// phrasing. Renders nothing when the whole list fits.
struct TruncationNote: View {
    let shown: Int
    let total: Int

    var body: some View {
        if total > shown {
            Text("Showing \(shown.formatted()) of \(total.formatted())")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Showing \(shown) of \(total) rows")
        }
    }
}

/// A followed member as a chip, for the Watchlist "Members you follow" strip. A person
/// glyph and the member's name in the regular text face — not the monospaced ticker
/// face `TickerChip` uses — with an accessible label and room to truncate a long name.
struct MemberChip: View {
    let name: String
    var filingCount: Int?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let filingCount {
                Text("\(filingCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Ink.chipFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.chipStroke, lineWidth: 0.75))
        .frame(maxWidth: 240, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            filingCount.map {
                "\(name), \($0) disclosed transaction\($0 == 1 ? "" : "s"). Followed."
            } ?? "\(name). Followed."
        )
    }
}

/// Horizontal ticker pills used on Watchlist and member pages.
struct TickerChip: View {
    let ticker: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(ticker)
                .font(.subheadline.weight(.semibold).monospaced())
            if let count {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Ink.chipFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.chipStroke, lineWidth: 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(ticker), \($0) disclosed trade\($0 == 1 ? "" : "s")" } ?? ticker)
    }
}
