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
| `SenateFetcher.swift` | Orchestrator: one session, handshake once, list, then fetch + parse every electronic detail; resolves filers by name within the Senate chamber; collects `ParseStats` in the House `PTRFetcher.Output` shape. Paper filings recorded as missing (OCR pending). | live `seedgen --senate` run |
| `MemberDirectory.resolve(last:first:chamber:)` | Name-only resolution for a source with no state (the eFD search). Answers only when the chamber narrows to one person. | proven live — Coons/McCormick/Boozman → real bioguide IDs |

`seedgen` gained **`--senate`**: fetches Senate PTRs since Jan 1 of the earliest
`--years` year, folds them into the House rows before de-dup, sets
`chambersCovered = [.house, .senate]` and the combined source string. Verified end to
end — a limited run produced a 104-row feed (82 Senate rows) with senators resolved and
`documentURL`s pointing at eFD.

---

## What's left (in order)

1. **Paper PTR OCR** — the paper page embeds `efd-media-public.senate.gov/…/NNN.gif`
   scanned images. Extract those, download, run through `PTROCR` / Vision, feed the text
   to a scan parser. Until then, paper Senate filings are counted and shown as missing,
   exactly like unreadable House scans (~5–10% of Senate PTRs).
2. **`Trade.chamber`** (or an app-side `store.member(id:)?.chamber` lookup) + schema
   bump to 3, so the app can filter and tag by chamber. The feed already carries the
   `Member.chamber` needed for the lookup path.
3. **App UI** — a `chamber` facet in `TradeFilter`, a "Senate" / "House" **text** tag in
   `DisclosureRow` (never a colour — colour carries no meaning in this app), and
   Senate-aware "View the source filing" (opens the eFD page, not a House Clerk PDF —
   `Trade.documentURL` already carries the right URL).
4. **A full `seedgen --senate` run** into the real `seed-filings.json`, then regenerate
   the App Store screenshots (the feed's "House · public record" framing changes).
5. **Ship it as one dated "now covers the full Congress" update** — only once electronic
   *and* paper coverage is complete enough that a watchlist hit is as reliable for a
   senator as for a representative. A partial Senate tab is a North-Star violation.

The on-device `IncrementalRefresher` stays House-only. Senate data refreshes when
`seedgen` runs and ships in the next app update — acceptable because Senate filings are
already 45-day-lagged and the app shows data age on every screen.
