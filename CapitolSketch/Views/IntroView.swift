import SwiftUI

/// The one-time intro. Three facts the app is built on — the disclosure lag, what the
/// watchlist is for, and that nothing here is advice — said once, before the reader is
/// dropped into ten thousand rows. Shown from `RootView` on first launch and never again
/// (`SharedContainer.Key.hasSeenIntro`).
///
/// It sells nothing and asks for nothing: no account, no permission prompt, no email.
/// The only button dismisses it.
struct IntroView: View {
    var onDone: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let points: [Point] = [
        Point(
            symbol: "clock.arrow.circlepath",
            title: "History, not headlines",
            body: "The law gives members up to 45 days to disclose a trade. Every entry here "
                + "is already weeks old — and every entry shows exactly how old."
        ),
        Point(
            symbol: "bell.badge",
            title: "One alert worth having",
            body: "Add the tickers you own, or follow a member. The app taps you on the "
                + "shoulder when a disclosure touches them — and stops there."
        ),
        Point(
            symbol: "lock.shield",
            title: "Yours, and only yours",
            body: "No account, no ads, no analytics. Your watchlist never leaves this phone. "
                + "Everyone downloads the same public snapshot."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CapitolSketch")
                            .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        Text("Congress trade disclosures, as the public record — nothing added.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(points) { point in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: point.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Ink.accent)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(point.title)
                                        .font(.headline)
                                    Text(point.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Text(Copy.noAdvice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onDone) {
                    Text("Show me the filings")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Ink.accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(.bar)
        }
        .background(Ink.canvas)
        .interactiveDismissDisabled()
    }
}
