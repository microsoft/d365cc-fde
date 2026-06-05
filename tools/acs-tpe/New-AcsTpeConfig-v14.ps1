#Requires -Version 5.1
<#
.SYNOPSIS
    Auto-builds new-acs-tpe-config-v14.11.0.json by querying Azure, D365, and ACS. v14

.DESCRIPTION
    Discovers as many config fields as possible automatically:
      - TenantId, SubscriptionId, AdminUpn       via az CLI
      - D365OrgUrl                                via D365 Global Discovery Service
      - DynamicsAppId, CommsProviderId, AcsResourceId  via D365 Web API (FetchXML)
      - AcsEndpoint, AcsConnectionString          via Azure Management REST API
      - SbcFqdn, SbcPort                          via ACS SIP REST API

    Only Domain is required as input. All naming fields (RaPrefix, PolicyName,
    UsageName, RouteName) have sensible defaults.

.PARAMETER OutputPath
    Path to write the generated config JSON.
    Default: .\new-acs-tpe-config-v14.11.0.json

.PARAMETER Domain
    Custom domain for Resource Account UPNs, e.g. cbg-voice.contoso.com
    This is the only field that cannot be auto-discovered.

.PARAMETER SubscriptionId
    Override the Azure subscription to use. If omitted, uses current az CLI subscription.

.PARAMETER D365OrgUrl
    Override the D365 org URL. If omitted, discovered via D365 Global Discovery Service.

.PARAMETER RaPrefix
    Resource Account name prefix. Default: acs-tpe-ra-<phonenumber>

.PARAMETER PolicyName
    Teams Voice Routing Policy name to create. Default: acs-tpe-migration

.PARAMETER UsageName
    Teams PSTN Usage name to create. Default: acs-tpe-pstn-usage

.PARAMETER RouteName
    Teams Voice Route name to create. Default: acs-tpe-voice-route

.PARAMETER DryRun
    Discover and display all values without writing the config file.

.EXAMPLE
    .\New-AcsTpeConfig-v14.ps1 -Domain "cbg-voice.contoso.com"

.EXAMPLE
    .\New-AcsTpeConfig-v14.ps1 -Domain "cbg-voice.contoso.com" -DryRun

.EXAMPLE
    .\New-AcsTpeConfig-v14.ps1 -Domain "cbg-voice.contoso.com" -OutputPath ".\my-org-config.json" -SubscriptionId "00cc9e1b-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = ".\new-acs-tpe-config-v14.11.0.json",

    [Parameter()]
    [string]$Domain = "",

    [Parameter()]
    [string]$SubscriptionId = "",

    [Parameter()]
    [string]$D365OrgUrl = "",

    [Parameter()]
    [string]$RaPrefix = "acs-tpe-ra-<phonenumber>",

    [Parameter()]
    [string]$PolicyName = "acs-tpe-migration",

    [Parameter()]
    [string]$UsageName = "acs-tpe-pstn-usage",

    [Parameter()]
    [string]$RouteName = "acs-tpe-voice-route",

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step  { param([string]$m) Write-Host "  >> $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "  OK $m" -ForegroundColor Green }
function Write-Warn  { param([string]$m) Write-Host "  WARN $m" -ForegroundColor Yellow }
function Write-Fail  { param([string]$m) Write-Host "  FAIL $m" -ForegroundColor Red }
function Write-Info  { param([string]$m) Write-Host "  -- $m" -ForegroundColor Gray }
function Write-Found { param([string]$k, [string]$v) Write-Host ("  {0,-26} = {1}" -f $k, $v) -ForegroundColor White }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  New-AcsTpeConfig v14.11.0" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  DRY RUN -- no file will be written" -ForegroundColor Yellow }
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Phase 1: Validate login via Invoke-AcsTpeLogin (single-login enforcement)
# ---------------------------------------------------------------------------
Write-Step "Phase 1: Validating authenticated session..."

$SESSION_PATH    = Join-Path $PSScriptRoot "acs-tpe-session.json"
$SESSION_TTL_MIN = 50
$session         = $null

# Use existing valid session if present and tenant matches
if (Test-Path $SESSION_PATH) {
    try {
        $s   = Get-Content $SESSION_PATH -Raw | ConvertFrom-Json
        $age = (Get-Date) - [datetime]$s.ValidatedAt
        $tenantOk = ([string]::IsNullOrWhiteSpace($SubscriptionId)) -or ($s.SubscriptionId -eq $SubscriptionId)
        if ($age.TotalMinutes -lt $SESSION_TTL_MIN -and $tenantOk) {
            $session = $s
            Write-Found "Session"   "valid (age: $([int]$age.TotalMinutes)m)"
        }
    } catch {}
}

# No valid session — run login script
if (-not $session) {
    Write-Info "No valid session found. Launching Invoke-AcsTpeLogin..."
    $loginScript = Join-Path $PSScriptRoot "Invoke-AcsTpeLogin.ps1"
    if (-not (Test-Path $loginScript)) {
        Write-Fail "Invoke-AcsTpeLogin.ps1 not found alongside this script."
        Write-Fail "Run: .\Invoke-AcsTpeLogin.ps1 first, then re-run New-AcsTpeConfig-v14.ps1."
        exit 1
    }
    $session = & $loginScript -SkipTeamsConnect
    if (-not $session -or [string]::IsNullOrWhiteSpace($session.TenantId)) {
        Write-Fail "Login validation failed. Cannot continue."
        exit 1
    }
}

# Hydrate from validated session
$TenantId = $session.TenantId
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { $SubscriptionId = $session.SubscriptionId }
$AdminUpn = $session.AdminUpn

Write-Found "TenantId"       $TenantId
Write-Found "SubscriptionId" $SubscriptionId
Write-Found "AdminUpn"       $AdminUpn

# ---------------------------------------------------------------------------
# Phase 2: D365 Global Discovery -- D365OrgUrl
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Phase 2: Discovering D365 org URL..."

if ([string]::IsNullOrWhiteSpace($D365OrgUrl)) {
    $discoToken = az account get-access-token --resource "https://globaldisco.crm.dynamics.com" --query accessToken --output tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($discoToken)) {
        Write-Warn "Could not get D365 discovery token."
        $D365OrgUrl = (Read-Host "  Enter D365 Org URL (e.g. https://contoso.crm10.dynamics.com)").Trim()
    } else {
        $discoHeaders = @{
            "Authorization" = "Bearer $($discoToken.Trim())"
            "Accept"        = "application/json"
        }
        try {
            $discoResp = Invoke-RestMethod -Uri "https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances" -Headers $discoHeaders
            $instances = $discoResp.value
            if ($instances -and $instances.Count -eq 1) {
                $D365OrgUrl = $instances[0].ApiUrl.TrimEnd("/")
                Write-Found "D365OrgUrl" $D365OrgUrl
            } elseif ($instances -and $instances.Count -gt 1) {
                Write-Info "Multiple D365 instances found:"
                for ($i = 0; $i -lt $instances.Count; $i++) {
                    Write-Host ("    [{0}] {1}  ({2})" -f $i, $instances[$i].FriendlyName, $instances[$i].ApiUrl) -ForegroundColor Gray
                }
                Write-Host "  (If your org is not listed, type the full URL instead, e.g. https://contoso.crm10.dynamics.com)" -ForegroundColor DarkGray
                $selRaw = (Read-Host "  Select instance number OR type org URL").Trim()
                if ($selRaw -match "^https?://") {
                    $D365OrgUrl = $selRaw.TrimEnd("/")
                } else {
                    $D365OrgUrl = $instances[[int]$selRaw].ApiUrl.TrimEnd("/")
                }
                Write-Found "D365OrgUrl" $D365OrgUrl
            } else {
                Write-Warn "No D365 instances returned from discovery."
                $D365OrgUrl = (Read-Host "  Enter D365 Org URL").Trim()
            }
        } catch {
            Write-Warn "D365 discovery request failed: $_"
            $D365OrgUrl = (Read-Host "  Enter D365 Org URL").Trim()
        }
    }
} else {
    $D365OrgUrl = $D365OrgUrl.TrimEnd("/")
    Write-Found "D365OrgUrl" "$D365OrgUrl (provided)"
}

# ---------------------------------------------------------------------------
# Phase 3: D365 Web API -- DynamicsAppId, CommsProviderId, AcsResourceId
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Phase 3: Querying D365 for provider settings..."

$d365Token = az account get-access-token --resource "$D365OrgUrl" --query accessToken --output tsv 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($d365Token)) {
    Write-Fail "Could not get D365 token for $D365OrgUrl. Ensure az login covers this tenant."
    exit 1
}
$d365Headers = @{
    "Authorization"    = "Bearer $($d365Token.Trim())"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Accept"           = "application/json"
}

# Provider setting (Teams Phone System = 192350003)
$DynamicsAppId   = ""
$CommsProviderId = ""
$AcsResourceId   = ""

$providerFetch = '<fetch top="1"><entity name="msdyn_occommunicationprovidersetting"><attribute name="msdyn_occommunicationprovidersettingid" /><attribute name="msdyn_name" /><attribute name="msdyn_occommunicationproviderimmutableid" /><filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" /></filter></entity></fetch>'
$providerUri = "$D365OrgUrl/api/data/v9.2/msdyn_occommunicationprovidersettings?fetchXml=" + [System.Uri]::EscapeDataString($providerFetch)

try {
    $providerResp = Invoke-RestMethod -Uri $providerUri -Method GET -Headers $d365Headers
    if ($providerResp.value -and $providerResp.value.Count -gt 0) {
        $ps = $providerResp.value[0]
        $CommsProviderId = $ps.msdyn_occommunicationprovidersettingid
        $AcsResourceId   = $ps.msdyn_occommunicationproviderimmutableid
        Write-Found "CommsProviderId" $CommsProviderId
        Write-Found "AcsResourceId"   $AcsResourceId
    } else {
        Write-Warn "No active Teams communication provider setting found in D365."
    }
} catch {
    Write-Warn "D365 provider setting query failed: $_"
}

# DynamicsAppId from setting entries
if (-not [string]::IsNullOrWhiteSpace($CommsProviderId)) {
    $entryFetch = "<fetch><entity name=""msdyn_occommunicationprovidersettingentry""><attribute name=""msdyn_key"" /><attribute name=""msdyn_value"" /><filter type=""and""><condition attribute=""msdyn_key"" operator=""eq"" value=""DynamicsAppId"" /><condition attribute=""msdyn_communicationprovidersettingentid"" operator=""eq"" value=""$CommsProviderId"" /></filter></entity></fetch>"
    $entryUri = "$D365OrgUrl/api/data/v9.2/msdyn_occommunicationprovidersettingentries?fetchXml=" + [System.Uri]::EscapeDataString($entryFetch)
    try {
        $entryResp = Invoke-RestMethod -Uri $entryUri -Method GET -Headers $d365Headers
        if ($entryResp.value -and $entryResp.value.Count -gt 0) {
            $DynamicsAppId = $entryResp.value[0].msdyn_value
            Write-Found "DynamicsAppId" $DynamicsAppId
        } else {
            Write-Warn "DynamicsAppId setting entry not found in D365."
        }
    } catch {
        Write-Warn "D365 setting entry query failed: $_"
    }
}

if ([string]::IsNullOrWhiteSpace($DynamicsAppId)) {
    $DynamicsAppId = (Read-Host "  Enter DynamicsAppId (D365 App Registration Client ID)").Trim()
}
if ([string]::IsNullOrWhiteSpace($AcsResourceId)) {
    $AcsResourceId = (Read-Host "  Enter AcsResourceId (GUID from D365 CSAC > Channels > Advanced)").Trim()
}

# ---------------------------------------------------------------------------
# Phase 4: Azure Management API -- ACS resource, endpoint, connection string
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Phase 4: Discovering ACS resource in Azure subscription..."

$AcsEndpoint        = ""
$AcsConnectionString = ""
$AcsSubscriptionId  = $SubscriptionId

# Helper: get Azure management headers for a given subscription (handles cross-tenant)
function Get-MgmtHeaders {
    param([string]$subId)
    $tok = az account get-access-token --subscription $subId --resource "https://management.azure.com" --query accessToken --output tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tok)) { return $null }
    return @{ "Authorization" = "Bearer $($tok.Trim())"; "Accept" = "application/json" }
}

# Helper: extract RG name from Azure resource ID (index 4 after split on /)
function Get-RgFromId { param([string]$id) ($id -split "/")[4] }

# Helper: strip portal UI suffix from a resource ID or portal URL
# Keeps only up to the resource name; discards /resource_overview or similar
function Trim-ResourceId {
    param([string]$raw)
    if ($raw -match "(/subscriptions/[^/\s]+/resourceGroups/[^/\s]+/providers/Microsoft\.Communication/CommunicationServices/[^/?#\s]+)") {
        return $Matches[1]
    }
    return $raw
}

# Helper: display a list of ACS resources
function Show-AcsResourceList {
    param([object[]]$resources)
    for ($i = 0; $i -lt $resources.Count; $i++) {
        $rg = Get-RgFromId $resources[$i].id
        Write-Host ("    [{0}] {1}  RG={2}  host={3}" -f $i, $resources[$i].name, $rg, $resources[$i].properties.hostName) -ForegroundColor Gray
    }
}

$mgmtHeaders = Get-MgmtHeaders $SubscriptionId
if (-not $mgmtHeaders) {
    Write-Warn "Could not get Azure management token."
} else {
    $listUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Communication/communicationServices?api-version=2023-04-01-preview"
    try {
        $acsResources = (Invoke-RestMethod -Uri $listUri -Method GET -Headers $mgmtHeaders).value

        if ($acsResources -and $acsResources.Count -gt 0) {
            # If only one resource, use it directly
            $acsResource = $null
            $acsHeaders  = $mgmtHeaders
            if ($acsResources.Count -eq 1) {
                $acsResource = $acsResources[0]
            } else {
                Write-Info "Searching subscription: $SubscriptionId"
                Write-Info "Multiple ACS resources found in subscription:"
                Show-AcsResourceList $acsResources
                Write-Host "  Options:" -ForegroundColor DarkGray
                Write-Host "    - Type a number to select from the list above" -ForegroundColor DarkGray
                Write-Host "    - Type a subscription GUID to search a different subscription" -ForegroundColor DarkGray
                Write-Host "    - Paste an Azure portal URL or full resource ID -- portal suffix /resource_overview is stripped automatically" -ForegroundColor DarkGray
                $selRaw = (Read-Host "  Enter selection").Trim()

                if ($selRaw -match "^/subscriptions/" -or $selRaw -match "portal\.azure\.com") {
                    # Full resource ID or portal URL -- strip portal suffix, get sub-specific token
                    $cleanId = Trim-ResourceId $selRaw
                    $altSub  = ($cleanId -split "/")[2]
                    $altHdrs = Get-MgmtHeaders $altSub
                    if (-not $altHdrs) { $altHdrs = $mgmtHeaders }
                    try {
                        $fetchUri = "https://management.azure.com$cleanId`?api-version=2023-04-01-preview"
                        $acsResource = Invoke-RestMethod -Uri $fetchUri -Method GET -Headers $altHdrs
                        $acsHeaders  = $altHdrs
                        Write-Found "AcsResource" $acsResource.name
                    } catch {
                        Write-Warn "Could not fetch resource '$cleanId': $_"
                    }
                } elseif ($selRaw -match "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") {
                    # Subscription GUID -- list ACS resources in that subscription with its own token
                    $altSub  = $selRaw
                    $altHdrs = Get-MgmtHeaders $altSub
                    if (-not $altHdrs) { $altHdrs = $mgmtHeaders }
                    $altUri  = "https://management.azure.com/subscriptions/$altSub/providers/Microsoft.Communication/communicationServices?api-version=2023-04-01-preview"
                    try {
                        $altResources = (Invoke-RestMethod -Uri $altUri -Method GET -Headers $altHdrs).value
                        if ($altResources -and $altResources.Count -gt 0) {
                            Write-Info "ACS resources in subscription $altSub :"
                            Show-AcsResourceList $altResources
                            if ($altResources.Count -eq 1) {
                                $acsResource = $altResources[0]
                            } else {
                                $sel2 = [int](Read-Host "  Select ACS resource number")
                                $acsResource = $altResources[$sel2]
                            }
                            $acsHeaders = $altHdrs
                        } else {
                            Write-Warn "No ACS resources found in subscription $altSub."
                        }
                    } catch {
                        Write-Warn "Could not list ACS resources in subscription $altSub : $_"
                    }
                } else {
                    $acsResource = $acsResources[[int]$selRaw]
                }
            }

            if ($acsResource) {
                # Derive actual subscription from resource id -- may differ from az CLI default
                $AcsSubscriptionId = ($acsResource.id -split "/")[2]
                $AcsEndpoint = "https://$($acsResource.properties.hostName)/"
                Write-Found "AcsSubscriptionId" $AcsSubscriptionId
                Write-Found "AcsEndpoint"        $AcsEndpoint

                # Get connection string via listKeys using the correct tenant's token
                $keysUri = "https://management.azure.com$($acsResource.id)/listKeys?api-version=2023-04-01-preview"
                $keysHeaders = $acsHeaders.Clone()
                $keysHeaders["Content-Type"] = "application/json"
                try {
                    $keys = Invoke-RestMethod -Uri $keysUri -Method POST -Headers $keysHeaders -Body "{}"
                    $AcsConnectionString = $keys.primaryConnectionString
                    Write-Found "AcsConnectionString" ($AcsConnectionString.Substring(0, [Math]::Min(60, $AcsConnectionString.Length)) + "...")
                } catch {
                    Write-Warn "Could not retrieve ACS keys: $_"
                }
            }
        } else {
            Write-Warn "No ACS Communication Services resources found in subscription $SubscriptionId."
        }
    } catch {
        Write-Warn "ACS resource list failed: $_"
    }
}

if ([string]::IsNullOrWhiteSpace($AcsConnectionString)) {
    Write-Info "ACS connection string not auto-retrieved."
    $AcsConnectionString = (Read-Host "  Enter ACS Connection String (from Azure Portal > ACS > Keys)").Trim()
    if ([string]::IsNullOrWhiteSpace($AcsEndpoint) -and $AcsConnectionString -match "endpoint=([^;]+)") {
        $AcsEndpoint = $Matches[1]
    }
}

# ---------------------------------------------------------------------------
# Phase 5: ACS SIP REST API -- SbcFqdn, SbcPort
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Phase 5: Querying ACS SIP trunks for SBC FQDN and port..."

$SbcFqdn = ""
$SbcPort = 0

if (-not [string]::IsNullOrWhiteSpace($AcsConnectionString)) {
    $connParts = @{}
    $AcsConnectionString.Split(";") | ForEach-Object {
        $kv = $_ -split "=", 2
        if ($kv.Count -eq 2) { $connParts[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
    }
    $sipEp  = $connParts["endpoint"].TrimEnd("/")
    $sipKey = $connParts["accesskey"]
    $pq     = "/sip?api-version=2023-04-01-preview"
    $sipUrl = "$sipEp$pq"
    $sipHost = ([System.Uri]$sipUrl).Host

    $date    = [System.DateTime]::UtcNow.ToString("r")
    $sha256  = [System.Security.Cryptography.SHA256]::Create()
    try {
        $emptyH  = [System.Convert]::ToBase64String($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("")))
    } finally { $sha256.Dispose() }
    $keyB    = [System.Convert]::FromBase64String($sipKey)
    $toSign  = "GET`n$pq`n$date;$sipHost;$emptyH"
    $hmac    = [System.Security.Cryptography.HMACSHA256]::new($keyB)
    try {
        $sig     = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
    } finally { $hmac.Dispose() }
    $sipHdrs = @{
        "x-ms-date"           = $date
        "x-ms-content-sha256" = $emptyH
        "Authorization"       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
        "Accept"              = "application/json"
    }

    try {
        $sipResp = Invoke-RestMethod -Uri $sipUrl -Method GET -Headers $sipHdrs
        $trunks  = $sipResp.trunks.PSObject.Properties
        $trunkList = @($trunks)
        if ($trunkList.Count -eq 1) {
            $SbcFqdn = $trunkList[0].Name
            $SbcPort = $trunkList[0].Value.sipSignalingPort
            Write-Found "SbcFqdn" $SbcFqdn
            Write-Found "SbcPort" "$SbcPort"
        } elseif ($trunkList.Count -gt 1) {
            Write-Info "Multiple ACS SIP trunks found:"
            for ($i = 0; $i -lt $trunkList.Count; $i++) {
                Write-Host ("    [{0}] {1}  port={2}  enabled={3}" -f $i, $trunkList[$i].Name, $trunkList[$i].Value.sipSignalingPort, $trunkList[$i].Value.enabled) -ForegroundColor Gray
            }
            $sel = [int](Read-Host "  Select SBC trunk number")
            $SbcFqdn = $trunkList[$sel].Name
            $SbcPort = $trunkList[$sel].Value.sipSignalingPort
            Write-Found "SbcFqdn" $SbcFqdn
            Write-Found "SbcPort" "$SbcPort"
        } else {
            Write-Warn "No SIP trunks found in ACS."
        }
    } catch {
        Write-Warn "ACS SIP query failed: $_"
    }
}

if ([string]::IsNullOrWhiteSpace($SbcFqdn)) {
    $SbcFqdn = (Read-Host "  Enter SBC FQDN (e.g. sbc.contoso.com)").Trim()
}
if ($SbcPort -eq 0) {
    $portInput = (Read-Host "  Enter SBC SIP signaling port (e.g. 5075)").Trim()
    while (-not ($portInput -match '^\d+$' -and [int]$portInput -gt 0 -and [int]$portInput -le 65535)) {
        Write-Warn "Port must be a number between 1 and 65535."
        $portInput = (Read-Host "  Enter SBC SIP signaling port (e.g. 5075)").Trim()
    }
    $SbcPort = [int]$portInput
}

# ---------------------------------------------------------------------------
# Phase 6: Prompt for Domain (only mandatory manual input)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Phase 6: Collecting remaining required inputs..."

if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = (Read-Host "  Enter Domain for Resource Account UPNs (e.g. cbg-voice.contoso.com)").Trim()
}
if ([string]::IsNullOrWhiteSpace($Domain)) {
    Write-Fail "Domain is required."
    exit 1
}
Write-Found "Domain"     $Domain
Write-Found "RaPrefix"   $RaPrefix
Write-Found "PolicyName" $PolicyName
Write-Found "UsageName"  $UsageName
Write-Found "RouteName"  $RouteName

# ---------------------------------------------------------------------------
# Phase 7: Assemble and write config
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Phase 7: Assembling config..."

$config = [ordered]@{
    "_help" = [ordered]@{
        "TenantId"           = "Microsoft Entra ID Tenant ID -- auto-retrieved from az CLI"
        "AdminUpn"           = "Teams and Graph Admin UPN -- auto-retrieved from az ad signed-in-user"
        "Domain"             = "Domain for Resource Account UPNs -- registered in Entra ID during Step 4"
        "DynamicsAppId"      = "D365 App Registration Client ID -- auto-retrieved from D365 provider setting entry"
        "D365OrgUrl"         = "D365 Org URL -- auto-retrieved from D365 Global Discovery Service"
        "RaPrefix"           = "Resource Account name prefix -- use token <phonenumber> for auto-substitution"
        "AcsSubscriptionId"  = "Azure Subscription ID -- auto-retrieved from az CLI"
        "AcsResourceId"      = "ACS Resource ID (GUID) -- auto-retrieved from D365 provider setting immutableId"
        "AcsEndpoint"        = "ACS Endpoint URL -- auto-retrieved from Azure Management API"
        "AcsConnectionString"= "ACS Connection String -- auto-retrieved from Azure Management API (listKeys)"
        "SbcFqdn"            = "SBC FQDN -- auto-retrieved from ACS SIP API"
        "SbcPort"            = "SBC SIP signaling port -- auto-retrieved from ACS SIP API"
        "PolicyName"         = "Teams Voice Routing Policy name to create"
        "UsageName"          = "Teams PSTN Usage name to create"
        "RouteName"          = "Teams Voice Route name to create"
        "CommsProviderId"    = "D365 Communications Provider Setting ID -- auto-retrieved from D365 Web API"
        "ResourceAccounts"   = "Auto-populated by migration script from D365 -- leave as empty array"
    }
    "TenantId"            = $TenantId
    "AdminUpn"            = $AdminUpn
    "Domain"              = $Domain
    "DynamicsAppId"       = $DynamicsAppId
    "D365OrgUrl"          = $D365OrgUrl
    "RaPrefix"            = $RaPrefix
    "AcsSubscriptionId"   = $AcsSubscriptionId
    "AcsResourceId"       = $AcsResourceId
    "AcsEndpoint"         = $AcsEndpoint
    "AcsConnectionString" = $AcsConnectionString
    "SbcFqdn"             = $SbcFqdn
    "SbcPort"             = $SbcPort
    "PolicyName"          = $PolicyName
    "UsageName"           = $UsageName
    "RouteName"           = $RouteName
    "CommsProviderId"     = $CommsProviderId
    "ResourceAccounts"    = @()
}

$configJson = $config | ConvertTo-Json -Depth 5

# Check for any empty required fields
$missingFields = @()
@("TenantId","AdminUpn","Domain","DynamicsAppId","D365OrgUrl","AcsSubscriptionId","AcsResourceId","AcsEndpoint","AcsConnectionString","SbcFqdn") | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($config[$_])) { $missingFields += $_ }
}
if ($SbcPort -eq 0) { $missingFields += "SbcPort" }

if ($missingFields.Count -gt 0) {
    Write-Host ""
    Write-Warn "The following fields could not be auto-retrieved and are empty:"
    $missingFields | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    Write-Warn "Update them manually in the output file before running the migration."
}

# ---------------------------------------------------------------------------
# Phase 8: Write or display
# ---------------------------------------------------------------------------
Write-Host ""
if ($DryRun) {
    Write-Host "========== DRY RUN -- CONFIG PREVIEW ==========" -ForegroundColor Yellow
    Write-Host $configJson
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-OK "DRY RUN complete. No file written."
} else {
    $configJson | Out-File -FilePath $OutputPath -Encoding utf8 -Force
    Write-OK "Config written to: $OutputPath"
    Write-Host ""
    Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
    Write-Host "  Output file:     $OutputPath"
    Write-Host "  TenantId:        $TenantId"
    Write-Host "  AdminUpn:        $AdminUpn"
    Write-Host "  D365OrgUrl:      $D365OrgUrl"
    Write-Host "  AcsResourceId:   $AcsResourceId"
    Write-Host "  SbcFqdn:         $SbcFqdn  port=$SbcPort"
    Write-Host "  DynamicsAppId:   $DynamicsAppId"
    Write-Host "  CommsProviderId: $CommsProviderId"
    if ($missingFields.Count -gt 0) {
        Write-Host "  INCOMPLETE:      $($missingFields -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host "  Status:          All fields populated" -ForegroundColor Green
    }
    Write-Host "=============================="
    Write-Host ""
    Write-Host "Next step:" -ForegroundColor Gray
    Write-Host "  .\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath $OutputPath -DryRun" -ForegroundColor Gray
}

