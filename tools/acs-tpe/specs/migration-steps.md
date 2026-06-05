# Migration Steps

## Overview

The full migration is orchestrated by `Invoke-ACS-TPE-Full-Migration-v14.ps1`. It runs Phase 0, Phase 0D, and Steps 1–11 in sequence. Each step can be skipped via `-StartAtStep` / `-StopAfterStep` for partial runs and resume-after-failure.

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-DryRun` | switch | false | Show planned actions without any mutations |
| `-ConfigPath` | string | '' | Path to saved config JSON; skips interactive prompts |
| `-StartAtStep` | int (0-11) | 0 | Resume from this step. `[ValidateRange(0, 11)]` |
| `-StopAfterStep` | int (0-11) | 11 | Stop after this step. `[ValidateRange(0, 11)]` |
| `-OutputPath` | string | `.\tpe-migration-results.csv` | CSV results path |
| `-UsageLocation` | string (2-char) | `US` | Country code for license assignment. `[ValidatePattern('^[A-Za-z]{2}$')]` |

### Step-Range Validation

- `StartAtStep > StopAfterStep` is rejected with error: `"For Invoke, steps run low-to-high"`
- This is the inverse of Undo which validates `StartAtStep >= StopAfterStep` (Undo runs high-to-low)

## Phase 0 — Module Setup

**Purpose**: Ensure Teams and Graph PowerShell modules are installed and connected.

**Actions**:
1. Check for `MicrosoftTeams` module; install if missing (`Install-Module -Force -AllowClobber -Scope CurrentUser`)
2. Check for `Microsoft.Graph` module; install if missing (same flags)
3. Check for existing Teams session via `Get-CsTenant -ErrorAction SilentlyContinue`; only call `Connect-MicrosoftTeams -TenantId $cfg.TenantId` if no active session detected
4. Connect-MgGraph with required scopes: `User.ReadWrite.All`, `Organization.Read.All`, `Directory.ReadWrite.All`, `Domain.ReadWrite.All` and `-TenantId $cfg.TenantId`
5. **License count pre-check**: Queries `Get-MgSubscribedSku` for available `PHONESYSTEM_VIRTUALUSER` licenses, compares against `ResourceAccounts.Count`. Two distinct failure modes:
   - **SKU not found** → hard exit with error indicating the SKU is not available in the tenant
   - **Insufficient licenses** → hard exit with error showing available vs. required count

**Resume behavior (`StartAtStep > 0`)**: Phase 0 reconnects to both Teams and Graph AND re-fetches the `PHONESYSTEM_VIRTUALUSER` SKU ID so that later steps have valid session state. Module installation is skipped on resume (only connection is re-established).

**DryRun behavior**: Connections are still established (needed for validation in dry run).

**Failure**: Phase 0 failure exits the script with a clear error.

## Phase 0D — D365 Discovery

**Purpose**: Query Dynamics 365 for active ACS phone numbers and auto-build the ResourceAccounts list.

**Actions**:
1. Acquire D365 OAuth2 token (client_credentials flow using TenantId + ACS accesskey, or interactive via `az account get-access-token`)
2. Query provider settings via FetchXML:
   ```xml
   <fetch top="1">
     <entity name="msdyn_occommunicationprovidersetting">
       <filter type="and">
         <condition attribute="statecode" operator="eq" value="0" />
         <condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" />
       </filter>
     </entity>
   </fetch>
   ```
3. GET `msdyn_ocphonenumbers?$filter=statecode eq 0&$orderby=msdyn_phonenumber` — all active records
4. GET `msdyn_ocphonenumberroutes` — fetch route patterns for DR vs DO classification
5. **DR/DO classification**: Phase 0D fetches live ACS route patterns via HMAC-signed GET and classifies numbers as DR (Direct Routing) or DO (Direct Outward/Operator Connect). If ACS is unreachable, falls back to `acs-export.json`. If neither is available, all numbers are classified as DO.
6. Filter to DR numbers (those matching ACS route patterns)
7. Apply `IncludeNumbers` filter: if non-empty, select only listed numbers; if empty, show interactive multi-select prompt
8. Validate each selected number as E.164 (`^\+[1-9]\d{6,14}$`); warn and skip non-conforming entries
9. Build `cfg.ResourceAccounts` array: one entry per number with auto-generated UPN and DisplayName
10. Save enriched config to `-ConfigPath`

**IncludeNumbers behavior**:
- `[]` → interactive prompt; user selects from numbered list. **Hybrid input**: user can select by row number OR by typing a phone number directly.
- `["+12202140029"]` → auto-selects, **no interactive prompt** (the prompt is completely skipped); shows "Selected: 1 number(s)"

**Silent degradation**: If the ACS REST API is unreachable AND `acs-export.json` does not exist on disk, Phase 0D cannot fetch route patterns. In this case, all numbers are silently classified as DO (Direct Outward). The script emits an info message but does not fail.

**Output**:
- `OK Found N active phone number(s) in D365`
- `OK Selected: N number(s) will be migrated`
- `OK ResourceAccounts set from D365: N real phone number(s)`

## Step 1 — Export ACS Config

**Purpose**: Export existing ACS SIP trunks and voice routes; create baseline snapshot.

**Actions**:
1. Authenticate to ACS REST API using HMAC-SHA256 signing
2. GET SIP config: `https://<acs-endpoint>/sip?api-version=2023-04-01-preview`
3. Extract trunks and routes from the response
4. Write snapshot to `.\acs-export.json`

**Resume behavior**: When `-StartAtStep > 1`, loads `.\acs-export.json` from disk instead of querying ACS. Fails with clear error if file is missing.

**ACS unreachable fallback**: If the ACS REST API is unreachable during a live run (not resume), Step 1 synthesizes a trunk and route from config values using `Get-NumberPatternRegex`. This allows migration to proceed even when ACS export fails.

**DryRun**: Does not write `acs-export.json`.

**Output**:
- `OK Exported N trunk(s) and M route(s) from ACS`

## Step 2 — Zero-Downtime Teams DR Registration

**Purpose**: Register the SBC FQDN as a Teams Direct Routing gateway without interrupting ACS calls.

**Actions** (in order):
1. Filter ACS trunks to `cfg.SbcFqdn` only — ignore other tenants' trunks
2. PATCH ACS trunk: set `routes: []` and `enabled: false` (one atomic call to avoid HTTP 422). If the PATCH fails, the script reads the response stream for the error body, logs it, and continues anyway (Teams gateway creation may fail if FQDN conflicts).
3. Wait 15 seconds for ACS propagation
4. `New-CsOnlinePSTNGateway -Identity cfg.SbcFqdn -SipSignalingPort <port> -Enabled $false -MediaBypass $false`
5. Wait 30 seconds after Teams gateway registration
6. Immediately PATCH ACS trunk: restore original routes and `enabled: true`
7. If Teams gateway creation fails: restore ACS trunk and exit with error

**Net result**: ACS trunk is disabled for ~45 seconds (15s + 30s waits). ACS resumes handling all calls after step 2. Teams gateway stays `Enabled=$false` until Step 10.

**Artifact**: Writes `acs-trunk-disabled.json` listing the FQDNs disabled during registration. Used by Undo Step 2 to know which trunks to re-enable.

**Idempotency**: If the Teams gateway already exists, the script reuses it with a WARN and still re-enables ACS. If the ACS trunk for `cfg.SbcFqdn` is not found in the export, Step 2 exits with an error.

**DryRun**: Shows planned PATCH and New-CsOnlinePSTNGateway without executing. Does not write `acs-trunk-disabled.json`.

## Step 3 — Configure PSTN Usages, Voice Routes, and Routing Policy

**Purpose**: Create the Teams routing objects needed to route calls through the new DR gateway.

**Actions**:
1. `Set-CsOnlinePstnUsage -Usage cfg.PstnUsageName` — create PSTN usage (idempotent WARN if exists)
2. Build number pattern via `Get-NumberPatternRegex`:
   ```powershell
   $vrPattern = Get-NumberPatternRegex -Numbers @($cfg.ResourceAccounts | ForEach-Object { [string]$_.PhoneNumber })
   ```
   Pattern generation logic:
   - 0 numbers → `.*` (matches all)
   - 1 number → `^\+12202140029$` (exact match, `[regex]::Escape()` applied)
   - Multiple numbers with common prefix → `^\+1202555\d*$` (prefix match)
   - Multiple numbers without common prefix → joined E.164 alternation: `^\+12202140029$|^\+14255550100$`
   - Source: config `ResourceAccounts` array (not ACS export routes — v14.14.0 change)
3. `New-CsOnlineVoiceRoute -Identity cfg.RouteName -NumberPattern <pattern> -OnlinePstnGatewayList cfg.SbcFqdn -OnlinePstnUsages cfg.PstnUsageName`
   - Single SBC gateway: `cfg.SbcFqdn`
4. `New-CsOnlineVoiceRoutingPolicy -Identity cfg.RoutingPolicyName -OnlinePstnUsages cfg.PstnUsageName`

**Idempotency**: If route or policy already exists, warns and skips.

**DryRun**: Shows planned commands without executing.

**Output**:
- `OK Route created` / `WARN Route already exists -- skipped`
- `OK Policy created` / `WARN Policy already exists -- skipped`

## Step 4 — Register and Verify Domain in Microsoft Entra ID

**Purpose**: Ensure the SBC hostname domain is registered and DNS-verified in the tenant's Entra ID.

**Actions**:
1. Extract domain from `cfg.SbcFqdn` (e.g. `staging.ivr.nuance.com` from `sip-eastus.staging.ivr.nuance.com`)
2. Check if domain is already registered: `Get-MgDomain -DomainId <domain>`
3. If registered and verified: `OK Domain already registered and verified. Skipping Step 4.`
4. If not registered: `New-MgDomain -BodyParameter @{Id=<domain>}` (only in live mode)
5. If registered but not verified:
   - Retrieve DNS verification records via `Get-MgDomainVerificationDnsRecord`
   - Display required TXT/CNAME records for manual DNS entry
   - Poll for verification: `Confirm-MgDomain` every 30 seconds, max 10 attempts (5 minutes)
   - Validate `IsVerified` flag after each attempt

**DryRun**: Step 4 is fully guarded — no `New-MgDomain` in dry run mode. Domain check (read-only) is still performed but `$verified` is NOT set to `$true` (v14.7.0 fix).

## Step 5 — Validate SBC, Routes, and Policies

**Purpose**: Confirm that the objects created in Steps 2–4 are visible and correct in Teams.

**Actions** (validates only config objects — not full ACS export):
1. `Get-CsOnlinePSTNGateway -Identity cfg.SbcFqdn` — must exist; Enabled=$false is expected at this stage
2. `Get-CsOnlineVoiceRoute -Identity cfg.RouteName` — must exist
3. `Get-CsOnlineVoiceRoutingPolicy -Identity cfg.RoutingPolicyName` — must exist

**Failure handling**: Reports each missing object with specific remediation guidance:
- Missing gateway → `Please re-run from Step 2`
- Missing route → `Please re-run from Step 3`
- Missing policy → `Please re-run from Step 3`

**Note**: Step 5 does NOT validate all ACS export trunks/routes. It only validates the three objects from `cfg`. This was the v14.15.0 fix.

**Confirm-Continue**: After successful validation, Step 5 shows a `Confirm-Continue` prompt: "Ready to proceed to Step 6?" before continuing. User can decline to pause the migration.

## Step 6 — Upload Phone Numbers into Teams

**Purpose**: Make the phone numbers available in the Teams tenant for assignment.

**Actions**:
1. `New-CsOnlineDirectRoutingTelephoneNumberUploadOrder` — bulk upload of all numbers in `cfg.ResourceAccounts` (always uses bulk API, not per-number `Set-CsPhoneNumberAssignment`)
2. Poll for DR number propagation: checks unassigned numbers every 10 seconds, max 120 seconds (2 minutes)

**Idempotency**: If number is already uploaded, Teams returns a non-fatal error; step treats it as a WARN.

**Timeout behavior**: If numbers have not appeared after the 120-second polling window, Step 6 emits a WARN (`"N number(s) did not appear in Teams after 120s..."`) and **continues** to Step 7 — the timeout is non-fatal. Teams provisioning may still complete in the background.

## Step 7 — Create Resource Accounts

**Purpose**: Create Teams application instances (resource accounts) for each phone number.

**Actions**:
Per resource account in `cfg.ResourceAccounts`:
1. `New-CsOnlineApplicationInstance -UserPrincipalName <UPN> -DisplayName <DisplayName> -ApplicationId <cfg.CommsProviderId>`
   - `-ApplicationId` is the CommsProviderId from config (the D365 `msdyn_occommunicationprovidersettingid`)
2. Store returned `ObjectId` in `$raObjectIds[UPN]`
3. Write `ra-objectids.json` after all accounts are created

**Authorization requirement**: `New-CsOnlineApplicationInstance` creates an AAD user object via Microsoft Graph. Requires:
- Teams Administrator role
- **User Administrator** role in Entra ID

**Existing RA reuse**: Before creating, uses `Get-CsOnlineApplicationInstance` to check if RA already exists. If found, reuses the existing ObjectId silently.

**RA stamping**: After creating an RA, the script attempts `Set-CsOnlineApplicationInstance` (not `Sync-CsOnlineApplicationInstance` — that runs later in Step 9) up to 5 times with 15-second delays to stamp `ApplicationId` and `AcsResourceId` onto the RA. Output shows `[stamped]` on success or `[stamp failed -- will retry on next run]` on failure.

**Retry logic**: RA creation retries up to 5 times with 15-second delay between attempts. After all RAs are created, `Wait-UntilRAsReady` polls for RA visibility in Teams (max 180 seconds, interval 10 seconds) to handle Azure AD replication latency. Optionally calls `Sync-CsOnlineApplicationInstance` to accelerate propagation.

**Resume without `ra-objectids.json`**: Falls back to live Teams lookup per RA UPN when the file is missing.

**Failure handling**: If creation fails (e.g. Unauthorized, duplicate UPN), records the error and continues to next RA. Does NOT populate ObjectId for failed accounts.

**DryRun**: Shows planned `New-CsOnlineApplicationInstance` without executing; does not write `ra-objectids.json`.

**Output**:
- `OK RA created: <UPN> (ObjectId: <id>)`
- `! RA creation failed for <UPN>: <error>`

## Step 8 — Assign Resource Account Licenses

**Purpose**: Assign `Teams Phone Resource Account` license (SKU: `PHONESYSTEM_VIRTUALUSER`) to each resource account.

**Actions**:
1. Find the `PHONESYSTEM_VIRTUALUSER` SKU ID via `Get-MgSubscribedSku`
2. Build `$pendingUPNs` — only UPNs where `$raObjectIds[UPN]` is non-empty (guard against Step 7 partial failure)
3. Per UPN: set `UsageLocation` on the user object via `Update-MgUser -UserId <ObjectId> -UsageLocation <UsageLocation>` (required before license assignment; uses `-UsageLocation` parameter, default `US`)
4. Per UPN: `Set-MgUserLicense -UserId <ObjectId> -AddLicenses @{SkuId=<skuId>} -RemoveLicenses @()`
5. Poll until licensed: `Get-MgUser -UserId <ObjectId> -Property AssignedLicenses` — retry every 15s, max 20 attempts (300 seconds total)
6. In-loop guard: skip UPNs with empty ObjectId (in case ObjectId was not populated)

**v14.16.0 fix**: `$pendingUPNs` construction filters to only UPNs with valid ObjectId. Inner loop also guards with `if (-not $objectId) { continue }`. This prevents `Get-MgUser -UserId ""` crash when Step 7 fails.

**DryRun**: Shows planned license assignment without executing.

## Step 9 — Assign Phone Numbers to Resource Accounts

**Purpose**: Assign the Direct Routing phone number to each resource account and back up D365 state.

**Actions**:
1. Acquire D365 token and back up current phone number state to `d365-phone-backup.json` (DryRun: skip). The backup queries **18 fields** per phone number including carrier, enabled flags, country code, objective, app module, and provider setting. See [D365 Integration — Backup fields](d365-integration.md#backup-fields-18-total) for the complete field list.
2. **Prior assignment removal**: Before assigning a number to a new RA, Step 9 checks if the number is already assigned to a different target and removes that assignment first.
3. Per resource account: `Set-CsPhoneNumberAssignment -Identity <UPN> -PhoneNumber <number> -PhoneNumberType DirectRouting`
   - **Retry logic**: Retries up to 6 times with 30-second delay for license activation errors (the PHONESYSTEM_VIRTUALUSER license may take time to propagate). After 6 failed attempts, the number's status is set to `InProgress` (not `Pending`) — indicating the assignment was attempted but did not complete within the retry window.
4. Export results to CSV at `-OutputPath`
5. **Post-sync D365 verification**: After `Sync-CsOnlineApplicationInstance`, queries D365 to verify `msdyn_teamsresourceaccount` and `msdyn_ocphonenumbersource` per number. Infers telephony status: if `msdyn_teamsresourceaccount` is set → `Telephony=Teams`; otherwise → `Telephony=ACS` (there is no literal "Telephony" field in D365; the status is derived from the RA link and source fields).

**DryRun**: Shows planned assignments; does not write backup JSON or CSV.

**D365 sync note**: Step 9 may show a Teams→D365 sync warning (`Sync did not link a Teams RA`). This is benign — Step 11 explicitly PATCHes the D365 record to link the Teams RA.

## Step 10 — Cutover

**Purpose**: Switch live call routing from ACS to Teams by enabling the Teams DR gateway and disabling the ACS trunk.

**Pre-cutover display**:
1. Current state banner:
   - ACS trunk: enabled=true (handling live calls)
   - Teams gateway: Enabled=$false (ready, not yet active)
2. Cutover checklist reminder:
   - All Steps 1–9 validated and signed off
   - End-to-end call routing tested
   - Maintenance window confirmed
   - SBC admin available

**Actions**:
1. Confirm-Continue prompt with explicit cutover impact warning
2. Invoke `Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath <cfg> -AutoConfirm`
3. Toggle auto-detects direction (ACS active) and flips: disable ACS trunk + enable Teams gateway
4. On success: log cutover timestamp and display rollback instructions (Toggle can auto-detect direction and re-enable ACS)

**Confirmation**: Step 10 shows a final Y/N prompt before calling Toggle (the `-AutoConfirm` suppresses Toggle's own prompt since the orchestrator already confirmed). If the user declines, Step 10 is skipped with exit code 0.

**Failure handling**: If Toggle fails (non-zero `$LASTEXITCODE`), it restores ACS routes before exiting. The migration script exits and reports the step as FAILED.

## Step 11 — D365 Update and Sync

**Purpose**: Update D365 phone records to reflect the Teams routing state and trigger CCaaS sync.

**Actions**:
Per resource account:
1. `Invoke-MigrateTpsPhoneNumber-v14.ps1 -PhoneNumber <number> -Direction ACS_TO_TPS -TeamsResourceAccountObjectId <ObjectId>`
   - `-TeamsResourceAccountObjectId` is passed conditionally — only when the ObjectId exists in `$raObjectIds` for that UPN
   - PATCH `msdyn_phonenumbertype = 1` (TPS)
   - PATCH `msdyn_ocphonenumbersource = 192350001` (TPS)
   - PATCH `msdyn_teamsresourceaccount = <ObjectId>` (link RA — raw GUID, not `@odata.bind` format)
   - Call `CCaaS_SynchronizePhoneNumbers` bound action
2. Log result per number

**Failure handling**: If a per-number invoke fails, the error is recorded and the script continues with remaining numbers. Step 11 tracks failures in `$step11Failed` and emits a warning summary at the end showing how many numbers failed D365 update.

**Output**:
- `OK D365 record updated for <number>`
- `OK CCaaS sync triggered for <number>`

## Run Record

After completion, the orchestrator writes to `stats/tpe-runs.jsonl`:
```json
{
  "timestamp": "2026-04-28T18:00:45Z",
  "type": "migrate",
  "result": "OK",
  "dryRun": false,
  "startStep": 3,
  "stopStep": 11,
  "completed": 1,
  "skipped": 0,
  "failures": 0,
  "phoneNumbers": ["+12202140029"],
  "logFile": "tpe-migration-run-20260428-180045.html",
  "configPath": "acs-tpe-config-fromd365.json",
  "d365OrgUrl": "https://ccaivrtest.crm.dynamics.com/"
}
```

The `type` field is `migrate` for complete runs (StopAfterStep >= 10) or `migrate-partial` for partial runs (StopAfterStep < 10). The `dryRun` boolean is always present; dry run records are written to JSONL even during dry runs so they appear in the dashboard history with a `(dry)` suffix.

## DryRun Behavior

The orchestrator's DryRun mode exits immediately after displaying the step plan summary with `[DRY RUN COMPLETE] No changes were made.` — no steps execute. This differs from individual script DryRun behavior where read-only operations (e.g. Teams/Graph connections, domain checks) still execute.

## HTML Footer

The orchestrator builds a detailed step summary table in the HTML footer showing which steps ran with checkmark indicators. Each step is listed with its name and a visual indicator of whether it completed successfully, was skipped, or failed.
