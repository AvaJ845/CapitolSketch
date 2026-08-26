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
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .fixedSize()
    }
}

/// Consistent empty state across tabs.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}

/// The 45-day window, restated wherever filings are listed.
struct DisclosureLagNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            Text(Copy.lagBanner)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}

/// The age of the data in hand, shown wherever filings are.
///
/// The app never implies it is current. It says when the snapshot was assembled, every
/// time, because "how old is this" is the first thing a reader should be able to answer.
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
