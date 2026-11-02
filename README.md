# LibraryShare for Koha 26.05

## 0.2.8 immediate listing visibility

Active items without an existing Koha checkout are now immediately visible, regardless of listing age or the viewer's sharing credits. This applies to upgraded installations too: legacy early-access settings remain stored but are no longer enforced or advertised. Other credits, badges and incentives remain unchanged.

The global available count, browse inventory and direct request eligibility share the active/not-checked-out rule. Browse shows a separate filtered result count (at most 100 per search) and refreshes the global count. Owners can still manage paused or checked-out listings through their own detail page; other viewers cannot request them. Requests still require native sign-in, agreements and circulation eligibility, and reject self-borrowing and duplicate active requests. A request does not require a pre-created pickup slot; scheduling remains a separate step.

Upgrade in place with `LibraryShare-0.2.8.kpz`, reload Koha API/Plack workers and reopen both patron sessions. No production changes or circulation transactions were performed. Local SQL fixtures and source-contract checks do not prove a live two-patron Koha flow; native staging verification remains dependent on access and installation.

## 0.2.7 public navigation and hours diagnostics

- Set Koha's `OPACBaseURL` to the actual public catalog URL. Staff “Open public LibraryShare” now uses this trusted setting. No hostnames or cross-domain cookies are inferred.
- The public catalog must serve `/api/v1/contrib/libraryshare/` through its Koha API handler. Ask the host to verify that specific mapping if the public entry returns a web-server 403/404; do not disable security globally. Existing plugin contrib routes use Koha's native cookie authentication and controller-level patron/ownership/admin checks; this patch does not make private actions anonymous.
- Enable the plugin's OPAC JavaScript hook using the installation's supported plugin settings. It adds the public entry and, when session storage is available, returns to the fixed same-origin app after a successful native patron login. Without the hook/storage, the LibraryShare link remains the manual return route.
- Staff sign-in stays on the staff host; patron sign-in stays on OPAC. Expired API sessions clear the current identity/admin flag and prompt sign-in.
- Opening hours are read through `Koha::Libraries->find(...)->library_hours`. Missing rows, model/service failures and closure-calendar failures have different diagnostics. Existing closed/null hours never imply an open branch; no default hours are invented.

Upgrade in place with `LibraryShare-0.2.7.kpz`, reload Koha API/Plack workers, and reopen the public entry. This workspace does not contain a live Koha database. Local model fixtures do not establish compatibility with your installed schema, and post-installation native patron/staff sign-in and actual branch-hours verification remain required. No production changes or circulation actions were performed.

## 0.2.6 fix for rejected version queries

Corrects a regression in 0.2.5: versioned asset URLs sent `v`, but the seven static OpenAPI operations did not declare that parameter. Koha rejected them before the static controller ran. Each static GET now explicitly accepts optional string `v`. Unknown-parameter validation is not relaxed.

Read-only staging requests reproduced the defect: unversioned app.css returned 200, app.css?v=0.2.5 returned 400 with `Malformed query string` at `/query/v`, and an unrelated unknown parameter also returned 400. Local tests now assert the exact query contract on all seven routes and check bytes/MIME for each with and without a version. The local runtime lacks Mojolicious::Plugin::OpenAPI, so direct Mojo dispatch is **not** claimed as proof of Koha validator acceptance after the fix.

Upgrade in place to 0.2.6 without uninstalling, reload the staging Plack/API workers so they register the new route schema, and open `/api/v1/contrib/libraryshare/static/app.html?v=0.2.6#admin`. Verify 200 responses for versioned files and continued 400 rejection of unsupported query parameters. No database/schema changes are introduced by this patch and no security-policy change is needed for the `/query/v` error. Successful signed-in styling after installation remains to be checked separately; this fix does not establish the cause of the earlier unstyled-page issue.

## 0.2.5 versioned assets and startup diagnostics

All staff/OPAC launch links, the embedded console and its scripts/styles now carry the package version. The static controller sends `Cache-Control: no-store, max-age=0` and `X-LibraryShare-Version`. A visible HTML fallback remains if JavaScript is disabled or blocked; a separate inline watchdog reports failed scripts/styles, script errors and startup timeouts even when the main app cannot initialize. The outer staff workbench waits for a same-origin, same-frame, matching-release startup message instead of hiding its status as soon as bootstrap succeeds.

### Staging host checklist

The observed staging assets matched v0.2.4 byte-for-byte and returned correct MIME types, but were served with `public, max-age=43200`, overriding the origin's revalidation policy. This suggests cache interference; it does not prove the cause of the signed-in user's failure. Public HTML requests encountered security blocks, so signed-in browser evidence is still needed.

After installing this update on staging only, ask the host to:

1. Reload the Plack/API workers serving `staff-mcktest.bywatersolutions.com` and confirm the plugin route registration logs are clean and the installed release is 0.2.5.
2. Purge cached responses for that staging host's `/api/v1/contrib/libraryshare/static/*`, including query-string variants and cached error responses. Remove the twelve-hour cache override for this path and respect the origin's no-store policy. If a host instead retains caching for static files, its cache key must include the complete version query.
3. Inspect a signed-in browser's Network and Console tabs on the staff workbench and the direct console URL `/api/v1/contrib/libraryshare/static/app.html?v=0.2.5#admin`. Verify HTML/JS/CSS return 200, correct content types, and `X-LibraryShare-Version: 0.2.5`; do not mistake an HTML login/challenge page for a script.
4. If blocked, inspect the corresponding request/security logs and actual CSP, frame, MIME or authentication error. Make only a reviewed, staging-specific correction. Do not broadly disable the security layer or change production.
5. Verify session/bootstrap and configuration responses are not publicly cached. These are authenticated dynamic endpoints, not static assets. Hard-refresh, confirm startup completes, and open the item form without submitting it.

Version queries are preventive measures, not a workaround for a host that ignores query strings or blocks legitimate requests. No server configuration is changed by this package.

Verification for this release: 494 local Perl checks passed, plus independent startup-watchdog checks. A browser fixture using the actual HTML confirmed versioned requests, healthy styled startup, blocked-script/stylesheet diagnostics, and opening an unsubmitted item form. The live staging browser stopped at Cloudflare verification before login; credentials were not used and no server was changed. The authenticated staging cause and successful live startup remain unverified.

## 0.2.4 item-value savings

New listings require **Estimated item value ($)**; owners can edit it and it appears on cards and item details. Zero is valid; values must be between 0 and 99,999,999.99 with at most two decimal places. This is an estimate, not a borrowing fee.

Each returned loan contributes **50% of the current listing value**, rounded to cents per loan (half cents round up). Repeated loans count separately. Community reports count a loan once; personal savings remain attributed to the lender. Editing a listing value recalculates past savings and refreshes cached owner totals. There is no claim of measured financial savings.

Existing listings remain **Not set** until owners enter values. Their completed loans still count toward circulation but not savings; reports show the number of unvalued loans. CO₂ calculations, category estimate editing, and CO₂ displays/API outputs are retired, including certificates.

Upgrade in place without uninstalling. The idempotent migration adds a nullable listing value, widens the cached savings total, and rebuilds cached savings using the new formula. Existing circulation, listings, and historical unused impact fields are retained. Reload Koha API workers after upgrading and hard-refresh browsers.

Verification: local unit/contract/static-route checks cover rounding, invalid/zero/unset values, lender attribution, repeated loans, excluded loan statuses, historical recomputation, migration orchestration, and removal of retired runtime outputs. Migration tests use a database double, not a running Koha/MariaDB installation; live upgrade and circulation must still be verified on staging.

## 0.2.3 branch-aware pickup ranges

On an owned listing, choose **Add pickup availability**, enter inclusive first/last dates (up to 93 days), optionally narrow each day's time window, and generate one-hour blocks. Times are library-local, not converted from the browser timezone. Blocks start at the later of branch opening or the optional daily start; incomplete final hours are omitted.

Configure each pickup branch's opening/closing hours in **Koha Administration → Libraries** and its closures in the **Koha calendar**. Missing hours never imply an open branch. Koha's own calendar handles weekly, annual and one-off closures and calendar exceptions; an exception still needs configured opening hours for that weekday.

Past starts and overlapping existing slots are skipped. Repeating a range does not duplicate slots. A zero-result response explains why no new availability appeared. Listing details refresh immediately. Selection and checkout/rescheduling recheck current branch hours and closures. Existing booked meetings are not automatically cancelled when the calendar changes.

This release also fixes malformed minute-only timestamps and replaces the old manual checkout-time form with selection from generated availability. There is no schema migration. Compatibility covers both legacy Koha::Calendar and the newer Koha::Library::Calendar interface; runtime calendar/database failures are not treated as open days.

## 0.2.2 asset delivery and staff appearance controls

Replaces the generic static-file placeholder with explicit routes for extended.js, staff.js and extended.css. Mojolicious placeholders do not match dotted filenames by default; those missing scripts caused initialization and button handlers to fail. Asset regression tests now fetch every script and stylesheet referenced in the actual HTML and verify bytes and MIME types.

Staff → Branding includes Sunny, Ocean and Forest presets, font style, rounded/square corners, comfortable/compact density, existing custom colors, and local live preview. Save publishes changes for all members; Cancel preview and Reset to saved do not write to the database. Existing explicit colors remain in effect until staff change them.

## 0.2.1 route-loading correction

Version 0.2.0 used a reserved Mojolicious path parameter (`action`), which can interrupt API route construction, and omitted explicit controller namespaces. Upgrade to 0.2.1; do not use 0.2.0. The corrected paths have identical public URLs, so bookmarks do not change. If stale routes remain after upload, the hosting administrator must reload the staging Koha Plack/API workers. Do not uninstall or delete plugin tables to apply this update.

Executable routing regression tests now construct and dispatch every plugin route using real Mojolicious with stub actions. These prove routing, not live Koha circulation.

Patrons list items they own, agree pickup meetings, and lend to other patrons. Listings create actual Koha catalog/item records. Scheduling an accepted request creates a Koha checkout; the owner confirms return through Koha check-in.

Version 0.2.0 adds photos, profiles, agreements, full editing, facets, wanted matching, handoff history/rescheduling, moderation, reports, branding, configurable badges/challenges/incentives, impact reporting and circulation reconciliation. See `CONVERSION_STATUS.md` for implementation coverage, remaining differences and verification limits.

## Install on staging first

1. Enable Koha plugins and install with a Koha plugin-management account.
2. Create the patron-owned item type, recommended `PEERLEND`, and configure circulation rules for it.
3. Build: `bash plugins/koha-libraryshare/build.sh`.
4. Upload `generated-artifacts/LibraryShare-0.2.8.kpz` through Koha plugin administration.
5. Open the plugin tool. Its administration console uses the authenticated Koha session. Configure the item type, loan defaults and local settings.
6. Configure Koha's absolute `upload_path`. The instance user must be able to create/write its `libraryshare` subdirectory. Back up this directory together with the Koha database. Photos are not stored inside the KPZ.
7. Replace the clearly marked sample terms and waiver with library-approved documents. Publish a new version whenever changing an accepted agreement.
8. Enter estimated values on item listings. Savings reporting uses 50% of each current value per completed loan; items without values are excluded from monetary totals.
9. Sign into the OPAC and open LibraryShare. Verify create → request → accept → schedule → checkout → reschedule → return with two staging patrons.

The package uses Module::Bundled::Files: SQL, API specifications, templates and static files live beside its helper modules under `Koha/Plugin/Com/LibraryShare/` inside the archive. Earlier root-level resource packages must be replaced with this build.

## Maintenance

The staff credit/recompute control reconciles returns made directly by Koha staff and recomputes derived statistics. For nightly operation, run the installed `Koha/Plugin/Com/LibraryShare/bin/reconcile.pl` as the Koha instance user, with the same `KOHA_CONF` and `PERL5LIB` used by that instance's other cron jobs. Add the plugin install directory to `PERL5LIB` if needed. Do not run it with another instance's database configuration.

Back up the database and upload directory before installing/upgrading. Uninstall deliberately retains LibraryShare and Koha circulation data; it is not a data-deletion tool.

## Behavior and safety

- Pickup timestamps use the Koha server's local time.
- Real circulation rules are checked before checkout; blocks or required staff confirmations are not silently overridden.
- Requests are serialized per listing. Only the owner can cancel an already checked-out handoff, and check-in verifies the expected issue and borrower.
- Credits use stable event keys. Reconciliation does not create extra completed-loan credits.
- Photos: JPEG, PNG or WebP, up to 5 MB and six per listing/review. The reverse proxy and Mojolicious request-size limits must permit the base64 JSON upload (roughly 7 MB).
- LibraryShare administrators cannot grant Koha-wide permissions. Only Koha plugin managers can assign LibraryShare administrator roles.
- Custom CSS is a trusted-admin capability; external logo/asset URLs can contact third parties.
- Early-access defaults follow the original app: new listings are visible first to owners and members with enough credits. Staff can set the window to zero.
- Catalog creation currently targets MARC21. A local required-field framework must be tested.

## Checks

```sh
prove plugins/koha-libraryshare/tests/*.t
bash plugins/koha-libraryshare/build.sh
```

There is no live Koha runtime here. These checks do not establish successful installation or circulation on your server. The original destructive demo reset remains a difference; see the coverage document.

MIT. Original license retained in `LICENSE`.
