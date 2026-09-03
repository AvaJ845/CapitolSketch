#if canImport(Vision) && canImport(PDFKit)
import Foundation
import PDFKit
import Vision
import CoreGraphics

extension PTRParser {

    /// Runs Vision text recognition over each page of a scanned filing and returns the
    /// lines, top to bottom, joined the same way `PDFDocument.string` would — so the
    /// existing text parser can consume it unchanged.
    ///
    /// Language correction is off: the form is full of tickers, owner codes and dollar
    /// brackets that a dictionary would "fix" into the wrong thing.
    static func ocrText(from doc: PDFDocument) -> String? {
        var pageTexts: [String] = []

        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index),
                  let image = render(page: page)
            else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continue
            }

            let fragments: [(box: CGRect, text: String)] = (request.results ?? [])
                .compactMap { obs in
                    obs.topCandidates(1).first.map { (obs.boundingBox, $0.string) }
                }

            let lines = reconstructRows(from: fragments)
            if !lines.isEmpty { pageTexts.append(lines.joined(separator: "\n")) }
        }

        let joined = pageTexts.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// Vision returns text fragments, not lines. The form is a table, so fragments that
    /// share a vertical band are one logical row — rejoining them left to right puts the
    /// transaction code and its two dates back on one line, which is what the anchor in
    /// the text parser keys on.
    private static func reconstructRows(from fragments: [(box: CGRect, text: String)]) -> [String] {
        guard !fragments.isEmpty else { return [] }
        // Vision's y-origin is the bottom, so a larger midY is higher on the page.
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }

        let tolerance = 0.011  // fraction of page height that still counts as the same row
        var rows: [[(box: CGRect, text: String)]] = []
        var bandCenter = sorted[0].box.midY

        for fragment in sorted {
            if !rows.isEmpty, abs(fragment.box.midY - bandCenter) < tolerance {
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

    /// Rasterises one PDF page to a white-backed bitmap at roughly 200 dpi, which is
    /// where Vision's accuracy on printed forms levels off.
    private static func render(page: PDFPage) -> CGImage? {
        let box = PDFDisplayBox.mediaBox
        let pageRect = page.bounds(for: box)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let scale: CGFloat = 200.0 / 72.0
        let width = Int((pageRect.width * scale).rounded())
        let height = Int((pageRect.height * scale).rounded())
        // Bound each dimension before multiplying: a filing with an absurd MediaBox
        // (this raster runs on device, on downloaded PDF bytes) could otherwise overflow
        // the `width * height` product. A real page at 200 dpi is well under 3,000 px a
        // side; 20,000 is a generous ceiling that still keeps the area check exact.
        guard width > 0, height > 0, width < 20_000, height < 20_000,
              width * height < 40_000_000 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageRect.minX, y: -pageRect.minY)

        // PDFPage.draw applies the page's own rotation and box transform, drawing into a
        // bottom-left-origin context right-side up — which is what this bitmap is.
        page.draw(with: box, to: context)

        return context.makeImage()
    }
}
#endif
