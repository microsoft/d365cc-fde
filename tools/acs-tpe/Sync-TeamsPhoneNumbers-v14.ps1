#Requires -Version 5.1
<#
.SYNOPSIS
    Synchronizes Teams phone numbers in Dynamics 365 via the CCaaS_SynchronizePhoneNumbers API.

.DESCRIPTION
    PowerShell equivalent of SyncTeamsPhoneNumbers.js.
    1. Queries the active msdyn_occommunicationprovidersetting for Microsoft Teams Phone System (192350003)
    2. Captures msdyn_occommunicationproviderimmutableid
    3. Queries msdyn_occommunicationprovidersettingentries for key = DynamicsAppId
    4. POSTs to CCaaS_SynchronizePhoneNumbers bound action

    Authentication uses az CLI to acquire a token for the D365 org.

.PARAMETER OrgUrl
    Your Dynamics 365 org URL, e.g. https://contoso.crm.dynamics.com

.EXAMPLE
    .\Sync-TeamsPhoneNumbers-v14.ps1 -OrgUrl "https://contoso.crm.dynamics.com"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OrgUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OrgUrl = $OrgUrl.TrimEnd("/")
$ApiUrl  = "$OrgUrl/api/data/v9.2"

# Auth - use az CLI to get a token scoped to the D365 org
Write-Host "=== Sync-TeamsPhoneNumbers v14.11.0 ===" -ForegroundColor Cyan
Write-Host "Org URL: $OrgUrl"
Write-Host ""
Write-Host "Acquiring access token via az CLI..." -ForegroundColor Gray

$tokenJson = az account get-access-token --resource "$OrgUrl" --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "az account get-access-token failed. Ensure you are logged in and the org URL is correct.`n$tokenJson"
    exit 1
}
$accessToken = ($tokenJson | ConvertFrom-Json).accessToken

$headers = @{
    "Authorization"    = "Bearer $accessToken"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Accept"           = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
}

# Step 1: FetchXML - active Teams communication provider setting
# msdyn_occommunicationprovider = 192350003 (Microsoft Teams Phone System)
# v14.11.0: Steps 1 & 2 HTTP calls wrapped in try-catch (was unguarded)
Write-Host "--- Step 1: Querying Teams Communication Provider Setting ---" -ForegroundColor Yellow

$providerFetchXml = '<fetch top="1"><entity name="msdyn_occommunicationprovidersetting"><attribute name="msdyn_occommunicationprovidersettingid" /><attribute name="msdyn_name" /><attribute name="msdyn_occommunicationproviderimmutableid" /><attribute name="msdyn_occommunicationprovider" /><attribute name="statecode" /><filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" /></filter></entity></fetch>'

$encodedProviderFetch = [System.Uri]::EscapeDataString($providerFetchXml)
$providerUri = "$ApiUrl/msdyn_occommunicationprovidersettings?fetchXml=$encodedProviderFetch"

try {
    $providerResponse = Invoke-RestMethod -Uri $providerUri -Method GET -Headers $headers
} catch {
    Write-Error "Step 1 query failed: $($_.Exception.Message)"
    exit 1
}
$providerRecords  = $providerResponse.value

if (-not $providerRecords -or $providerRecords.Count -eq 0) {
    Write-Error "No active Teams communication provider setting found (msdyn_occommunicationprovider = 192350003, statecode = 0)."
    exit 1
}

$providerSetting   = $providerRecords[0]
$providerSettingId = $providerSetting.msdyn_occommunicationprovidersettingid
$providerName      = $providerSetting.msdyn_name
$immutableId       = $providerSetting.msdyn_occommunicationproviderimmutableid

Write-Host "  Name:         $providerName"
Write-Host "  ID:           $providerSettingId"
Write-Host "  Immutable ID: $immutableId"
Write-Host ""

# Step 2: FetchXML - setting entry where key = DynamicsAppId
Write-Host "--- Step 2: Querying DynamicsAppId Setting Entry ---" -ForegroundColor Yellow

$entriesFetchXml = "<fetch><entity name=""msdyn_occommunicationprovidersettingentry""><attribute name=""msdyn_occommunicationprovidersettingentryid"" /><attribute name=""msdyn_key"" /><attribute name=""msdyn_value"" /><attribute name=""msdyn_name"" /><filter type=""and""><condition attribute=""msdyn_key"" operator=""eq"" value=""DynamicsAppId"" /><condition attribute=""msdyn_communicationprovidersettingentid"" operator=""eq"" value=""$providerSettingId"" /></filter></entity></fetch>"

$encodedEntriesFetch = [System.Uri]::EscapeDataString($entriesFetchXml)
$entriesUri = "$ApiUrl/msdyn_occommunicationprovidersettingentries?fetchXml=$encodedEntriesFetch"

try {
    $entriesResponse = Invoke-RestMethod -Uri $entriesUri -Method GET -Headers $headers
} catch {
    Write-Warning "Step 2 query failed: $($_.Exception.Message) -- continuing without DynamicsAppId."
    $entriesResponse = @{ value = @() }
}
$entryRecords    = $entriesResponse.value

$dynamicsAppId = $null
if ($entryRecords -and $entryRecords.Count -gt 0) {
    $i = 1
    foreach ($entry in $entryRecords) {
        Write-Host "  Entry $i - Key: $($entry.msdyn_key)  Value: $($entry.msdyn_value)"
        $i++
    }
    $dynamicsAppId = $entryRecords[0].msdyn_value
} else {
    Write-Warning "  No setting entries found with key DynamicsAppId for this provider setting."
}
Write-Host ""

# Step 3: POST - CCaaS_SynchronizePhoneNumbers (bound action)
Write-Host "--- Step 3: Calling CCaaS_SynchronizePhoneNumbers ---" -ForegroundColor Yellow
Write-Host "  Target: msdyn_occommunicationprovidersettings($providerSettingId)"

$syncUri = "$ApiUrl/msdyn_occommunicationprovidersettings($providerSettingId)/Microsoft.Dynamics.CRM.CCaaS_SynchronizePhoneNumbers"

try {
    $syncResult = Invoke-RestMethod -Uri $syncUri -Method POST -Headers $headers -Body "{}"
    $syncStatus = "Success"
    Write-Host "  Response: $($syncResult | ConvertTo-Json -Depth 5 -Compress)" -ForegroundColor Green
} catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 204) {
        $syncStatus = "Success"
        Write-Host "  Response: 204 No Content -- accepted." -ForegroundColor Green
    } else {
        Write-Error "SyncPhoneNumbers POST failed: $_"
        exit 1
    }
}

# Summary
Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Provider Setting Name:  $providerName"
Write-Host "Provider Setting ID:    $providerSettingId"
Write-Host "Immutable ID:           $immutableId"
if ($dynamicsAppId) {
    Write-Host "DynamicsAppId:          $dynamicsAppId"
} else {
    Write-Host "DynamicsAppId:          (not found)"
}
Write-Host "SyncPhoneNumbers:       $syncStatus"
Write-Host "=============================="

