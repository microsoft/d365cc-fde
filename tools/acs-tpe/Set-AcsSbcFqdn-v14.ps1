#Requires -Version 5.1
<#
.SYNOPSIS
    Update (rename) a trunk FQDN in ACS SIP Routing via the REST API.

.DESCRIPTION
    Reads the current SIP trunks from ACS, lets you pick an existing trunk by FQDN,
    enter a new FQDN, and PATCHes ACS with the updated trunk list.
    All other trunks and routes are preserved unchanged.

    Auth: HMAC-SHA256 using the AcsConnectionString access key.
    API:  {AcsEndpoint}/sip?api-version=2023-04-01-preview

.PARAMETER ConfigPath
    Path to acs-tpe-config-fromd365.json (must contain AcsConnectionString).

.PARAMETER OldFqdn
    FQDN of the trunk to rename (optional; prompted if omitted).

.PARAMETER NewFqdn
    New FQDN to set for the trunk (optional; prompted if omitted).

.PARAMETER NewPort
    New SIP signaling port. If omitted, the existing port is kept.

.PARAMETER DryRun
    Show what would be changed without calling the API.

.PARAMETER List
    Query and display current trunks and routes, then exit. No changes made.

.PARAMETER RemoveFqdn
    Delete a trunk from ACS SIP configuration by setting it to null in the merge-patch.

.EXAMPLE
    .\Set-AcsSbcFqdn-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -List
    .\Set-AcsSbcFqdn-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -DryRun
    .\Set-AcsSbcFqdn-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -OldFqdn abc.cip-voice.com -NewFqdn xyz.cip-voice.com
    .\Set-AcsSbcFqdn-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -RemoveFqdn xyz.cip-voice.com

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.11.0   : Version string parity with all scripts.
    v14.9.0    : Version string parity with all scripts.
    v14.8.0    : Version string parity with all scripts.
    v14.6.0    : Added blank FQDN input validation (OldFqdn/NewFqdn).
    v14.0.0    : Compatible with v10 migration (no ACS consent step).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$OldFqdn    = '',
    [string]$NewFqdn    = '',
    [string]$RemoveFqdn = '',
    [int]$NewPort       = 0,
    [switch]$DryRun,
    [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ACS_API_VERSION = '2023-04-01-preview'
$EMPTY_BODY_HASH = '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='  # SHA256 of empty string

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Info  { param([string]$m) Write-Host "  -- $m" -ForegroundColor Gray }
function Write-Step  { param([string]$m) Write-Host "  >> $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "  OK $m" -ForegroundColor Green }
function Write-Warn  { param([string]$m) Write-Host "  WARN $m" -ForegroundColor Yellow }
function Write-Err   { param([string]$m) Write-Host "  ERR $m" -ForegroundColor Red }

function Parse-ConnectionString {
    param([string]$Conn)
    $parts = @{}
    foreach ($seg in $Conn.Split(';')) {
        $kv = $seg.Split('=', 2)
        if ($kv.Count -eq 2) { $parts[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
    }
    return $parts
}

function Build-HmacHeaders {
    param(
        [string]$Method,
        [string]$PathAndQuery,
        [string]$ApiHost,
        [string]$AccessKey,
        [string]$Body = ''
    )
    $date      = [System.DateTime]::UtcNow.ToString('r')
    $sha256    = [System.Security.Cryptography.SHA256]::Create()
    try {
        if ($Body) {
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $bodyHash  = [System.Convert]::ToBase64String($sha256.ComputeHash($bodyBytes))
        } else {
            $bodyHash  = $EMPTY_BODY_HASH
        }
    } finally { $sha256.Dispose() }
    $keyBytes  = [System.Convert]::FromBase64String($AccessKey)
    $toSign    = "$Method`n$PathAndQuery`n$date;$ApiHost;$bodyHash"
    $hmac      = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
    try {
        $sig   = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
    } finally { $hmac.Dispose() }
    $headers   = @{
        'x-ms-date'           = $date
        'x-ms-content-sha256' = $bodyHash
        'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
    }
    if ($Body) { $headers['Content-Type'] = 'application/merge-patch+json' }
    return $headers
}

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------

Write-Step "Loading config: $ConfigPath"
if (-not (Test-Path $ConfigPath)) { Write-Err "Config not found: $ConfigPath"; exit 1 }
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if (-not $cfg.AcsConnectionString) { Write-Err "AcsConnectionString missing from config."; exit 1 }
$conn     = Parse-ConnectionString $cfg.AcsConnectionString
$endpoint = $conn['endpoint'].TrimEnd('/')
$key      = $conn['accesskey']
$apiHost  = ([System.Uri]"$endpoint/sip").Host

Write-OK "ACS endpoint: $endpoint"

# ---------------------------------------------------------------------------
# GET current trunks
# ---------------------------------------------------------------------------

$pathQuery = "/sip?api-version=$ACS_API_VERSION"
$apiUrl    = "$endpoint$pathQuery"

Write-Step "Fetching current SIP trunks from ACS ..."
$getHeaders = Build-HmacHeaders -Method 'GET' -PathAndQuery $pathQuery -ApiHost $apiHost -AccessKey $key
$sipData    = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $getHeaders

# ACS returns trunks as a dictionary keyed by FQDN: { "fqdn": { "sipSignalingPort": N, "enabled": true, ... } }
# Convert to array of PSCustomObjects for easier handling; preserve all fields from the value
$trunkDict = $sipData.trunks
$trunks    = @($trunkDict.PSObject.Properties | ForEach-Object {
    $val = $_.Value
    [PSCustomObject]@{ fqdn = $_.Name; sipSignalingPort = $val.sipSignalingPort; enabled = $val.enabled; _raw = $val }
})
$routes    = @($sipData.routes)

if ($trunks.Count -eq 0) {
    Write-Warn "No trunks found in ACS SIP configuration."
    exit 0
}

Write-OK "Found $($trunks.Count) trunk(s):"
$i = 0
foreach ($t in $trunks) {
    $i++
    $enabledLabel = if ($t.enabled -eq $false) { ' [DISABLED]' } else { '' }
    Write-Host "  [$i] $($t.fqdn)  port=$($t.sipSignalingPort)$enabledLabel" -ForegroundColor White
}

if ($routes.Count -gt 0) {
    Write-Host ""
    Write-Host "  Routes ($($routes.Count)):" -ForegroundColor Gray
    foreach ($r in $routes) {
        Write-Host "    name=$($r.name)  pattern=$($r.numberPattern)  trunks=[$($r.trunks -join ', ')]" -ForegroundColor DarkGray
    }
}

if ($List) {
    Write-Host ""
    Write-Info "(-List) query complete. No changes made."
    exit 0
}

# ---------------------------------------------------------------------------
# -RemoveFqdn: delete a trunk by patching it to null
# ---------------------------------------------------------------------------

if ($RemoveFqdn) {
    $match = $trunks | Where-Object { $_.fqdn -eq $RemoveFqdn }
    if (-not $match) {
        Write-Err "Trunk '$RemoveFqdn' not found in ACS."
        exit 1
    }
    Write-Host ""
    Write-Host "  Remove trunk: $RemoveFqdn" -ForegroundColor Yellow
    if ($DryRun) { Write-Warn "DRY RUN -- no changes made."; exit 0 }
    $confirm = (Read-Host "  Proceed? [Y/n]").Trim()
    if ($confirm -ne '' -and $confirm -notmatch '^[Yy]') { Write-Info "Aborted."; exit 0 }

    # Build patch: null out the trunk AND update any routes that reference it
    $removePatch = [ordered]@{ trunks = [ordered]@{ $RemoveFqdn = $null } }

    $affectedRoutes = @($routes | Where-Object { $_.trunks -contains $RemoveFqdn })
    if ($affectedRoutes.Count -gt 0) {
        Write-Info "Trunk is referenced by $($affectedRoutes.Count) route(s) - updating routes too."
        $removePatch['routes'] = @($routes | ForEach-Object {
            $r = $_
            $newTrunkList = @($r.trunks | Where-Object { $_ -ne $RemoveFqdn })
            @{ name = $r.name; numberPattern = $r.numberPattern; trunks = $newTrunkList }
        })
    }

    $removeBody = $removePatch | ConvertTo-Json -Depth 6 -Compress
    $removeHeaders = Build-HmacHeaders -Method 'PATCH' -PathAndQuery $pathQuery -ApiHost $apiHost -AccessKey $key -Body $removeBody
    try {
        Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $removeHeaders -Body $removeBody | Out-Null
        Write-OK "Trunk '$RemoveFqdn' removed from ACS."
    } catch {
        $errBody = $null
        try { $errBody = $_.ErrorDetails.Message } catch {}
        Write-Err "Remove failed: $($_.Exception.Message)"
        if ($errBody) { Write-Err "Response: $errBody" }
        exit 1
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Determine which trunk to update
# ---------------------------------------------------------------------------

if (-not $OldFqdn) {
    $OldFqdn = (Read-Host "`n  Enter the FQDN to rename (exact match)").Trim()
}
if ([string]::IsNullOrWhiteSpace($OldFqdn)) {
    Write-Err "Old FQDN cannot be blank."; exit 1
}

$target = $trunks | Where-Object { $_.fqdn -eq $OldFqdn }
if (-not $target) {
    Write-Err "Trunk '$OldFqdn' not found in ACS. Check spelling and re-run."
    exit 1
}

Write-OK "Found trunk: $($target.fqdn)  port=$($target.sipSignalingPort)"

if (-not $NewFqdn) {
    $NewFqdn = (Read-Host "  Enter new FQDN").Trim()
}
if (-not $NewFqdn) { Write-Err "New FQDN cannot be blank."; exit 1 }

$portToUse = if ($NewPort -gt 0) { $NewPort } else { $target.sipSignalingPort }

Write-Host ""
Write-Host "  Change summary:" -ForegroundColor Yellow
Write-Host "    Old FQDN : $($target.fqdn)" -ForegroundColor DarkGray
Write-Host "    New FQDN : $NewFqdn" -ForegroundColor White
Write-Host "    Port     : $portToUse" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Warn "DRY RUN -- no changes made."
    exit 0
}

$confirm = (Read-Host "  Proceed? [Y/n]").Trim()
if ($confirm -ne '' -and $confirm -notmatch '^[Yy]') {
    Write-Info "Aborted."
    exit 0
}

# ---------------------------------------------------------------------------
# Build merge-patch body (RFC 7396):
#   - Set old FQDN key to null  → ACS removes it
#   - Set new FQDN key to value → ACS adds/updates it
#   - Only include routes if any route references the old FQDN (need updating)
# ---------------------------------------------------------------------------

# Trunk entry for the new FQDN — preserve all original fields
$newTrunkEntry = @{ sipSignalingPort = $portToUse; enabled = $true }
if ($null -ne $target._raw) {
    foreach ($prop in $target._raw.PSObject.Properties) {
        if ($prop.Name -notin @('sipSignalingPort','enabled')) { $newTrunkEntry[$prop.Name] = $prop.Value }
    }
}

$patchDict = [ordered]@{
    trunks = [ordered]@{
        $OldFqdn = $null          # null = delete this key
        $NewFqdn = $newTrunkEntry  # add/update new key
    }
}

# Only patch routes if any reference the old FQDN
$affectedRoutes = @($routes | Where-Object { $_.trunks -contains $OldFqdn })
if ($affectedRoutes.Count -gt 0) {
    $patchDict['routes'] = @($routes | ForEach-Object {
        $r = $_
        $newTrunkList = @($r.trunks | ForEach-Object { if ($_ -eq $OldFqdn) { $NewFqdn } else { $_ } })
        @{ name = $r.name; numberPattern = $r.numberPattern; trunks = $newTrunkList }
    })
}

# ---------------------------------------------------------------------------
# PATCH ACS SIP configuration
# ---------------------------------------------------------------------------

$patchBody = $patchDict | ConvertTo-Json -Depth 6 -Compress

Write-Step "PATCHing ACS SIP configuration ..."
Write-Info "Request body: $patchBody"
$patchHeaders = Build-HmacHeaders -Method 'PATCH' -PathAndQuery $pathQuery -ApiHost $apiHost -AccessKey $key -Body $patchBody
try {
    Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $patchHeaders -Body $patchBody | Out-Null
} catch {
    $responseBody = $null
    try { $responseBody = $_.ErrorDetails.Message } catch {}
    if (-not $responseBody) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = [System.IO.StreamReader]::new($stream)
            $responseBody = $reader.ReadToEnd()
        } catch {}
    }
    Write-Err "PATCH failed: $($_.Exception.Message)"
    if ($responseBody) { Write-Err "Response: $responseBody" }
    exit 1
}

Write-OK "ACS trunk renamed: '$OldFqdn' -> '$NewFqdn' (port $portToUse)"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

Write-Step "Verifying update ..."
$verifyHeaders = Build-HmacHeaders -Method 'GET' -PathAndQuery $pathQuery -ApiHost $apiHost -AccessKey $key
$verified      = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $verifyHeaders
$found         = $verified.trunks.PSObject.Properties | Where-Object { $_.Name -eq $NewFqdn }
if ($found) {
    Write-OK "Confirmed: '$NewFqdn' port=$($found.Value.sipSignalingPort) is now in ACS."
} else {
    Write-Warn "New FQDN not found in verification GET -- check ACS portal."
}

Write-Host ""
Write-OK "Done."

