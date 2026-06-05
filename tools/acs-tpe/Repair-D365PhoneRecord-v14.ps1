#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnoses and optionally restores D365 msdyn_ocphonenumbers records to ACS state.

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.11.0   : Version string parity with all scripts.
    v14.9.0    : Version string parity with all scripts.
    v14.8.0    : Version string parity with all scripts.
    v14.6.0    : Update-PhoneNumberType msdyn_ocphonenumbersource parity + DryRun + sync,
                 Fix-AcsRoutePattern parameterized (no hardcoded FQDN/pattern) + DryRun,
                 Add-AcsTrunkDisabled DryRun switch, Set-AcsSbcFqdn blank FQDN validation,
                 Archive-TpeRuns Sort-Object dedup fix, Invoke-TeamsPhoneSync GUID validation,
                 version strings bumped to v14.6.0.
    v14.0.0    : Compatible with v10 migration (no ACS consent step).

.DESCRIPTION
    After an Undo run, phone numbers that were migrated to Teams may disappear from
    D365 CSAC (Channels -> Phone numbers) because:
      1. msdyn_teamsresourceaccount was not cleared, OR
      2. msdyn_ocphonenumbersource was left as 192350001 (Teams DR) with no RA, OR
      3. statecode was set to 1 (inactive) by D365's sync when Teams removed the number.

    This script queries D365 for each phone number, shows the current state, and
    (with -Fix) patches the record back to visible ACS state.

.PARAMETER ConfigPath
    Path to acs-tpe-config-fromd365-local.json (provides D365OrgUrl, TenantId).

.PARAMETER PhoneNumbers
    One or more E.164 phone numbers to check (e.g. +12069990030).
    If omitted, discovers all msdyn_ocphonenumbers records.

.PARAMETER Fix
    Apply the repair PATCH. Without this switch the script is read-only (diagnosis only).

.EXAMPLE
    .\Repair-D365PhoneRecord-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -PhoneNumbers +12069990030
    .\Repair-D365PhoneRecord-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -PhoneNumbers +12069990030 -Fix
    .\Repair-D365PhoneRecord-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -Fix
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [string[]]$PhoneNumbers = @(),
    [switch]$Fix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate E.164 format on any supplied phone numbers
foreach ($pn in $PhoneNumbers) {
    if ($pn -notmatch '^\+[1-9]\d{6,14}$') {
        Write-Host "  ! '$pn' is not valid E.164 format (must match ^\+[1-9]\d{6,14}$)." -ForegroundColor Red; exit 1
    }
}

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
if (-not (Test-Path $ConfigPath)) {
    Write-Host "  ! Config not found: $ConfigPath" -ForegroundColor Red; exit 1
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$orgUrl          = $cfg.D365OrgUrl.TrimEnd('/')
$tenantId        = $cfg.TenantId
$commsProviderId = if ($cfg.PSObject.Properties['CommsProviderId']) { $cfg.CommsProviderId } else { $null }
$acsEndpoint     = if ($cfg.PSObject.Properties['AcsEndpoint'])     { $cfg.AcsEndpoint }     else { $null }

Write-Host ""
Write-Host "  Repair-D365PhoneRecord" -ForegroundColor Cyan
Write-Host "  D365 Org : $orgUrl" -ForegroundColor Gray
Write-Host "  Mode     : $(if ($Fix) { 'FIX (will PATCH records)' } else { 'DIAGNOSE ONLY (read-only)' })" `
    -ForegroundColor $(if ($Fix) { 'Yellow' } else { 'Gray' })
Write-Host ""

# ---------------------------------------------------------------------------
# Acquire D365 token
# ---------------------------------------------------------------------------
Write-Host "  >> Acquiring D365 access token ..." -ForegroundColor Cyan
try {
    $tokenJson = az account get-access-token --resource $orgUrl --tenant $tenantId 2>&1
    $token = ($tokenJson | ConvertFrom-Json).accessToken
    if (-not $token) { throw "Empty token" }
    Write-Host "  OK  Token acquired." -ForegroundColor Green
} catch {
    Write-Host "  ! Could not get D365 token. Run: az login --tenant $tenantId" -ForegroundColor Red
    exit 1
}

$hdrsGet = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}
$hdrsPatch = $hdrsGet + @{
    "Content-Type" = "application/json"
    "If-Match"     = "*"
}

# ---------------------------------------------------------------------------
# Build query URI
# ---------------------------------------------------------------------------
$baseUri = "$orgUrl/api/data/v9.2/msdyn_ocphonenumbers"
$select  = "`$select=msdyn_phonenumber,msdyn_ocphonenumberid,msdyn_ocphonenumbersource,msdyn_teamsresourceaccount,statecode,statuscode"

if ($PhoneNumbers.Count -gt 0) {
    $filters = $PhoneNumbers | ForEach-Object {
        $enc = $_ -replace '\+', '%2B'
        "msdyn_phonenumber eq '$enc'"
    }
    $filter = "`$filter=" + ($filters -join ' or ')
    $queryUri = "${baseUri}?${select}&${filter}"
} else {
    # All records including inactive (no statecode filter)
    $queryUri = "${baseUri}?${select}"
}

# ---------------------------------------------------------------------------
# Query D365
# ---------------------------------------------------------------------------
Write-Host "  >> Querying D365 msdyn_ocphonenumbers ..." -ForegroundColor Cyan
try {
    $result  = Invoke-RestMethod -Uri $queryUri -Headers $hdrsGet -Method Get
    $records = @($result.value)
} catch {
    Write-Host "  ! D365 query failed: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

if ($records.Count -eq 0) {
    Write-Host "  WARN No records found -- they may have been deleted entirely." -ForegroundColor Yellow
    Write-Host "       Numbers deleted from D365 cannot be restored by this script." -ForegroundColor Yellow
    Write-Host "       They must be re-imported via the ACS resource sync in D365 CSAC." -ForegroundColor Yellow
    exit 0
}

Write-Host "  OK  Found $($records.Count) record(s)." -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------------
# Diagnose each record
# ---------------------------------------------------------------------------
$srcLabel = @{
    192350000 = 'ACS'
    192350001 = 'Teams DR'
}

$needsFix = @()

foreach ($rec in $records) {
    $num       = $rec.msdyn_phonenumber
    $recId     = $rec.msdyn_ocphonenumberid
    $src       = $rec.msdyn_ocphonenumbersource
    $ra        = $rec.msdyn_teamsresourceaccount
    $state     = $rec.statecode
    $status    = $rec.statuscode
    $srcName   = if ($srcLabel[$src]) { $srcLabel[$src] } else { "unknown($src)" }
    $stateStr  = if ($state -eq 0) { 'active' } else { "INACTIVE(statecode=$state)" }

    $issues = @()
    if ($state -ne 0) { $issues += 'inactive record (hidden from CSAC)' }
    if ($ra)          { $issues += "Teams RA still set ($ra)" }
    # source=192350001 (Teams DR) with NO Teams RA = correct pre-migration state for BYON Direct Routing numbers.
    # Only flag source mismatch when a Teams RA is still linked (migration active, not yet undone).
    # source=192350000 (ACS) is correct for ACS-purchased numbers.
    # source=192350001 + teamsRA=null is correct for BYON DR numbers -- do NOT flag this.
    if ($src -ne 192350000 -and $ra) { $issues += "source=$srcName with active Teams RA (migration not undone)" }

    # Determine record type for display
    $recordType = if ($src -eq 192350000) { 'ACS-purchased' } elseif ($src -eq 192350001 -and -not $ra) { 'BYON Direct Routing (pre-migration)' } elseif ($src -eq 192350001 -and $ra) { 'Migrated to Teams (Teams RA active)' } else { "unknown" }

    $color = if ($issues.Count -eq 0) { 'Green' } else { 'Yellow' }
    Write-Host "  $num" -ForegroundColor White
    Write-Host "    RecordId : $recId" -ForegroundColor Gray
    Write-Host "    State    : $stateStr" -ForegroundColor $(if ($state -eq 0) { 'Gray' } else { 'Red' })
    Write-Host "    Source   : $srcName ($src)" -ForegroundColor $color
    Write-Host "    Teams RA : $(if ($ra) { $ra } else { '(none)' })" -ForegroundColor $(if ($ra) { 'Yellow' } else { 'Gray' })
    Write-Host "    Type     : $recordType" -ForegroundColor Gray

    if ($issues.Count -eq 0) {
        Write-Host "    Status   : OK -- record is in correct pre-migration state" -ForegroundColor Green
    } else {
        Write-Host "    Issues   : $($issues -join '; ')" -ForegroundColor Yellow
        $needsFix += $rec
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Apply fix
# ---------------------------------------------------------------------------
if ($needsFix.Count -eq 0) {
    Write-Host "  OK  All records are already in correct ACS state." -ForegroundColor Green
    Write-Host "      If numbers still do not appear in D365 CSAC, click 'Sync from Azure'" -ForegroundColor Gray
    Write-Host "      on the Manage telephony panel to refresh the view." -ForegroundColor Gray
    exit 0
}

if (-not $Fix) {
    Write-Host "  $($needsFix.Count) record(s) need repair. Re-run with -Fix to apply patches." -ForegroundColor Yellow
    exit 0
}

Write-Host "  >> Applying fix to $($needsFix.Count) record(s) ..." -ForegroundColor Cyan
$ok = 0; $fail = 0

foreach ($rec in $needsFix) {
    $num   = $rec.msdyn_phonenumber
    $recId = $rec.msdyn_ocphonenumberid
    $patchUri  = "$orgUrl/api/data/v9.2/msdyn_ocphonenumbers($recId)"
    # Restore statecode=0 and clear teamsRA. Do NOT force source to ACS (192350000) --
    # BYON Direct Routing numbers correctly have source=192350001 with teamsRA=null.
    # Only force source=ACS if the record genuinely has source=Teams DR AND a Teams RA still linked.
    $currentSrc = $rec.msdyn_ocphonenumbersource
    $currentRA  = $rec.msdyn_teamsresourceaccount
    $restoreSrc = if ($currentSrc -eq 192350001 -and $currentRA) { 192350000 } else { $currentSrc }
    $patchBody  = "{`"statecode`": 0, `"statuscode`": 1, `"msdyn_teamsresourceaccount`": null, `"msdyn_ocphonenumbersource`": $restoreSrc}"

    Write-Host "  PATCH $num ..." -ForegroundColor Cyan
    try {
        Invoke-RestMethod -Uri $patchUri -Method PATCH -Headers $hdrsPatch -Body $patchBody | Out-Null
        Write-Host "  OK  $num restored to ACS state (statecode=0, source=ACS, teamsRA=null)" -ForegroundColor Green
        $ok++
    } catch {
        $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        Write-Host "  ! $num PATCH failed (HTTP $code): $($_.Exception.Message -replace '\r?\n.*','')" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "  Repair complete: OK=$ok  Failed=$fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Yellow' })
Write-Host ""

if ($ok -gt 0) {
    # ---------------------------------------------------------------------------
    # Trigger D365 'Sync from Azure' programmatically
    # ---------------------------------------------------------------------------
    if ($commsProviderId -and $acsEndpoint) {
        Write-Host "  >> Triggering D365 Sync from Azure (msdyn_TelephonyACSSyncPhoneNumbersAction) ..." -ForegroundColor Cyan
        try {
            $resourceName   = ([System.Uri]$acsEndpoint).Host.Split('.')[0]
            $correlationId  = [System.Guid]::NewGuid().ToString()
            $actionReqObj   = [ordered]@{
                ResourceName    = $resourceName
                commsProviderId = $commsProviderId
                CorrelationId   = $correlationId
            }
            $actionReqStr   = $actionReqObj | ConvertTo-Json -Compress
            $syncBody       = @{ ActionRequest = $actionReqStr } | ConvertTo-Json -Compress
            $syncUri        = "$orgUrl/api/data/v9.2/msdyn_TelephonyACSSyncPhoneNumbersAction"
            $syncHdrs       = @{
                Authorization      = "Bearer $token"
                "Content-Type"     = "application/json"
                "OData-MaxVersion" = "4.0"
                "OData-Version"    = "4.0"
            }
            $syncResult = Invoke-RestMethod -Uri $syncUri -Method POST -Headers $syncHdrs -Body $syncBody
            $resultStr  = if ($syncResult.ActionResult) { $syncResult.ActionResult } else { '(no ActionResult)' }
            Write-Host "  OK  Sync triggered. Result: $resultStr" -ForegroundColor Green
            Write-Host "      Refresh D365 CSAC browser tab (Ctrl+Shift+R) to see updated phone numbers." -ForegroundColor Gray
        } catch {
            Write-Host "  WARN  Sync action failed: $($_.Exception.Message -replace '\r?\n.*','')" -ForegroundColor Yellow
            Write-Host "        Manually click 'Sync from Azure' on the Manage telephony panel in D365 CSAC." -ForegroundColor Gray
        }
    } else {
        Write-Host "  Next: click 'Sync from Azure' on the Manage telephony panel in D365 CSAC." -ForegroundColor Gray
        Write-Host "        (Add CommsProviderId to config to automate this step.)" -ForegroundColor Gray
    }
}

