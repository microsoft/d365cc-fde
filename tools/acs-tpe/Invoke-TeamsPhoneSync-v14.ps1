#Requires -Version 5.1
<#
.SYNOPSIS
    Calls CCaaS_SynchronizePhoneNumbers for a given Teams communication provider setting.

.DESCRIPTION
    POSTs to the CCaaS_SynchronizePhoneNumbers bound action on msdyn_occommunicationprovidersetting.
    Run Get-TeamsProviderSetting.ps1 first to obtain the ProviderSettingId.

.PARAMETER OrgUrl
    Your Dynamics 365 org URL, e.g. https://contoso.crm.dynamics.com

.PARAMETER ProviderSettingId
    The GUID of the msdyn_occommunicationprovidersetting record (from Get-TeamsProviderSetting.ps1).

.EXAMPLE
    .\Invoke-TeamsPhoneSync-v14.ps1 -OrgUrl "https://contoso.crm.dynamics.com" -ProviderSettingId "f12273ec-bcf3-4078-aed5-36aad92fb7ea"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OrgUrl,

    [Parameter(Mandatory)]
    [string]$ProviderSettingId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OrgUrl = $OrgUrl.TrimEnd("/")
$ApiUrl = "$OrgUrl/api/data/v9.2"

try { [System.Guid]::Parse($ProviderSettingId) | Out-Null } catch {
    Write-Error "ProviderSettingId '$ProviderSettingId' is not a valid GUID."
    exit 1
}

Write-Host "=== Invoke-TeamsPhoneSync v14.11.0 ===" -ForegroundColor Cyan
Write-Host "Org URL:             $OrgUrl"
Write-Host "Provider Setting ID: $ProviderSettingId"
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

Write-Host "--- Calling CCaaS_SynchronizePhoneNumbers ---" -ForegroundColor Yellow
Write-Host "  Target: msdyn_occommunicationprovidersettings($ProviderSettingId)"

$syncUri = "$ApiUrl/msdyn_occommunicationprovidersettings($ProviderSettingId)/Microsoft.Dynamics.CRM.CCaaS_SynchronizePhoneNumbers"

try {
    $syncResult = Invoke-RestMethod -Uri $syncUri -Method POST -Headers $headers -Body "{}"
    Write-Host "  Response: $($syncResult | ConvertTo-Json -Depth 5 -Compress)" -ForegroundColor Green
} catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 204) {
        Write-Host "  Response: 204 No Content -- accepted." -ForegroundColor Green
    } else {
        Write-Error "CCaaS_SynchronizePhoneNumbers POST failed: $_"
        exit 1
    }
}

Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Provider Setting ID: $ProviderSettingId"
Write-Host "SyncPhoneNumbers:    Success"
Write-Host "=============================="

