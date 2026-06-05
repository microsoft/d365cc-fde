# ACS REST API

## Overview

The ACS-TPE tool interacts with Azure Communication Services (ACS) via its SIP routing REST API to manage trunks and voice routes. All ACS API calls use HMAC-SHA256 request signing derived from the ACS connection string.

## Authentication

### Connection String

The ACS connection string contains two components:

```
endpoint=https://<resource>.communication.azure.com/;accesskey=<base64-encoded-key>
```

Parsing:
- Extract `endpoint` value (strip trailing `/` if present) — used as base URL
- Extract `accesskey` value — base64-decoded into a byte array for HMAC signing

### HMAC-SHA256 Request Signing

Every ACS REST API request is authenticated with an `Authorization` header using the HMAC-SHA256 scheme. The signing process:

**1. Compute content hash**

For GET requests, the content hash is the SHA256 of an empty string:
```
x-ms-content-sha256 = Base64(SHA256(""))
```

For PATCH requests, the content hash is the SHA256 of the JSON request body:
```
x-ms-content-sha256 = Base64(SHA256(requestBody))
```

**2. Build the canonical signing string**

```
<METHOD>\n<pathAndQuery>\n<date>;<host>;<contentHash>
```

- `METHOD`: `GET` or `PATCH` (uppercase)
- `pathAndQuery`: URL path including query string (e.g. `/sip?api-version=2023-04-01-preview`)
- `date`: UTC date in RFC 1123 format (`[System.DateTime]::UtcNow.ToString('r')`)
- `host`: ACS endpoint hostname (e.g. `resource.communication.azure.com`)
- `contentHash`: the `x-ms-content-sha256` value computed in step 1

**3. Compute HMAC signature**

```powershell
$keyBytes = [System.Convert]::FromBase64String($acsAccessKey)
$hmac     = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
try {
    $sig = [System.Convert]::ToBase64String(
        $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($signingString))
    )
} finally {
    $hmac.Dispose()
}
```

**4. Set request headers**

```
x-ms-date:           <RFC 1123 UTC date>
x-ms-content-sha256: <content hash>
Authorization:       HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=<sig>
Content-Type:        application/merge-patch+json    (PATCH only)
```

### Crypto Object Lifecycle

All cryptographic objects (`HMACSHA256`, `SHA256`) must be disposed immediately after use via `try/finally`:

```powershell
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $bodyHash = [System.Convert]::ToBase64String(
        $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($body))
    )
} finally {
    $sha256.Dispose()
}
```

This pattern is mandatory for both `Invoke-AcsGet` and `Invoke-AcsPatch` helper functions. Direct use of crypto objects without `Dispose()` is a bug.

## API Version

```
api-version=2023-04-01-preview
```

All ACS SIP routing calls use this version string in the query parameter.

## Endpoints

### GET — Retrieve SIP Configuration

```
GET https://<acs-endpoint>/sip?api-version=2023-04-01-preview
```

Returns the full SIP configuration including all trunks and routes:

```json
{
  "trunks": {
    "sip-eastus-yt-00.staging.ivr.nuance.com": {
      "sipSignalingPort": 5061,
      "enabled": true
    }
  },
  "routes": [
    {
      "name": "route-name",
      "description": "",
      "numberPattern": "^\\+12202140029$",
      "trunks": ["sip-eastus-yt-00.staging.ivr.nuance.com"]
    }
  ]
}
```

The `enabled` field on trunk objects indicates whether the trunk is active. Scripts that read trunk state use null-safe property access (`PSObject.Properties['enabled']`) and default to `$true` if the field is absent (older ACS API responses may omit it).

**Used by**:
- Step 1 (export ACS config to `acs-export.json`)
- Step 2 (read current trunk state before modification)
- Toggle (read current trunk state for direction detection and route backup)

### PATCH — Update SIP Configuration

```
PATCH https://<acs-endpoint>/sip?api-version=2023-04-01-preview
Content-Type: application/merge-patch+json
```

Uses JSON Merge Patch semantics. The body contains only the fields to update.

**Disable trunk (Step 2, Toggle ACS→TPE)**:
```json
{
  "trunks": {
    "sip-eastus-yt-00.staging.ivr.nuance.com": {
      "sipSignalingPort": 5061
    }
  },
  "routes": []
}
```

Removes all routes and leaves the trunk entry present but effectively disabled (no routes to match).

**Note on `Add-AcsTrunkDisabled-v14.ps1`**: This script does NOT perform a GET before PATCH — it sends the PATCH directly with the trunk FQDN and port from config. The body format differs from the orchestrator's Step 2: it uses `{"trunks":{"<fqdn>":{"sipSignalingPort":<port>,"enabled":false}}}` (merge-patch setting a trunk-level `enabled` flag).

**Restore trunk (Step 2 re-enable, Toggle TPE→ACS)**:
```json
{
  "trunks": {
    "sip-eastus-yt-00.staging.ivr.nuance.com": {
      "sipSignalingPort": 5061
    }
  },
  "routes": [
    {
      "name": "route-name",
      "numberPattern": "^\\+12202140029$",
      "trunks": ["sip-eastus-yt-00.staging.ivr.nuance.com"]
    }
  ]
}
```

Restores the original routes from the saved `acs-export.json` snapshot.

### PATCH Atomicity

ACS PATCH operations on the `/sip` endpoint are atomic: routes and trunk state are updated together in a single call. Partial updates (e.g. clearing routes in one call and disabling trunk in another) can trigger HTTP 422 from ACS if the intermediate state is invalid. Always send routes and trunk state in the same PATCH body.

## Helper Functions

Each script that calls the ACS REST API defines two internal helper functions:

### Invoke-AcsGet

```powershell
function Invoke-AcsGet {
    $date   = [System.DateTime]::UtcNow.ToString('r')
    $keyB   = [System.Convert]::FromBase64String($acsKey)
    $toSign = "GET`n$pq`n$date;$apiHost;$EMPTY"
    $hmac   = [System.Security.Cryptography.HMACSHA256]::new($keyB)
    try {
        $sig = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
    } finally { $hmac.Dispose() }
    $hdrs = @{
        'x-ms-date'           = $date
        'x-ms-content-sha256' = $EMPTY
        'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
    }
    Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $hdrs
}
```

`$EMPTY` is the pre-computed SHA256 hash of an empty string (`47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`).

### Invoke-AcsPatch

```powershell
function Invoke-AcsPatch([string]$body) {
    $date   = [System.DateTime]::UtcNow.ToString('r')
    $keyB   = [System.Convert]::FromBase64String($acsKey)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bodyHash = [System.Convert]::ToBase64String($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($body)))
    } finally { $sha256.Dispose() }
    $toSign = "PATCH`n$pq`n$date;$apiHost;$bodyHash"
    $hmac   = [System.Security.Cryptography.HMACSHA256]::new($keyB)
    try {
        $sig = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
    } finally { $hmac.Dispose() }
    $hdrs = @{
        'x-ms-date'           = $date
        'x-ms-content-sha256' = $bodyHash
        'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
        'Content-Type'        = 'application/merge-patch+json'
    }
    Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $hdrs -Body $body
}
```

### Closure Variables

Both helpers rely on script-scoped variables set before first call:
- `$acsEp` — ACS endpoint URL (from connection string)
- `$acsKey` — ACS access key (from connection string)
- `$apiVer` — API version string (`2023-04-01-preview`)
- `$pq` — path and query string (`/sip?api-version=2023-04-01-preview`)
- `$apiUrl` — full URL (`$acsEp$pq`)
- `$apiHost` — hostname extracted via `[System.Uri]`
- `$EMPTY` — SHA256 of empty string (pre-computed constant)

### Set-AcsSbcFqdn-v14.ps1 Helpers

`Set-AcsSbcFqdn-v14.ps1` contains the most mature helper implementations across the suite:

- **`Build-HmacHeaders`**: A reusable function that encapsulates the full HMAC signing process for both GET and PATCH methods, including body hash computation and header assembly. Accepts the HTTP method and optional body, returns a ready-to-use headers hashtable.
- **`Parse-ConnectionString`**: A standalone function for splitting ACS connection strings into endpoint and access key components.
- **`_raw` field preservation**: When renaming a trunk, the script copies all non-standard fields from the original trunk object to the new entry, ensuring unknown/future ACS trunk properties are preserved during rename operations.

## Verification GET Pattern

Three scripts perform a full HMAC-signed verification GET after a successful PATCH to confirm the trunk/route state was actually applied:

| Script | What it verifies |
|--------|-----------------|
| `Add-AcsTrunkDisabled-v14.ps1` | Trunk was created with the correct port and enabled state |
| `Fix-AcsRoutePattern-v14.ps1` | Route pattern and trunk list match the PATCH payload |
| `Set-AcsSbcFqdn-v14.ps1` | Renamed FQDN appears in the GET response |

**Graceful degradation**: Verification GET failure is **non-fatal** — it emits a warning (Yellow for partial mismatches, Red for HTTP errors) but does NOT exit with error. The PATCH itself is considered the source of truth for success/failure.

**Authentication**: The verification GET uses the same HMAC-SHA256 authentication as all other ACS calls.

**Crypto disposal**: Verification GET crypto objects (`$getSha`, `$getHmac` or `$vSha`, `$vHmac`) must also be disposed via `try/finally`, just like the primary request crypto objects.

## Error Handling

- HTTP 4xx/5xx responses from `Invoke-RestMethod` throw terminating errors (caught by `$ErrorActionPreference = 'Stop'`)
- Step 2 catch block: if Teams gateway creation fails after ACS is disabled, the catch block restores ACS routes before re-throwing
- Toggle catch block: if `Set-CsOnlinePSTNGateway -Enabled $true` fails during ACS→TPE flip, ACS routes are restored from the saved snapshot

### Error Detail Extraction

On PATCH failure, scripts extract detailed error info using `$_.ErrorDetails.Message`. If `ErrorDetails.Message` is null, the scripts fall back to reading the response stream directly via `GetResponseStream()` + `StreamReader`. This provides richer error context than the default PowerShell exception message, which often truncates the ACS error response body.

## File Artifacts

### acs-trunk-disabled.json

Written by Step 2 after disabling the ACS trunk. Contains the FQDN(s) that were disabled during zero-downtime registration:

```json
["sip-eastus-yt-00.staging.ivr.nuance.com"]
```

Read by:
- **Undo Step 2**: determines which trunks to re-enable when reversing the migration
- **Toggle TPE→ACS**: falls back to `acs-export.json` routes, not `acs-trunk-disabled.json`

Not written in DryRun mode.

### acs-export.json

Written by Step 1 (full ACS SIP config snapshot) and overwritten by Toggle during ACS→TPE cutover (route-only snapshot for rollback). Structure:

```json
{
  "trunks": { "<fqdn>": { "sipSignalingPort": 5061 } },
  "routes": [ { "name": "...", "numberPattern": "...", "trunks": ["..."] } ]
}
```

## DryRun Behavior

When `-DryRun` is active:
- `Invoke-AcsGet` is still called (read-only; needed for direction detection and export)
- `Invoke-AcsPatch` is NOT called; the planned PATCH body is logged to the HTML run log instead
- The planned body is shown with `(DRY RUN) Would PATCH ACS trunk: <body>`
