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

---

## 5. Long-form fields (perishable — editable every submission)

Added 2026-08-31 alongside the v1 screenshot set. These are not keyword-indexed the way
Name/Subtitle/Keywords are, but they carry the same honesty constraints: no cut features
(no practice portfolio, no prediction scoreboard), amounts are always ranges, the
disclosure lag is never hidden, House-only is stated, and nothing reads as advice.

### 5.1 Promotional Text (≤170, editable any time without review)

> Track the stock trades U.S. House members disclose — and get a private alert when one
> trades a ticker you hold. Ranges only, always dated, every row links to the PDF.

Count: 166 / 170.

### 5.2 Description (≤4000)

> **See what the U.S. House of Representatives discloses about its stock trades — and get a private alert when a member trades something you hold.**
>
> CapitolSketch reads the House Clerk's own Periodic Transaction Report filings and lays every disclosed trade out in one plain, chronological feed: who traded, what, when, the dollar bracket, and how many days passed before it was disclosed. Every row links straight to the original PDF so you can check it yourself.
>
> **A watchlist that watches for you**
> Add the tickers you own. When a House member discloses a trade in one of them, CapitolSketch tells you — with a notification that only restates the public filing. Your ticker list never leaves your phone. It is not uploaded as a list, a hash, or a count, and no request the app makes changes based on it.
>
> **Honest about the data, by design**
> • Amounts are ranges. The form only requires a bracket like "$1,001–$15,000," so that is what you see — never an invented exact figure.
> • Everything is already weeks old. The law gives members up to 45 days to disclose. Every entry shows exactly how old it is.
> • Some filings are scanned paper. CapitolSketch runs them through on-device text recognition; whatever it recovers is flagged as lower-confidence, and the rest are counted and shown as missing.
> • No prices, no returns, no "profit." Computing performance from a weeks-old bracket midpoint would be a made-up number. This app does not do it.
>
> **Private and free**
> No account. No sign-in. No ads. No analytics. No brokerage connection. The app downloads one public file of House disclosures — the same file for everyone — and everything else happens on your device.
>
> **On your Home Screen**
> Home Screen and Lock Screen widgets show the latest disclosures, or hits on your watchlist, at a glance. Three app icons to choose from in Settings.
>
> **What this is not**
> Not investment advice. Not a trading app. Not a prediction engine. CapitolSketch tells you something was disclosed. It never tells you what to do about it.
>
> House filings only in this version. Senate disclosures live on a separate system and are not covered yet.
>
> All data comes from U.S. House Clerk financial disclosure filings, which are public domain. Nothing in this app is investment advice.

Count: ~2,180 / 4,000. Headroom left deliberately — a legislative change (see §4) is
edited in here, not bolted on.

### 5.3 What's New

**v1.0 (first release):**

> The first release. The whole U.S. House disclosure feed, a private on-device watchlist
> with alerts, Home Screen and Lock Screen widgets, three app icons, and a link to the
> source PDF on every single trade.

**Template for later updates** (keep it specific, no marketing filler):

> • <what changed, in the user's terms>
> • <data coverage change, if any — e.g. "now recovers X% more scanned filings">
> Every field still links to the source filing.

### 5.4 App Review notes (App Store Connect → App Review Information → Notes)

> No account or login is required. The app opens straight into real data from a bundled
> snapshot and works fully offline.
>
> DATA SOURCE. All content is U.S. House Clerk financial disclosure filings
> (disclosures-clerk.house.gov), which are public domain. There is no third-party API and
> no backend server. On refresh the app downloads (a) one public tab-separated index file
> and (b) individual public PDF filings, directly from the House Clerk. No user data of
> any kind is transmitted; the watchlist never leaves the device.
>
> TO TEST ALERTS. Settings → turn on "Notify me about watchlist trades" and grant
> notification permission. Add a ticker that appears in filings (e.g. NVDA or AAPL) from
> the Watchlist tab. The app checks for matches on launch and when returning to the
> foreground; a local notification fires if an unseen disclosure matches.
>
> TO TEST WIDGETS. Long-press the Home Screen → add a CapitolSketch widget. It renders
> the bundled/downloaded public filing data.
>
> AMOUNTS. Every dollar figure shown is a disclosure bracket (a range), exactly as the
> filing reports it. The app never displays an exact transaction value because that value
> does not exist in this data.
>
> NOT ADVICE. The app restates public records and links to the source PDF for each one.
> It contains no recommendations, no predictions, and no simulated trading.
>
> PRICING. Free, with no in-app purchases.
>
> URL SCHEME. capitolsketch:// (feed / watchlist / members / settings / filing/<id>) — used
> only by the app's own widgets and notifications.

### 5.5 Age rating & privacy

| Field | Value | Note |
| --- | --- | --- |
| Age rating | 4+ | No objectionable content. Outbound links open the House Clerk's public PDFs in Safari. |
| Data collection (Privacy Nutrition Label) | **None** | No data is collected. No tracking. No third-party SDKs. The watchlist and preferences are stored only on-device / in the app's App Group. |
| Account required | No | |
| Sign in with Apple | N/A | No accounts at all. |

---

## 6. Screenshot set — v1 (shot 2026-08-31)

Raw device captures in `Screenshots/appstore-v1/raw/`; captioned marketing frames in
`Screenshots/appstore-v1/`. Built from the Release build with the `-tab-*`,
`-seed-watchlist`, and `-demo-filing` launch arguments. Devices: iPhone 17 Pro Max
(1320 × 2868, satisfies the 6.9" slot) and iPad Pro 13-inch M5 (2064 × 2752).

The four-frame plan in `ASO_PLAYBOOK.md` §4 is superseded by this six-frame set — the
"three badges" trust panel described there was never built; the real
Settings → "What this app is" screen carries the same claims and is what ships.

| # | iPhone frame | Caption | Real content shown |
| --- | --- | --- | --- |
| 1 | Feed | "Every trade the U.S. House discloses" | 10,146 real transactions, real members, range bars, "disclosed N days later" |
| 2 | Watchlist | "Told when they trade a ticker you hold" | Seeded chips (AAPL/BE/MSFT/NVDA), 377 real matches |
| 3 | Disclosure detail | "Every number links back to the filing" | The prominent "View the source filing" action + "transcribed from the source PDF" note |
| 4 | Feed (dark) | "Ranges only. Every row dated." | Dark mode, same real feed, range + lag visible |
| 5 | Settings | "Free. No account. No ads. No tracking." | Appearance toggle, the three-icon picker, "Private by default" copy |
| 6 | Members | "The whole House, in one plain feed" | 128 members, seats, disclosed-trade counts |

| # | iPad frame | Caption |
| --- | --- | --- |
| 1 | Feed (sidebar) | "Every trade the U.S. House discloses" |
| 2 | Watchlist | "Told when they trade a ticker you hold" |
| 3 | Members | "The whole House, in one plain feed" |
| 4 | Settings | "Free. No account. No ads. No tracking." |

Reshoot trigger: any change to the range rendering, the disclosure-lag wording, the
Settings claims, or the app icon.
