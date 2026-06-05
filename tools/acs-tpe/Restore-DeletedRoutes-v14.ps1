#Requires -Version 5.1
<#
.SYNOPSIS
    Restores pre-existing Teams voice routes that were incorrectly deleted by
    Undo-ACS-TPE-Migration-v14.ps1 (bug: removed routes from acs-export.json
    instead of only cfg.RouteName). Reads routes from acs-export.json and
    recreates any that are missing.

.EXAMPLE
    .\Restore-DeletedRoutes-v14.ps1 -DryRun
    .\Restore-DeletedRoutes-v14.ps1
#>
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  Restore Deleted Voice Routes v14" -ForegroundColor Cyan
Write-Host "  Mode: $(if ($DryRun) { 'DRY RUN' } else { 'LIVE' })" -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Red' })
Write-Host ""

# Load acs-export.json
$acsExportPath = '.\acs-export.json'
if (-not (Test-Path $acsExportPath)) {
    Write-Host "  ! acs-export.json not found." -ForegroundColor Red
    exit 1
}
$acsExport = Get-Content $acsExportPath -Raw | ConvertFrom-Json
$routes = @($acsExport.routes)
Write-Host "  -- Loaded $($routes.Count) route(s) from acs-export.json" -ForegroundColor Gray

# Connect to Teams if not already connected
try {
    $null = Get-CsOnlineVoiceRoute -ErrorAction Stop | Select-Object -First 1
    Write-Host "  OK Teams already connected." -ForegroundColor Green
} catch {
    Write-Host "  >> Connecting to Microsoft Teams ..." -ForegroundColor Cyan
    Connect-MicrosoftTeams -UseDeviceAuthentication | Out-Null
    Write-Host "  OK Connected." -ForegroundColor Green
}

Write-Host ""
$restored = 0
$skipped  = 0
$failed   = 0

foreach ($route in $routes) {
    $name    = $route.name
    $pattern = $route.numberPattern
    $trunks  = @($route.trunks)

    # Check if route already exists
    $existing = $null
    try {
        $existing = Get-CsOnlineVoiceRoute -Identity $name -ErrorAction SilentlyContinue
    } catch {}

    if ($existing) {
        Write-Host "  -- '$name' already exists -- skipped." -ForegroundColor Gray
        $skipped++
        continue
    }

    # Verify all gateways exist in Teams before attempting to create the route
    $missingGateways = @()
    foreach ($gw in $trunks) {
        try {
            $null = Get-CsOnlinePSTNGateway -Identity $gw -ErrorAction Stop
        } catch {
            $missingGateways += $gw
        }
    }
    if ($missingGateways.Count -gt 0) {
        Write-Host "  WARN '$name' skipped -- gateway(s) not found in Teams: $($missingGateways -join ', ')" -ForegroundColor Yellow
        $skipped++
        continue
    }

    Write-Host "  >> Restore route '$name' (pattern=$pattern, gateways=$($trunks -join ',')) ..." -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "     (DRY RUN) Would run: New-CsOnlineVoiceRoute -Identity '$name' -NumberPattern '$pattern' -OnlinePstnGatewayList @($( ($trunks | ForEach-Object { "'$_'" }) -join ',' ))" -ForegroundColor DarkGray
        $restored++
    } else {
        try {
            $params = @{
                Identity               = $name
                NumberPattern          = $pattern
                OnlinePstnGatewayList  = $trunks
            }
            if ($route.PSObject.Properties['description'] -and $route.description) {
                $params['Description'] = $route.description
            }
            New-CsOnlineVoiceRoute @params | Out-Null
            Write-Host "  OK '$name' restored." -ForegroundColor Green
            $restored++
        } catch {
            Write-Host "  ! Failed to restore '$name': $_" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host ""
Write-Host "  +------------------------------------------+" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  |  Restore complete                         |" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  |  Restored : $restored" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  |  Skipped  : $skipped (already existed)   |" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  |  Failed   : $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  +------------------------------------------+" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if (-not $DryRun -and $restored -gt 0) {
    Write-Host "  NOTE: Routes have been recreated but may not be associated with" -ForegroundColor Yellow
    Write-Host "        any PSTN usage yet. If calls are not routing correctly," -ForegroundColor Yellow
    Write-Host "        verify route-to-usage associations in Teams Admin Center." -ForegroundColor Yellow
    Write-Host ""
}
