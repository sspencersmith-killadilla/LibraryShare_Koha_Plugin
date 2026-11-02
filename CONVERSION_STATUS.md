# Conversion coverage — 0.2.8

Public/staff navigation now resolves from OPACBaseURL, and the OPAC launcher can resume a fixed same-origin app after login. Branch hours use the Koha library model with separate service/configuration errors. Native authenticated flows and actual branch/schema compatibility still need post-installation staging verification; local fixtures are not live Koha proof.

All seven static routes declare the optional version query parameter required by Koha validation. Staging reproduced the previous missing-parameter error; post-upgrade validator acceptance remains a live verification step. Local tests separately cover schema contracts and static delivery.

Static asset URLs are release-versioned. Standalone and embedded startup diagnostics report asset failures without depending on the main app script; actual Koha host cache/security rules remain outside the package.

Pickup availability now accepts inclusive date ranges and generates complete one-hour blocks using branch opening hours and the Koha calendar. It skips past/overlapping slots and revalidates closures when selecting or booking. Unit tests exercise range generation; live branch configuration and checkout still require validation after installation.

Source: supplied MIT-licensed LibraryShare application. Target: Koha 26.05.
“Implemented” below means source and UI exist, not that live Koha integration has passed.

| Original area | Native plugin implementation |
|---|---|
| Card/PIN authentication | Existing Koha OPAC session, no duplicate credential store |
| Listings | Create/edit/pause/resume/remove, catalog/item creation, catalog title/author updates, photos, detail pages |
| Discovery | Search, category/condition/branch/location/date filters, pickup availability; no credit-based visibility delay |
| Borrowing | Requested dates and message, acceptance/decline, prioritized incoming queue, eligibility indicators |
| Circulation | Koha checkout/check-in, preflight circulation checks, loan-day perk limits, per-listing lock and shared transaction |
| Handoffs | Slots, meeting location, reschedule, cancellation, event history, participant messaging |
| Returns | Owner confirms return; reconciliation also recognizes check-ins performed by staff in Koha |
| Reviews | Ratings, written reviews, review photos, moderation |
| Wanted | Posts, interests, close/reopen, matching, prefill, linked fulfilment |
| Dashboard | Requests, own listings, notices, bulk read/dismiss, account statistics |
| Profiles | Reviews, kudos, lender/borrower levels, badges, progress, leaderboard privacy |
| Gamification | Original tier thresholds and badge definitions, configurable badges, challenges, deduplicated credits, manual adjustments |
| Perks | Early visibility, priority ordering, longer loan allowance, fast-track eligibility displayed to lender (not an automatic approval bypass) |
| Legal | Original sample terms/waiver, help, versioned publishing, acceptance history, lending gates; replace samples before production |
| Branding | Sunny/Ocean/Forest presets, fonts, corners, density, preview/save/cancel, names, text, colors, logo/favicon URLs, library links, trusted-admin CSS |
| Administration | Listing/review/photo/kudos moderation, reports, plugin roles, audit records, diagnostics and settings |
| Savings | Monthly/category/branch tables, 50% of per-listing values per returned loan, unvalued-loan count, community goal/milestone, featured lender |
| Sharing | Downloadable PNG/HTML certificate and browser print-to-PDF |
| Maintenance | Staff reconciliation control and standalone nightly reconciliation script |

## Remaining differences / acceptance limits

- The original destructive demo snapshot/reset system is **not implemented**. Resetting plugin tables while real Koha checkouts and catalog records survive would corrupt circulation relationships. An isolated Koha demo-instance workflow is still needed for equivalent demo restoration.
- Analytics are accessible tables rather than reproductions of every original chart.
- Catalog creation currently assumes a MARC21 framework; non-MARC21 installations require adaptation.
- Native Koha sessions and in-process circulation deliberately replace the original external Koha connection/card-PIN configuration.
- Per user request, CO₂ tracking is removed and savings use 50% of the current estimated listing value per completed loan. Existing listings remain unset until owners supply a value.
- No live Koha runtime or MariaDB installation is available in this workspace. Installation, SQL execution, cookie authentication, staff permissions, upload filesystem permissions and circulation must pass on a staging Koha 26.05 instance before production use.

## Verification performed

- Perl syntax with minimal Koha dependency stubs: syntax only, not runtime assurance.
- Static API/schema contracts and pure level-boundary unit tests.
- Executable Mojolicious route construction/dispatch tests with stub actions, including the reserved-parameter regression.
- Actual static-controller tests fetch every HTML-referenced asset and verify status, MIME type and exact bytes.
- JavaScript syntax checks.
- Design-helper Chromium checks using fixture responses: navigation/forms/payloads/branding, not live Koha.
- KPZ archive checks: correct Module::Bundled::Files layout, required resources and no uploaded credentials.

This is an expanded conversion candidate, **not a certified feature-for-feature production release**.
