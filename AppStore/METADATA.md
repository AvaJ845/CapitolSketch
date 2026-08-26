# CapitolSketch — App Store Metadata (Shipping Record)

This file is the source of truth for the App Store Connect fields. The three limited
fields below are recorded verbatim. They are not to be reworded, re-ordered, or
"improved" without an explicit product decision; see `ASO_PLAYBOOK.md` for the
naming-council record and the 2026-08-25 user override of the Rotunda recommendation.

---

## 1. Limited fields (auditable counts)

| Field | Value | Used / Limit |
| --- | --- | --- |
| Name | `CapitolSketch: Congress Trade` | **29 / 30** |
| Subtitle | `Politician Tracker & Alerts` | **27 / 30** |
| Keywords | `senate,senator,house,insider,lawmaker,disclosure,watchlist,portfolio,stock,free,widget,ticker,filing` | **100 / 100** |

### Count verification

**Name — 29 / 30 (1 character of headroom)**

| Segment | Characters | Running total |
| --- | --- | --- |
| `CapitolSketch` | 13 | 13 |
| `:` | 1 | 14 |
| space | 1 | 15 |
| `Congress` | 8 | 23 |
| space | 1 | 24 |
| `Trade` | 5 | **29** |

Wording, punctuation, and spacing are the user's binding choice. Do not change them.

**Subtitle — 27 / 30 (3 characters of headroom)**

| Segment | Characters | Running total |
| --- | --- | --- |
| `Politician` | 10 | 10 |
| space | 1 | 11 |
| `Tracker` | 7 | 18 |
| space | 1 | 19 |
| `&` | 1 | 20 |
| space | 1 | 21 |
| `Alerts` | 6 | **27** |

Kept as-is. `Politician`, `Tracker`, and `Alerts` do not repeat a token from the new
Name (`CapitolSketch`, `Congress`, `Trade`). Repeating `Congress` or `Trade` here would
waste indexed characters.

**Keywords — 100 / 100 (at the cap, zero headroom)**

There are no spaces after the commas. Apple indexes Name + Subtitle + Keywords as one
string, so tokens already spent above are not repeated.

Dropped from the previous 100/100 string:

- `capitol` — stem-overlaps `CapitolSketch` in the Name
- (the Name now spends `congress` and `trade`, so those never enter this field)

Added to refill the cap after dropping `capitol` (7 characters) and because `stock` is
no longer in the Name:

- `stock` — high-intent term freed by the rename
- `filing` — the unit of content, and +2 characters vs. the previous trailing `news`
  so the field still lands on 100. News remains the secondary *category*, which is a
  browse path, not a keyword-field spend.

| # | Term | Characters | Running total (incl. separators) |
| --- | --- | --- | --- |
| 1 | `senate` | 6 | 6 |
| 2 | `senator` | 7 | 14 |
| 3 | `house` | 5 | 20 |
| 4 | `insider` | 7 | 28 |
| 5 | `lawmaker` | 8 | 37 |
| 6 | `disclosure` | 10 | 48 |
| 7 | `watchlist` | 9 | 58 |
| 8 | `portfolio` | 9 | 68 |
| 9 | `stock` | 5 | 74 |
| 10 | `free` | 4 | 79 |
| 11 | `widget` | 6 | 86 |
| 12 | `ticker` | 6 | 93 |
| 13 | `filing` | 6 | **100** |

Term characters total 88; twelve commas add 12; 88 + 12 = 100.

---

## 2. Fixed facts

| Field | Value |
| --- | --- |
| Home-screen name (`CFBundleDisplayName`) | `CapitolSketch` |
| Bundle identifier | `com.avaresearch.capitolsketch` |
| App Group | `group.com.avaresearch.capitolsketch` |
| Primary category | Finance |
| Secondary category | News |
| Price | Free |
| In-app purchase | None |

### "Free" is load-bearing

The word `free` occupies four of the hundred keyword characters, and "Free." is the
first word of the trust-panel screenshot caption ("Free. No account. No brokerage.").
It is therefore not a temporary pricing decision — it is a shipped claim in two
separate places in the store listing.

Introducing an in-app purchase later would falsify metadata that is already live: the
keyword field would be claiming a search term the app no longer honestly matches, and
the screenshot would be making a promise the binary breaks. Adding an IAP is not a
pricing change for this app; it is a metadata correction that requires pulling the
keyword and re-shooting screenshot 3. Treat "no IAP" as a product constraint, not a
launch-phase choice.

---

## 3. Why each field is what it is

**Name — `CapitolSketch: Congress Trade`.** The user's binding name (29 / 30). Brand
first on the Home Screen (`CapitolSketch`); the Name field still carries the two
highest-intent category words that fit, `Congress` and `Trade`. The colon split keeps
the perishable category words in the editable Name field. See `ASO_PLAYBOOK.md`.

**Subtitle — `Politician Tracker & Alerts`.** Indexed for search and read by humans on
the results page. It picks up "politician", "tracker", and "alerts" — none of which
appear in the Name, and none of which are repeated in the keyword field.

**Keywords — the 100-character field.** Every term is either a synonym the Name and
Subtitle do not already cover (`senate`, `senator`, `house`, `lawmaker`, `insider`,
`disclosure`, `filing`), a feature a searcher may look for directly (`watchlist`,
`portfolio`, `widget`, `ticker`, `stock`), or a qualifier that filters for our actual
audience (`free`). `senate` and `senator` both appear because they are distinct search
tokens. No term duplicates a word already present in the Name or Subtitle.

Note that `senate` and `senator` are forward-looking: v1 is House-only. They are
honest as search terms for the category the app sits in, but the app's own copy must
not claim Senate coverage until Senate filings actually ship.

**Home-screen name — `CapitolSketch`.** The Home Screen only has room for a short
label, and the label the user lives with day to day should be the brand, not the
keyword string.

**Categories — Finance primary, News secondary.** The app is about securities
transactions, so Finance is where the intent is. News is the honest secondary: the unit
of content is a newly disclosed filing.

---

## 4. Perishable vs. permanent

The distinction matters because congressional stock-trading ban legislation is active.
If a ban passes, the data supply for this category changes shape or disappears, and
the descriptive half of the Name stops being accurate. The full reasoning is in
`ASO_PLAYBOOK.md` section 1.

**Perishable — editable in a single App Store submission, no listing loss:**

- Name suffix after the colon: `Congress Trade`
- Subtitle: `Politician Tracker & Alerts`
- Keywords: the entire 100-character field
- Screenshots and their caption copy
- Description, promotional text, categories

**Permanent — cannot be changed without losing the listing's accumulated equity:**

- Brand: `CapitolSketch` (and the words before the colon, which *can* actually be
  edited — the Home Screen label and bundle id cannot)
- Home-screen name: `CapitolSketch`
- Bundle identifier: `com.avaresearch.capitolsketch`
- App icon (changeable in principle, but it is the recognition asset)
- Ratings, reviews, and install base, all of which are attached to the bundle
  identifier and would reset to zero on a new listing

The design goal is that a legislative shock touches only the perishable column.
The persisted-data keys (`watchlistTickers`, `appearance`, `seenRowIDs`, …) are
deliberately not branded, so a future rename does not force a migration.
