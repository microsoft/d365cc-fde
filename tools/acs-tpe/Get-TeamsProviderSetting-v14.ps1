#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieves the active Teams communication provider setting and its DynamicsAppId entry from Dynamics 365.

.DESCRIPTION
    Queries msdyn_occommunicationprovidersetting for the active Microsoft Teams Phone System provider (192350003)
    and the associated DynamicsAppId setting entry. Use the returned Provider Setting ID with
    Invoke-TeamsPhoneSync-v14.ps1 to trigger the sync.

.PARAMETER OrgUrl
    Your Dynamics 365 org URL, e.g. https://contoso.crm.dynamics.com

.EXAMPLE
    .\Get-TeamsProviderSetting-v14.ps1 -OrgUrl "https://contoso.crm.dynamics.com"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OrgUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OrgUrl = $OrgUrl.TrimEnd("/")
$ApiUrl = "$OrgUrl/api/data/v9.2"

Write-Host "=== Get-TeamsProviderSetting v14.11.0 ===" -ForegroundColor Cyan
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
}

# Step 1: FetchXML - active Teams communication provider setting
Write-Host "--- Step 1: Querying Teams Communication Provider Setting ---" -ForegroundColor Yellow

$providerFetchXml = '<fetch top="1"><entity name="msdyn_occommunicationprovidersetting"><attribute name="msdyn_occommunicationprovidersettingid" /><attribute name="msdyn_name" /><attribute name="msdyn_occommunicationproviderimmutableid" /><attribute name="msdyn_occommunicationprovider" /><attribute name="statecode" /><filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" /></filter></entity></fetch>'

$encodedFetch = [System.Uri]::EscapeDataString($providerFetchXml)
$providerUri  = "$ApiUrl/msdyn_occommunicationprovidersettings?fetchXml=$encodedFetch"

try {
    $providerResponse = Invoke-RestMethod -Uri $providerUri -Method GET -Headers $headers
} catch {
    $errDetail = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { ($_.Exception.Message -split '\r?\n')[0] }
    Write-Error "Failed to query Teams provider settings: $errDetail"
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

# Step 2: FetchXML - DynamicsAppId setting entry
Write-Host "--- Step 2: Querying DynamicsAppId Setting Entry ---" -ForegroundColor Yellow

$entriesFetchXml = "<fetch><entity name=""msdyn_occommunicationprovidersettingentry""><attribute name=""msdyn_occommunicationprovidersettingentryid"" /><attribute name=""msdyn_key"" /><attribute name=""msdyn_value"" /><attribute name=""msdyn_name"" /><filter type=""and""><condition attribute=""msdyn_key"" operator=""eq"" value=""DynamicsAppId"" /><condition attribute=""msdyn_communicationprovidersettingentid"" operator=""eq"" value=""$providerSettingId"" /></filter></entity></fetch>"

$encodedEntries = [System.Uri]::EscapeDataString($entriesFetchXml)
$entriesUri     = "$ApiUrl/msdyn_occommunicationprovidersettingentries?fetchXml=$encodedEntries"

try {
    $entriesResponse = Invoke-RestMethod -Uri $entriesUri -Method GET -Headers $headers
} catch {
    Write-Warning "Could not query setting entries: $($_.Exception.Message -replace '\r?\n.*','')"
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

# Summary
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Name:                   $providerName"
Write-Host "Provider Setting ID:    $providerSettingId"
Write-Host "Immutable ID:           $immutableId"
if ($dynamicsAppId) {
    Write-Host "DynamicsAppId:          $dynamicsAppId"
} else {
    Write-Host "DynamicsAppId:          (not found)"
}
Write-Host ""
Write-Host "To sync phone numbers, run:" -ForegroundColor Gray
Write-Host "  .\Invoke-TeamsPhoneSync-v14.ps1 -OrgUrl ""$OrgUrl"" -ProviderSettingId ""$providerSettingId""" -ForegroundColor Gray
Write-Host "=============================="

