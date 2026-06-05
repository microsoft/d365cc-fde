#Requires -Version 5.1
<#
.SYNOPSIS
    Adds the SBC FQDN as a disabled trunk in ACS Direct Routing.
    Used to pre-register the trunk so Toggle-AcsTeamsRouting-v14.ps1 can enable it later.

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.11.0   : PATCH failure now exits with code 1 (was silent), added
                 verification GET after successful PATCH, version bump.
    v14.9.0    : Version string parity with all scripts.
    v14.8.0    : Version string parity with all scripts.
    v14.6.0    : Added DryRun switch to preview without API call.
    v14.0.0    : #Requires added, Set-StrictMode, SHA256/HMAC Dispose(), Toggle ref updated to v14.
#>
param(
    [string]$ConfigPath = '.\acs-tpe-config-fromd365-local.json',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ConfigPath)) {
    Write-Host "  ! Config not found: $ConfigPath" -ForegroundColor Red; exit 1
}
$cfg  = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$fqdn = $cfg.SbcFqdn
if (-not $cfg.SbcPort -or [int]$cfg.SbcPort -le 0 -or [int]$cfg.SbcPort -gt 65535) {
    Write-Host "  ! Invalid SbcPort in config: $($cfg.SbcPort). Must be 1-65535." -ForegroundColor Red; exit 1
}
$port = [int]$cfg.SbcPort

$acsConn = @{}
$cfg.AcsConnectionString.Split(';') | ForEach-Object {
    $kv = $_ -split '=', 2
    if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
}
$acsEp  = $acsConn['endpoint'].TrimEnd('/')
$acsKey = $acsConn['accesskey']
$pq     = '/sip?api-version=2023-04-01-preview'
$apiUrl = "$acsEp$pq"
$apiHost= ([System.Uri]$apiUrl).Host
$EMPTY  = '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='

Write-Host "  Adding ACS trunk: $fqdn  port=$port  enabled=false ..." -ForegroundColor Cyan
if ($DryRun) { Write-Host "  *** DRY RUN ***" -ForegroundColor Yellow }

$body = @{ trunks = @{ $fqdn = @{ sipSignalingPort = $port; enabled = $false } } } | ConvertTo-Json -Depth 4 -Compress
Write-Host "  Patch body: $body" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "  DRY RUN -- no API call made." -ForegroundColor Yellow
    exit 0
}

$date     = [System.DateTime]::UtcNow.ToString('r')
$keyB     = [System.Convert]::FromBase64String($acsKey)
$sha256   = [System.Security.Cryptography.SHA256]::Create()
try {
    $bodyHash = [System.Convert]::ToBase64String($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($body)))
} finally { $sha256.Dispose() }
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
    Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $hdrs -Body $body | Out-Null
    Write-Host "  OK  ACS trunk '$fqdn' added with enabled=false." -ForegroundColor Green
} catch {
    Write-Host "  !   Failed: $($_.Exception.Message)" -ForegroundColor Red
    try { Write-Host "  Response: $($_.ErrorDetails.Message)" -ForegroundColor Red } catch {}
    exit 1
}

# Verification GET
Write-Host "  Verifying trunk state ..." -ForegroundColor Gray
$getDate     = [System.DateTime]::UtcNow.ToString('r')
$getSha      = [System.Security.Cryptography.SHA256]::Create()
try {
    $getHash = [System.Convert]::ToBase64String($getSha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('')))
} finally { $getSha.Dispose() }
$getSign     = "GET`n$pq`n$getDate;$apiHost;$getHash"
$getHmac     = [System.Security.Cryptography.HMACSHA256]::new($keyB)
try {
    $getSig  = [System.Convert]::ToBase64String($getHmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($getSign)))
} finally { $getHmac.Dispose() }
$getHdrs     = @{
    'x-ms-date'           = $getDate
    'x-ms-content-sha256' = $getHash
    'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$getSig"
}
try {
    $result = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $getHdrs
    $trunk  = $result.trunks.PSObject.Properties | Where-Object { $_.Name -eq $fqdn }
    if ($trunk) {
        Write-Host "  Verified: $fqdn  port=$($trunk.Value.sipSignalingPort)  enabled=$($trunk.Value.enabled)" -ForegroundColor Green
    } else {
        Write-Host "  !   Trunk '$fqdn' not found in GET response." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  !   Verification GET failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

