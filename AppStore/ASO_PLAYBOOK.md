# CapitolSketch — Naming Council Decision and ASO Playbook

This file records why the app is named what it is named, what was ruled out and on
what evidence, and what the four launch screenshots must contain. The shipping field
values themselves live in `METADATA.md`.

---

## 0. User override (2026-08-25)

The naming council recommended **`Congress Stock Trades: Rotunda`**. On 2026-08-25 the
user overrode that recommendation in favor of:

**`CapitolSketch: Congress Trade`** (29 / 30)

Home-screen display name: **`CapitolSketch`**. Bundle id:
`com.avaresearch.capitolsketch`. App Group: `group.com.avaresearch.capitolsketch`.

The collision-check record below (Cloakroom, Quorum, Roll Call, Docket, Tally,
Bellwether, Argus, Ledger) is still useful — those names remain disqualified. The
Rotunda recommendation is retained as history, not as the shipping name.

### Live App Store collision check for the shipping name (2026-08-26)

Queried Apple's search API (`itunes.apple.com/search`, `entity=software`, `country=us`):

| Query | Result count | Exact-name match |
| --- | --- | --- |
| `CapitolSketch` | 31 | **None** |
| `Capitol Sketch` | 30 | **None** |

No listing is named `CapitolSketch` or `Capitol Sketch`. Near-misses, none in the same
job-to-be-done:

- **CapitolCanary Intelligence** — advocacy/intel SaaS companion (Productivity)
- **CapitolConnect Illinois** — state-level lobbying (Business)
- **Capitol Hill Club** — private club (Lifestyle)
- **The Capitol Morning Report** — California political newsletter (News)
- Drawing apps matching `Sketch` (`Sketch Mirror`, `Infinity Sketch`, `iSketch`, …)

**No hard collision.** Soft "Capitol…" crowding exists in News/Reference; the compound
`CapitolSketch` is unclaimed. The name is applied as specified.

---

## 1. The chosen name, and the structural reason for it

**Shipping: `CapitolSketch: Congress Trade`** (29 / 30 characters).

The name is built as two halves joined by a colon:

- **`CapitolSketch`** — the permanent half. It carries the brand. It is what appears on
  the Home Screen, what people say out loud when they recommend the app, and what the
  icon means.
- **`Congress Trade`** — the perishable half. It carries the search keywords that still
  fit after the brand. These are words a person actually types, and they are why the
  listing is findable at all.

The council's original recommendation was **`Congress Stock Trades: Rotunda`** (30 / 30),
with the descriptive half first. The structural reason for the colon split still holds
under the override; only which half is the brand changed.

The reason for the split is legislative risk, and it is the most important structural
decision in this document.

Multiple congressional stock-trading ban bills are active, including the ETHICS Act. If
one of them passes, the underlying data supply for this entire app category disappears
or changes shape. Members would no longer be filing the same Periodic Transaction
Reports describing the same individual trades, and an app whose name literally reads
"Congress Trade" would be describing a thing that no longer exists. This is not
a hypothetical tail risk to insure against cheaply; it is an openly debated policy
outcome with named bills behind it.

The App Store **Name is an editable field**. It can be changed with an ordinary app
submission. So by putting the perishable, category-describing words into that editable
field, the migration path is a single submission: the suffix is swapped for whatever
the app has become, and everything that took years to accumulate survives untouched —
the brand, the app icon, the bundle identifier, the App Store ratings and reviews, and
the entire install base. Existing users see the app they already have; its Home Screen
label never changed, because the Home Screen label is `CapitolSketch`.

Compare the alternative. Had the perishable words been pushed down into the bundle
identifier (something like `com.avaresearch.congressstocktrades`) or baked into the
app icon artwork, they would have become effectively immovable. A bundle identifier
cannot be changed on a shipped app; changing it means publishing a **new** App Store
listing, which starts at zero ratings, zero reviews, zero ranking history, and zero
installs, with no supported way to carry existing users across. A category-defining
legislative change would then cost the entire accumulated store equity of the product.

The colon construction buys the search value of the descriptive words while keeping
them in the one field that is cheap to change. That is the whole trade, and it is why
the name looks the way it does.

---

## 2. Hard disqualifications

Each of the following was considered as the brand half and ruled out. None of these
are close calls; each has concrete evidence against it.

| Candidate | Evidence | Verdict |
| --- | --- | --- |
| **Cloakroom** | `cloakroomai.com` is a live congressional STOCK Act tracker — the same product, in the same category, shipping today. | Disqualified. Direct collision. |
| **Quorum** | QuorumCivic is an existing congressional tracker. Separately, there is a credit-union app named Quorum in the Finance category carrying roughly 5,166 ratings. | Disqualified. Two independent collisions. |
| **Roll Call** | Existing trademark of FiscalNote. | Disqualified. Trademark. |
| **Docket** | Exact-name match already on the App Store. | Disqualified. |
| **Tally** | Exact-name match already on the App Store. | Disqualified. |
| **Bellwether** | Exact-name match already on the App Store. | Disqualified. |
| **Argus** | Exact-name match already on the App Store. | Disqualified. |
| **Ledger** | Exact-name match already on the App Store. | Disqualified. |

Two of these deserve a note beyond the table.

**Cloakroom** was the strongest word of the set on pure aesthetics — it is a real
Capitol place name, it is evocative, and it carries exactly the right connotation of
things happening just out of public view. It is also taken, by a product doing the
same job we are doing. Shipping under a name a live competitor in the identical
category already uses is not a branding risk to be managed; it is a guarantee of
permanent confusion, in a search results page where we would be the one explaining
ourselves.

**Quorum** fails on the harder of its two collisions. The congressional-tracker
overlap with QuorumCivic is bad enough on its own, but the credit-union app is worse:
it is an established Finance app with thousands of ratings sitting on the exact word.
Finance is our primary category. Trying to out-rank roughly 5,166 ratings on a
single-word search term, from a cold start, is not a fight that gets won by better
metadata. There is no version of that competition we win.

---

## 3. Runners-up

Two names survived to the final round alongside Rotunda. Both would have taken the
same structural form: `Congress Stock Trades: <brand>`.

**`Congress Stock Trades: Caucus`.** Pronounceable, short, unmistakably congressional,
and easy to remember. It lost on connotation. A caucus is a partisan grouping — the
word's primary meaning is a bloc of members organized by party or faction. For an app
whose entire credibility rests on being a neutral reader of public filings that reports
what both parties disclose without editorial framing, naming it after a partisan
structure works against the product. The name would be quietly arguing with the
positioning.

**`Congress Stock Trades: Cloture`.** The most distinctive word of the three and almost
certainly unclaimed, but it lost on two counts. It is a procedural term for ending
debate, which means it describes a parliamentary mechanic that has nothing to do with
what this app does — the metaphor does not land even for people who know the word. And
most people do not know the word: it is hard to pronounce on first sight, and a name a
user cannot confidently say out loud is a name that does not get recommended.

**Rotunda was the council's pick.** It is a neutral architectural place inside the Capitol — a room, not a
procedure and not a faction. It is non-partisan by construction, since a room does not
belong to a party. It is immediately pronounceable by anyone who reads it, it is
memorable, it evokes the right institution without claiming any affiliation with it,
and it is unclaimed in this category. It also gives the icon an obvious and ownable
visual subject.

**The user overrode that pick on 2026-08-25** in favor of `CapitolSketch`. The reasoning
above is kept so a later rename has the record of what was checked. See section 0.

---

## 4. Screenshot plan

> **2026-08-31 update.** The four-frame plan below is superseded by the shipped
> six-frame iPhone / four-frame iPad set recorded in `METADATA.md` §6, captured from the
> current build. Frame 3's "trust panel with three badges" was never built — the real
> `Settings → What this app is` screen carries the same literal claims and is what ships.
> The **accuracy constraints in this section still bind every frame**: real parsed House
> filings only, amounts shown only as brackets, the disclosure lag always visible, and
> neither cut feature (practice portfolio, prediction scoreboard) anywhere in frame.

### Cut features — must not appear anywhere

Two features were **cut** from this product and must not appear in any screenshot, any
caption, the description, the promotional text, or the keyword field:

1. **The practice portfolio.** Cut. No simulated trading, no paper positions, no
   "what if you had followed this member" balance.
2. **The "Call it, keep score" prediction scoreboard.** Cut. No predictions, no
   accuracy tracking, no leaderboard.

This is stated first and prominently because both features are visually appealing and
both would be tempting to mock up for a screenshot. Showing either would advertise
functionality the binary does not contain, which is a review rejection and a
misrepresentation of the app.

### The four frames, in order

Exactly four frames ship, in this order, with this caption copy.

---

**Frame 1 — The real, dense filing feed**

> Caption: **"Every trade Congress discloses."**

What must be genuinely real in the capture: the feed must be actual filings parsed from
real US House Clerk Periodic Transaction Report PDFs. Real member names, real tickers,
real transaction dates, real filing dates. No mock rows, no placeholder tickers, no
invented members.

The word "dense" is the point of the frame. This screenshot's job is to prove there is
substantial content behind the app, so the capture should be a scroll position where the
feed is genuinely full, not an artificially tidy three-row state.

Two accuracy constraints apply to what the rows show. Amounts are **disclosure brackets
(ranges)**, exactly as the PTR reports them — the capture must never display an exact
dollar figure, because exact figures do not exist in this data. And the filings will be
weeks old relative to the transaction dates, because the STOCK Act allows members up to
45 days to disclose. That lag must be visible and unhidden in the capture; do not stage
a feed that implies real-time reporting.

---

**Frame 2 — Lock Screen watchlist alert**

> Caption: **"Alerts when they touch your ticker."**

What must be genuinely real in the capture: an actual Lock Screen notification from the
app on a real device, fired by a real parsed filing for a ticker on a real watchlist.
The member, ticker, and transaction in the alert must correspond to an actual
disclosure. No composited or mocked-up notification banner.

This frame carries the app's core value proposition — the app watches on the user's
behalf so they do not have to check it — so the alert copy in the capture must match
what the shipping notification actually says.

---

**Frame 3 — Trust panel**

> Caption: **"Free. No account. No brokerage."**

The frame shows the in-app trust panel with its three badges: **"No account"**,
**"No brokerage"**, **"On-device"**.

What must be genuinely real in the capture: this must be a real screen that exists in
the shipping app, not a marketing graphic assembled in a design tool. Every badge is a
literal claim about the binary and each one must hold: there is no account and no
sign-in, there is no brokerage connection, and the user's watchlist of tickers never
leaves the device.

"On-device" refers to the watchlist and the user's data. The app does download one
public file of House disclosures — the same file for everyone, containing no user
information — and ships with a bundled snapshot of public filings. That distinction
should not be blurred in the capture; the badge is about user data staying local, and
it is true.

This is also the frame where "Free" becomes a shipped claim in the screenshots as well
as the keyword field. See the note in `METADATA.md` on why that forecloses adding an
in-app purchase later.

---

**Frame 4 — Widgets on a real Home Screen**

> Caption: **"A once-a-day read, on your Home Screen."**

What must be genuinely real in the capture: real widgets rendering real parsed filing
data, placed on an actual iOS Home Screen, captured from a device. Not a rendered
mockup of a Home Screen, and not widgets showing placeholder content.

The caption sets an honest expectation about cadence. The data updates on the timescale
of disclosure filings, not the timescale of a market feed, so the app is positioned as
something worth glancing at once a day. The widget content in the capture must be
consistent with that — the same bracket amounts and the same disclosure lag that appear
everywhere else in the app.
