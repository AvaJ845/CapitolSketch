# CapitolSketch

An iOS app that tracks stock trades disclosed by members of the US House of
Representatives, with a personal watchlist that tells you when a House member
trades a ticker you hold.

House only. Read-only. No brokerage, no account, no analytics. Nothing here is
investment advice.

App Store name: **CapitolSketch: Congress Trade**. Home Screen: **CapitolSketch**.

## Why it is not a Pelosi tracker

The idea started as a Nancy Pelosi holdings tracker. Two findings redirected it:

- **Pelosi retires on January 3, 2027.** She announced in November 2025 that she would
  not seek reelection. With the STOCK Act's 45-day disclosure window, her last filings
  land around February 2027 and then the data source permanently dries up. A
  single-subject app would have outlived its subject within months.
- **That niche is taken.** Autopilot, built by the team behind the viral Pelosi Tracker
  account, has 180,000+ users and over $1B in connected assets, auto-executes the trades
  in your own brokerage, and has already rebranded its flagship portfolio to "Pelosi+"
  in anticipation of her exit.

So the app covers the whole House, treats Pelosi as one member among many, and competes
on something Autopilot does not sell: a read-only, ad-free, no-brokerage-connection view
with alerts scoped to *your* holdings.

## Architecture

```
Packages/DisclosureKit/   shared parser, models, incremental refresh (iOS + Mac)
Tools/PTRKit/             seedgen — build-time ingestion CLI (macOS, SwiftPM)
CapitolSketch/            the iOS app (SwiftUI)
  Models/                 presentation and copy
  Data/                   TradeStore, WatchlistStore, AlertService, AppearanceStore
  Views/                  Feed, Watchlist, Members, Settings, disclosure row
  Resources/              seed-filings.json — bundled snapshot
CapitolSketchWidget/      one WidgetKit widget (Home Screen + Lock Screen)
Shared/                   App Group container (feed + watchlist keys)
project.yml               xcodegen project definition
```

There is no backend and no third-party API. `seedgen` reads primary sources directly,
and the app ships the result as a bundled JSON snapshot. On device, an incremental
refresh asks the House Clerk's own public index which filings have appeared since and
reads only those PDFs. The widget refreshes the same way from `getTimeline` via
URLSession. There is no `BGTaskScheduler`.

Persisted keys (`watchlistTickers`, `appearance`, `seenRowIDs`, …) are deliberately
not branded, so a future rename does not force a migration.

### Why the data pipeline works this way

There is no official API for congressional trades. The options were all bad in
different ways:

- The commercial APIs (Kapitol.ai, politicianstocktracker) are paid, and embedding a key
  in a shipped binary leaks it.
- The free one (CongressInvests) turned out to be stale by 86 days when checked, and its
  records contained duplicate rows, transaction dates *after* their filing dates, and raw
  PDF text bleeding into asset names.

The House Clerk's own bulk index is free, public domain, needs no key, and is
regenerated daily. It costs a PDF parser to use, which is what DisclosureKit is.

## Regenerating the data

```bash
cd Tools/PTRKit
swift run seedgen --years 2025,2026 --out ../../CapitolSketch/Resources/seed-filings.json
```

Options: `--limit N` to process only the N most recent filings, `--concurrency N` for
parallel downloads (default 6; be polite to the Clerk's servers), `--cache DIR` to reuse
downloaded PDFs across runs, `--pretty` for readable JSON.

The pipeline:

1. Download `https://disclosures-clerk.house.gov/public_disc/financial-pdfs/{year}FD.txt`
   and keep the rows with `FilingType == "P"` (Periodic Transaction Report).
2. Fetch each PTR PDF and extract text with PDFKit.
3. Parse transaction rows and emit a single JSON feed.

Current snapshot: **10,146 transactions from 128 members** across 2025–2026.

## Building the app

```bash
/Users/dj/bin/xcodegen generate
open CapitolSketch.xcodeproj
```

Requires Xcode 26 / iOS 18+ deployment target. Never hand-edit the `.xcodeproj`;
regenerate it from `project.yml`.

Parser tests live in `Packages/DisclosureKit/Tests` (real PTR PDF fixtures, including
Pelosi DocID 20035143):

```bash
cd Packages/DisclosureKit && swift test
```

## How the parser works

PDFKit flattens the PTR table into a stream of lines where one logical row spans several
lines and the columns arrive out of order. Rather than reconstructing the table, the
parser anchors on the one unambiguous pattern per row — transaction code, two dates, a
dollar range — and attributes surrounding text to it.

Quirks it handles, each found by reading real filings:

- Small-caps labels ("FILING STATUS:") render as a letter followed by **NUL bytes**, not
  spaces. Control characters are normalised before matching.
- Owner codes are sometimes repeated: `SP SP SP SP SP Bloom Energy…`.
- The upper bound of a dollar range frequently wraps onto the next line.
- Descriptions appear either *before* or *after* the row they belong to, and wrap onto
  unlabelled continuation lines.
- When a row's columns fail to match, its asset name would prefix the next row. Since
  each asset ends with a bracketed type code, text before the second-to-last code is
  discarded as leftover.

Validated against Pelosi's August 21, 2026 filing (`20035143`): all 7 rows parse with
correct owner, stock-vs-option split, dollar range, and description.

## Known limitations

These are real and worth stating plainly:

- **House only.** Senate disclosures live on a separate portal behind a CSRF-protected
  session, and are not yet covered.
- **Some filings yield nothing.** They are scanned paper documents with no extractable
  text. Those transactions are simply missing, and the count is shown in Settings.
- **Everything is stale by design.** Members have 45 days to disclose. Median observed
  lag is 28 days; 16% of filings exceed the 45-day limit. This is inherent to the data,
  not a bug, and the UI says so on every screen.
- **Amounts are ranges, not values.** The form only requires a bracket like
  "$1,001 – $15,000". Any total or ranking built on these is an estimate.
- **A few filings contain impossible dates** — a transaction date after the filing date,
  almost always a mistyped year. These are shown exactly as filed and flagged in the UI
  rather than silently corrected.
- **No party affiliation.** The Clerk index does not include it and inventing a lookup
  table for 400+ members would be error-prone.
- **No prices or performance.** Deliberately: computing returns from a 45-day-stale range
  midpoint would be a fabricated number dressed up as analysis.

## Regulatory risk

Multiple congressional stock trading ban bills are active, including the ETHICS Act. If
one passes, the underlying data supply for this entire category of app disappears.

## Data source and licence

All data comes from US House Clerk financial disclosure filings, which are public
domain. Every transaction in the app links back to its source PDF.
