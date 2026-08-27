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

/// Initials in a navy disc. Used on the members list so rows have a face without photos.
struct MonogramView: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ").filter { !$0.hasSuffix(".") }
        let letters = parts.suffix(2).compactMap { $0.first }
        let s = String(letters).uppercased()
        return s.isEmpty ? "—" : s
    }

    var body: some View {
        Text(initials)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ink.badgeOnFill)
            .frame(width: 36, height: 36)
            .background(Ink.badgeFill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Three or four headline numbers in a single row.
struct StatStrip: View {
    let items: [(label: String, value: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                if index < items.count - 1 {
                    Divider().frame(height: 28)
                }
            }
        }
        .padding(.vertical, 4)
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
        .background(Ink.navy.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.navy.opacity(0.18), lineWidth: 0.5))
    }
}
