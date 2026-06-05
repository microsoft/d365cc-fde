# Dynamics 365 Integration

## Overview

The ACS-TPE tool interacts with Dynamics 365 (D365) Customer Service / CCaaS to:
1. Discover active ACS phone numbers (Phase 0D)
2. Back up phone number state before mutations (Step 9)
3. Update phone number type and source after migration (Step 11, FlipToTeams)
4. Clear Teams RA link after rollback (FlipToACS)
5. Trigger CCaaS synchronization

## Authentication

### Token Acquisition

**Primary method (config builder)**: Azure CLI token acquisition with D365 resource scope:

```powershell
$d365Token = az account get-access-token --resource "$D365OrgUrl" --query accessToken --output tsv
```

Used by `New-AcsTpeConfig-v14.ps1` and `Invoke-MigrateTpsPhoneNumber-v14.ps1`. Requires the user to be logged into az CLI with a principal that has D365 API access.

**Orchestrator method**: OAuth2 client_credentials flow against the D365 organization's authority:

```
POST https://login.microsoftonline.com/<TenantId>/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<ACS resource ID parsed from AcsConnectionString>
&client_secret=<ACS accesskey decoded from base64>
&scope=https://<D365OrgHost>/.default
```

**Fallback method**: Interactive browser-based authentication. Used when the client_credentials flow fails (e.g. ACS connection string credentials lack D365 permissions, or the tenant requires interactive consent). The script falls back to an interactive OAuth2 device code or browser flow, prompting the user to sign in.

The access token is cached for the duration of the script run. Token requests are retried on failure with exponential backoff.

### D365 Global Discovery Service

`New-AcsTpeConfig-v14.ps1` Phase 2 uses the D365 Global Discovery Service to auto-discover the D365 org URL:

```
GET https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances
Authorization: Bearer <token>
```

Token is acquired via: `az account get-access-token --resource "https://globaldisco.crm.dynamics.com"`

Response contains an array of D365 instances. Behavior:
- 1 instance → auto-selects its `ApiUrl`
- Multiple instances → interactive numbered list; user selects by index or types a URL directly
- 0 instances → prompts for manual URL entry
- Token failure → prompts for manual URL entry

### D365 API Base URL

Derived from `cfg.D365OrgUrl`:
```
https://<org>.crm.dynamics.com/api/data/v9.2/
```

All API calls use:
```
Authorization: Bearer <token>
OData-MaxVersion: 4.0
OData-Version: 4.0
Accept: application/json
```

### OData Headers

- All PATCH operations include `If-Match: *` header for unconditional updates
- Some scripts use `--output json` for az CLI token acquisition while others use `--output tsv`

## Phone Number Discovery (Phase 0D)

### Query: Active phone numbers

```
GET /api/data/v9.2/msdyn_ocphonenumbers
  ?$select=msdyn_name,msdyn_phonenumber,statecode,statuscode
  &$filter=statecode eq 0
  &$orderby=msdyn_phonenumber
```

Returns all active (`statecode=0`) phone number records. Each record has:
- `msdyn_phonenumber`: E.164 string (e.g. `+12202140029`)
- `msdyn_name`: display name
- `statecode`: 0=active

### Query: Route patterns for DR/DO classification

```
GET /api/data/v9.2/msdyn_ocphonenumberroutes
  ?$select=msdyn_ocphonenumberrouteid,msdyn_name,msdyn_pattern
```

ACS Direct Routing (DR) numbers match one of the ACS route patterns. Numbers not matching any ACS route pattern are Direct Outward Dialing (DO) and excluded from migration.

### FetchXML: Provider Setting Discovery

Used by `New-AcsTpeConfig-v14.ps1` Phase 3 and `Invoke-MigrateTpsPhoneNumber-v14.ps1` Step 1 to find the active Teams communication provider:

```xml
<fetch top="1">
  <entity name="msdyn_occommunicationprovidersetting">
    <attribute name="msdyn_occommunicationprovidersettingid" />
    <attribute name="msdyn_name" />
    <attribute name="msdyn_occommunicationproviderimmutableid" />
    <filter type="and">
      <condition attribute="statecode" operator="eq" value="0" />
      <condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" />
    </filter>
  </entity>
</fetch>
```

- `192350003` = Teams Phone System provider type
- `statecode=0` = active record
- Returns: `CommsProviderId` (`msdyn_occommunicationprovidersettingid`) and `AcsResourceId` (`msdyn_occommunicationproviderimmutableid`)

### FetchXML: DynamicsAppId Setting Entry

Used to retrieve the D365 App Registration Client ID:

```xml
<fetch>
  <entity name="msdyn_occommunicationprovidersettingentry">
    <attribute name="msdyn_key" />
    <attribute name="msdyn_value" />
    <filter type="and">
      <condition attribute="msdyn_key" operator="eq" value="DynamicsAppId" />
      <condition attribute="msdyn_communicationprovidersettingentid" operator="eq" value="<CommsProviderId>" />
    </filter>
  </entity>
</fetch>
```

FetchXML queries are URL-encoded and passed via `?fetchXml=` query parameter on the entity set endpoint.

### IncludeNumbers filter

After fetching all active DR numbers, the `IncludeNumbers` array from config is applied:
- If `IncludeNumbers` is non-empty: silently select only those numbers
- If `IncludeNumbers` is empty: show interactive numbered list; user selects which numbers to migrate

## Phone Number Record Schema

Key fields on `msdyn_ocphonenumber`:

| Field | Type | ACS value | TPS value | Description |
|-------|------|-----------|-----------|-------------|
| `msdyn_phonenumbertype` | int | `0` | `1` | 0=ACS, 1=Teams Phone System |
| `msdyn_ocphonenumbersource` | int | `192350000` | `192350001` | Source type option set |
| `msdyn_teamsresourceaccount` | lookup | null | RA entity ref | Linked Teams RA (systemuser record) |
| `msdyn_name` | string | — | — | Display name of the phone number |
| `msdyn_phonenumber` | string | — | — | E.164 phone number |
| `statecode` | int | 0 | 0 | 0=active |

## PATCH Operations

### ACS → TPS (migration / FlipToTeams, Step 11)

```http
PATCH /api/data/v9.2/msdyn_ocphonenumbers(<record-id>)
Content-Type: application/json

{
  "msdyn_phonenumbertype": 1,
  "msdyn_ocphonenumbersource": 192350001,
  "msdyn_teamsresourceaccount": "<Teams-RA-ObjectId>"
}
```

Followed by CCaaS sync.

### TPS → ACS (rollback / FlipToACS)

```http
PATCH /api/data/v9.2/msdyn_ocphonenumbers(<record-id>)
Content-Type: application/json

{
  "msdyn_phonenumbertype": 0,
  "msdyn_ocphonenumbersource": 192350000,
  "msdyn_teamsresourceaccount": null
}
```

**No CCaaS sync** after TPS→ACS PATCH. Sync would re-link the Teams RA and revert the rollback.

## CCaaS Sync

### Trigger

```http
POST /api/data/v9.2/msdyn_ocphonenumbers(<record-id>)/Microsoft.Dynamics.CRM.CCaaS_SynchronizePhoneNumbers
Content-Type: application/json

{}
```

Response: HTTP 200 with sync result, or HTTP 204 (no content) — both treated as success.

### When to sync

| Operation | Sync? | Sync Type |
|-----------|-------|-----------|
| ACS → TPS (Step 11, FlipToTeams) | Yes | `CCaaS_SynchronizePhoneNumbers` |
| TPS → ACS (FlipToACS Step C) | **No** | — |
| D365 backup before Step 9 | No | — |
| Repair-D365PhoneRecord | Optional | `msdyn_TelephonyACSSyncPhoneNumbersAction` |
| Undo Step 9 (D365 restore) | Yes | `msdyn_TelephonyACSSyncPhoneNumbersAction` |
| Undo Step 6 (post-removal re-patch) | Yes | `msdyn_TelephonyACSSyncPhoneNumbersAction` |

## D365 Sync from Azure (msdyn_TelephonyACSSyncPhoneNumbersAction)

In addition to `CCaaS_SynchronizePhoneNumbers`, some scripts trigger a D365-to-Azure sync action:

```http
POST /api/data/v9.2/msdyn_occommunicationprovidersettings(<ProviderId>)/Microsoft.Dynamics.CRM.msdyn_TelephonyACSSyncPhoneNumbersAction
Content-Type: application/json

{}
```

This action syncs phone number state from Azure back into D365. Used by:
- `Repair-D365PhoneRecord-v14.ps1` — after fix PATCH, if `CommsProviderId` and `AcsEndpoint` are available
- `Undo-ACS-TPE-Migration-v14.ps1` — after Step 9 D365 restore and after Step 6 DR number removal, to re-sync Azure state into D365

### Sync warning

D365 sync may return `Sync did not link a Teams RA` if the RA does not yet have a phone number assigned. This warning is **benign** when Step 11 follows immediately: Step 11 uses an explicit PATCH to set `msdyn_teamsresourceaccount` directly (raw GUID, not `@odata.bind` format), making the sync optional.

## D365 Backup

Before Step 9 mutations, the orchestrator backs up the current D365 state per phone number. The backup queries **without a `statecode` filter** to capture inactive records too (records that were deactivated by a prior sync or migration attempt).

```powershell
$backup = @{}
foreach ($ra in $cfg.ResourceAccounts) {
    $num = $ra.PhoneNumber
    $bkpUri = "$baseUrl/msdyn_ocphonenumbers?`$select=<18 fields>&`$filter=msdyn_phonenumber eq '$numEncoded'&`$orderby=statecode asc&`$top=1"
    $bkpR = Invoke-RestMethod -Uri $bkpUri -Headers $bkpHdrs -Method Get
    $backup[$num] = $bkpR.value[0]
}
$backup | ConvertTo-Json -Depth 5 | Set-Content -Path $d365BackupPath -Encoding UTF8
```

### Backup structure

The backup is a hashtable keyed by E.164 phone number, serialized as JSON:

```json
{
  "+12202140029": {
    "@odata.etag": "W/\"7794506\"",
    "msdyn_ocphonenumberid": "0e76113b-6956-ef11-a317-6045bdd4763a",
    "msdyn_phonenumber": "+12202140029",
    "msdyn_name": "+12202140029",
    "msdyn_phonenumbertype": null,
    "msdyn_ocphonenumbersource": 192350001,
    "msdyn_teamsresourceaccount": null,
    "statecode": 0,
    "statuscode": 1,
    "msdyn_type": 192350000,
    "msdyn_countryisocode": "US",
    "msdyn_phoneoutboundenabled": true,
    "msdyn_phoneinboundenabled": true,
    "msdyn_smsoutboundenabled": false,
    "msdyn_smsinboundenabled": false,
    "msdyn_objective": 192350000,
    "msdyn_appmodule": "192350000",
    "_msdyn_carrierid_value": "cccd8e92-113b-ef11-840a-6045bddaad1a",
    "_msdyn_occommunicationprovidersettingid_value": "f5736200-9038-ef11-8409-000d3a9e85b8"
  }
}
```

### Backup fields (18 total)

| # | Field | Type | Purpose |
|---|-------|------|---------|
| 1 | `msdyn_ocphonenumberid` | GUID | Primary key — record identity |
| 2 | `msdyn_phonenumber` | string | E.164 phone number |
| 3 | `msdyn_name` | string | Display name |
| 4 | `msdyn_phonenumbertype` | int/null | 0=ACS, 1=TPS, null=unset |
| 5 | `msdyn_ocphonenumbersource` | int | 192350000=ACS, 192350001=TPS/DR |
| 6 | `msdyn_teamsresourceaccount` | GUID/null | Linked Teams RA (systemuser) |
| 7 | `statecode` | int | 0=active, 1=inactive |
| 8 | `statuscode` | int | Status reason (1=active) |
| 9 | `msdyn_type` | int | Phone number type category |
| 10 | `msdyn_countryisocode` | string | ISO country code (e.g. `US`) |
| 11 | `msdyn_phoneoutboundenabled` | bool | Outbound voice enabled |
| 12 | `msdyn_phoneinboundenabled` | bool | Inbound voice enabled |
| 13 | `msdyn_smsoutboundenabled` | bool | Outbound SMS enabled |
| 14 | `msdyn_smsinboundenabled` | bool | Inbound SMS enabled |
| 15 | `msdyn_objective` | int | Phone number objective |
| 16 | `msdyn_appmodule` | string | Application module |
| 17 | `_msdyn_carrierid_value` | GUID | Carrier lookup (navigation property) |
| 18 | `_msdyn_occommunicationprovidersettingid_value` | GUID | Provider setting lookup (navigation property) |

### Backup path resolution

The backup file path is resolved relative to the config file directory:
- If `-ConfigPath` has a directory component: `<config-dir>/d365-phone-backup.json`
- If `-ConfigPath` is a bare filename: `.\d365-phone-backup.json`

### Backup error handling

- Token acquisition failure → WARN, continues without backup (undo will use fallback field values)
- Per-number query failure → WARN per number, continues to next number
- No D365 record found → INFO message "will be created fresh by Sync"

DryRun: backup file is not written.

## Summary Blocks

Every D365 script prints a formatted `========== SUMMARY ==========` block at the end of execution showing key operation details, field values before/after, and result status.

## Invoke-MigrateTpsPhoneNumber-v14.ps1

Standalone script for patching a single D365 phone record. Does NOT require a config file — only the D365 org URL and phone number.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-OrgUrl` | Yes | D365 organization URL (e.g. `https://contoso.crm.dynamics.com`) |
| `-PhoneNumber` | Yes | E.164 phone number to patch |
| `-Direction` | Yes | `ACS_TO_TPS` or `TPS_TO_ACS` (ValidateSet) |
| `-TeamsResourceAccountObjectId` | No | Teams RA ObjectId (GUID) for ACS_TO_TPS direction; when provided, sets `msdyn_teamsresourceaccount` (raw GUID) explicitly rather than relying on async CCaaS sync. Ignored for TPS_TO_ACS |
| `-DryRun` | No | Discover and display current state without PATCH or sync |

### Authentication

Uses az CLI to acquire a D365-scoped Bearer token: `az account get-access-token --resource "$OrgUrl"`

**Three distinct header sets**: The script uses separate header objects — `$headersGet` (Accept: application/json), `$headersPatch` (Content-Type: application/json, If-Match: *), and `$headersPost` (Content-Type: application/json) — each with appropriate OData version headers.

### 6-Step Workflow

1. Auto-discover active Teams provider setting (FetchXML: `msdyn_occommunicationprovider = 192350003, statecode = 0`)
2. Retrieve DynamicsAppId setting entry (informational)
3. Lookup phone number record by `msdyn_phonenumber` filter. If multiple D365 records match the phone number, logs a warning and uses the first record.
4. PATCH phone type fields (see PATCH Operations above). Uses `msdyn_teamsresourceaccount` (not `msdyn_teamsresourceaccount@odata.bind`) for the RA binding in the PATCH body.
5. Verify PATCH by re-reading the record
6. Call `CCaaS_SynchronizePhoneNumbers` (ACS_TO_TPS only; TPS_TO_ACS skips to avoid re-linking). When no `-TeamsResourceAccountObjectId` is provided for ACS_TO_TPS, prints a user-facing tip suggesting to pass the parameter for explicit binding.

### Validation

- `-PhoneNumber` must match `^\+[1-9]\d{6,14}$` (E.164)
- Direction mismatch warning: if current `msdyn_phonenumbertype` already matches the target type, shows a sanity warning but proceeds
- D365 record must exist (Step 3 fails if no matching phone number found)

### DryRun Behavior

DryRun mode exits with code 0 after displaying planned changes (before Step 4 PATCH). Shows the would-be PATCH body.

### HTTP 204 Handling

PowerShell may treat HTTP 204 (No Content) from the sync endpoint as an error in some versions. The script catches this specifically and treats it as success.

### Summary Block

After completion, prints a formatted summary including DynamicsAppId, Immutable ID, previous/new type, and provider setting info.

## Repair-D365PhoneRecord-v14.ps1

Corrects corrupted D365 phone number records where the type/source fields are inconsistent.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ConfigPath` | Yes | ACS-TPE config JSON (needs D365OrgUrl, TenantId) |
| `-PhoneNumbers` | No | Array of E.164 phone numbers to repair (default: empty = queries ALL active `msdyn_ocphonenumbers` records from D365) |
| `-Fix` | No | Apply PATCH to repair detected issues. Without `-Fix`, the script operates in read-only diagnostic mode by default. There is no `-DryRun` switch — the inverted control model means the default is safe (read-only). |

**E.164 validation**: Each supplied phone number is validated against `^\+[1-9]\d{6,14}$` before processing.

### Mismatch Detection

| Condition | Inconsistency | Repair action |
|-----------|---------------|---------------|
| `type=1` + `source=192350000` (ACS) | TPS type but ACS source | PATCH source → `192350001` |
| `type=0` + `source=192350001` (TPS) | ACS type but TPS source | PATCH source → `192350000` |
| `type=0` + RA link present | ACS type with Teams RA bound | PATCH RA link → `null` |
| `type=1` + RA link missing | TPS type without Teams RA | WARN (requires manual RA lookup to fix) |

### Actions

1. Fetch the phone record from D365
2. Classify each record as `ACS-purchased`, `BYON Direct Routing (pre-migration)`, `Migrated to Teams (Teams RA active)`, or `unknown`
3. Detect mismatches between `msdyn_phonenumbertype`, `msdyn_ocphonenumbersource`, and `msdyn_teamsresourceaccount`
4. PATCH the record to restore consistency (PATCH body includes `statuscode = 1` alongside `statecode = 0`)
5. Trigger `msdyn_TelephonyACSSyncPhoneNumbersAction` automatically whenever fixes are applied and `CommsProviderId` + `AcsEndpoint` are available from the config

### BYON Direct Routing Awareness

The script distinguishes between BYON DR numbers (source=192350001 with no Teams RA) and migrated numbers using tri-state logic:
- `source=192350001` with **no** RA → valid BYON DR number, not flagged
- `source=192350001` with active RA → migrated number, flagged only if type/source mismatch detected
- `source=192350000` with active RA → ACS type with Teams RA bound, flagged for repair

The script does NOT force source to ACS (192350000) for BYON numbers — only restores source when both TPS source and active RA link are present.

### Deleted Records Guidance

When no records are found for a phone number, the script provides specific guidance about re-importing the number via ACS resource sync.

## Update-PhoneNumberType-v14.ps1

Update `msdyn_phonenumbertype` and `msdyn_ocphonenumbersource` for a single phone number. Requires the Teams RA GUID for ACS_TO_TPS direction.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-OrgUrl` | Yes | D365 organization URL |
| `-PhoneNumber` | Yes | E.164 phone number to update |
| `-Direction` | Yes | `ACS_TO_TPS` or `TPS_TO_ACS` (ValidateSet) |
| `-TeamsResourceAccount` | Required for ACS_TO_TPS | Teams RA ObjectId (GUID) to bind |
| `-DryRun` | No | Show plan without mutations |

### 5-Step Workflow

1. Lookup phone number record (select: id, phonenumber, name, type, teamsresourceaccount, statecode)
2. Display current state
3. PATCH with `msdyn_ocphonenumbersource` parity (ACS=192350000, Teams DR=192350001)
4. GET verification
5. Auto-discover provider + call `CCaaS_SynchronizePhoneNumbers` (ACS_TO_TPS only)

### Validation

- Each number validated as E.164 before processing
- Provider array bounds checked before accessing index [0]
- PATCH wrapped in try-catch; failures logged per-number, continue to next

### TeamsResourceAccount Enforcement

For ACS_TO_TPS direction, the `-TeamsResourceAccount` parameter is enforced with `Write-Error` + `exit 1` if missing.

### Provider Auto-Discovery Details

Step 5 uses a full FetchXML query with array bounds check and nested try-catch. Guard: `if (-not $provResp.value -or $provResp.value.Count -eq 0)` warns and skips sync if no provider found.

### TPS_TO_ACS Sync Skip

Prints an explanation of why sync is skipped for TPS_TO_ACS direction.

### Verification GET Error Handling

If the verification GET fails, warns "PATCH may have succeeded" and exits with code 0 (success).

### Summary Block

Formatted summary with Direction, Phone Number, Record ID, Previous/New Type, Source, Resource Account, and Result.

## Sync-TeamsPhoneNumbers-v14.ps1

Auto-discovers the Teams provider setting and triggers CCaaS sync. Combines Steps 1–3 of Invoke-TeamsPhoneSync into a single command.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-OrgUrl` | Yes | D365 organization URL |

### 3-Step Workflow

1. Query active Teams provider setting (FetchXML: `msdyn_occommunicationprovider = 192350003, statecode = 0`)
2. Retrieve DynamicsAppId setting entry (informational, non-fatal if missing)
3. POST `CCaaS_SynchronizePhoneNumbers` bound action

### Error Handling

- Steps 1 and 2 HTTP calls wrapped in try-catch (v14.11.0)
- Step 2 failure is non-fatal (warning only)
- HTTP 204 from sync endpoint is treated as success (same as 200)

### Immutable ID Display

Retrieves and displays the `msdyn_occommunicationproviderimmutableid` field from the provider setting record.

### Entry Iteration

Iterates DynamicsAppId entries with a sequential counter display (`Entry $i`).

### Summary Block

Formatted summary with Provider Setting Name/ID, Immutable ID, DynamicsAppId, and sync status.

## Invoke-TeamsPhoneSync-v14.ps1

Calls CCaaS sync using an explicit provider setting ID. Use when the provider setting is already known.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-OrgUrl` | Yes | D365 organization URL |
| `-ProviderSettingId` | Yes | GUID of the `msdyn_occommunicationprovidersetting` record |

### Validation

- `ProviderSettingId` must be a valid GUID (validated with `[System.Guid]::Parse` inside a try-catch block)
- HTTP calls wrapped in try-catch (v14.11.0)
- HTTP 204 from sync endpoint is treated as success (same as 200)
