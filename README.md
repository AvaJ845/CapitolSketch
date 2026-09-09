# CapitolSketch

An iOS app that tracks stock trades disclosed by members of the US Congress, with a
personal watchlist that tells you when a member trades a ticker you hold.

House and Senate. Read-only. No brokerage, no account, no analytics. Nothing here is
investment advice. Senate paper filings are counted but not machine-readable (see
[Known limitations](#known-limitations)).

App Store name: **CapitolSketch: Congress Trade**. Home Screen: **CapitolSketch**.

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — the system, the code, the build pipeline, the runtime data flow (diagrams).
- [`SECURITY.md`](SECURITY.md) — attack surface and how to report a vulnerability.
- [`LICENSE`](LICENSE) — source is published for review; it is not licensed for reuse.

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

So the app covers the whole Congress, treats Pelosi as one member among many, and competes
on something Autopilot does not sell: a read-only, ad-free, no-brokerage-connection view
with alerts scoped to *your* holdings.

## Architecture

Full diagrams — system, code layers with the `SEEDGEN` compile boundary, the build &
release pipeline, and the runtime sequence — are in [`ARCHITECTURE.md`](ARCHITECTURE.md).
The layout:

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

There is no backend, and the shipped app talks to nothing but the House Clerk (Senate
data arrives baked into the snapshot; the on-device incremental refresh stays House-only).
`seedgen` reads the trade data straight from primary sources (the Clerk's index and PDFs;
the Senate eFD when `--senate` is set) and ships the result as a bundled JSON snapshot. Two
things it cannot get from a primary source — the Bioguide ID crosswalk that turns a
printed name and seat into a stable identifier, and full-committee assignments — come
from the community-maintained `unitedstates/congress-legislators` dataset. Both are
resolved once, at build time, on a Mac; neither dataset ships to the device, and a
member the crosswalk cannot place degrades gracefully (fallback ID, empty committee
list). On device, an incremental refresh asks the House Clerk's own public index which
filings have appeared since and reads only those PDFs. The widget refreshes the same way
from `getTimeline` via URLSession. There is no `BGTaskScheduler`.

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
swift run seedgen --years 2025,2026 --senate --out ../../CapitolSketch/Resources/seed-filings.json
```

Options: `--senate` to fold in Senate eFD PTRs (drop it for a House-only snapshot),
`--limit N` to process only the N most recent filings, `--concurrency N` for parallel
downloads (default 6; be polite to the Clerk's servers), `--cache DIR` to reuse
downloaded PDFs across runs, `--pretty` for readable JSON.

The pipeline:

1. Download `https://disclosures-clerk.house.gov/public_disc/financial-pdfs/{year}FD.txt`
   and keep the rows with `FilingType == "P"` (Periodic Transaction Report).
2. Fetch each PTR PDF and extract text with PDFKit.
3. Load the `congress-legislators` crosswalk (`legislators-current`,
   `legislators-historical`) and resolve each filer to a Bioguide ID, a party, and
   (for the members list) the name they go by.
4. Load the `congress-legislators` committee files (`committees-current`,
   `committee-membership-current`) and attach each member's full-committee assignments,
   by Bioguide ID, as plain names. Never matched against a traded company. A copy of
   these two files is checked in under `Tools/PTRKit/Sources/PTRKit/ReferenceData/` as an
   offline floor; a networked build always prefers a fresh fetch.
5. Parse transaction rows and emit a single JSON feed.

With `--senate`, an extra pass reads the Senate eFD portal for electronic PTRs since
Jan 1 of the earliest `--years` year, resolves each senator by name (the eFD carries no
identifier), parses the HTML report, and folds the rows into the House feed before
de-duplication. Paper filings are counted and recorded as unreadable.

Current snapshot: **~12,700 transactions from 164 members** (House + Senate) across
2025–2026, with party for every resolved member and committee assignments where the
roster has them.

## Building the app

```bash
xcodegen generate
open CapitolSketch.xcodeproj
```

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Xcode 26 / iOS 18+
deployment target. The `.xcodeproj` is generated and git-ignored — never hand-edit it,
regenerate it from `project.yml`. Signing uses the team in `project.yml`
(`DEVELOPMENT_TEAM`); to build against your own, add a git-ignored `Local.xcconfig` or
override it in Xcode rather than committing the change.

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

Senate electronic PTRs come from the eFD portal as HTML, not PDF, so they take a separate
parser (`SenatePTRParser`) but land in the same `Trade` model. Senate *paper* PTRs are
scanned images with hand-marked amount brackets that OCR cannot read reliably; `seedgen`
counts them and records the gap, the same as an unreadable House scan.

## Known limitations

These are real and worth stating plainly:

- **Senate electronic only.** Senate PTRs filed electronically are covered. Senate *paper*
  PTRs — a hand-marked scan, roughly 5–10% of Senate filings — cannot be machine-read;
  they are counted and disclosed on the data-quality screen but their transactions are not
  in the feed, the same treatment as an unreadable House scan.
- **Some filings yield nothing.** They are scanned paper documents (House or Senate) with
  no extractable text. Those transactions are simply missing, and the count is shown in
  Settings.
- **Everything is stale by design.** Members have 45 days to disclose. Median observed
  lag is 28 days; 16% of filings exceed the 45-day limit. This is inherent to the data,
  not a bug, and the UI says so on every screen.
- **Amounts are ranges, not values.** The form only requires a bracket like
  "$1,001 – $15,000". Any total or ranking built on these is an estimate.
- **A few filings contain impossible dates** — a transaction date after the filing date,
  almost always a mistyped year. These are shown exactly as filed and flagged in the UI
  rather than silently corrected.
- **No prices or performance.** Deliberately: computing returns from a 45-day-stale range
  midpoint would be a fabricated number dressed up as analysis.
- **Party is from the crosswalk, not the filing.** The Clerk index carries no party;
  `seedgen` reads it from the same `congress-legislators` dataset it uses for Bioguide
  IDs and committees, and bakes it into the seed. Shown as a plain "D" / "R" / "I" tag,
  never a colour, never aggregated. A member the crosswalk did not place shows no tag.

## Regulatory risk

Multiple congressional stock trading ban bills are active, including the ETHICS Act. If
one passes, the underlying data supply for this entire category of app disappears.

## Data source and licence

All trade data comes from US House Clerk and US Senate financial disclosure filings, which
are public domain. Identifier and committee reference data is from
`unitedstates/congress-legislators` (CC0). Every transaction in the app links back to its
source — a House Clerk PDF or a Senate eFD page.

The **code** in this repository is published for transparency and review, not for reuse —
see [`LICENSE`](LICENSE). © 2026 Ava Research LLC, all rights reserved.
