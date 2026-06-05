# Teams Integration

## Overview

The ACS-TPE tool uses two PowerShell modules to interact with Microsoft Teams and Entra ID:
- `MicrosoftTeams` — Teams Direct Routing, resource accounts, phone number assignment
- `Microsoft.Graph` — Entra ID domain management, user licensing

## Module Installation (Phase 0)

```powershell
# Auto-installed if missing (CurrentUser scope for non-admin installs)
Install-Module MicrosoftTeams -Force -AllowClobber -Scope CurrentUser
Install-Module Microsoft.Graph -Force -AllowClobber -Scope CurrentUser
```

## Authentication

### Teams Module

```powershell
# Pre-check: reuse existing session if available
$tenant = Get-CsTenant -ErrorAction SilentlyContinue
if (-not $tenant) {
    Connect-MicrosoftTeams -TenantId $cfg.TenantId
}
```

Interactive browser-based auth (device code flow for headless environments). Before connecting, Phase 0 checks for an existing session via `Get-CsTenant`; if a session is already active, the connection is reused. Session is reused within a script run. In resume mode (`-StartAtStep > 0`), the script reconnects to both Teams and Graph before continuing.

### Graph Module

```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All","Organization.Read.All","Directory.ReadWrite.All","Domain.ReadWrite.All" -TenantId $cfg.TenantId
```

Required scopes:
- `User.ReadWrite.All` — create and license resource accounts (AAD users)
- `Organization.Read.All` — read organization/tenant metadata
- `Directory.ReadWrite.All` — read/write directory objects
- `Domain.ReadWrite.All` — domain registration and management in Entra ID

## Required Roles

| Operation | Required Role |
|-----------|--------------|
| All Teams DR operations | **Teams Administrator** |
| `New-CsOnlineApplicationInstance` (Step 7) | **User Administrator** (Entra ID) |
| Domain registration (Step 4) | **Global Administrator** or **Domain Name Administrator** |
| License assignment (Step 8) | **License Administrator** |

**Important**: `New-CsOnlineApplicationInstance` creates an AAD user object via Microsoft Graph on behalf of the caller. This requires the **User Administrator** role in addition to Teams Administrator. Without it, Step 7 returns `user not authorized`.

## Teams Direct Routing Gateway

### Registration (Step 2)

```powershell
New-CsOnlinePSTNGateway `
    -Identity        $cfg.SbcFqdn `
    -SipSignalingPort $sbcPort `
    -Enabled         $false `
    -MediaBypass     $false
```

The gateway is created disabled (`Enabled=$false`) and stays dormant until Step 10.

### Port extraction

SBC FQDN may include port: `sip-eastus-yt-00.staging.ivr.nuance.com:5061`
- If port suffix present: extract numeric port, use as `-SipSignalingPort`
- If no suffix: default to `5061`
- Port must parse as integer; non-numeric port triggers validation error

### Validation (Step 5)

```powershell
Get-CsOnlinePSTNGateway -Identity $cfg.SbcFqdn
```

Expected: gateway exists; `Enabled=$false` is correct at Steps 5–9. `Enabled=$true` would indicate an unexpected state.

### Cutover (Step 10)

```powershell
Set-CsOnlinePSTNGateway -Identity $cfg.SbcFqdn -Enabled $true
```

Called atomically by Toggle after ACS trunk is disabled. On failure, Toggle restores the ACS trunk.

### Rollback

```powershell
Set-CsOnlinePSTNGateway -Identity $cfg.SbcFqdn -Enabled $false
```

Called by Toggle when flipping TPE → ACS.

## PSTN Usages, Voice Routes, Voice Routing Policy (Step 3)

### PSTN Usage

```powershell
Set-CsOnlinePstnUsage -Usage $cfg.PstnUsageName
```

Idempotent: warns if usage already exists.

### Voice Route

```powershell
$pattern = '^' + (($cfg.ResourceAccounts | ForEach-Object { [regex]::Escape($_.PhoneNumber) }) -join '|^') + '$'

New-CsOnlineVoiceRoute `
    -Identity               $cfg.RouteName `
    -NumberPattern          $pattern `
    -OnlinePstnGatewayList  $cfg.SbcFqdn `
    -OnlinePstnUsages       $cfg.PstnUsageName
```

Route pattern matches only the migrated numbers exactly. Single number example: `^\+12202140029$`. Multiple: `^\+12202140029$|^\+14255550100$`.

### Voice Routing Policy

```powershell
New-CsOnlineVoiceRoutingPolicy `
    -Identity          $cfg.RoutingPolicyName `
    -OnlinePstnUsages  $cfg.PstnUsageName
```

## Phone Number Upload (Step 6)

```powershell
Set-CsPhoneNumberAssignment `
    -PhoneNumber      $ra.PhoneNumber `
    -PhoneNumberType  DirectRouting `
    -AssignmentCategory Unassigned
```

Makes the number available in the Teams tenant without assigning it to a specific user or RA yet.

**Bulk upload**: The implementation always uses `New-CsOnlineDirectRoutingTelephoneNumberUploadOrder` for bulk upload, not per-number `Set-CsPhoneNumberAssignment`. Upload order status is tracked via `Get-CsOnlineDirectRoutingTelephoneNumberUploadOrder`.

**Propagation polling**: After upload, polls for DR number availability every 10 seconds, max 120 seconds (2 minutes), to ensure numbers are visible before proceeding to Step 7. If numbers are still not visible after the polling window, Step 6 emits a WARN and **continues** — the timeout is non-fatal because Teams provisioning may complete in the background.

## Resource Accounts (Step 7)

Resource accounts are Teams application instances — special AAD users linked to a communications provider.

### Creation

```powershell
$ra = New-CsOnlineApplicationInstance `
    -UserPrincipalName  $ra.UPN `
    -DisplayName        $ra.DisplayName `
    -ApplicationId      $cfg.CommsProviderId
```

Returns an object with `ObjectId` property (AAD object ID of the new user).

### ra-objectids.json

After all RAs are created, the script writes:
```json
{
  "ra_12202140029@tenant.onmicrosoft.com": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

This file scopes flip scripts to numbers migrated in this specific run.

### Existing RA Reuse

Before creating a new RA, the script uses `Get-CsOnlineApplicationInstance -Identity <UPN>` to check if the RA already exists. If found, the existing ObjectId is reused silently (no WARN, no error). This differs from the "UPN conflict" error path which occurs during `New-CsOnlineApplicationInstance` creation — that path triggers the retry/failure logic described below.

### RA Stamping

After creating an RA, the script attempts `Set-CsOnlineApplicationInstance` up to 5 times with 15-second delays to stamp `ApplicationId` and `AcsResourceId` onto the RA. Output shows `[stamped]` on success or `[stamp failed -- will retry on next run]` on failure. This stamping logic is separate from the RA creation retry logic below.

### Retry logic

RA creation retries up to 5 times per RA with 15-second delay between attempts. After all RAs are created, `Wait-UntilRAsReady` polls for RA visibility in Teams every 10 seconds (max 180 seconds) to handle Azure AD replication latency.

Optionally calls `Sync-CsOnlineApplicationInstance` to accelerate AAD→Teams propagation.

### Partial failure handling

If `New-CsOnlineApplicationInstance` fails for one RA (e.g. UPN already exists, authorization error), the script:
- Logs the error with `!` prefix
- Continues to the next RA
- Does NOT populate `ObjectId` for the failed RA
- Step 8 guards against empty ObjectId by filtering `$pendingUPNs`

## License Assignment (Step 8)

### SKU Discovery

```powershell
$sku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER' }
$skuId = $sku.SkuId
```

`PHONESYSTEM_VIRTUALUSER` is the Teams Phone Resource Account license.

### UsageLocation Pre-Set

Before assigning a license, the resource account's `UsageLocation` must be set. Azure AD requires a usage location for license assignment.

```powershell
Update-MgUser -UserId $objectId -UsageLocation $UsageLocation
```

The `-UsageLocation` parameter on the orchestrator (default: `US`) provides the 2-character ISO country code. This must be set before `Set-MgUserLicense` or the license assignment will fail with a "usage location" error.

### Assignment

```powershell
Set-MgUserLicense `
    -UserId         $objectId `
    -AddLicenses    @(@{ SkuId = $skuId }) `
    -RemoveLicenses @()
```

### Polling

After assignment, the script polls until the license appears:
```powershell
do {
    Start-Sleep -Seconds 15
    $mgUser = Get-MgUser -UserId $objectId -Property AssignedLicenses
    $licensed = $mgUser.AssignedLicenses | Where-Object { $_.SkuId -eq $skuId }
} while (-not $licensed -and $attempt++ -lt 20)
```

Max wait: 20 × 15s = 5 minutes. If not licensed after 5 minutes, reports WARN and continues.

### Guard (v14.16.0)

```powershell
$pendingUPNs = @($cfg.ResourceAccounts | Where-Object { $raObjectIds[$_.UPN] } | ForEach-Object { $_.UPN })
```

Only UPNs with a valid (non-empty) ObjectId in `$raObjectIds` are included in the polling loop. UPNs where Step 7 failed are skipped silently.

### Phase 0 License Pre-Check

Phase 0 compares available `PHONESYSTEM_VIRTUALUSER` license count against `ResourceAccounts.Count` and hard exits if insufficient licenses are available. This prevents the orchestrator from proceeding through Steps 1-7 only to fail at Step 8 due to license exhaustion.

## Phone Number Assignment to Resource Accounts (Step 9)

```powershell
Set-CsPhoneNumberAssignment `
    -Identity        $ra.UPN `
    -PhoneNumber     $ra.PhoneNumber `
    -PhoneNumberType DirectRouting
```

Assigns the Direct Routing number to the resource account identity.

**Prior assignment removal**: Before assigning a number to a new RA, Step 9 checks if the number is already assigned to a different target and removes that assignment first using `Remove-CsPhoneNumberAssignment`. This ensures the assignment succeeds even when a number was previously bound to another RA or user.

**Retry logic**: Retries up to 6 times with 30-second delay between attempts. This handles cases where the PHONESYSTEM_VIRTUALUSER license has not yet fully propagated — the assignment may fail with a license-related error until the license is active.

## Domain Registration (Step 4)

### Check

```powershell
$domain = Get-MgDomain -DomainId $domainName -ErrorAction SilentlyContinue
if ($domain -and $domain.IsVerified) { # skip }
```

### Register

```powershell
New-MgDomain -BodyParameter @{ Id = $domainName }
```

Only executed in live mode (DryRun guard). If domain already exists, step is skipped with `OK`.

### Verification

Domain verification requires a DNS TXT record. The script displays the required record if the domain is registered but not yet verified. The operator must add the DNS record externally; Step 4 will pass on a subsequent run once DNS propagates.

## Undo (Undo-ACS-TPE-Migration-v14.ps1)

Full undo of a completed migration, reversing Steps 9 through 1 (high-to-low):

| Undo Step | Action |
|-----------|--------|
| Step 9 | `Remove-CsPhoneNumberAssignment` per RA |
| Step 8 | Remove `PHONESYSTEM_VIRTUALUSER` license from each RA (`Set-MgUserLicense -RemoveLicenses`) |
| Step 7 | `Remove-MgUser` per RA (using ObjectId from `ra-objectids.json`); backs up ra-objectids.json with undooperation timestamp |
| Step 6 | `Remove-CsOnlineTelephoneNumber` per number; post-removal D365 re-patch and sync |
| Step 4 | Remove registered domain from Entra ID (`Remove-MgDomain`) |
| Step 3 | Remove voice routing policy, voice routes, PSTN usage |
| Step 2 | Remove Teams DR gateway; PATCH ACS trunk to re-enable with original routes (from `acs-export.json`) |
| Step 1 | Backup reference only (file kept) |

Steps 5, 10, 11 have no undo action: Step 5 is read-only validation; Steps 10–11 are reversed by `Invoke-FlipToACS-v14.ps1`.

Supports `-StartAtStep` / `-StopAfterStep` for partial undo (e.g. `-StartAtStep 9 -StopAfterStep 7` undoes only Steps 9, 8, 7).

Undo is scoped to the numbers in `ra-objectids.json`. Uses `Test-IsIgnorableUndoError()` to classify "already removed" errors as benign.
