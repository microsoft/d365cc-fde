#Requires -Version 5.1
<#
.SYNOPSIS
    Migrates a D365 phone number between ACS and Teams Phone System (TPS). v14

.DESCRIPTION
    Combined workflow that:
      1. Auto-discovers the active Teams communication provider setting
         (msdyn_occommunicationprovider = 192350003, statecode = 0).
      2. Retrieves the DynamicsAppId setting entry (informational).
      3. Looks up the msdyn_ocphonenumber record by phone number string.
      4. PATCHes the phone number type:
           ACS_TO_TPS -- sets msdyn_phonenumbertype = 1 (Teams).
                         Does NOT touch msdyn_teamsresourceaccount here;
                         the sync call in Step 6 manages the RA association.
           TPS_TO_ACS -- sets msdyn_phonenumbertype = 0 (ACS) and clears
                         msdyn_teamsresourceaccount (null).
      5. Verifies the PATCH by re-reading the record.
      6. Calls CCaaS_SynchronizePhoneNumbers (async bound action on the
         provider setting). This is what actually wires up the resource
         account on the Teams side.

    Unlike Update-PhoneNumberType-v14.ps1, no TeamsResourceAccount GUID is
    required. Unlike Invoke-TeamsPhoneSync-v14.ps1, the ProviderSettingId is
    auto-discovered -- only OrgUrl, PhoneNumber, and Direction are needed.

    Authentication uses az CLI to acquire a D365-scoped Bearer token.

    Converted from MigratingTPSNumbers.js (browser console script).

.PARAMETER OrgUrl
    Your Dynamics 365 org URL, e.g. https://contoso.crm.dynamics.com

.PARAMETER PhoneNumber
    The phone number string as stored in msdyn_phonenumber, e.g. +14255550100

.PARAMETER Direction
    Either "ACS_TO_TPS" or "TPS_TO_ACS".
      ACS_TO_TPS -- Migrate from ACS Direct Routing to Teams Phone System.
      TPS_TO_ACS -- Roll back from Teams Phone System to ACS.

.PARAMETER TeamsResourceAccountObjectId
    Optional. The Teams Resource Account ObjectId (GUID) to link for ACS_TO_TPS
    direction. When provided, msdyn_teamsresourceaccount is explicitly set in
    the PATCH rather than relying on the async CCaaS sync to populate it.
    Pass the ObjectId from ra-objectids.json (written by migration Step 7).
    Ignored for TPS_TO_ACS (where msdyn_teamsresourceaccount is always cleared).

.PARAMETER DryRun
    If specified, discovers and displays the current record state but does
    not perform the PATCH or the sync call.

.EXAMPLE
    # Migrate a number from ACS to Teams Phone System
    .\Invoke-MigrateTpsPhoneNumber-v14.ps1 `
        -OrgUrl "https://ppescale-2506-org8.crm10.dynamics.com" `
        -PhoneNumber "+14255550100" `
        -Direction ACS_TO_TPS

.EXAMPLE
    # Roll back a number from Teams to ACS
    .\Invoke-MigrateTpsPhoneNumber-v14.ps1 `
        -OrgUrl "https://ppescale-2506-org8.crm10.dynamics.com" `
        -PhoneNumber "+14255550100" `
        -Direction TPS_TO_ACS

.EXAMPLE
    # Preview without making changes
    .\Invoke-MigrateTpsPhoneNumber-v14.ps1 `
        -OrgUrl "https://ppescale-2506-org8.crm10.dynamics.com" `
        -PhoneNumber "+14255550100" `
        -Direction ACS_TO_TPS `
        -DryRun
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

    # Optional Teams RA ObjectId for ACS_TO_TPS -- avoids relying on async sync
    [Parameter()]
    [string]$TeamsResourceAccountObjectId,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PhoneNumber -notmatch '^\+[1-9]\d{6,14}$') {
    Write-Error "PhoneNumber '$PhoneNumber' is not valid E.164 format (must match ^\+[1-9]\d{6,14}$)."
    exit 1
}

$PHONE_TYPE_ACS   = 0
$PHONE_TYPE_TEAMS = 1

$OrgUrl = $OrgUrl.TrimEnd("/")
$ApiUrl = "$OrgUrl/api/data/v9.2"

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host "=== Invoke-MigrateTpsPhoneNumber v14.11.0 ===" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  *** DRY RUN -- no changes will be made ***" -ForegroundColor Yellow }
$directionLabel = if ($Direction -eq "ACS_TO_TPS") { "ACS -> Teams Phone System" } else { "Teams Phone System -> ACS" }
Write-Host "Direction:    $directionLabel"
Write-Host "Phone Number: $PhoneNumber"
Write-Host "Org URL:      $OrgUrl"
Write-Host ""

# ---------------------------------------------------------------------------
# Acquire D365 token
# ---------------------------------------------------------------------------
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

$headersPost = @{
    "Authorization"    = "Bearer $accessToken"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Accept"           = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
}

# ---------------------------------------------------------------------------
# Step 1: Auto-discover the active Teams communication provider setting
#         msdyn_occommunicationprovider = 192350003 (Teams Phone System)
#         statecode = 0 (Active)
# ---------------------------------------------------------------------------
Write-Host "--- Step 1: Retrieving Teams Communication Provider Setting ---" -ForegroundColor Yellow

$providerFetchXml = @"
<fetch top="1">
  <entity name="msdyn_occommunicationprovidersetting">
    <attribute name="msdyn_occommunicationprovidersettingid" />
    <attribute name="msdyn_name" />
    <attribute name="msdyn_occommunicationproviderimmutableid" />
    <attribute name="msdyn_occommunicationprovider" />
    <attribute name="statecode" />
    <filter type="and">
      <condition attribute="statecode" operator="eq" value="0" />
      <condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" />
    </filter>
  </entity>
</fetch>
"@

$encodedProviderFetch = [System.Uri]::EscapeDataString($providerFetchXml.Trim())
$providerUri = "$ApiUrl/msdyn_occommunicationprovidersettings?fetchXml=$encodedProviderFetch"
$providerResponse = Invoke-RestMethod -Uri $providerUri -Method GET -Headers $headersGet

$providerRecords = $providerResponse.value
if (-not $providerRecords -or $providerRecords.Count -eq 0) {
    Write-Error "No active Teams communication provider setting found (msdyn_occommunicationprovider = 192350003, statecode = 0)."
    exit 1
}

$providerSetting    = $providerRecords[0]
$providerSettingId  = $providerSetting.msdyn_occommunicationprovidersettingid
$providerName       = $providerSetting.msdyn_name
$immutableId        = $providerSetting.msdyn_occommunicationproviderimmutableid

Write-Host "  Name:         $providerName"
Write-Host "  ID:           $providerSettingId"
Write-Host "  Immutable ID: $immutableId"

# ---------------------------------------------------------------------------
# Step 2: Retrieve DynamicsAppId setting entry (informational)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 2: Retrieving DynamicsAppId Setting Entry ---" -ForegroundColor Yellow

$entriesFetchXml = @"
<fetch>
  <entity name="msdyn_occommunicationprovidersettingentry">
    <attribute name="msdyn_occommunicationprovidersettingentryid" />
    <attribute name="msdyn_key" />
    <attribute name="msdyn_value" />
    <attribute name="msdyn_name" />
    <filter type="and">
      <condition attribute="msdyn_key" operator="eq" value="DynamicsAppId" />
      <condition attribute="msdyn_communicationprovidersettingentid" operator="eq" value="$providerSettingId" />
    </filter>
  </entity>
</fetch>
"@

$encodedEntriesFetch = [System.Uri]::EscapeDataString($entriesFetchXml.Trim())
$entriesUri = "$ApiUrl/msdyn_occommunicationprovidersettingentries?fetchXml=$encodedEntriesFetch"
$entriesResponse = Invoke-RestMethod -Uri $entriesUri -Method GET -Headers $headersGet

$entryRecords = $entriesResponse.value
$dynamicsAppId = $null
if ($entryRecords -and $entryRecords.Count -gt 0) {
    foreach ($entry in $entryRecords) {
        Write-Host "  Key:   $($entry.msdyn_key)"
        Write-Host "  Value: $($entry.msdyn_value)"
        $dynamicsAppId = $entry.msdyn_value
    }
} else {
    Write-Warning "No setting entries found with key 'DynamicsAppId' for this provider setting."
}

# ---------------------------------------------------------------------------
# Step 3: Look up the phone number record
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 3: Looking up phone number record ---" -ForegroundColor Yellow
Write-Host "  Searching for msdyn_phonenumber = $PhoneNumber"

$filterValue = "msdyn_phonenumber eq '$PhoneNumber'"
$lookupUri   = "$ApiUrl/msdyn_ocphonenumbers?`$select=msdyn_ocphonenumberid,msdyn_phonenumber,msdyn_name,msdyn_phonenumbertype,msdyn_teamsresourceaccount,statecode&`$filter=" + [System.Uri]::EscapeDataString($filterValue)

$lookupResponse = Invoke-RestMethod -Uri $lookupUri -Method GET -Headers $headersGet
$lookupRecords  = $lookupResponse.value

if (-not $lookupRecords -or $lookupRecords.Count -eq 0) {
    Write-Error "No msdyn_ocphonenumber record found with msdyn_phonenumber = '$PhoneNumber'."
    exit 1
}

if ($lookupRecords.Count -gt 1) {
    Write-Warning "Found $($lookupRecords.Count) records matching '$PhoneNumber'. Using the first one."
}

$currentRecord       = $lookupRecords[0]
$phoneNumberRecordId = $currentRecord.msdyn_ocphonenumberid
$currentType         = $currentRecord.msdyn_phonenumbertype

$currentTypeLabel = switch ($currentType) {
    $PHONE_TYPE_ACS   { "ACS (0)" }
    $PHONE_TYPE_TEAMS { "Teams (1)" }
    default           { "Unknown ($currentType)" }
}

$currentRa = $currentRecord.msdyn_teamsresourceaccount
if ([string]::IsNullOrWhiteSpace($currentRa)) { $currentRa = "(empty)" }

Write-Host "  Record ID:                $phoneNumberRecordId"
Write-Host "  Phone Number:             $($currentRecord.msdyn_phonenumber)"
Write-Host "  Name:                     $($currentRecord.msdyn_name)"
Write-Host "  Current Type:             $currentTypeLabel"
Write-Host "  Current Resource Account: $currentRa"

# Sanity warnings
if ($Direction -eq "ACS_TO_TPS" -and $currentType -ne $PHONE_TYPE_ACS) {
    Write-Warning "Direction is ACS_TO_TPS but current type is not ACS ($currentTypeLabel). Proceeding anyway."
}
if ($Direction -eq "TPS_TO_ACS" -and $currentType -ne $PHONE_TYPE_TEAMS) {
    Write-Warning "Direction is TPS_TO_ACS but current type is not Teams ($currentTypeLabel). Proceeding anyway."
}

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN -- skipping PATCH and sync." -ForegroundColor Yellow
    Write-Host "  Would set msdyn_phonenumbertype = $(if ($Direction -eq 'ACS_TO_TPS') { "$PHONE_TYPE_TEAMS (Teams)" } else { "$PHONE_TYPE_ACS (ACS)" })"
    if ($Direction -eq "TPS_TO_ACS") {
        Write-Host "  Would clear msdyn_teamsresourceaccount (null)"
        Write-Host "  Would set msdyn_ocphonenumbersource = 192350000 (ACS)"
        Write-Host "  Step 6 (CCaaS sync) will be SKIPPED for TPS_TO_ACS -- avoids re-linking Teams RA"
    } elseif (-not [string]::IsNullOrWhiteSpace($TeamsResourceAccountObjectId)) {
        Write-Host "  Would set msdyn_teamsresourceaccount = $TeamsResourceAccountObjectId (explicit ObjectId)"
    } else {
        Write-Host "  msdyn_teamsresourceaccount will be managed by sync (Step 6) -- not touched in PATCH."
    }
    Write-Host "  Would call CCaaS_SynchronizePhoneNumbers on provider setting $providerSettingId"
    exit 0
}

# ---------------------------------------------------------------------------
# Step 4: PATCH -- update phone number type
#   ACS_TO_TPS: set type = 1 (Teams). RA is NOT set here; sync manages it.
#   TPS_TO_ACS: set type = 0 (ACS) and clear msdyn_teamsresourceaccount.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 4: Updating phone number record ---" -ForegroundColor Yellow

$patchUri = "$ApiUrl/msdyn_ocphonenumbers($phoneNumberRecordId)"

if ($Direction -eq "ACS_TO_TPS") {
    $patchBody = @{
        msdyn_phonenumbertype     = $PHONE_TYPE_TEAMS
        msdyn_ocphonenumbersource = 192350001   # Teams DR (192350000 = ACS)
    }
    if (-not [string]::IsNullOrWhiteSpace($TeamsResourceAccountObjectId)) {
        $patchBody['msdyn_teamsresourceaccount'] = $TeamsResourceAccountObjectId
        Write-Host "  Setting msdyn_phonenumbertype = $PHONE_TYPE_TEAMS (Teams)"
        Write-Host "  Setting msdyn_ocphonenumbersource = 192350001 (Teams DR)"
        Write-Host "  Setting msdyn_teamsresourceaccount = $TeamsResourceAccountObjectId (explicit ObjectId)"
    } else {
        Write-Host "  Setting msdyn_phonenumbertype = $PHONE_TYPE_TEAMS (Teams)"
        Write-Host "  Setting msdyn_ocphonenumbersource = 192350001 (Teams DR)"
        Write-Host "  msdyn_teamsresourceaccount NOT set -- sync (Step 6) will manage the RA association."
        Write-Host "  Tip: pass -TeamsResourceAccountObjectId to link the RA explicitly and avoid sync delays." -ForegroundColor DarkCyan
    }
} else {
    $patchBody = @{
        msdyn_phonenumbertype       = $PHONE_TYPE_ACS
        msdyn_teamsresourceaccount  = $null
        msdyn_ocphonenumbersource   = 192350000   # ACS (192350001 = Teams DR)
    }
    Write-Host "  Setting msdyn_phonenumbertype = $PHONE_TYPE_ACS (ACS)"
    Write-Host "  Clearing msdyn_teamsresourceaccount (null)"
    Write-Host "  Setting msdyn_ocphonenumbersource = 192350000 (ACS)"
}

$patchJson = $patchBody | ConvertTo-Json -Depth 3
Invoke-RestMethod -Uri $patchUri -Method PATCH -Headers $headersPatch -Body $patchJson | Out-Null
Write-Host "  PATCH succeeded." -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 5: GET -- verify the type update
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 5: Verifying type update ---" -ForegroundColor Yellow

$verifyUri     = "$ApiUrl/msdyn_ocphonenumbers($phoneNumberRecordId)?`$select=msdyn_phonenumber,msdyn_name,msdyn_phonenumbertype,msdyn_teamsresourceaccount,statecode"
$updatedRecord = Invoke-RestMethod -Uri $verifyUri -Method GET -Headers $headersGet

$updatedType = $updatedRecord.msdyn_phonenumbertype
$updatedTypeLabel = switch ($updatedType) {
    $PHONE_TYPE_ACS   { "ACS (0)" }
    $PHONE_TYPE_TEAMS { "Teams (1)" }
    default           { "Unknown ($updatedType)" }
}

$updatedRa = $updatedRecord.msdyn_teamsresourceaccount
if ([string]::IsNullOrWhiteSpace($updatedRa)) { $updatedRa = "(empty)" }

Write-Host "  Phone Number:                $($updatedRecord.msdyn_phonenumber)"
Write-Host "  Updated Type:                $updatedTypeLabel"
Write-Host "  Resource Account (pre-sync): $updatedRa"

# ---------------------------------------------------------------------------
# Step 6: POST -- CCaaS_SynchronizePhoneNumbers (async bound action)
#   ACS_TO_TPS only: wires up the resource account on the Teams side.
#   TPS_TO_ACS: SKIPPED -- the Teams sync reads the Teams RA assignment
#   which is still present in Teams Phone System, causing it to re-link
#   msdyn_teamsresourceaccount and undo the PATCH we just applied.
# ---------------------------------------------------------------------------
Write-Host ""
if ($Direction -eq "TPS_TO_ACS") {
    Write-Host "--- Step 6: CCaaS_SynchronizePhoneNumbers SKIPPED (TPS_TO_ACS) ---" -ForegroundColor DarkCyan
    Write-Host "  Skipped: calling the Teams sync after TPS->ACS rollback causes it to" -ForegroundColor DarkCyan
    Write-Host "  re-read the Teams RA assignment and undo the PATCH. D365 fields are" -ForegroundColor DarkCyan
    Write-Host "  already correct from Step 4 -- no sync needed." -ForegroundColor DarkCyan
} else {
    Write-Host "--- Step 6: Calling CCaaS_SynchronizePhoneNumbers ---" -ForegroundColor Yellow
    Write-Host "  Target: msdyn_occommunicationprovidersettings($providerSettingId)"

    $syncUri = "$ApiUrl/msdyn_occommunicationprovidersettings($providerSettingId)/Microsoft.Dynamics.CRM.CCaaS_SynchronizePhoneNumbers"

    try {
        $syncResult = Invoke-RestMethod -Uri $syncUri -Method POST -Headers $headersPost -Body "{}"
        if ($syncResult) {
            Write-Host "  Response: $($syncResult | ConvertTo-Json -Depth 5 -Compress)" -ForegroundColor Green
        } else {
            Write-Host "  Response: (204 No Content -- accepted)" -ForegroundColor Green
        }
    } catch {
        # 204 No Content throws in some PS versions because there is no response body
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 204) {
            Write-Host "  Response: 204 No Content -- accepted." -ForegroundColor Green
        } else {
            Write-Error "CCaaS_SynchronizePhoneNumbers POST failed: $_"
            exit 1
        }
    }
}

Write-Host ""
Write-Host "  NOTE: The sync is asynchronous. The API returns immediately but the" -ForegroundColor DarkCyan
Write-Host "  actual sync runs in the background. Allow a few minutes before the" -ForegroundColor DarkCyan
Write-Host "  updated phone number and resource account changes appear in D365 UI." -ForegroundColor DarkCyan

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$newTypeDisplay = if ($Direction -eq "ACS_TO_TPS") { "Teams (1)" } else { "ACS (0)" }

Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Direction:              $directionLabel"
Write-Host "Phone Number:           $PhoneNumber"
Write-Host "Phone Number Record ID: $phoneNumberRecordId"
Write-Host "Previous Type:          $currentTypeLabel"
Write-Host "New Type:               $newTypeDisplay"
Write-Host "Provider Setting:       $providerName ($providerSettingId)"
Write-Host "Immutable ID:           $immutableId"
Write-Host "DynamicsAppId:          $(if ($dynamicsAppId) { $dynamicsAppId } else { 'Not found' })"
Write-Host "Type Update (PATCH):    Success (type + source + RA cleared)"
Write-Host "Sync Phone Numbers:     $(if ($Direction -eq 'TPS_TO_ACS') { 'Skipped (TPS->ACS: sync would re-link Teams RA)' } else { 'Success (async -- allow a few minutes)' })"
Write-Host "=============================="

