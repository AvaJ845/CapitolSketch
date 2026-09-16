// White House OGE Form 278-T OCR. Build-time only (`seedgen` / the test target); the
// shipping app never runs this — same reasoning as `WhiteHouseFilingIndex`.
#if SEEDGEN && canImport(Vision) && canImport(PDFKit)
import Foundation
import PDFKit
import Vision
import CoreGraphics

/// Runs Vision text recognition over every page of a scanned OGE Form 278-T and returns
/// the lines, top to bottom — the same shape `PTROCR.ocrText(from:)` produces for a
/// scanned House filing, so `OGE278TParser.parse(lines:filing:)` can consume either.
///
/// Every filing sampled while building this (see `OGE278TParser`'s doc comment for which
/// ones) had no embedded text layer at all — no `/Font`, `/Image` XObjects on every page
/// — so unlike `PTRParser`, there is no "prefer embedded text, fall back to OCR" branch
/// here: this form is scanned, full stop, until a counterexample turns up.
public enum OGE278TOCR {

    /// Every recognized line across every page, in page order. A page that fails to
    /// render or yields no text is simply absent from the result — the caller sees that
    /// as fewer transaction rows than the filing's own page count would suggest, not as a
    /// crash.
    public static func lines(from doc: PDFDocument) -> [String] {
        var allLines: [String] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index), let image = render(page: page) else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { continue }

            let fragments: [(box: CGRect, text: String)] = (request.results ?? [])
                .compactMap { obs in obs.topCandidates(1).first.map { (obs.boundingBox, $0.string) } }
            allLines.append(contentsOf: VisionText.lines(from: fragments))
        }
        return allLines
    }

    /// Rasterises one PDF page to a white-backed bitmap at roughly 200 dpi, where
    /// Vision's accuracy on printed forms levels off. Identical in substance to
    /// `PTROCR`'s private renderer; kept as its own copy rather than shared because the
    /// two files are `#if`-gated on different conditions (this one adds `SEEDGEN`) and
    /// the body is CoreGraphics boilerplate, not shared logic worth a cross-file
    /// dependency for.
    private static func render(page: PDFPage) -> CGImage? {
        let box = PDFDisplayBox.mediaBox
        let pageRect = page.bounds(for: box)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let scale: CGFloat = 200.0 / 72.0
        let width = Int((pageRect.width * scale).rounded())
        let height = Int((pageRect.height * scale).rounded())
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
        page.draw(with: box, to: context)
        return context.makeImage()
    }
}
#endif
