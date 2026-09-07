// Senate eFD paper-filing OCR. Build-time only (`seedgen` / the test target); the
// shipping app never runs this. See `SenatePaperReport` for how the page images are
// located, and `SENATE.md` for why paper filings are still not turned into transactions.
#if SEEDGEN && canImport(Vision)
import Foundation
import Vision
import CoreGraphics
import ImageIO

/// Runs Vision text recognition over the scanned GIF pages of a Senate paper PTR.
///
/// **This does not produce transactions, and on current evidence it cannot.** The Senate
/// paper form records the amount as a hand-drawn `X` in one of eleven narrow
/// dollar-bracket columns. Vision reads the printed text on these scans — the filer, the
/// dates, the asset names — but the `X` marks themselves do not register, even after
/// upscaling, contrast-stretching and thresholding (verified against the checked-in
/// Blumenthal pages). A parser built on this output would be blank or wrong on the amount
/// for almost every row, which is worse than counting the filing as unreadable.
///
/// It is kept so the finding is reproducible, so a future OS with better handwriting
/// recognition can be re-measured against the same fixtures, and so `seedgen` can log
/// what OCR *does* recover for a paper filing.
public enum SenatePaperOCR {

    public struct PageText: Sendable {
        public let pageIndex: Int
        public let lines: [String]
    }

    /// One `PageText` per GIF that decoded and yielded any text, in page order.
    public static func recognise(gifPages: [Data]) -> [PageText] {
        var out: [PageText] = []
        for (index, data) in gifPages.enumerated() {
            guard let image = decodeFirstFrame(data) else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            guard (try? handler.perform([request])) != nil else { continue }

            let fragments: [(box: CGRect, text: String)] = (request.results ?? [])
                .compactMap { obs in
                    obs.topCandidates(1).first.map { (obs.boundingBox, $0.string) }
                }
            let lines = VisionText.lines(from: fragments)
            if !lines.isEmpty { out.append(PageText(pageIndex: index, lines: lines)) }
        }
        return out
    }

    private static func decodeFirstFrame(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
#endif
