# Senate coverage — design & status

Outcome of the Apple-Fellows concept review (2026-08-31): **Reshape**. Senate belongs in
the app, but *not* as an on-device scrape of an Akamai-protected portal. Build it as
**build-time ingestion in `seedgen`**, ship it baked into the seed, keep the on-device
incremental refresher House-only.

**Status (2026-09-07):** electronic PTRs parse and fold into the feed. Paper PTRs have
been investigated and **cannot be turned into transactions** — see item 1 below; that
now needs a product call, and it blocks the ship gate (item 5).

North Star it has to serve: *the same public record for every reader, from primary
sources, no backend, no third-party data, no fetch that varies by what the reader holds,
and no claim of Senate coverage the app can't actually deliver.*

---

## The mechanism (proven live, 2026-08-31)

`efdsearch.senate.gov` — a Django app. There is **no bulk index** (unlike the House
Clerk's `{year}FD.txt`), so coverage is: one API to list filings, then one HTTP
round-trip per filing.

1. **`GET /search/home/`** → scrape `csrfmiddlewaretoken` from the agreement form.
2. **`POST /search/home/`** with that token + `prohibition_agreement=1` → session cookie
   + `csrftoken` cookie. That cookie value is the token the search endpoint wants.
3. **`POST /search/report/data/`** (a DataTables endpoint) with `report_types=[11]`
   (Periodic Transaction Report), `start`/`length` paging, `submitted_start_date`, and
   `csrfmiddlewaretoken`. Returns JSON: `{"data": [[first, last, displayName, linkHTML,
   filedDate], …], "recordsTotal": N}`.
4. Per row, pull the `<a href>` out of `linkHTML`:
   - `/search/view/ptr/<uuid>/` → **electronic** report. `GET` it; parse the one
     `<table class="table table-striped">`. Columns: `# · Transaction Date · Owner ·
     Ticker · Asset Name · Asset Type · Type · Amount · Comment`.
   - `/search/view/paper/<uuid>/` → **paper** report. The page embeds scanned page
     **GIF images** at `efd-media-public.senate.gov/media/…/NNNNNNNNN.gif`. No text
     layer — needs OCR (same problem as House scanned PDFs).
   - `"Amendment N"` in the link text → a restatement; existing de-dup handles it.
5. Session expires mid-run → the detail `GET` 302s back to `/search/home/` → re-handshake.
6. Be polite: a short delay between requests.

**Akamai:** recon said datacenter IPs get 403 and it can serve a JS challenge. From this
build machine the full handshake + pagination + detail fetch **worked with a plain
`URLSession`** and a Safari User-Agent — no challenge. A residential `seedgen` run should
be at least as clean. This is exactly why it must not run on every reader's phone: an
unknowable fraction of consumer IPs *will* get challenged, and `URLSession` can't solve a
JS challenge.

**Volume:** ~50 PTRs per rolling 3-month window (100 senators, and senators trade far
less than the House's power-traders). Trivial.

---

## What's built (`Packages/DisclosureKit/Sources/DisclosureKit/`)

| File | Does | Tested against |
|---|---|---|
| `SenatePTRParser.swift` | Electronic PTR HTML table → `[Trade]`. Dependency-free, scoped to the exact template. Reuses `PTRParser.parseAmount`, `CalendarDate`, `DisclosedAmount`. | 4 real report pages + the index JSON in `Tests/…/Fixtures/senate/` |
| `SenatePaperReport.swift` | Paper report page → ordered `[URL]` of the scanned GIF pages. Locates only; does not parse. | `paper-blumenthal` fixture, `SenatePaperReportTests` |
| `SenatePaperOCR.swift` | Scanned GIF pages → recognised text lines (Vision, shared `VisionText` band-grouping). Recovers printed text only — **not** the hand-drawn amount `X`. Kept as a reproducible measurement, not a parser. | `paper-blumenthal-pages/` fixtures, `SenatePaperOCRTests` |
| `SenateFilingIndex.swift` | CSRF handshake + paginated DataTables query → `[SenateFilingRow]`. **Build-time only.** | `report-index.json` fixture; `SenateLiveTests` (disabled, run by hand) |
| `SenateFetcher.swift` | Orchestrator: one session, handshake once, list, then fetch + parse every electronic detail; resolves filers by name within the Senate chamber; collects `ParseStats` in the House `PTRFetcher.Output` shape. Paper filings fetched for their page count, recorded as incomplete (OCR pending). | live `seedgen --senate` run |
| `MemberDirectory.resolve(last:first:chamber:)` | Name-only resolution for a source with no state (the eFD search). Answers only when the chamber narrows to one person. | proven live — Coons/McCormick/Boozman → real bioguide IDs |

`seedgen` gained **`--senate`**: fetches Senate PTRs since Jan 1 of the earliest
`--years` year, folds them into the House rows before de-dup, sets
`chambersCovered = [.house, .senate]` and the combined source string. A full
`--years 2025,2026 --senate` run (2026-09-07): ~2,400 Senate rows from ~36 senators fold
into the House feed for ~12,600 rows total; ~30 Senate paper filings are counted as
unreadable (see item 1).

---

## What's left (in order)

1. **Paper PTR OCR — investigated, and it does not work. This is now a product decision,
   not an engineering task.** (branches `senate-paper-groundwork` and
   `senate-paper-ocr-finding`, 2026-09-07)

   What's built:
   - `SenatePaperReport.imageURLs(fromHTML:)` — the `efd-media-public.senate.gov` GIF
     page URLs from a paper report page, in carousel order. `SenateFetcher` fetches the
     page and records the scanned-page count on the filing.
   - `SenatePaperOCR.recognise(gifPages:)` — Vision text recognition over the scanned
     GIFs, sharing the band-grouping (`VisionText`) with the House `PTROCR` path.
   - Two real Blumenthal transaction pages checked in under
     `Fixtures/senate/paper-blumenthal-pages/`, with `SenatePaperOCRTests` pinning what
     OCR does and does not recover.

   **The finding.** The Senate paper form is a carbon-copy column grid. The amount is a
   hand-drawn `X` in one of eleven narrow dollar-bracket columns; transaction type is a
   separate Purchase/Sale/Exchange column. Vision reads the *printed* text on these scans
   — filer, transaction dates, asset names (ticker included) — but **the `X` marks do not
   register at all**, even after 2× upscaling, contrast-stretching and thresholding.
   Across the two Blumenthal pages, every printed date came through and **zero** amount
   marks did. A spatial parser has nothing to read. Any amount it emitted would be a
   guess, which the North Star forbids outright — worse than counting the filing as
   unreadable.

   **So the options are:**
   - **(A) Ship Senate electronic-only; treat paper PTRs exactly like unreadable House
     scans.** They are counted and disclosed on the data-quality screen, not in the feed
     — the same class of gap the app already has for ~12% of House filings, at a *lower*
     rate (~5–10% of Senate PTRs). Arguably this already meets "as reliable for a senator
     as for a representative", since the House bar is not 100% either.
   - **(B) A + surface each paper filing as a non-matchable feed entry** — "Sen. X filed
     a paper PTR on <date> — view the N-page scan" — so its existence is visible even
     though its contents are not machine-readable. More honest; needs a feed row type
     that has no ticker/amount.
   - **(C) Keep Senate unshipped** until someone does per-cell image processing (crop each
     bracket column, upscale hard, template-match the `X`). Research project, uncertain
     payoff, for 5–10% of one chamber.

   **Decision (2026-09-07): (A).** Ship Senate electronic-only; paper PTRs are treated
   like unreadable House scans — counted, disclosed on the data-quality screen, not in
   the feed. The "a partial Senate tab is a North-Star violation" line from 2026-08-31 is
   superseded: full paper *transaction* coverage is not achievable, and the honest bar is
   the same one the app already holds for the ~12% of House filings it can't read. (B) is
   a later enhancement.

2. **Chamber on the feed — DONE** (branch `senate-electronic-coverage`). No new field, no
   schema bump — chamber is read through `TradeStore.chamber(of:)` / `chamberTag(for:)`.
3. **App UI — DONE.** `chamber` facet in `TradeFilter`; a "House" / "Senate" text tag in
   `DisclosureRow` / `StandoutRow`, shown only when `feed.chambersCovered.count > 1`;
   a "Chamber" row + chamber-aware source wording in `DisclosureDetailView`; Settings and
   data-quality copy adapts to `store.isMultiChamber`. `Trade.documentURL` already points
   at the eFD page for a Senate filing.
3b. **Senate name resolution — DONE.** The eFD prints only a name and the crosswalk holds
   every historical namesake. `MemberDirectory.resolve(last:first:chamber:)` now strips a
   generational suffix (`, Jr.` / `III` / `IV`, in either name column) and takes a
   `servingInOrAfter:` year so a long-gone Senate "Kennedy" or "King" is ignored.
   `Entry.lastTermEndYear` was added for the year filter.
4. **A full `seedgen --senate` run** into the real `seed-filings.json`, then regenerate
   the App Store screenshots (the feed's "House · public record" framing changes). The
   seed is regenerated on this branch; the screenshot reshoot is still to do.
5. **Ship it as one dated "now covers the full Congress" update** — an App Store release,
   the owner's call. Electronic coverage is complete; paper filings are handled per (A).

The on-device `IncrementalRefresher` stays House-only. Senate data refreshes when
`seedgen` runs and ships in the next app update — acceptable because Senate filings are
already 45-day-lagged and the app shows data age on every screen.
