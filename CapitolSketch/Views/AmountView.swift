import SwiftUI
import DisclosureKit

/// The disclosed value, drawn as the shape of fact it actually is.
///
/// The House form asks for a bracket. Drawing a bracket as a bar, a sparkline point or a
/// pie slice would invent a single figure the filing never stated, so a range is drawn as
/// a range: a tick at each end and a visibly empty gap between them, because where inside
/// the bracket the real number sits is genuinely unknown.
///
/// The three shapes are drawn differently on purpose, since they are different claims:
///
/// - `.range` — two ticks and a gap. `$1,001 – $15,000`.
/// - `.atLeast` — one tick and an open end running off the edge. `Over $1,000,000`. There
///   is no upper bound on the form, so none is drawn.
/// - `.exact` — a single solid mark. The form carries these occasionally, for cash in
///   lieu of fractional shares, and they are exact to the cent (`$2,722.50`).
struct AmountView: View {
    let amount: DisclosedAmount
    /// Detail screens can afford the caption; dense list rows cannot.
    var showsKindCaption = true

    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility sizes a horizontal range does not fit, so the same two-ticks-and
    /// -a-gap idea is drawn down the page instead of across it.
    private var isStacked: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsKindCaption {
                Text(amount.kindCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
            }
            figure
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(amount.accessibleDescription)
    }

    @ViewBuilder
    private var figure: some View {
        switch amount.kind {
        case .range where amount.isRange:
            if isStacked { verticalRange } else { horizontalRange }

        case .atLeast:
            openEnded

        case .exact:
            singleMark(amount.headline, symbol: "diamond.fill")

        case .none:
            // The literal option on the form, verbatim. It is 24 characters and must be
            // allowed to wrap rather than being shortened into something else.
            Text(amount.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .unknown:
            singleMark(amount.headline, symbol: "questionmark.circle")

        case .range:
            // A `.range` whose ends coincide has one endpoint to draw, not two.
            singleMark(amount.headline, symbol: "diamond.fill")
        }
    }

    // MARK: - Range

    private var horizontalRange: some View {
        HStack(spacing: 8) {
            endpoint(amount.lowLabel)
            RangeTrack(axis: .horizontal, openEnded: false)
                .frame(minWidth: 56, idealWidth: 88, maxWidth: 120, minHeight: 14)
            endpoint(amount.highLabel)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var verticalRange: some View {
        HStack(alignment: .center, spacing: 8) {
            RangeTrack(axis: .vertical, openEnded: false)
                .frame(width: 12, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                endpoint(amount.lowLabel)
                endpoint(amount.highLabel)
            }
        }
    }

    private var openEnded: some View {
        // The open end is a 1.4pt arrowhead; the meaning cannot rest on that alone.
        let ceiling = Text("no ceiling")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        return Group {
            if isStacked {
                // Across the page the headline, the track and the caption overflow the
                // card at the accessibility sizes, so the caption drops below.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        endpoint(amount.headline)
                        RangeTrack(axis: .horizontal, openEnded: true)
                            .frame(minWidth: 40, idealWidth: 64, maxWidth: 88, minHeight: 14)
                    }
                    ceiling
                }
            } else {
                HStack(spacing: 8) {
                    endpoint(amount.headline)
                    RangeTrack(axis: .horizontal, openEnded: true)
                        .frame(minWidth: 40, idealWidth: 64, maxWidth: 88, minHeight: 14)
                    ceiling
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func endpoint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.primary)
    }

    private func singleMark(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Two ticks with a dotted gap between them, or one tick and an open end.
///
/// The gap is dotted rather than filled. A filled bar reads as a magnitude, and a
/// magnitude is exactly what the filing does not give.
private struct RangeTrack: View {
    enum TrackAxis { case horizontal, vertical }

    let axis: TrackAxis
    let openEnded: Bool

    var body: some View {
        Canvas { context, size in
            // `.secondary` is resolved rather than hard-coded, so this follows Increase
            // Contrast and inverts correctly under Smart Invert.
            let ink = GraphicsContext.Shading.color(.secondary)
            let line = StrokeStyle(lineWidth: 1.4, lineCap: .round)
            let dotted = StrokeStyle(
                lineWidth: 1.4, lineCap: .round, dash: [1.4, 2.6]
            )

            switch axis {
            case .horizontal:
                let y = size.height / 2
                let tick = size.height * 0.7
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0.7, y: y - tick / 2))
                            $0.addLine(to: CGPoint(x: 0.7, y: y + tick / 2)) },
                    with: ink, style: line
                )
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0.7, y: y))
                            $0.addLine(to: CGPoint(x: size.width - 0.7, y: y)) },
                    with: ink, style: dotted
                )
                if openEnded {
                    // Runs off the end: the form states no ceiling, so none is drawn.
                    context.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: size.width - 4.5, y: y - 3))
                            p.addLine(to: CGPoint(x: size.width - 0.7, y: y))
                            p.addLine(to: CGPoint(x: size.width - 4.5, y: y + 3))
                        },
                        with: ink, style: line
                    )
                } else {
                    context.stroke(
                        Path { $0.move(to: CGPoint(x: size.width - 0.7, y: y - tick / 2))
                                $0.addLine(to: CGPoint(x: size.width - 0.7, y: y + tick / 2)) },
                        with: ink, style: line
                    )
                }

            case .vertical:
                let x = size.width / 2
                let tick = size.width * 0.7
                for y in [0.7, size.height - 0.7] {
                    context.stroke(
                        Path { $0.move(to: CGPoint(x: x - tick / 2, y: y))
                                $0.addLine(to: CGPoint(x: x + tick / 2, y: y)) },
                        with: ink, style: line
                    )
                }
                context.stroke(
                    Path { $0.move(to: CGPoint(x: x, y: 0.7))
                            $0.addLine(to: CGPoint(x: x, y: size.height - 0.7)) },
                    with: ink, style: dotted
                )
            }
        }
        .accessibilityHidden(true)
    }
}
