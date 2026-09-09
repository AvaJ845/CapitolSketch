// Senate eFD portal scraping / parsing. The shipping app is House-only and no app or
// widget code path reaches this type; it is compiled only for `seedgen` and the
// DisclosureKit test target, both of which define SEEDGEN. See P0-2 in the security
// review and `Package.swift`.
#if SEEDGEN
import Foundation

/// Pulls the scanned page images out of a Senate **paper** PTR report page.
///
/// A paper report on efdsearch.senate.gov has no text layer — the filing is a set of
/// scanned GIFs in a Bootstrap carousel, each an `<img class="filingImage" src="…">`
/// pointing at `efd-media-public.senate.gov`. The carousel lists them in page order and
/// that order is preserved here.
///
/// This only locates the images. Turning them into transactions is the OCR + spatial
/// parser work tracked in `_private/SENATE.md` — the Senate paper form is a column grid where an
/// `X` in one of several amount-bracket columns carries the figure, so `PTRParser` (which
/// anchors on a House text row) cannot read it.
public enum SenatePaperReport {

    /// The scanned page image URLs, in the order the carousel presents them. Empty when
    /// the page carries no `filingImage` — treat that as "layout changed", not "no pages".
    public static func imageURLs(fromHTML html: String) -> [URL] {
        let pattern = #"<img\b[^>]*\bclass="[^"]*\bfilingImage\b[^"]*"[^>]*\bsrc="([^"]+)""#
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        var urls: [URL] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range(at: 1), in: html) else { continue }
            let src = String(html[r])
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(src).inserted, let url = URL(string: src) else { continue }
            urls.append(url)
        }
        return urls
    }
}
#endif // SEEDGEN
