#if canImport(Vision)
import Foundation
import CoreGraphics

/// Turns Vision's loose text fragments back into lines.
///
/// Vision returns a box and a string per fragment, in no useful order. A government form
/// is a table, so fragments that share a vertical band are one logical row; rejoining
/// them left to right puts a transaction code and its dates back on one line, which is
/// what the text parsers anchor on. Shared by the House scanned-PDF path (`PTROCR`) and
/// the Senate scanned-GIF path (`SenatePaperOCR`).
enum VisionText {

    /// Fragments grouped into lines, top of the page first, each line's fragments joined
    /// left to right with a double space.
    static func lines(
        from fragments: [(box: CGRect, text: String)],
        bandTolerance: Double = 0.011
    ) -> [String] {
        guard !fragments.isEmpty else { return [] }
        // Vision's y-origin is the bottom, so a larger midY is higher on the page.
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }

        var rows: [[(box: CGRect, text: String)]] = []
        var bandCenter = sorted[0].box.midY
        for fragment in sorted {
            if !rows.isEmpty, abs(fragment.box.midY - bandCenter) < bandTolerance {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
                bandCenter = fragment.box.midY
            }
        }

        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: "  ")
        }
    }
}
#endif
