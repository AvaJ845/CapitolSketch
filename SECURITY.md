# Security

## Reporting a vulnerability

Email **avaresearchLLC@gmail.com** with "SECURITY" in the subject. Please include
what you found, how to reproduce it, and the impact you see. Expect an
acknowledgement within 72 hours.

Please do **not** open a public issue for a security report.

## What is in scope

- The iOS app and widget (`CapitolSketch/`, `CapitolSketchWidget/`, `Shared/`).
- The shared core (`Packages/DisclosureKit/`).
- The build-time ingestion tool (`Tools/PTRKit/`, `seedgen`).
- The committed data snapshot (`CapitolSketch/Resources/seed-filings.json`) — e.g.
  a parsing flaw that lets a malformed source filing inject misleading rows.

## Design facts that bound the attack surface

These are enforced by architecture, not policy (see `ARCHITECTURE.md`):

- **No backend.** There is no server owned by this project. Nothing to breach, and
  no endpoint that accepts user input.
- **No account, no analytics, no third-party SDK.** The Privacy Nutrition Label is
  *None*. The watchlist and preferences never leave the device; they live in a
  `UserDefaults` App Group container.
- **The shipped binary contacts exactly one host:** `disclosures-clerk.house.gov`
  (plus `fd.house.gov` for user-tapped reference links). All requests are HTTPS
  and App Transport Security is strict (`NSAllowsArbitraryLoads` = false). No
  request's shape depends on the watchlist or the reader's identity.
- **No secrets in the repo or the binary.** There is no API key to embed — the app
  reads a free, public, key-less government index. The Senate eFD scraper and the
  `congress-legislators` crosswalk run only in `seedgen`, on a Mac, at build time;
  their code is `#if SEEDGEN`-gated out of the iOS build entirely.
- **No dynamic code, no `BGTaskScheduler`, no push.** The app runs only while open
  or when its widget timeline fires.

## Supported versions

Only the latest App Store / TestFlight build is supported. Fixes ship in a new
build, not as patches to older ones.
