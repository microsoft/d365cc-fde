#Requires -Version 5.1
<#
.SYNOPSIS
    Corrects an ACS SIP route number pattern via HMAC-signed PATCH.

.DESCRIPTION
    PATCHes an ACS SIP route with the specified name, number pattern, and trunk FQDN.
    Parameters are now fully configurable (previously hardcoded in v14.0.0).

.PARAMETER ConfigPath
    Path to the config JSON file containing AcsConnectionString.

.PARAMETER RouteName
    The ACS route name to PATCH (e.g. 'cbg').

.PARAMETER NumberPattern
    The regex number pattern for the route (e.g. '^\+1206\d*$').

.PARAMETER TrunkFqdn
    The trunk FQDN to wire the route to (e.g. 'sbc.contoso.com').

.PARAMETER DryRun
    Show what would be changed without calling the API.

.EXAMPLE
    .\Fix-AcsRoutePattern-v14.ps1 -ConfigPath .\acs-tpe-config.json -RouteName 'cbg' -NumberPattern '^\+1206\d*$' -TrunkFqdn 'sbc.contoso.com'

.EXAMPLE
    .\Fix-AcsRoutePattern-v14.ps1 -ConfigPath .\acs-tpe-config.json -RouteName 'cbg' -NumberPattern '^\+1206\d*$' -TrunkFqdn 'sbc.contoso.com' -DryRun

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.11.0  : PATCH failure now exits with code 1 (was silent), added
                verification GET after successful PATCH, version bump.
    v14.9.0   : Version string parity with all scripts.
    v14.8.0   : Version string parity with all scripts.
    v14.6.0   : Parameterized RouteName/NumberPattern/TrunkFqdn (no longer hardcoded),
                added DryRun switch, version bump.
    v14.0.0   : #Requires added, Set-StrictMode, SHA256/HMAC Dispose().
#>

param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$RouteName,

    [Parameter(Mandatory)]
    [string]$NumberPattern,

    [Parameter(Mandatory)]
    [string]$TrunkFqdn,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ConfigPath)) {
    Write-Host "  ! Config not found: $ConfigPath" -ForegroundColor Red; exit 1
}
$cfg     = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$parts   = @{}
$cfg.AcsConnectionString.Split(';') | ForEach-Object {
    $kv = $_ -split '=', 2
    if ($kv.Count -eq 2) { $parts[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
}
$ep      = $parts['endpoint'].TrimEnd('/')
$key     = $parts['accesskey']
$apiHost = ([System.Uri]"$ep/sip").Host
$pq      = '/sip?api-version=2023-04-01-preview'
$apiUrl  = "$ep$pq"

$patch = @{
    routes = @(
        @{
            name          = $RouteName
            numberPattern = $NumberPattern
            trunks        = @($TrunkFqdn)
        }
    )
}
$patchBody = $patch | ConvertTo-Json -Depth 4 -Compress

Write-Host "=== Fix-AcsRoutePattern v14.11.0 ===" -ForegroundColor Cyan
Write-Host "  Route:   $RouteName"
Write-Host "  Pattern: $NumberPattern"
Write-Host "  Trunk:   $TrunkFqdn"
Write-Host "  Patch:   $patchBody" -ForegroundColor Gray

if ($DryRun) {
    Write-Host ""
    Write-Host "  DRY RUN -- no changes made." -ForegroundColor Yellow
    exit 0
}

$date     = [System.DateTime]::UtcNow.ToString('r')
$sha256   = [System.Security.Cryptography.SHA256]::Create()
try {
    $bodyHash = [System.Convert]::ToBase64String($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($patchBody)))
} finally { $sha256.Dispose() }
$keyB     = [System.Convert]::FromBase64String($key)
$toSign   = "PATCH`n$pq`n$date;$apiHost;$bodyHash"
$hmac     = [System.Security.Cryptography.HMACSHA256]::new($keyB)
try {
    $sig  = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
} finally { $hmac.Dispose() }
$hdrs     = @{
    'x-ms-date'           = $date
    'x-ms-content-sha256' = $bodyHash
    'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
    'Content-Type'        = 'application/merge-patch+json'
}

try {
    Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $hdrs -Body $patchBody | Out-Null
    Write-Host "  OK Route pattern updated: $NumberPattern -> trunk $TrunkFqdn" -ForegroundColor Green
} catch {
    Write-Host "  ! Error: $($_.Exception.Message)" -ForegroundColor Red
    try { Write-Host "  Response: $($_.ErrorDetails.Message)" -ForegroundColor Red } catch {}
    exit 1
}

# Verification GET
Write-Host "  Verifying route state ..." -ForegroundColor Gray
$vDate     = [System.DateTime]::UtcNow.ToString('r')
$vSha      = [System.Security.Cryptography.SHA256]::Create()
try {
    $vHash = [System.Convert]::ToBase64String($vSha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('')))
} finally { $vSha.Dispose() }
$vSign     = "GET`n$pq`n$vDate;$apiHost;$vHash"
$vHmac     = [System.Security.Cryptography.HMACSHA256]::new($keyB)
try {
    $vSig  = [System.Convert]::ToBase64String($vHmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($vSign)))
} finally { $vHmac.Dispose() }
$vHdrs     = @{
    'x-ms-date'           = $vDate
    'x-ms-content-sha256' = $vHash
    'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$vSig"
}
try {
    $vResult = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $vHdrs
    $route   = $vResult.routes | Where-Object { $_.name -eq $RouteName }
    if ($route) {
        Write-Host "  Verified: route='$($route.name)'  pattern='$($route.numberPattern)'  trunks=$($route.trunks -join ',')" -ForegroundColor Green
    } else {
        Write-Host "  !   Route '$RouteName' not found in GET response." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  !   Verification GET failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
