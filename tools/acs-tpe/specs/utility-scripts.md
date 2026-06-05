# Utility Scripts

## Overview

Eight utility scripts handle configuration, SBC management, route repair, domain testing, and log archiving. All support `-DryRun`. Only Undo-ACS-TPE-Migration produces HTML run logs and JSONL run records; the other seven utility scripts use console-only output via `Write-Host`.

---

## New-AcsTpeConfig-v14.ps1

### Purpose

Auto-discovery config builder. Queries Azure, D365, and ACS APIs to populate config fields automatically. Only `Domain` is required as manual input — all other fields are discovered from the authenticated session.

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-OutputPath` | No | `.\new-acs-tpe-config-v14.11.0.json` | Path to write the generated config JSON |
| `-Domain` | No | `""` (prompted) | Custom domain for Resource Account UPNs |
| `-SubscriptionId` | No | Current az CLI subscription | Override Azure subscription |
| `-D365OrgUrl` | No | Auto-discovered (Phase 2) | Override D365 org URL |
| `-RaPrefix` | No | `acs-tpe-ra-<phonenumber>` | Resource Account name prefix template |
| `-PolicyName` | No | `acs-tpe-migration` | Teams Voice Routing Policy name |
| `-UsageName` | No | `acs-tpe-pstn-usage` | Teams PSTN Usage name |
| `-RouteName` | No | `acs-tpe-voice-route` | Teams Voice Route name |
| `-DryRun` | No | — | Discover and display all values without writing config file |

### Output Helper Functions

Defines six console-output formatting functions for consistent display:

| Function | Purpose |
|----------|---------|
| `Write-Step` | Step header output |
| `Write-OK` | Success message |
| `Write-Warn` | Warning message |
| `Write-Fail` | Failure message |
| `Write-Info` | Informational detail |
| `Write-Found` | Discovery result display |

### 8-Phase Discovery Flow

**Phase 1 — Session Validation**
- Checks for existing `acs-tpe-session.json` (written by `Invoke-AcsTpeLogin.ps1`)
- Session TTL: 50 minutes; reuses valid session if tenant matches
- If no valid session: launches `Invoke-AcsTpeLogin.ps1 -SkipTeamsConnect`
- Hydrates: `TenantId`, `SubscriptionId`, `AdminUpn`

**Phase 2 — D365 Global Discovery**
- Token: `az account get-access-token --resource "https://globaldisco.crm.dynamics.com"`
- Endpoint: `GET https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances`
- Single instance → auto-selects; multiple → interactive numbered list; zero → manual prompt
- User may type a URL directly instead of selecting by index

**Phase 3 — D365 Web API (FetchXML)**
- Token: `az account get-access-token --resource "$D365OrgUrl"`
- Query 1: Provider setting (`msdyn_occommunicationprovidersetting` where `msdyn_occommunicationprovider = 192350003, statecode = 0`) → `CommsProviderId`, `AcsResourceId`
- Query 2: Setting entry (`msdyn_occommunicationprovidersettingentry` where `msdyn_key = "DynamicsAppId"`) → `DynamicsAppId`
- Missing fields prompt for manual input

**Phase 4 — Azure Management API**
- Token: `az account get-access-token --subscription $subId --resource "https://management.azure.com"`
- Endpoint: `GET /subscriptions/{subId}/providers/Microsoft.Communication/communicationServices?api-version=2023-04-01`
- Lists ACS resources in the subscription; user selects if multiple
- Supports cross-subscription: `Trim-ResourceId` extracts canonical resource ID from portal URLs
- Retrieves `AcsEndpoint` (hostname) and `AcsConnectionString` (primary connection string via `/listKeys`)

**Phase 5 — ACS SIP REST API**
- Uses HMAC-SHA256 signed GET (same auth as all ACS REST calls)
- Discovers `SbcFqdn` and `SbcPort` from active SIP trunk configuration
- If multiple trunks: displays list for user selection

**Phase 6 — Domain and Naming**
- Prompts for `Domain` if not supplied via parameter
- Collects/confirms naming defaults: `RaPrefix`, `PolicyName`, `UsageName`, `RouteName`

**Phase 7 — Assembly**
- Builds the JSON config object with `_help` embedded documentation
- Shows field-by-field summary in console

**Phase 8 — Write/Preview**
- Writes to `OutputPath` (guarded by `-DryRun`)
- In DryRun mode: shows DryRun preview without writing
- Prints suggested next command: `Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath ... -DryRun`

### Post-Assembly Validation

After assembly, checks 10 required fields plus `SbcPort` and reports which ones are empty:
- `TenantId`, `AdminUpn`, `Domain`, `DynamicsAppId`, `D365OrgUrl`
- `AcsSubscriptionId`, `AcsResourceId`, `AcsEndpoint`, `AcsConnectionString`, `SbcFqdn`
- `SbcPort`

### SBC Port Validation Loop

When SBC port is prompted interactively, validates it is a number between 1-65535 in a retry loop. Invalid inputs re-prompt until a valid port is entered.

### Connection String Manual Fallback

When `AcsConnectionString` is not auto-retrieved, the script prompts the user. If `AcsEndpoint` is also empty, auto-extracts the endpoint hostname from the connection string via regex.

### Helper Functions

| Function | Purpose |
|----------|---------|
| `Get-MgmtHeaders($subId)` | Acquires Azure Management API token for a specific subscription |
| `Trim-ResourceId($raw)` | Extracts canonical resource path from portal URLs using regex |
| `Get-RgFromId($id)` | Extracts resource group name from Azure resource ID (index 4 after `/` split) |
| `Show-AcsResourceList($resources)` | Displays numbered list of ACS resources |

### Output

Writes config JSON file with `_help` object. See [Configuration](configuration.md) for the full output schema.

---

## Set-AcsSbcFqdn-v14.ps1

### Purpose

Rename, update, or remove an ACS SIP trunk FQDN via the ACS REST API. Also preserves affected voice routes by updating their trunk lists.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ConfigPath` | Yes | Path to config JSON (needs `AcsConnectionString`) |
| `-OldFqdn` | No | FQDN of the trunk to rename (prompted if omitted) |
| `-NewFqdn` | No | New FQDN to set (prompted if omitted) |
| `-RemoveFqdn` | No | Delete a trunk by setting it to `null` in the merge-patch |
| `-NewPort` | No | New SIP signaling port (keeps existing port if omitted) |
| `-DryRun` | No | Show planned PATCH without executing |
| `-List` | No | Query and display current trunks/routes, then exit (no changes) |

### Helper Functions

| Function | Purpose |
|----------|---------|
| `Parse-ConnectionString` | Standalone function for splitting ACS connection strings into endpoint and accesskey components |
| `Build-HmacHeaders` | Reusable HMAC header builder that handles both GET and PATCH methods, computing body hash and HMAC signature. This is the most mature HMAC implementation across the suite. |
| `Write-Info` | Informational detail output |
| `Write-Step` | Step header output |
| `Write-OK` | Success message |
| `Write-Warn` | Warning message |
| `Write-Err` | Error message |

### Operation Modes

**Rename mode** (`-OldFqdn` + `-NewFqdn`): Sends a single PATCH that sets the old FQDN to `null` and creates a new entry with the new FQDN and port. Updates any voice routes that reference the old FQDN to reference the new FQDN. Preserves `_raw` field — copies all non-standard fields from the original trunk object to the new entry, ensuring unknown/future ACS trunk properties survive rename operations.

**Remove mode** (`-RemoveFqdn`): Sets the trunk entry to `null` in the merge-patch and updates affected routes to remove the trunk from their `trunks` arrays.

**List mode** (`-List`): Reads and displays current ACS SIP configuration (trunks + routes) without making changes. Displays trunk list with `[DISABLED]` labels for trunks with `enabled=$false`. Also displays all routes with name/pattern/trunks after the trunk list.

**Verification GET**: After a successful rename or remove PATCH, performs a full HMAC-signed verification GET to confirm the change was applied.

**Confirmation prompt format**: Uses `[Y/n]` format where blank input equals Yes.

### Validation

- `-OldFqdn` / `-NewFqdn` must be non-empty and non-whitespace (v14.6.0 fix)
- Config file must exist and be valid JSON
- ACS connection string validated for `endpoint=` and `accesskey=` tokens
- Confirmation prompt before destructive operations (unless `-DryRun`)
- Response stream fallback for error details: if `ErrorDetails.Message` is null, reads the response stream directly via `GetResponseStream()` + `StreamReader`

---

## Add-AcsTrunkDisabled-v14.ps1

### Purpose

Temporarily disables an ACS SIP trunk by PATCHing it to `enabled: false` with empty routes. Used internally by Step 2 of the full migration, but can also be called standalone for testing or manual operations.

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-ConfigPath` | No | `.\acs-tpe-config-fromd365-local.json` | ACS-TPE config JSON |
| `-DryRun` | No | — | Show planned PATCH without executing |

Note: The script does NOT have a `-Fqdn` parameter. It always reads `$cfg.SbcFqdn` from the config file.

### Actions

1. Authenticate to ACS REST API (HMAC-SHA256)
2. PATCH `{"trunks":{"<fqdn>":{"sipSignalingPort":<port>,"enabled":false}}}` to `/sip?api-version=2023-04-01-preview`
3. Verification GET: Performs a full HMAC-signed verification GET to confirm the trunk was created with the correct port and enabled state. Verification failure is non-fatal (Yellow warning only).
4. Report trunk disabled

### ACS REST API authentication

All ACS REST calls use HMAC-SHA256 request signing:
```
Authorization: HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=<signature>
```
The signature is computed over the request method, URL path+query, date header, host, and SHA256 of the request body.

### Validation

- SBC port validated as numeric AND in range 1-65535 (v14.5.0 fix)
- ACS connection string validated for `endpoint=` and `accesskey=` tokens

### DryRun Behavior

DryRun exits with code 0 after showing the planned PATCH body. Live PATCH failure exits with code 1.

---

## Fix-AcsRoutePattern-v14.ps1

### Purpose

Patches the E.164 number pattern on an ACS voice route. Used when an ACS route has an incorrect pattern (e.g. wrong regex, missing `+` prefix) that needs correction without recreating the route.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ConfigPath` | Yes | ACS-TPE config JSON |
| `-RouteName` | Yes | ACS route name to update |
| `-NumberPattern` | Yes | New E.164 regex pattern (e.g. `^\+12202140029$`) |
| `-TrunkFqdn` | Yes | Trunk FQDN to wire the route to |
| `-DryRun` | No | Show planned PATCH without executing |

### Actions

1. Authenticate to ACS REST API
2. Print route name, pattern, trunk FQDN, and raw PATCH body to console before executing
3. Build merge-patch body: `{"routes": [{"name": <RouteName>, "numberPattern": <NumberPattern>, "trunks": [<TrunkFqdn>]}]}`
4. PATCH the ACS SIP config
5. Verification GET after successful PATCH: Performs a full HMAC-signed GET to verify route pattern and trunks match. Checks the route by name in the response and prints the verified pattern and trunks. Verification failure is non-fatal.

### Error Handling

- On PATCH failure, exits with code 1 (added v14.11.0)

### History

v14.6.0: Parameterized — no longer has a hardcoded FQDN/pattern. Also gained `-ConfigPath` parameter and `-DryRun` support.

---

## Get-TeamsProviderSetting-v14.ps1

### Purpose

Reads the Teams communications provider configuration from D365 to find the `CommsProviderId` and `DynamicsAppId` needed for creating resource accounts. Run this before `New-AcsTpeConfig-v14.ps1` if the provider ID is unknown.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-OrgUrl` | Yes | D365 organization URL (e.g. `https://org.crm.dynamics.com`) |

Note: The script does NOT have `-TenantId` or `-AdminUpn` parameters.

### Authentication

Uses Azure CLI token acquisition (`az account get-access-token --resource "$OrgUrl"`) — NOT Teams PowerShell. No `Connect-MicrosoftTeams` call.

### Actions (2-step D365 REST API workflow)

1. **Step 1 — Provider Setting lookup**: FetchXML query for `msdyn_occommunicationprovidersetting` where `msdyn_occommunicationprovider=192350003` (Teams Phone System) and `statecode=0` (active). Returns `CommsProviderId`, provider name, and `msdyn_occommunicationproviderimmutableid`. FetchXML queries are URI-encoded via `[System.Uri]::EscapeDataString()`.
2. **Step 2 — DynamicsAppId lookup**: FetchXML query for `msdyn_occommunicationprovidersettingentry` where `msdyn_key="DynamicsAppId"` and `msdyn_communicationprovidersettingentid=<CommsProviderId>`. Returns DynamicsAppId. This step is wrapped in try-catch; failure is non-fatal (continues with empty value).

### Output

Multi-field summary showing:
- Provider Name
- Setting ID (CommsProviderId)
- Immutable ID
- DynamicsAppId
- Suggested sync command

### Error Handling

API calls wrapped in try-catch (v14.5.0 fix). Step 2 failure is non-fatal — the script continues with an empty DynamicsAppId value. If the provider setting is not found, shows a diagnostic message.

---

## Test-DomainRegistration-v14.ps1

### Purpose

Validates whether a domain is registered and DNS-verified in Entra ID. Can register, verify, check, or remove domains.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-Domain` | No | Domain name to check (e.g. `staging.ivr.nuance.com`); prompted if not supplied |
| `-TenantId` | No | Tenant ID; will prompt if not supplied |
| `-AdminUpn` | No | Admin UPN; will prompt if not supplied |
| `-ConfigPath` | No | Config JSON; extracts Domain/TenantId/AdminUpn if provided |
| `-CheckOnly` | No | Status check only — report state without making changes |
| `-Remove` | No | Remove domain from Entra ID (cleanup/deletion mode) |
| `-DryRun` | No | Show what would be done without making API changes |

### Helper Functions

| Function | Purpose |
|----------|---------|
| `Write-Info` | Informational detail output |
| `Write-Step` | Step header output |
| `Write-OK` | Success message |
| `Write-Warn` | Warning message |
| `Write-Err` | Error message |

### Config Loading

Extracts `TenantId`, `AdminUpn`, `Domain` from config JSON using `PSObject.Properties['X']` null-safe pattern. If Domain, TenantId, or AdminUpn are still empty after config loading, prompts via `Read-Host`.

### Banner Box

Prints a bordered box showing Domain, Tenant ID, Admin UPN, and current Mode (DRY RUN, CHECK ONLY, REMOVE, or REGISTER + VERIFY).

### Operation Modes

**Check mode** (`-CheckOnly`): Connects to Graph, reads domain state, reports registered/verified status.

**Register + Verify mode** (default): If domain is not registered, calls `New-MgDomain`. If registered but not verified, retrieves DNS verification records and polls for verification completion (30s intervals, 10 attempts = 5 min max). Catches "already exists" or "ObjectConflict" errors during registration and continues to verification.

**Remove mode** (`-Remove`): Calls `Remove-MgDomain` to delete the domain registration from Entra ID. Checks `IsDefault` and `IsInitial` flags and refuses to remove them. Uses `[Y/n]` confirmation (not typed "DELETE").

### Graph Scope

Requests `Domain.ReadWrite.All` with `-NoWelcome` flag on `Connect-MgGraph`.

### DNS Record Display

Shows TXT Value, CNAME, Label, TTL for each verification DNS record. User can type "skip" during DNS verification wait to defer verification.

### DryRun behavior

In DryRun mode, `Connect-MgGraph` is not called and no actual domain check happens. No `New-MgDomain` or `Remove-MgDomain` calls are made. The dry run shows the actual domain state (v14.7.0 fix — previously DryRun incorrectly set `$verified=$true` and masked the real verification status).

---

## Archive-TpeRuns-v14.ps1

### Purpose

Moves old HTML run logs and outdated JSON config artifacts into dedicated backup subdirectories to keep the working directory clean.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-DryRun` | No | Show planned moves without executing |

### Helper Functions

| Function | Purpose |
|----------|---------|
| `Write-Head` | Section header helper |
| `Write-Move` | Formatted move display showing source filename and destination folder |
| `Write-Keep` | Displays "KEEP" label for retained files |
| `Write-Info` | Detail output helper |
| `Move-File` | Wrapper that handles DryRun vs. live moves, auto-creates destination directories, and increments `$script:movedCount` |

### Actions

**HTML run log archiving** (`backup-run/`):
1. Collect HTML files matching: `tpe-migration-run-*`, `tpe-undo-run-*`, `tpe-flip-acs-run-*`, `tpe-flip-teams-run-*`, `tpe-toggle-run-*`
2. Sort by **Name** (lexicographic, not LastWriteTime) — relies on the `yyyyMMdd-HHmmss` timestamp in filenames for chronological ordering
3. Keep the latest of each type in the working directory
4. Archive older versioned status pages
5. Move files into `backup-run/`

**JSON config archiving** (`backup-config-json/`):
- Keep active config (newest by Name sort)
- Archive old configs and backup artifacts (`*-backup-*`, `*-undooperation-*`)
- Move files into `backup-config-json/`

**Catch-all JSON sweep**: After targeted archiving, performs a final sweep of ALL remaining `.json` files in root (except the keep list and active config), archiving anything left over.

**Never archived** (essential working files):
- `ra-objectids.json`
- `acs-export.json`
- `d365-phone-backup.json`
- `acs-trunk-disabled.json`
- `tpe-status.html` — implicitly excluded; not matched by any HTML archive pattern since archive patterns target timestamped run logs (`tpe-*-run-*`), not the live dashboard

**Auto-creates directories**: Creates `backup-run/` and `backup-config-json/` automatically if they don't exist.

### DryRun

Prints each planned move without executing. Shows: `Would move <file> → <backup-dir>/<file>`. The `$script:movedCount` counter is not incremented in DryRun.

### Summary Box

Prints a bordered box showing DRY RUN indicator or actual file count moved.

### `$script:movedCount` Counter

Tracks total files moved across all archiving phases. Only incremented for actual moves (not DryRun).

### Sort-Object dedup fix (v14.6.0)

Prevents processing the same file twice when `Sort-Object` returns duplicate entries for the same file path. Uses `Sort-Object { $_.FullName } -Unique` to deduplicate.

---

## Undo-ACS-TPE-Migration-v14.ps1

### Purpose

Full reversal of a completed migration. Reverses all Teams and D365 changes in reverse step order (high-to-low).

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ConfigPath` | Yes | ACS-TPE config JSON |
| `-DryRun` | No | Show planned undo without executing |
| `-StartAtStep` | No | Undo from a specific step downward (default: `9`, range: 1–9) |
| `-StopAfterStep` | No | Stop undoing at this step (default: `1`, range: 1–9) |
| `-AutoConfirm` | No | Skip Y/N confirmation prompt |

### Step-Range Validation

Undo steps run **high-to-low** (reverse of migration). The validation rule is inverted:
- `-StartAtStep` must be **≥** `-StopAfterStep`
- Error: `-StartAtStep 3 -StopAfterStep 7` → `"For Undo, steps run high-to-low"`
- Valid: `-StartAtStep 9 -StopAfterStep 7` → undoes Steps 9, 8, 7

### Helper Functions

| Function | Purpose |
|----------|---------|
| `Invoke-Undo` | Wraps each step action in try-catch; tracks completed/skipped/failures counters |
| `Confirm-Step` | Per-step confirmation with Y/S/Q (Yes/Skip/Quit) options |
| `Invoke-AcsTrunkPatch` | Reusable HMAC-SHA256 ACS trunk PATCH helper for trunk re-enable |
| `Invoke-D365SyncFromAzure` | Triggers `msdyn_TelephonyACSSyncPhoneNumbersAction` to sync D365 from Azure |
| `Backup-JsonFile` | Creates timestamped backup copies with `undooperation-<timestamp>` suffix |

### Undo Sequence (Steps 9 → 1)

1. **Step 9 undo**: `Remove-CsPhoneNumberAssignment` per RA; restore D365 phone records from `d365-phone-backup.json`; trigger `Invoke-D365SyncFromAzure`
2. **Step 8 undo**: Remove PHONESYSTEM_VIRTUALUSER license from each RA (`Set-MgUserLicense -RemoveLicenses`)
3. **Step 7 undo**: `Remove-MgUser` per RA (using ObjectId from `ra-objectids.json`); backs up `ra-objectids.json` with undooperation timestamp
4. **Step 6 undo**: `Remove-CsOnlineTelephoneNumber` per number; re-patch D365 records after removal (post-Step-6 sync guard); trigger `Invoke-D365SyncFromAzure`
5. **Step 4 undo**: Remove registered domain from Entra ID (`Remove-MgDomain`); checks for `.onmicrosoft.com` domain and `IsDefault` flag before removal. Error matching: "in use", "referenced", "dependent", "BadRequest" trigger targeted guidance
6. **Step 3 undo**: Remove voice routing policy (`Remove-CsOnlineVoiceRoutingPolicy`), voice routes (`Remove-CsOnlineVoiceRoute`), PSTN usage (`Set-CsOnlinePstnUsage -Usage @{Remove=...}`)
7. **Step 2 undo**: Remove Teams DR gateways (`Remove-CsOnlinePSTNGateway`); re-enable ACS trunks from `acs-trunk-disabled.json` (idempotent); loads routes from `acs-export.json` and restores them alongside the trunk enable (not just from `acs-trunk-disabled.json`). JSON array wrapping uses a three-branch null guard: `if ($null -eq $raw)` → empty array (handles PowerShell `ConvertFrom-Json` returning `$null` for `[]`); `elseif ($raw -is [System.Array])` → wrap in `@()`; `else` → wrap scalar in `@([string]$raw)`
8. **Step 1 undo**: Backup `acs-export.json` with undooperation timestamp (file kept for reference, not deleted)

Steps 5, 10, 11 have no undo action (Step 5 is read-only validation; Steps 10–11 are reversed by `Invoke-FlipToACS-v14.ps1`).

### D365 Restoration

Undo Step 9 restores D365 phone records from `d365-phone-backup.json`:
- Restores all fields: `statecode`, `statuscode`, `msdyn_ocphonenumbersource`, `msdyn_phonenumbertype`, `msdyn_objective`, `msdyn_appmodule`, `msdyn_type`
- Fallback for pre-backup migrations: hardcoded ACS values (`statecode=0`, `statuscode=1`, `source=192350000`)
- Queries include inactive records (no `statecode` filter) to find deactivated records

### ACS Endpoint Resolution

Falls back from `AcsEndpoint` to `AcsResourceName` property, adds `https://` prefix if missing.

### ACS Key Manual Prompt

If ACS key is missing from config and Step 2 undo is in scope, prompts the user to enter the key manually.

### Live-Mode Confirmation

In live mode (no `-DryRun`), the script requires typed "YES" confirmation before starting (unless `-AutoConfirm`). Step 4 domain removal additionally requires typed "DELETE" confirmation.

### Tracking Counters

Undo tracks four separate outcome categories:

| Counter | Purpose |
|---------|---------|
| `$script:undoCompleted` | Items successfully reversed |
| `$script:undoSkipped` | Items skipped (e.g. `$null` ObjectId from failed Step 7) |
| `$script:undoFailures` | Items that failed during undo |
| `$script:undoAlreadyRemoved` | Items that were already gone (not-found is not an error) |

### Error Handling: Test-IsIgnorableUndoError

The `Test-IsIgnorableUndoError()` function filters recoverable errors that indicate an object is already removed:
- "not found"
- "already removed"
- "does not exist"
- "cannot find"
- "Identity is invalid"

These are classified as `undoAlreadyRemoved` (not failures), allowing the undo to continue cleanly.

### Scoping

Reads `ra-objectids.json` to determine which RAs and numbers to undo. Only numbers in that file are reversed.

### Idempotency

Each undo step checks whether the object exists before attempting removal. Missing objects produce a WARN (not an error) and processing continues.

### HTML Log

Undo writes `tpe-undo-run-<timestamp>.html` and a run record with type `undo`.

### Summary Box

Undo completion shows an aligned summary box with XSS-escaped phone numbers (v14.5.0):
```
  ┌────────────────────────────────────┐
  │  Undo complete                     │
  │  Numbers reversed : 1              │
  │  Already removed  : 0              │
  │  Failures         : 0              │
  └────────────────────────────────────┘
```

The box uses aligned padding; this was corrected in v14.8.0 (alignment fix).
