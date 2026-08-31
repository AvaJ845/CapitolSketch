# Senate coverage — design & status

Outcome of the Apple-Fellows concept review (2026-08-31): **Reshape**. Senate belongs in
the app, but *not* as an on-device scrape of an Akamai-protected portal. Build it as
**build-time ingestion in `seedgen`**, ship it baked into the seed, keep the on-device
incremental refresher House-only.

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
| `SenateFilingIndex.swift` | CSRF handshake + paginated DataTables query → `[SenateFilingRow]`. **Build-time only.** | `report-index.json` fixture; `SenateLiveTests` (disabled, run by hand) |
| `SenateFilingRef` | UUID + member + paper/electronic/amendment flags; `documentURL` → the eFD view page. | — |

The **model already supports Senate**: `MemberDirectory.fromCongressLegislators` reads
`type == "sen"` → `chamber: .senate`; `Member.chamber`, `Chamber.senate`,
`TradeFeed.chambersCovered` all exist. Senator identity resolves through the same
`congress-legislators` crosswalk the House uses.

---

## What's left (in order)

1. **`SenateFetcher`** — orchestrator: one session, handshake once, list, then
   fetch+parse every electronic detail, reusing the session; resolve each filer against
   `MemberDirectory` (senators are in the crosswalk); collect `ParseStats`.
2. **Paper PTR OCR** — extract the `efd-media-public` GIF URLs from the paper page,
   download, run through `PTROCR` / Vision, feed the text to a scan parser. Until then,
   paper Senate filings are counted and shown as missing, exactly like unreadable House
   scans.
3. **`seedgen` wiring** — a `--senate` flag (default on once validated); merge House +
   Senate through `FeedBuilder`; `chambersCovered = [.house, .senate]`; log Senate
   coverage separately.
4. **`Trade.chamber`** (or an app-side `store.member(id:)?.chamber` lookup) + schema bump
   to 3.
5. **App UI** — a `chamber` facet in `TradeFilter`, a "Senate" / "House" **text** tag in
   `DisclosureRow` (never a colour — colour carries no meaning in this app), and
   Senate-aware "View the source filing" (opens the eFD page, not a House Clerk PDF).
6. **Ship it as one dated "now covers the full Congress" update** — only once electronic
   *and* paper coverage is complete enough that a watchlist hit is as reliable for a
   senator as for a representative. A partial Senate tab is a North-Star violation.

The on-device `IncrementalRefresher` stays House-only. Senate data refreshes when
`seedgen` runs and ships in the next app update — acceptable because Senate filings are
already 45-day-lagged and the app shows data age on every screen.
