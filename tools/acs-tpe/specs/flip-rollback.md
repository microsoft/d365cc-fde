# Flip and Rollback

## Overview

Three scripts manage routing direction changes after an initial migration:

| Script | Direction | When to use |
|--------|-----------|-------------|
| `Invoke-FlipToACS-v14.ps1` | Teams → ACS | Roll back after cutover |
| `Invoke-FlipToTeams-v14.ps1` | ACS → Teams | Re-migrate after a rollback |
| `Toggle-AcsTeamsRouting-v14.ps1` | Auto-detect | Low-level atomic flip; called by other scripts |

## Number Scoping

Both flip scripts default to reading `ra-objectids.json` (written by Step 7), which contains only the numbers migrated in the most recent full migration run. Use `-PhoneNumbers` to override with specific numbers.

**FlipToACS** has an additional `-AllNumbers` switch that queries D365 for all phone numbers where `msdyn_phonenumbertype = 1` (Teams). This finds all numbers currently in Teams state, regardless of which migration run created them — useful when ra-objectids.json is unavailable or when rolling back numbers from a different migration run. `-AllNumbers` and `-PhoneNumbers` are mutually exclusive — specifying both is an error.

**FlipToTeams** reads `ra-objectids.json` to determine which phone numbers to operate on. Use `-PhoneNumbers` to override with specific numbers.

### Phone Number Extraction from ra-objectids.json

When reading `ra-objectids.json`, both flip scripts extract phone numbers from the UPN keys using the `RaPrefix` template from the config:

1. Sanitize `RaPrefix`: lowercase, replace special characters with hyphens, trim
2. Extract digits after the prefix portion and before the `<phonenumber>` placeholder
3. **Fallback**: If prefix-based extraction fails, use regex to find the last block of 7–15 digits in the UPN
4. Prepend `+` to reconstruct E.164 format

This allows flip scripts to work even when the RA naming convention varies between migrations.

```powershell
# FlipToACS: scopes to ra-objectids.json (default)
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-config.json

# FlipToACS: query D365 for ALL Teams-type numbers
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-config.json -AllNumbers

# FlipToACS: explicit override
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-config.json -PhoneNumbers "+12202140029","+14255550100"

# FlipToTeams: scopes to ra-objectids.json
.\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\my-config.json
```

---

## Invoke-FlipToACS-v14.ps1 (Teams → ACS Rollback)

### Purpose

Rolls back a completed migration. Restores ACS routing for affected phone numbers and clears the Teams RA link in D365.

### Steps

**Step A — Toggle routing (Teams → ACS)**
- Calls `Toggle-AcsTeamsRouting-v14.ps1 -AutoConfirm`
- Toggle detects Teams is active, flips: `Set-CsOnlinePSTNGateway -Enabled $false`, then PATCH ACS trunk `enabled:true` with routes from `acs-export.json`

**Step B — Remove Teams phone number assignments**
- Per number: `Remove-CsPhoneNumberAssignment -Identity <UPN> -PhoneNumber <number> -PhoneNumberType DirectRouting`
- Required to prevent D365 CCaaS background sync from immediately re-linking the Teams RA after Step C clears it
- **Teams reconnection**: FlipToACS reconnects to Teams specifically for `Remove-CsPhoneNumberAssignment`. If the Teams connection fails, Step B is skipped entirely and the script emits manual remediation commands (`Remove-CsPhoneNumberAssignment` per number) for the operator to run later.
- **Per-number ObjectId lookup**: Matches phone digits against `ra-objectids.json` keys using regex for identity resolution

**Step C — Update D365 phone type (TPS → ACS)**
- Per number: calls `Invoke-MigrateTpsPhoneNumber-v14.ps1 -Direction TPS_TO_ACS`
  - PATCH `msdyn_phonenumbertype = 0` (ACS)
  - PATCH `msdyn_ocphonenumbersource = 192350000` (ACS)
  - PATCH `msdyn_teamsresourceaccount = null` (clear RA link)
  - **Skips** `CCaaS_SynchronizePhoneNumbers` — intentional; sync would re-link the Teams RA and revert the rollback

**Post-rollback checklist**: After rollback completes, the script displays 4 verification items for the operator to confirm.

**Failure remediation**: On per-number D365 failure, the script displays specific re-run commands for each failed number (`Invoke-MigrateTpsPhoneNumber -Direction TPS_TO_ACS ...`).

**Exit code**: Returns exit code 1 if any numbers failed the D365 update.

### HTML Log and Run Record

FlipToACS writes:
- HTML run log: `tpe-flip-acs-run-<timestamp>.html`
- Run record: appended to `stats/tpe-runs.jsonl` with type `flip-acs`
- Dashboard: regenerates `tpe-status.html`

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ConfigPath` | Yes | ACS-TPE config JSON (needs AcsConnectionString, SbcFqdn, TenantId, AdminUpn, D365OrgUrl) |
| `-PhoneNumbers` | No | Explicit E.164 number list; default: from `ra-objectids.json` |
| `-AllNumbers` | No | Query D365 for ALL numbers with `msdyn_phonenumbertype = 1` (Teams) instead of reading `ra-objectids.json` |
| `-DryRun` | No | Show plan without mutations |

### Confirmation Prompt

In live mode (no `-DryRun`), FlipToACS shows a confirmation before executing:

```
Read-Host "Proceed? Flip from Teams to ACS [Y/n]"
```

If the user cancels, the script writes a run record with `Result='FAIL'` and `Failures=0` before exiting with code 0.

### Number Resolution Priority

FlipToACS resolves phone numbers in this order:

1. **`-PhoneNumbers` parameter** — explicit list takes highest priority
2. **`-AllNumbers` switch** — queries D365 for all Teams-type numbers (see below)
3. **`ra-objectids.json`** (default) — reads numbers from the most recent migration run

### D365 Auto-Discovery Scoping (`-AllNumbers`)

When `-AllNumbers` is specified (and `-PhoneNumbers` is not), FlipToACS queries D365:
```
GET /api/data/v9.2/msdyn_ocphonenumbers
  ?$select=msdyn_phonenumber,msdyn_teamsresourceaccount
  &$filter=msdyn_phonenumbertype eq 1 and statecode eq 0
  &$orderby=msdyn_phonenumber
```
This returns all active phone numbers currently configured as Teams Phone System. The script displays a numbered list of discovered numbers with their RA links, then processes each through Steps A–C.

If no Teams-type numbers are found, the script exits cleanly with `OK No numbers found`.

### DryRun

Passes `-DryRun` to Toggle and `Invoke-MigrateTpsPhoneNumber`. No ACS PATCH, no Teams commands, no D365 PATCH executed.

---

## Invoke-FlipToTeams-v14.ps1 (ACS → Teams Re-migration)

### Purpose

Re-migrates numbers back to Teams Phone System after a rollback. Mirror operation of the full migration Steps 9–11.

### Steps

**Step A — Assign Teams phone numbers**
- Per number: `Set-CsPhoneNumberAssignment -Identity <UPN> -PhoneNumber <number> -PhoneNumberType DirectRouting`

**Step B — Toggle routing (ACS → Teams)**
- Calls `Toggle-AcsTeamsRouting-v14.ps1 -AutoConfirm`
- Toggle detects ACS is active, flips: PATCH ACS `enabled:false routes:[]`, wait 15s, `Set-CsOnlinePSTNGateway -Enabled $true`

**Step C — Update D365 phone type (ACS → TPS) + sync**
- Per number: calls `Invoke-MigrateTpsPhoneNumber-v14.ps1 -Direction ACS_TO_TPS`
  - PATCH `msdyn_phonenumbertype = 1` (TPS)
  - PATCH `msdyn_ocphonenumbersource = 192350001` (TPS)
  - PATCH `msdyn_teamsresourceaccount = <ObjectId>` (link RA — raw GUID, not `@odata.bind` format)
  - **Runs** `CCaaS_SynchronizePhoneNumbers` — syncs the Teams RA into D365

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ConfigPath` | Yes | ACS-TPE config JSON |
| `-PhoneNumbers` | No | Explicit E.164 number list; default: from ra-objectids.json |
| `-DryRun` | No | Show plan without mutations |

### Confirmation Prompt

In live mode (no `-DryRun`), FlipToTeams shows a confirmation before executing:

```
Read-Host "Proceed? Flip from ACS to Teams [Y/n]"
```

If the user cancels, the script writes a run record with `Result='FAIL'` and `Failures=0` before exiting with code 0.

### ra-objectids.json Requirement

FlipToTeams hard-exits if `ra-objectids.json` is not found, even when `-PhoneNumbers` is provided, because it needs the ObjectId for each number's Resource Account to create the Teams assignment and the D365 `@odata.bind` reference.

### Step Details

**Step A — Abort on failure**: If ANY phone number fails Teams assignment in Step A, the script aborts entirely (unlike FlipToACS which continues past failures). This asymmetry is intentional — a partial Teams assignment before a routing flip would leave some numbers unreachable.

**Step B — No AutoConfirm**: FlipToTeams does NOT pass `-AutoConfirm` to Toggle. This means Toggle shows its own Y/N prompt, creating a double-confirmation experience. (By contrast, the orchestrator Step 10 and FlipToACS both pass `-AutoConfirm`.) On Toggle failure, the script displays specific guidance: "Numbers are assigned to Teams RAs but routing has NOT switched."

**Step C — Conditional TeamsResourceAccountObjectId**: FlipToTeams passes `-TeamsResourceAccountObjectId` to `Invoke-MigrateTpsPhoneNumber` only when the ObjectId exists in the `ra-objectids.json` lookup (i.e., `if ($objectId) { ... }`). FlipToACS does not pass this parameter, relying on null to clear the binding.

**Post-cutover checklist**: After cutover completes, the script displays 4 verification items specific to Teams.

**Failure remediation**: On partial failure, displays per-number re-run commands including `-TeamsResourceAccountObjectId`.

**Exit code**: Returns exit code 1 on partial failure.

### HTML Log and Run Record

FlipToTeams writes:
- HTML run log: `tpe-flip-teams-run-<timestamp>.html`
- Run record: appended to `stats/tpe-runs.jsonl` with type `flip-teams`
- Dashboard: regenerates `tpe-status.html`

---

## Toggle-AcsTeamsRouting-v14.ps1 (Atomic Flip)

### Purpose

Low-level atomic routing direction flip for a shared SBC FQDN. Auto-detects current direction and confirms with the user before proceeding (unless `-AutoConfirm`).

### Direction Detection

| ACS State | Teams State | Detected Direction | Will flip to |
|-----------|-------------|-------------------|--------------|
| enabled | disabled | ACS active | TPE |
| disabled | enabled | TPE active | ACS |
| both enabled | — | ERROR — ambiguous | — |
| both disabled | — | ERROR — ambiguous | — |
| not found on either | — | ERROR — FQDN not registered | — |

### Pre-Flight Guards

- **ConfigPath required**: If `-ConfigPath` is empty, Toggle exits with error `"Please provide -ConfigPath."` (the Parameters table says it defaults to empty and uses individual params, but the script hard-exits if no config is provided).
- **Interactive fallbacks**: If `Fqdn`, `TenantId`, or `AdminUpn` are still empty after config load, Toggle falls back to `Read-Host` prompts for each missing value.
- **Target side must exist**: Before flipping, Toggle checks that the target side (ACS trunk or Teams gateway) actually exists. Exits with an "Add it first" message if missing.
- **ACS trunk enabled default**: If the `enabled` property is missing from the ACS trunk response, Toggle defaults to `$true`.

### ACS → TPE Flip (cutover)

1. Save current ACS routes from `GET /routing/trunks/<fqdn>`
2. Persist routes to `acs-export.json` for future rollback (overwritten each cutover)
3. PATCH ACS: `{"routes": [], "enabled": false}` — one atomic call (avoids HTTP 422 from partial updates)
4. Wait 15 seconds for ACS propagation
5. `Set-CsOnlinePSTNGateway -Identity <fqdn> -Enabled $true`
6. **On Teams failure**: restore ACS (`PATCH {"routes": <original>, "enabled": true}`), exit 1

Route save to `acs-export.json` (step 2) can fail — Toggle warns but continues if the file write fails. On PATCH failure, the script extracts the HTTP status code from the exception response for detailed error logging.

### TPE → ACS Flip (rollback)

1. Load routes from `.\acs-export.json`; fall back to `[]` if file missing or cannot be parsed
2. `Set-CsOnlinePSTNGateway -Identity <fqdn> -Enabled $false`
3. **On Teams failure**: exit 1 (ACS is still disabled at this point — nothing to restore safely)
4. PATCH ACS: `{"routes": <loaded>, "enabled": true}` — one atomic call
5. **On ACS re-enable failure**: attempt to re-enable Teams gateway as recovery (`Set-CsOnlinePSTNGateway -Enabled $true`). If that recovery also fails, exits with a "NEITHER side is active" error. Then exit 1.

### SIP Port Fallback

Toggle resolves the SBC SIP signaling port with this priority:
1. `trunk.sipSignalingPort` (from ACS GET response)
2. `config.SbcPort` (from config JSON)
3. `5075` (hardcoded default)

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ConfigPath` | Yes* | ACS-TPE config JSON; hard-exits with `"Please provide -ConfigPath."` if empty. Individual params (`-Fqdn`, `-TenantId`, `-AdminUpn`) serve as overrides on top of config, not as standalone substitutes |
| `-Fqdn` | No | Overrides SbcFqdn from config |
| `-TenantId` | No | Overrides TenantId from config |
| `-AdminUpn` | No | Overrides AdminUpn from config |
| `-AutoConfirm` | No | Skip Y/N prompt; used when called by orchestrator/flip scripts |
| `-DryRun` | No | Show planned flip without executing |

### Confirmation Behavior

| Mode | Behavior |
|------|----------|
| `-DryRun` | Automatic — shows plan only, no prompt |
| `-AutoConfirm` | Automatic — no prompt (used when called by orchestrator/flip scripts) |
| Normal | Y/N prompt (case-insensitive); cancelled runs exit 0 |

### DryRun

Shows current direction detection and planned flip without any ACS PATCH or Teams cmdlet calls. `Wait-WithMessage` displays `(DRY RUN)` message instead of counting down. Post-flip state shows projected values rather than re-querying live state.

### HTML Log and Run Record

Toggle writes:
- HTML run log: `tpe-toggle-run-<timestamp>.html`
- Run record: appended to `stats/tpe-runs.jsonl` with type `toggle-to-tpe` or `toggle-to-acs`
- Dashboard: regenerates `tpe-status.html`

### Observability

After a successful flip, the HTML log shows:
```
OK  ACS trunk: disabled
OK  Teams gateway: enabled
OK  Toggle complete — routing is now: Teams
```

### Observability Details

- `6>$null` redirection is used on `Set-CsOnlinePSTNGateway` calls to suppress the Information stream
- `Write-TpeRunRecord` is called on every failure path, not just success
- Config property access uses `$cfg.PSObject.Properties['X']` null-safe pattern
