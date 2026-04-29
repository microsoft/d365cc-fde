# Changelog — Recording Search

All notable changes to this project are documented here.
Format: `[version] YYYY-MM-DD — summary`

---

## [1.4.1] 2026-04-29 — More filters split into two rows

### Changed
- "More filters" panel now uses two rows instead of one:
  - Row 1: Queue, Workstream, Direction, Sentiment
  - Row 2: Duration, Recordings only, Transferred

---

## [1.4.0] 2026-04-29 — Filter panel redesign

### Changed
- **Primary filters** (Date, Agent, Phone, Contact + Search/Clear) always visible in two compact rows
- **Secondary filters** (Queue, Workstream, Direction, Sentiment, Duration, Recordings Only, Transferred)
  moved into a collapsible "More filters" panel, collapsed by default
- "More filters" toggle shows a blue count badge when any secondary filter has a value
  (e.g. "More filters ③") and auto-opens the panel when filters are restored from session cache
- Search and Clear buttons promoted to the primary row for quicker access

---

## [1.3.4] 2026-04-29 — Fix queue dropdown showing personal queues

### Fixed
- Queue dropdown now filters to public queues only (`queuetypecode eq 1`),
  removing the auto-generated personal/default queues that appear with `<` characters in their names

---

## [1.3.3] 2026-04-29 — Recordings only unchecked by default

### Changed
- "Recordings only" checkbox no longer checked on load — all conversations shown by default

---

## [1.3.2] 2026-04-29 — Version bump / redeploy

---

## [1.3.1] 2026-04-29 — Caller number now populated via phone call context

### Fixed
- Caller Number column and detail panel now show the actual ANI (caller's phone number).
  Previously blank because `msdyn_calleridnumber` doesn't exist in this environment.

### How it works
- After fetching conversations, a batch query fetches `msdyn_ocphonecallengagementctx`
  records linked by `_msdyn_liveworkitemid_value` and builds a `phoneMap` (convId → ANI).
- Display uses `msdyn_fromphone` (dedicated ANI field); falls back to `msdyn_callername`.
- Phone number search filter now queries `msdyn_ocphonecallengagementctxes` via
  `contains(msdyn_fromphone, '...')` → extracts conversation IDs → intersects with other filters.
  No longer dead-ends with "not available" error.
- `phoneMap` saved to and restored from session cache.

---

## [1.3.0] 2026-04-29 — Expanded filter panel

### Added
- **Date quick-select** — preset dropdown (Today / Yesterday / Last 7 days / Last 30 days /
  Last 90 days / This month / Last month) as an alternative to manual date pickers.
  The two modes are displayed as side-by-side cards with a blue left-accent on the active card
  and dimmed inactive card — visually obvious which mode is in use.
- **Queue filter** — dropdown populated from Dataverse `queues` entity on load; adds
  `_msdyn_cdsqueueid_value eq {guid}` OData filter server-side.
- **Workstream filter** — dropdown populated from `msdyn_liveworkstreams` on load;
  adds `_msdyn_liveworkstreamid_value eq {guid}` OData filter server-side.
- **Direction filter** — All / Inbound / Outbound; adds `msdyn_isoutbound eq true/false` server-side.
- **Sentiment filter** — All / Positive (≤9) / Neutral (10) / Negative (≥11);
  uses `msdyn_customersentimentlabel` server-side.
- **Duration range** — Min and Max inputs in minutes; converted to seconds for
  `msdyn_conversationhandletimeinseconds ge/le` OData filter server-side.
- **Transferred toggle** — client-side checkbox (like Recordings only); filters to
  conversations where `msdyn_transfercount > 0` without re-querying.
- All new filters saved to and restored from session cache.

### Changed
- `$select` on conversation query extended to include `msdyn_conversationhandletimeinseconds`,
  `_msdyn_cdsqueueid_value`, `_msdyn_liveworkstreamid_value`, `msdyn_customersentimentlabel`,
  `msdyn_transfercount`.
- Duration column sort now uses `msdyn_conversationhandletimeinseconds` (seconds) as primary
  sort key with `actualdurationminutes` as fallback (the former is consistently populated).
- Minimum-filter validation removed — date is always set via preset, so a date-only search is valid.

---

## [1.2.0] 2026-04-29 — Sortable column headers

### Added
- Click any column header (Date/Time, Duration, Agent, Caller Number, Contact, Channel, Recording)
  to sort results by that column; click again to reverse direction
- Active sort column highlighted in blue with ▲/▼ arrow indicator
- Default sort: Date/Time descending (newest first)
- Sort state persisted in session cache — survives CSW tab switches

---

## [1.1.9] 2026-04-28 — Sync from CCIVR (merged remote → local)

Adopted the version deployed to the CCIVR environment as the new local baseline.
Intermediate versions (v1.0.1 – v1.1.9) were built and deployed directly from that environment.

### Changed
- Recording URI field updated to `msdyn_mediauri` (env-specific; was `msdyn_recordinguri`)
- Recording start/end/duration fields cleared — not present in this env; `createdon` used as date fallback
- `showState()` simplified: uniform `el.hidden` toggle, no special-casing for Results state
- `stateResults` div now uses `.state-results` CSS class instead of inline flex styles
- All state placeholder divs (initial/loading/error/no-results) now use `.state-box` class
- Result rows: `cursor: pointer`; clicking a row opens the conversation in Dynamics
- `openInDynamics()` upgraded — tries `Microsoft.Apm.createSession` first (proper CSW session tab),
  falls back to `Xrm.Navigation.navigateTo`; entity name corrected to `msdyn_ocliveworkitem` (singular)

### Added
- **Recordings-only (server-side inner-join mode)** — when "Recordings Only" is checked, pre-queries
  `msdyn_ocrecordings` by date range to get conversation IDs that have recordings, then filters the
  main conversation query to those IDs (true inner-join, not client-side filter)
- **`fetchAllRecordingsWithConvIds()`** — new function for the recordings-first pre-query
- **Batched recording fetch** — `fetchRecordingsForConvs` now batches in groups of 10 to avoid
  URL-too-long errors (was single query)
- **Session cache** — `saveToSession()` / `restoreFromSession()` persist search results in
  `sessionStorage` for 10 minutes; results survive CSW tab switches (iframe reloads)
- **`recOnly` checkbox defaults to checked** on load (matches FetchXML inner-join behaviour)
- Debug `console.log` statements for recording-map key matching (can be removed later)

---

## [1.0.0] 2026-03-11 — Initial Release

### Added
- **Search by date/time range** — default last 7 days, datetime-local pickers
- **Search by agent (any participant)** — resolves agent name to systemuser GUID,
  then finds all conversations via `msdyn_ocsessions` (not just assigned agent)
- **Search by caller phone number** — partial `contains()` match; strips formatting
  characters before querying
- **Search by contact record** — resolves contact name to GUID(s), filters conversations
  by `_customerid_value`
- **Recordings-only toggle** — client-side checkbox to hide conversations without recordings
- **Recording playback** — inline `<audio>` player in detail panel when URI is available
- **Detail panel** — expandable per-row panel showing full conversation metadata +
  recording(s) with play button and direct URL link
- **Open in Dynamics** — `Xrm.Navigation.navigateTo()` in CSW; fallback to new-tab URL
- **Version self-check** — 8s post-load + every 5 min; reload banner if newer version
- **Cache busting** — `Cache-Control: no-cache` meta tags
- **Pagination** — configurable `CONFIG.pageSize` (default 50), top + bottom controls
- **Fluent Design** — matches Dynamics 365 / CSW visual language (Segoe UI, CSS variables)
- **MSAL deploy script** — `npm run deploy` uploads + publishes web resource to Dataverse
  with silent re-auth via file-based token cache
