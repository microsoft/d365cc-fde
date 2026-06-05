#Requires -Version 5.1
<#
.SYNOPSIS
    Updates the phone number type on a Dynamics 365 msdyn_ocphonenumber record. v14

.DESCRIPTION
    Looks up the msdyn_ocphonenumber record by phone number string (e.g. +14255550100),
    then updates msdyn_phonenumbertype, msdyn_ocphonenumbersource, and manages
    msdyn_teamsresourceaccount accordingly.

    ACS to TPS (Teams): Sets msdyn_phonenumbertype = 1, msdyn_ocphonenumbersource = 192350001
                        (Teams DR), and populates msdyn_teamsresourceaccount.
    TPS to ACS:         Sets msdyn_phonenumbertype = 0, msdyn_ocphonenumbersource = 192350000
                        (ACS), and clears msdyn_teamsresourceaccount.

    Optionally triggers CCaaS_SynchronizePhoneNumbers after the PATCH (ACS_TO_TPS only).

    Authentication uses az CLI to acquire a token for the D365 org.

.PARAMETER OrgUrl
    Your Dynamics 365 org URL, e.g. https://contoso.crm.dynamics.com

.PARAMETER PhoneNumber
    The phone number string as stored in msdyn_phonenumber, e.g. +14255550100

.PARAMETER Direction
    Either "ACS_TO_TPS" or "TPS_TO_ACS".

.PARAMETER TeamsResourceAccount
    The Object ID (GUID) of the Teams Resource Account from Entra ID.
    Required when Direction is ACS_TO_TPS. Ignored for TPS_TO_ACS.

.PARAMETER DryRun
    If specified, looks up the record and shows what would change but does not PATCH.

.EXAMPLE
    .\Update-PhoneNumberType-v14.ps1 -OrgUrl "https://contoso.crm.dynamics.com" -PhoneNumber "+14255550100" -Direction ACS_TO_TPS -TeamsResourceAccount "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"

.EXAMPLE
    .\Update-PhoneNumberType-v14.ps1 -OrgUrl "https://ppescale-2506-org8.crm10.dynamics.com" -PhoneNumber "+14255550100" -Direction TPS_TO_ACS

.EXAMPLE
    .\Update-PhoneNumberType-v14.ps1 -OrgUrl "https://contoso.crm.dynamics.com" -PhoneNumber "+14255550100" -Direction ACS_TO_TPS -TeamsResourceAccount "guid" -DryRun

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.9.0   : Version string parity with all scripts.
    v14.8.0   : Provider array bounds check before [0] access in CCaaS sync,
                version string parity with all scripts.
    v14.6.0   : Added msdyn_ocphonenumbersource field (parity with Invoke-MigrateTpsPhoneNumber),
                DryRun switch, optional CCaaS sync for ACS_TO_TPS direction.
    v14.5.0   : PATCH wrapped in try-catch, E.164 validation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OrgUrl,

    [Parameter(Mandatory)]
    [string]$PhoneNumber,

    [Parameter(Mandatory)]
    [ValidateSet("ACS_TO_TPS", "TPS_TO_ACS")]
    [string]$Direction,

    [Parameter()]
    [string]$TeamsResourceAccount,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validate E.164 format
if ($PhoneNumber -notmatch '^\+[1-9]\d{6,14}$') {
    Write-Error "PhoneNumber '$PhoneNumber' is not valid E.164 format (must match ^\+[1-9]\d{6,14}$)."
    exit 1
}

# Validate TeamsResourceAccount is provided for ACS_TO_TPS
if ($Direction -eq "ACS_TO_TPS" -and [string]::IsNullOrWhiteSpace($TeamsResourceAccount)) {
    Write-Error "TeamsResourceAccount is required when Direction is ACS_TO_TPS."
    exit 1
}

$OrgUrl        = $OrgUrl.TrimEnd("/")
$ApiUrl        = "$OrgUrl/api/data/v9.2"
$EntitySetName = "msdyn_ocphonenumbers"

$PHONE_TYPE_ACS   = 0
$PHONE_TYPE_TEAMS = 1

# Auth - use az CLI to get a token scoped to the D365 org
Write-Host "=== UpdatePhoneNumberType v14.11.0 ===" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  *** DRY RUN -- no changes will be made ***" -ForegroundColor Yellow }
Write-Host "Direction:    $Direction"
Write-Host "Phone Number: $PhoneNumber"
if ($Direction -eq "ACS_TO_TPS") {
    Write-Host "Resource Account: $TeamsResourceAccount"
}
Write-Host "Org URL:      $OrgUrl"
Write-Host ""
Write-Host "Acquiring access token via az CLI..." -ForegroundColor Gray

$tokenJson = az account get-access-token --resource "$OrgUrl" --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "az account get-access-token failed. Ensure you are logged in and the org URL is correct.`n$tokenJson"
    exit 1
}
$accessToken = ($tokenJson | ConvertFrom-Json).accessToken

$headersGet = @{
    "Authorization"    = "Bearer $accessToken"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Accept"           = "application/json"
}

$headersPatch = @{
    "Authorization"    = "Bearer $accessToken"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Accept"           = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "If-Match"         = "*"
}

# ---------------------------------------------------------------------------
# Step 1: Look up the record ID from the phone number string
# ---------------------------------------------------------------------------
Write-Host "--- Step 1: Looking up phone number record ---" -ForegroundColor Yellow
Write-Host "  Searching for msdyn_phonenumber = $PhoneNumber"

$filterValue  = "msdyn_phonenumber eq '$PhoneNumber'"
$lookupUri    = "$ApiUrl/$($EntitySetName)?`$select=msdyn_ocphonenumberid,msdyn_phonenumber,msdyn_name,msdyn_phonenumbertype,msdyn_teamsresourceaccount,statecode&`$filter=" + [System.Uri]::EscapeDataString($filterValue)

try {
    $lookupResponse = Invoke-RestMethod -Uri $lookupUri -Method GET -Headers $headersGet
} catch {
    Write-Host "  ! D365 lookup failed: $($_.Exception.Message -replace '\r?\n.*','')" -ForegroundColor Red
    exit 1
}
$lookupRecords  = $lookupResponse.value

if (-not $lookupRecords -or $lookupRecords.Count -eq 0) {
    Write-Error "No msdyn_ocphonenumber record found with msdyn_phonenumber = '$PhoneNumber'."
    exit 1
}

if ($lookupRecords.Count -gt 1) {
    Write-Warning "Multiple records found for '$PhoneNumber'. Using the first result."
}

$foundRecord         = $lookupRecords[0]
$PhoneNumberRecordId = $foundRecord.msdyn_ocphonenumberid

Write-Host "  Found Record ID: $PhoneNumberRecordId"
Write-Host ""

# ---------------------------------------------------------------------------
# Step 2: Show current state
# ---------------------------------------------------------------------------
Write-Host "--- Step 2: Current record state ---" -ForegroundColor Yellow

$currentType = $foundRecord.msdyn_phonenumbertype
if ($currentType -eq $PHONE_TYPE_ACS) {
    $currentTypeLabel = "ACS (0)"
} elseif ($currentType -eq $PHONE_TYPE_TEAMS) {
    $currentTypeLabel = "Teams (1)"
} else {
    $currentTypeLabel = "Unknown ($currentType)"
}

$currentResourceAccount = $foundRecord.msdyn_teamsresourceaccount
if ([string]::IsNullOrWhiteSpace($currentResourceAccount)) {
    $currentResourceAccount = "(empty)"
}

Write-Host "  Phone Number:             $($foundRecord.msdyn_phonenumber)"
Write-Host "  Name:                     $($foundRecord.msdyn_name)"
Write-Host "  Current Type:             $currentTypeLabel"
Write-Host "  Current Resource Account: $currentResourceAccount"

# Sanity warnings
if ($Direction -eq "ACS_TO_TPS" -and $currentType -ne $PHONE_TYPE_ACS) {
    Write-Warning "Direction is ACS_TO_TPS but current type is not ACS ($currentTypeLabel). Proceeding anyway."
}
if ($Direction -eq "TPS_TO_ACS" -and $currentType -ne $PHONE_TYPE_TEAMS) {
    Write-Warning "Direction is TPS_TO_ACS but current type is not Teams ($currentTypeLabel). Proceeding anyway."
}
Write-Host ""

# ---------------------------------------------------------------------------
# Step 3: PATCH - update phonenumbertype and teamsresourceaccount
# ---------------------------------------------------------------------------
Write-Host "--- Step 3: Updating phone number record ---" -ForegroundColor Yellow

$patchUri = "$ApiUrl/$EntitySetName($PhoneNumberRecordId)"

if ($Direction -eq "ACS_TO_TPS") {
    $patchBody = @{
        msdyn_phonenumbertype      = $PHONE_TYPE_TEAMS
        msdyn_ocphonenumbersource  = 192350001   # Teams DR (192350000 = ACS)
        msdyn_teamsresourceaccount = $TeamsResourceAccount
    }
    Write-Host "  Setting msdyn_phonenumbertype      = $PHONE_TYPE_TEAMS (Teams)"
    Write-Host "  Setting msdyn_ocphonenumbersource  = 192350001 (Teams DR)"
    Write-Host "  Setting msdyn_teamsresourceaccount = $TeamsResourceAccount"
} else {
    $patchBody = @{
        msdyn_phonenumbertype      = $PHONE_TYPE_ACS
        msdyn_ocphonenumbersource  = 192350000   # ACS (192350001 = Teams DR)
        msdyn_teamsresourceaccount = $null
    }
    Write-Host "  Setting msdyn_phonenumbertype      = $PHONE_TYPE_ACS (ACS)"
    Write-Host "  Setting msdyn_ocphonenumbersource  = 192350000 (ACS)"
    Write-Host "  Clearing msdyn_teamsresourceaccount (null)"
}

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN -- skipping PATCH." -ForegroundColor Yellow
    Write-Host "  Would PATCH: $($patchBody | ConvertTo-Json -Depth 3 -Compress)"
} else {
    $patchJson = $patchBody | ConvertTo-Json -Depth 3
    try {
        Invoke-RestMethod -Uri $patchUri -Method PATCH -Headers $headersPatch -Body $patchJson | Out-Null
        Write-Host "  PATCH succeeded." -ForegroundColor Green
    } catch {
        $errDetail = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { ($_.Exception.Message -split '\r?\n')[0] }
        Write-Host "  ! PATCH failed: $errDetail" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# ---------------------------------------------------------------------------
# Step 4: GET - verify the update
# ---------------------------------------------------------------------------
if (-not $DryRun) {
    Write-Host "--- Step 4: Verifying update ---" -ForegroundColor Yellow

    $selectFields  = "msdyn_phonenumber,msdyn_name,msdyn_phonenumbertype,msdyn_teamsresourceaccount,msdyn_ocphonenumbersource,statecode"
    $verifyUri     = "$ApiUrl/$EntitySetName($PhoneNumberRecordId)?`$select=$selectFields"
    try {
        $updatedRecord = Invoke-RestMethod -Uri $verifyUri -Method GET -Headers $headersGet
    } catch {
        Write-Warning "Verification GET failed: $($_.Exception.Message -replace '\r?\n.*',''). PATCH may have succeeded -- check D365 manually."
        exit 0
    }

    $newType = $updatedRecord.msdyn_phonenumbertype
    if ($newType -eq $PHONE_TYPE_ACS) {
        $newTypeLabel = "ACS (0)"
    } elseif ($newType -eq $PHONE_TYPE_TEAMS) {
        $newTypeLabel = "Teams (1)"
    } else {
        $newTypeLabel = "Unknown ($newType)"
    }

    $updatedResourceAccount = $updatedRecord.msdyn_teamsresourceaccount
    if ([string]::IsNullOrWhiteSpace($updatedResourceAccount)) {
        $updatedResourceAccount = "(empty)"
    }
    $updatedSource = $updatedRecord.msdyn_ocphonenumbersource

    Write-Host "  Phone Number:             $($updatedRecord.msdyn_phonenumber)"
    Write-Host "  Updated Type:             $newTypeLabel"
    Write-Host "  Updated Source:           $updatedSource"
    Write-Host "  Updated Resource Account: $updatedResourceAccount"
    Write-Host ""

    # -----------------------------------------------------------------------
    # Step 5: CCaaS_SynchronizePhoneNumbers (ACS_TO_TPS only)
    # -----------------------------------------------------------------------
    if ($Direction -eq "ACS_TO_TPS") {
        Write-Host "--- Step 5: Auto-discovering provider for CCaaS sync ---" -ForegroundColor Yellow
        $providerFetchXml = @"
<fetch top="1"><entity name="msdyn_occommunicationprovidersetting"><attribute name="msdyn_occommunicationprovidersettingid" /><filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" /></filter></entity></fetch>
"@
        $encodedPF = [System.Uri]::EscapeDataString($providerFetchXml.Trim())
        $provUri   = "$ApiUrl/msdyn_occommunicationprovidersettings?fetchXml=$encodedPF"
        try {
            $provResp  = Invoke-RestMethod -Uri $provUri -Method GET -Headers $headersGet
            if (-not $provResp.value -or $provResp.value.Count -eq 0) {
                Write-Warning "No active Teams provider setting found -- skipping CCaaS sync."
            } else {
            $provId    = $provResp.value[0].msdyn_occommunicationprovidersettingid
            $syncUri   = "$ApiUrl/msdyn_occommunicationprovidersettings($provId)/Microsoft.Dynamics.CRM.CCaaS_SynchronizePhoneNumbers"
            $headersPost = @{ "Authorization" = "Bearer $accessToken"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"; "Accept" = "application/json"; "Content-Type" = "application/json; charset=utf-8" }
            try {
                Invoke-RestMethod -Uri $syncUri -Method POST -Headers $headersPost -Body "{}" | Out-Null
                Write-Host "  CCaaS sync triggered." -ForegroundColor Green
            } catch {
                if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 204) {
                    Write-Host "  CCaaS sync: 204 No Content -- accepted." -ForegroundColor Green
                } else {
                    Write-Warning "CCaaS sync failed (non-fatal): $($_.Exception.Message)"
                }
            }
            } # end provider found else block
        } catch {
            Write-Warning "Could not auto-discover provider for sync (non-fatal): $($_.Exception.Message)"
        }
    } else {
        Write-Host "--- Step 5: CCaaS sync SKIPPED (TPS_TO_ACS) ---" -ForegroundColor DarkCyan
        Write-Host "  Skipped: calling Teams sync after TPS->ACS rollback would re-link the RA." -ForegroundColor DarkCyan
    }
}

Write-Host ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if ($Direction -eq "ACS_TO_TPS") {
    $directionLabel  = "ACS -> Teams Phone System"
    $newTypeDisplay  = "Teams (1)"
    $resourceDisplay = $TeamsResourceAccount
} else {
    $directionLabel  = "Teams Phone System -> ACS"
    $newTypeDisplay  = "ACS (0)"
    $resourceDisplay = "(cleared)"
}

Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Direction:              $directionLabel"
Write-Host "Phone Number:           $PhoneNumber"
Write-Host "Phone Number Record ID: $PhoneNumberRecordId"
Write-Host "Previous Type:          $currentTypeLabel"
Write-Host "New Type:               $newTypeDisplay"
Write-Host "Source:                 $(if ($Direction -eq 'ACS_TO_TPS') { '192350001 (Teams DR)' } else { '192350000 (ACS)' })"
Write-Host "Resource Account:       $resourceDisplay"
Write-Host "Result:                 $(if ($DryRun) { 'DRY RUN' } else { 'Success' })"
Write-Host "=============================="

