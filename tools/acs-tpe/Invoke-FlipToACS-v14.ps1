#Requires -Version 5.1
<#
.SYNOPSIS
    Flips routing from Teams Phone System back to ACS Direct Routing. v14

.DESCRIPTION
    Two-step rollback:

      Step A -- Toggle routing  (Teams -> ACS)
        Calls Toggle-AcsTeamsRouting-v14.ps1 with the config path.
        Toggle auto-detects that Teams is active and flips:
          - Teams gateway: Enabled=$false
          - ACS trunk:     re-enabled with restored routes

      Step B -- Remove Teams phone number assignments
        Calls Remove-CsPhoneNumberAssignment for each number.
        Required to prevent D365 CCaaS background sync from re-linking the
        Teams RA after Step C clears it.

      Step C -- Update D365 phone type  (TPS -> ACS, per number)
        Calls Invoke-MigrateTpsPhoneNumber-v14.ps1 for each number with
        Direction=TPS_TO_ACS, which:
          - Sets msdyn_phonenumbertype = 0 (ACS)
          - Sets msdyn_ocphonenumbersource = 192350000 (ACS)
          - Clears msdyn_teamsresourceaccount (null)
          - Skips CCaaS_SynchronizePhoneNumbers (would re-revert fields)

    Phone numbers are discovered automatically from D365 by querying
    msdyn_ocphonenumbers where msdyn_phonenumbertype = 1 (Teams).
    Use -PhoneNumbers to override with a specific list.

.PARAMETER ConfigPath
    Path to the ACS-TPE config JSON, e.g. .\acs-tpe-config-fromd365-local.json
    Must contain: AcsConnectionString, SbcFqdn, TenantId, AdminUpn, D365OrgUrl.

.PARAMETER PhoneNumbers
    Optional. One or more phone numbers to flip (e.g. +12069990060,+14255550100).
    If omitted, the script queries D365 for all numbers currently set to
    msdyn_phonenumbertype = 1 (Teams Phone System).

.PARAMETER DryRun
    Show the plan without making any changes. Passes -DryRun to both
    Toggle and Invoke-MigrateTpsPhoneNumber.

.NOTES
    v14.9.0: Fix-AcsRoutePattern and Update-PhoneNumberType console banner
             version strings corrected (were v14.6.0), migration HTML title
             version added, README sections added for 5 missing scripts,
             version strings bumped to v14.9.0.
    v14.8.0: Dashboard state skips FAIL results when determining active system
             (prevents misleading state after failed operation), Test-DomainRegistration
             DryRun no longer sets $verified=$true (shows accurate DryRun behavior),
             version strings bumped to v14.8.0.
    v14.6.0: Update-PhoneNumberType msdyn_ocphonenumbersource parity + DryRun + sync,
             Fix-AcsRoutePattern parameterized (no hardcoded FQDN/pattern) + DryRun,
             Add-AcsTrunkDisabled DryRun switch, Set-AcsSbcFqdn blank FQDN validation,
             Archive-TpeRuns Sort-Object dedup fix, Invoke-TeamsPhoneSync GUID validation,
             version strings bumped to v14.6.0.
    v14.5.0: Version strings bumped to v14.5.0.
    v14.4.0: Write-TpeRunRecord -Failed→-Failures param fix, dashboard version
             parity, version strings bumped to v14.4.0.
    v14.3.0: Dashboard parity with Toggle/Migration — $esc XSS escaping, toggle-to-tpe/
             toggle-to-acs type recognition, Steps column, Migrate/Undo card labels,
             run-record startStep/stopStep/completed/skipped fields, version strings bumped.
    v14.0.0
    v14: Write-Err no longer hard-exits, version strings updated, script references updated.
    v14.0.3: HTML run log added (mirrors Undo/Migration pattern), stats/tpe-runs.jsonl record,
             tpe-status.html dashboard update.

.EXAMPLE
    # Dry run -- see what would flip, no changes
    .\Invoke-FlipToACS-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -DryRun

.EXAMPLE
    # Flip numbers from this migration run (reads ra-objectids.json -- default)
    .\Invoke-FlipToACS-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json

.EXAMPLE
    # Flip specific numbers only
    .\Invoke-FlipToACS-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -PhoneNumbers "+12069990060","+14255550100"

.EXAMPLE
    # Flip ALL Teams-type numbers found in D365 (not just this migration run)
    .\Invoke-FlipToACS-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -AllNumbers
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter()]
    [string[]]$PhoneNumbers,

    # Query D365 for ALL numbers with type=Teams rather than reading ra-objectids.json
    [switch]$AllNumbers,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# HTML LOG SETUP
# ---------------------------------------------------------------------------

$script:HtmlLogPath = ".\tpe-flip-acs-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ACS TPE Flip To ACS v14.11.0 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
<style>
  body      { background:#1e1e1e; color:#d4d4d4; font-family:Consolas,'Courier New',monospace; font-size:13px; padding:24px; }
  pre       { margin:0; white-space:pre-wrap; word-wrap:break-word; line-height:1.6; }
  .cyan     { color:#00bfff; }
  .darkcyan { color:#00ced1; }
  .darkgray { color:#808080; }
  .green    { color:#4ec94e; }
  .yellow   { color:#ffd700; }
  .red      { color:#ff6b6b; }
  .gray     { color:#aaaaaa; }
  .white    { color:#ffffff; }
  .magenta  { color:#da70d6; }
</style>
</head>
<body><pre>
"@
Set-Content -Path $script:HtmlLogPath -Value $htmlHeader -Encoding UTF8

$invokedAs = ($MyInvocation.Line).Trim() -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
Add-Content -Path $script:HtmlLogPath -Value "<span class=`"darkgray`">Run : $invokedAs</span>" -Encoding UTF8
Add-Content -Path $script:HtmlLogPath -Value "<span class=`"darkgray`">Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span>" -Encoding UTF8
Add-Content -Path $script:HtmlLogPath -Value "" -Encoding UTF8

# ---------------------------------------------------------------------------
# Exit-Script helper -- ensures HTML log footer is always written
# ---------------------------------------------------------------------------

function Exit-Script {
    param([int]$Code = 0, [string]$FooterHtml = '')
    try { Add-Content -Path $script:HtmlLogPath -Value "</pre>$FooterHtml</body></html>" -Encoding UTF8 } catch {}
    exit $Code
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-HtmlLine {
    param([string]$Text, [string]$Color = 'White')
    $css = switch ($Color) {
        'Cyan'     { 'cyan' }
        'DarkCyan' { 'darkcyan' }
        'DarkGray' { 'darkgray' }
        'Green'    { 'green' }
        'Yellow'   { 'yellow' }
        'Red'      { 'red' }
        'Gray'     { 'gray' }
        'Magenta'  { 'magenta' }
        default    { 'white' }
    }
    $escaped = $Text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    try { Add-Content -Path $script:HtmlLogPath -Value "<span class=`"$css`">$escaped</span>" -Encoding UTF8 } catch {}
}

function Write-Step { param([string]$m) Write-Host "  >> $m" -ForegroundColor Cyan;    Write-HtmlLine "  >> $m" 'Cyan' }
function Write-OK   { param([string]$m) Write-Host "  OK $m"  -ForegroundColor Green;  Write-HtmlLine "  OK $m" 'Green' }
function Write-Warn { param([string]$m) Write-Host "  WARN $m" -ForegroundColor Yellow; Write-HtmlLine "  WARN $m" 'Yellow' }
function Write-Err  { param([string]$m) Write-Host "  ! $m"  -ForegroundColor Red;    Write-HtmlLine "  ! $m" 'Red' }
function Write-Info { param([string]$m) Write-Host "  -- $m"  -ForegroundColor Gray;   Write-HtmlLine "  -- $m" 'Gray' }

# ---------------------------------------------------------------------------
# Run record + status dashboard
# ---------------------------------------------------------------------------

function Write-TpeRunRecord {
    param([string]$Type, [string[]]$PhoneNums, [string]$Result,
          [int]$Completed = 0, [int]$Skipped = 0, [int]$Failures = 0)
    try {
        if (-not (Test-Path '.\stats')) { $null = New-Item -ItemType Directory -Path '.\stats' -Force }
        $rec = [ordered]@{
            type         = $Type
            timestamp    = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
            logFile      = ($script:HtmlLogPath -replace '^\.\\', '')
            startStep    = 0
            stopStep     = 0
            dryRun       = [bool]$DryRun
            phoneNumbers = @($PhoneNums | Where-Object { $_ })
            result       = $Result
            completed    = $Completed
            skipped      = $Skipped
            failures     = $Failures
            d365OrgUrl   = if ($script:d365OrgUrlForRecord) { $script:d365OrgUrlForRecord } else { '' }
        }
        Add-Content -Path '.\stats\tpe-runs.jsonl' -Value ($rec | ConvertTo-Json -Compress) -Encoding UTF8
    } catch {}
}

function Update-TpeStatusDashboard {
    try {
        $esc = { param([string]$s) $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&#39;" }
        $jsonlPath = '.\stats\tpe-runs.jsonl'
        $dashPath  = '.\tpe-status.html'
        $records   = @()
        if (Test-Path $jsonlPath) {
            $records = @(Get-Content $jsonlPath | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_ })
        }
        $last       = $records | Where-Object { -not $_.dryRun -and $_.result -ne 'FAIL' } | Select-Object -Last 1
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams' -or $last.type -eq 'toggle-to-tpe')
        $lastFailed = $records | Where-Object { -not $_.dryRun } | Select-Object -Last 1
        $hasPendingFail = $lastFailed -and $lastFailed.result -eq 'FAIL'
        $stateLabel = if (-not $last) { 'Unknown' } elseif ($hasPendingFail) { ($(if ($isTeamsActive) { 'MIGRATED &mdash; Teams Active' } else { 'ROLLED BACK &mdash; ACS Active' }) + ' <span style="color:#ff6b6b">(last run FAILED)</span>') } elseif ($isTeamsActive) { 'MIGRATED &mdash; Teams Active' } else { 'ROLLED BACK &mdash; ACS Active' }
        $stateColor = if ($isTeamsActive) { '#ffd700' } else { '#4ec94e' }
        $lastTime   = if ($last) { $last.timestamp } else { 'N/A' }
        $lastNums   = if ($last -and $last.phoneNumbers -and @($last.phoneNumbers).Count -gt 0) { & $esc ((@($last.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { 'N/A' }
        $d365Url    = if ($last -and $last.d365OrgUrl) { & $esc $last.d365OrgUrl } else { '' }
        $total      = $records.Count
        $migCount   = @($records | Where-Object { ($_.type -eq 'migrate' -or $_.type -eq 'flip-teams' -or $_.type -eq 'toggle-to-tpe') -and -not $_.dryRun }).Count
        $undoCount  = @($records | Where-Object { ($_.type -eq 'undo' -or $_.type -eq 'flip-acs' -or $_.type -eq 'toggle-to-acs') -and -not $_.dryRun }).Count
        $rows       = ''
        $recent     = @($records | Select-Object -Last 30); [array]::Reverse($recent)
        foreach ($r in $recent) {
            $tHtml = if ($r.type -eq 'migrate' -or $r.type -eq 'flip-teams' -or $r.type -eq 'toggle-to-tpe') { '<span style="color:#00bfff">MIGRATE</span>' } else { '<span style="color:#ff6b6b">UNDO</span>' }
            $rHtml = switch ($r.result) { 'OK' { '<span style="color:#4ec94e">OK</span>' } 'WARN' { '<span style="color:#ffd700">WARN</span>' } 'FAIL' { '<span style="color:#ff6b6b">FAIL</span>' } default { '<span style="color:#666">&mdash;</span>' } }
            $dry   = if ($r.dryRun) { ' <span style="color:#555">(dry)</span>' } else { '' }
            $steps = if ($r.type -eq 'undo' -or $r.type -eq 'flip-acs' -or $r.type -eq 'toggle-to-acs') { "Steps $($r.stopStep)&#8592;$($r.startStep)" } else { "Steps $($r.startStep)&#8594;$($r.stopStep)" }
            $nums  = if ($r.phoneNumbers -and @($r.phoneNumbers).Count -gt 0) { & $esc ((@($r.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { '&mdash;' }
            $logEsc = if ($r.logFile) { & $esc $r.logFile } else { '' }
            $log   = if ($logEsc) { "<a href='$logEsc'>$logEsc</a>" } else { '&mdash;' }
            $fail  = if ($r.failures -gt 0) { " <span style='color:#ff6b6b'>($($r.failures) fail)</span>" } else { '' }
            $rows += "<tr><td>$($r.timestamp)</td><td>$tHtml$dry</td><td>$steps</td><td>$nums</td><td>$rHtml$fail</td><td>$log</td></tr>`n"
        }
        $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $html = "<!DOCTYPE html><html><head><meta charset=`"UTF-8`"><meta http-equiv=`"refresh`" content=`"60`"><title>ACS TPE Migration Status</title><style>*{box-sizing:border-box}body{background:#1e1e1e;color:#d4d4d4;font-family:Consolas,'Courier New',monospace;font-size:13px;padding:24px;margin:0}h1{color:#00bfff;font-size:16px;margin:0 0 2px 0}.sub{color:#555;font-size:11px;margin:0 0 20px 0}.state{border-left:4px solid $stateColor;background:#252526;padding:14px 18px;margin:16px 0;border-radius:0 4px 4px 0}.state .lbl{font-size:14px;font-weight:bold;color:$stateColor;margin-bottom:4px}.state .meta{color:#888;font-size:12px}.cards{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}.card{background:#252526;border:1px solid #333;border-radius:4px;padding:12px 16px;min-width:130px;text-align:center}.card .n{font-size:22px;font-weight:bold;margin-bottom:2px}.card .l{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:1px}table{width:100%;border-collapse:collapse}th{background:#252526;color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;padding:7px 10px;text-align:left;border-bottom:1px solid #333}td{padding:6px 10px;border-bottom:1px solid #222;font-size:12px}tr:hover td{background:#252526}a{color:#00bfff;text-decoration:none}a:hover{text-decoration:underline}.sh{color:#555;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin:20px 0 6px 0;border-bottom:1px solid #2a2a2a;padding-bottom:5px}.foot{margin-top:24px;color:#333;font-size:11px}</style></head><body><h1>ACS TPE Migration Status</h1><div class=`"sub`">v14.11.0 &nbsp;|&nbsp; $d365Url &nbsp;|&nbsp; Auto-refresh: 60s</div><div class=`"state`"><div class=`"lbl`">$stateLabel</div><div class=`"meta`">Last action: $lastTime &nbsp;|&nbsp; Numbers: $lastNums</div></div><div class=`"cards`"><div class=`"card`"><div class=`"n`" style=`"color:#d4d4d4`">$total</div><div class=`"l`">Total Runs</div></div><div class=`"card`"><div class=`"n`" style=`"color:#00bfff`">$migCount</div><div class=`"l`">Migrate</div></div><div class=`"card`"><div class=`"n`" style=`"color:#ff6b6b`">$undoCount</div><div class=`"l`">Undo</div></div></div><div class=`"sh`">Run History (last 30)</div><table><tr><th>Timestamp</th><th>Type</th><th>Steps</th><th>Numbers</th><th>Result</th><th>Log</th></tr>$rows</table><div class=`"foot`">Generated $generated &nbsp;|&nbsp; ACS TPE v14.11.0 &nbsp;|&nbsp; stats/tpe-runs.jsonl</div></body></html>"
        Set-Content -Path $dashPath -Value $html -Encoding UTF8
        Write-Host "  Status dashboard: $dashPath" -ForegroundColor DarkGray
        Write-HtmlLine "  Status dashboard: $dashPath" 'DarkGray'
    } catch {}
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
$line = '+' + ('=' * 66) + '+'
Write-Host ""
Write-Host $line -ForegroundColor Yellow
Write-Host "|                                                                  |" -ForegroundColor Yellow
Write-Host "|   Flip To ACS  v14.11.0  --  Teams -> ACS Rollback                  |" -ForegroundColor Yellow
if ($DryRun) {
Write-Host "|   *** DRY RUN -- no changes will be made ***                    |" -ForegroundColor Yellow
}
Write-Host "|                                                                  |" -ForegroundColor Yellow
Write-Host $line -ForegroundColor Yellow
Write-Host ""

Write-HtmlLine ""
Write-HtmlLine $line 'Yellow'
Write-HtmlLine "|                                                                  |" 'Yellow'
Write-HtmlLine "|   Flip To ACS  v14.11.0  --  Teams -> ACS Rollback                  |" 'Yellow'
if ($DryRun) { Write-HtmlLine "|   *** DRY RUN -- no changes will be made ***                    |" 'Yellow' }
Write-HtmlLine "|                                                                  |" 'Yellow'
Write-HtmlLine $line 'Yellow'
Write-HtmlLine ""

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
if (-not (Test-Path $ConfigPath)) {
    Write-Err "Config file not found: $ConfigPath"
    Exit-Script 1
}

Write-Step "Loading config: $ConfigPath"
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$d365OrgUrl = $cfg.D365OrgUrl
if ([string]::IsNullOrWhiteSpace($d365OrgUrl)) {
    Write-Err "D365OrgUrl is missing from config. Re-generate with New-AcsTpeConfig-v14.ps1."
    Exit-Script 1
}
$d365OrgUrl = $d365OrgUrl.TrimEnd('/')
$script:d365OrgUrlForRecord = $d365OrgUrl
Write-OK "Config loaded. D365OrgUrl: $d365OrgUrl"

# ---------------------------------------------------------------------------
# Resolve script directory for sub-script calls
# ---------------------------------------------------------------------------
$scriptDir       = $PSScriptRoot
$toggleScript    = Join-Path $scriptDir "Toggle-AcsTeamsRouting-v14.ps1"
$migrateScript   = Join-Path $scriptDir "Invoke-MigrateTpsPhoneNumber-v14.ps1"

foreach ($s in $toggleScript, $migrateScript) {
    if (-not (Test-Path $s)) {
        Write-Err "Required script not found: $s"
        Exit-Script 1
    }
}

# ---------------------------------------------------------------------------
# Resolve phone numbers
# ---------------------------------------------------------------------------
if ($PhoneNumbers -and $PhoneNumbers.Count -gt 0) {
    # Explicit list supplied
    $numbersToFlip = $PhoneNumbers
    Write-Info "Using $($numbersToFlip.Count) phone number(s) from -PhoneNumbers parameter."

} elseif ($AllNumbers) {
    # Query D365 for every number currently set to Teams Phone System (type=1)
    Write-Step "Querying D365 for ALL numbers with msdyn_phonenumbertype = 1 (Teams) ..."

    $tokenJson = az account get-access-token --resource "$d365OrgUrl" --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "az account get-access-token failed. Ensure you are logged in.`n$tokenJson"
        Exit-Script 1
    }
    $accessToken = ($tokenJson | ConvertFrom-Json).accessToken

    $headersGet = @{
        "Authorization"    = "Bearer $accessToken"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        "Accept"           = "application/json"
    }

    $filterValue = "msdyn_phonenumbertype eq 1 and statecode eq 0"
    $queryUri    = "$d365OrgUrl/api/data/v9.2/msdyn_ocphonenumbers" +
                   "?`$select=msdyn_phonenumber,msdyn_teamsresourceaccount" +
                   "&`$filter=" + [System.Uri]::EscapeDataString($filterValue) +
                   "&`$orderby=msdyn_phonenumber"

    $queryResult = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $headersGet
    $d365Records = $queryResult.value

    if (-not $d365Records -or $d365Records.Count -eq 0) {
        Write-OK "No numbers found in D365 with msdyn_phonenumbertype = 1. Nothing to flip."
        Exit-Script 0
    }

    Write-OK "Found $($d365Records.Count) Teams-type number(s) in D365 (-AllNumbers):"
    $i = 0
    foreach ($rec in $d365Records) {
        $i++
        $ra = if ([string]::IsNullOrWhiteSpace($rec.msdyn_teamsresourceaccount)) { '(no RA)' } else { $rec.msdyn_teamsresourceaccount }
        $line2 = ("    {0,2}  {1,-22}  RA: {2}" -f $i, $rec.msdyn_phonenumber, $ra)
        Write-Host $line2 -ForegroundColor Cyan
        Write-HtmlLine $line2 'Cyan'
    }
    $numbersToFlip = $d365Records | ForEach-Object { $_.msdyn_phonenumber }

} else {
    # Default: read ra-objectids.json -- only numbers migrated in this run
    $configDir   = Split-Path $ConfigPath -Parent
    $raOidsPath  = Join-Path $configDir "ra-objectids.json"

    if (-not (Test-Path $raOidsPath)) {
        Write-Err "ra-objectids.json not found at: $raOidsPath"
        Write-Info "This file is written by the migration script (Step 7)."
        Write-Info "Use -PhoneNumbers to supply numbers explicitly, or -AllNumbers to query all Teams-type numbers from D365."
        Exit-Script 1
    }

    Write-Step "Reading migrated numbers from ra-objectids.json ..."
    $raOids = Get-Content $raOidsPath -Raw | ConvertFrom-Json

    # UPN keys look like: acs-tpe-ra-12069990060@domain.com
    # Extract phone number using RaPrefix from config (e.g. "acs-tpe-ra-<phonenumber>")
    $raPrefix = if ($cfg.PSObject.Properties['RaPrefix'] -and $cfg.RaPrefix) { $cfg.RaPrefix } else { '' }
    # Sanitize prefix the same way Build-RaList does (lowercase, replace special chars with hyphens)
    $sanitizedPrefix = ($raPrefix -replace '[^a-zA-Z0-9\-\.<>]', '-' -replace '-+', '-').ToLower().Trim('-')
    $prefixBefore = if ($sanitizedPrefix -match '<phonenumber>') { ($sanitizedPrefix -split '<phonenumber>')[0] } else { '' }

    $numbersToFlip = foreach ($upn in $raOids.PSObject.Properties.Name) {
        $localPart = ($upn -split '@')[0]              # acs-tpe-ra-12069990060
        if ($prefixBefore -and $localPart.StartsWith($prefixBefore)) {
            $digits = $localPart.Substring($prefixBefore.Length)   # 12069990060
            "+$digits"
        } else {
            # Fallback: strip everything up to the last '-' block of digits
            if ($localPart -match '(\d{7,15})$') { "+$($Matches[1])" }
        }
    }

    $numbersToFlip = @($numbersToFlip | Where-Object { $_ })

    if ($numbersToFlip.Count -eq 0) {
        Write-Err "Could not parse any phone numbers from ra-objectids.json. Use -PhoneNumbers to supply them explicitly."
        Exit-Script 1
    }

    Write-OK "Found $($numbersToFlip.Count) number(s) from ra-objectids.json (this migration run):"
    $i = 0
    foreach ($num in $numbersToFlip) {
        $i++
        $oid = ($raOids.PSObject.Properties | Where-Object { $_.Name -match ($num -replace '\+','') } | Select-Object -First 1).Value
        $line2 = ("    {0,2}  {1,-22}  ObjectId: {2}" -f $i, $num, $oid)
        Write-Host $line2 -ForegroundColor Cyan
        Write-HtmlLine $line2 'Cyan'
    }
}

# ---------------------------------------------------------------------------
# Plan summary
# ---------------------------------------------------------------------------
$divider = '-' * 66

Write-Host ""
Write-Host "  PLAN:" -ForegroundColor Gray
Write-Host "  Step A -- Toggle-AcsTeamsRouting-v14.ps1 (Teams -> ACS)" -ForegroundColor Gray
Write-Host "            Config: $ConfigPath" -ForegroundColor Gray
Write-Host "  Step B -- Remove-CsPhoneNumberAssignment x $($numbersToFlip.Count) number(s)  (unlink Teams RA)" -ForegroundColor Gray
Write-Host "  Step C -- Invoke-MigrateTpsPhoneNumber-v14.ps1 x $($numbersToFlip.Count) number(s)" -ForegroundColor Gray
foreach ($num in $numbersToFlip) {
    Write-Host "            $num  ->  Direction=TPS_TO_ACS  (type=ACS, clear RA)" -ForegroundColor Gray
}
Write-Host ""

Write-HtmlLine ""
Write-HtmlLine "  PLAN:" 'Gray'
Write-HtmlLine "  Step A -- Toggle-AcsTeamsRouting-v14.ps1 (Teams -> ACS)" 'Gray'
Write-HtmlLine "            Config: $ConfigPath" 'Gray'
Write-HtmlLine "  Step B -- Remove-CsPhoneNumberAssignment x $($numbersToFlip.Count) number(s)  (unlink Teams RA)" 'Gray'
Write-HtmlLine "  Step C -- Invoke-MigrateTpsPhoneNumber-v14.ps1 x $($numbersToFlip.Count) number(s)" 'Gray'
foreach ($num in $numbersToFlip) { Write-HtmlLine "            $num  ->  Direction=TPS_TO_ACS  (type=ACS, clear RA)" 'Gray' }
Write-HtmlLine ""

if ($DryRun) {
    Write-Host "  [DRY RUN] No changes will be made." -ForegroundColor Yellow
    Write-Host "  Run without -DryRun to execute." -ForegroundColor Yellow
    Write-Host ""
    Write-HtmlLine "  [DRY RUN] No changes will be made." 'Yellow'
    Write-HtmlLine "  Run without -DryRun to execute." 'Yellow'
    Write-HtmlLine ""
}

# Confirmation
if (-not $DryRun) {
    Write-Host "  This will flip routing to ACS and update D365 for $($numbersToFlip.Count) number(s)." -ForegroundColor Yellow
    Write-HtmlLine "  This will flip routing to ACS and update D365 for $($numbersToFlip.Count) number(s)." 'Yellow'
    $confirm = Read-Host "  Proceed? Flip from Teams to ACS [Y/n]"
    if ($confirm -and $confirm.Trim().ToUpper() -ne 'Y') {
        Write-Host "  Aborted." -ForegroundColor Yellow
        Write-HtmlLine "  Aborted." 'Yellow'
        Write-TpeRunRecord -Type 'flip-acs' -PhoneNums @($numbersToFlip) -Result 'FAIL' -Failures 0
        Exit-Script 0
    }
    Write-Host ""
    Write-HtmlLine ""
}

# ---------------------------------------------------------------------------
# STEP A -- Toggle Teams -> ACS
# ---------------------------------------------------------------------------
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  STEP A -- Toggle Routing  (Teams -> ACS)" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine "  STEP A -- Toggle Routing  (Teams -> ACS)" 'Cyan'
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine ""

$toggleArgs = @{ ConfigPath = $ConfigPath }
if ($DryRun) { $toggleArgs['DryRun'] = $true }

& $toggleScript @toggleArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-HtmlLine ""
    Write-Err "Toggle script failed (exit $LASTEXITCODE). D365 update NOT run. Fix the toggle issue and re-run."
    Write-TpeRunRecord -Type 'flip-acs' -PhoneNums @($numbersToFlip) -Result 'FAIL' -Failures $numbersToFlip.Count
    Exit-Script 1
}

Write-Host ""
Write-OK "Step A complete -- ACS is now active."
Write-Host ""
Write-HtmlLine ""

# ---------------------------------------------------------------------------
# STEP B -- Remove Teams phone number assignments
#   Required to prevent the D365 background CCaaS sync from re-linking the
#   Teams RA after Step 2 clears it. As long as the number is assigned to a
#   Teams RA in Teams Phone System, the sync reads that state and overwrites
#   msdyn_teamsresourceaccount back to the RA ObjectId.
# ---------------------------------------------------------------------------
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  STEP B -- Remove Teams Phone Number Assignments" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine "  STEP B -- Remove Teams Phone Number Assignments" 'Cyan'
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine ""

# Load ra-objectids.json for ObjectId lookup (may already be loaded above)
$configDir  = Split-Path $ConfigPath -Parent
$raOidsPath = Join-Path $configDir "ra-objectids.json"
$raObjectIds = @{}
if (Test-Path $raOidsPath) {
    $loaded = Get-Content $raOidsPath -Raw | ConvertFrom-Json
    $loaded.PSObject.Properties | ForEach-Object { $raObjectIds[$_.Name] = $_.Value }
    Write-Info "Loaded $($raObjectIds.Count) ObjectId(s) from ra-objectids.json"
} else {
    Write-Warn "ra-objectids.json not found -- Remove-CsPhoneNumberAssignment will be skipped."
    Write-Warn "D365 sync may re-link the Teams RA. Re-run with ra-objectids.json present to fix."
}

$removeSkipped = $false
if ($raObjectIds.Count -gt 0) {
    if (-not $DryRun) {
        Write-Step "Connecting to Microsoft Teams for Remove-CsPhoneNumberAssignment ..."
        try {
            Connect-MicrosoftTeams -TenantId $cfg.TenantId | Out-Null
            Write-OK "Teams connected."
        } catch {
            Write-Warn "Could not connect to Teams: $($_.Exception.Message -replace '\r?\n.*','')"
            Write-Warn "Remove-CsPhoneNumberAssignment skipped. D365 sync may re-link Teams RA."
            Write-Warn "Run manually after this script:"
            foreach ($num in $numbersToFlip) {
                $digits = $num -replace '\+',''
                $oid = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value
                if ($oid) {
                    $manual = "  Remove-CsPhoneNumberAssignment -Identity '$oid' -PhoneNumber '$num' -PhoneNumberType DirectRouting"
                    Write-Host $manual -ForegroundColor Gray
                    Write-HtmlLine $manual 'Gray'
                }
            }
            $removeSkipped = $true
        }
    }

    if (-not $removeSkipped) {
        $rmTotal = $numbersToFlip.Count
        $rmIdx   = 0
        foreach ($num in $numbersToFlip) {
            $rmIdx++
            $digits   = $num -replace '\+',''
            $objectId = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value

            if (-not $objectId) {
                Write-Warn "[$rmIdx/$rmTotal] No ObjectId found for $num in ra-objectids.json -- skipping."
                continue
            }

            Write-Step "[$rmIdx/$rmTotal] Remove assignment: $num from RA $objectId ..."
            if ($DryRun) {
                Write-Info "  (DRY RUN) Remove-CsPhoneNumberAssignment -Identity '$objectId' -PhoneNumber '$num' -PhoneNumberType DirectRouting"
                continue
            }
            try {
                Remove-CsPhoneNumberAssignment -Identity $objectId -PhoneNumber $num -PhoneNumberType DirectRouting -ErrorAction Stop
                Write-OK "  [$num] Teams assignment removed."
            } catch {
                Write-Warn "  [$num] Remove-CsPhoneNumberAssignment failed: $($_.Exception.Message -replace '\r?\n.*','')"
                Write-Warn "  D365 sync may re-link RA for this number. Remove manually if needed."
            }
        }
    }
}

Write-Host ""
Write-OK "Step B complete."
Write-Host ""
Write-HtmlLine ""

# ---------------------------------------------------------------------------
# STEP C -- D365 phone type update: TPS -> ACS, clear RA (per number)
# ---------------------------------------------------------------------------
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  STEP C -- Update D365 Phone Type  (TPS -> ACS, clear RA)" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine "  STEP C -- Update D365 Phone Type  (TPS -> ACS, clear RA)" 'Cyan'
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine ""

$total  = $numbersToFlip.Count
$idx    = 0
$failed = @()

foreach ($num in $numbersToFlip) {
    $idx++
    Write-Step "[$idx/$total] $num  ->  TPS_TO_ACS ..."

    $migrateArgs = @{
        OrgUrl      = $d365OrgUrl
        PhoneNumber = $num
        Direction   = 'TPS_TO_ACS'
    }
    if ($DryRun) { $migrateArgs['DryRun'] = $true }

    & $migrateScript @migrateArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "  [$num] returned exit code $LASTEXITCODE. Continuing with remaining numbers."
        $failed += $num
    } else {
        Write-OK "  [$num] D365 type set to ACS, RA cleared, sync triggered."
    }
    Write-Host ""
    Write-HtmlLine ""
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$summaryColor = if ($failed.Count -eq 0) { 'Green' } else { 'Yellow' }
$sumLine = '+' + ('=' * 66) + '+'

Write-Host $sumLine -ForegroundColor $summaryColor
Write-Host "|  Flip To ACS Complete  v14.11.0                                      |" -ForegroundColor $summaryColor
Write-Host "|  Step A: Toggle        $(if ($DryRun) { 'DRY RUN' } else { 'Done -- ACS is live' })$((' ' * (26 - $(if ($DryRun) { 7 } else { 18 }))))|" -ForegroundColor $summaryColor
Write-Host "|  Step B: Unassign      $(if ($DryRun) { 'DRY RUN' } elseif ($removeSkipped) { 'Skipped (see warnings)   ' } else { 'Done -- Teams RA unlinked' })|" -ForegroundColor $summaryColor
Write-Host "|  Step C: D365 update   $($total - $failed.Count)/$total number(s) succeeded$((' ' * [Math]::Max(0, 20 - "$($total - $failed.Count)/$total number(s) succeeded".Length)))|" -ForegroundColor $summaryColor
Write-Host $sumLine -ForegroundColor $summaryColor

Write-HtmlLine ""
Write-HtmlLine $sumLine $summaryColor
Write-HtmlLine "|  Flip To ACS Complete  v14.11.0                                      |" $summaryColor
Write-HtmlLine "|  Step A: Toggle        $(if ($DryRun) { 'DRY RUN' } else { 'Done -- ACS is live' })$((' ' * (26 - $(if ($DryRun) { 7 } else { 18 }))))|" $summaryColor
Write-HtmlLine "|  Step B: Unassign      $(if ($DryRun) { 'DRY RUN' } elseif ($removeSkipped) { 'Skipped (see warnings)   ' } else { 'Done -- Teams RA unlinked' })|" $summaryColor
Write-HtmlLine "|  Step C: D365 update   $($total - $failed.Count)/$total number(s) succeeded$((' ' * [Math]::Max(0, 20 - "$($total - $failed.Count)/$total number(s) succeeded".Length)))|" $summaryColor
Write-HtmlLine $sumLine $summaryColor

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Warn "$($failed.Count) number(s) failed D365 update:"
    foreach ($f in $failed) {
        Write-Host "    $f" -ForegroundColor Yellow
        Write-HtmlLine "    $f" 'Yellow'
    }
    Write-Host ""
    Write-Host "  Re-run Step 2 only for failed numbers:" -ForegroundColor Gray
    Write-HtmlLine "" ; Write-HtmlLine "  Re-run Step 2 only for failed numbers:" 'Gray'
    foreach ($f in $failed) {
        $cmd = "    .\Invoke-MigrateTpsPhoneNumber-v14.ps1 -OrgUrl '$d365OrgUrl' -PhoneNumber '$f' -Direction TPS_TO_ACS"
        Write-Host $cmd -ForegroundColor Gray
        Write-HtmlLine $cmd 'Gray'
    }
} else {
    Write-Host ""
    Write-Host "  Post-rollback checklist:" -ForegroundColor Gray
    Write-Host "  [ ] D365 CSAC -> Channels -> Phone numbers: verify type = ACS" -ForegroundColor Gray
    Write-Host "  [ ] msdyn_teamsresourceaccount = (empty) on all flipped numbers" -ForegroundColor Gray
    Write-Host "  [ ] Test inbound call routing via ACS end-to-end" -ForegroundColor Gray
    Write-Host "  [ ] Allow 2-3 min for async CCaaS sync to reflect in D365 UI" -ForegroundColor Gray
    Write-HtmlLine ""
    Write-HtmlLine "  Post-rollback checklist:" 'Gray'
    Write-HtmlLine "  [ ] D365 CSAC -> Channels -> Phone numbers: verify type = ACS" 'Gray'
    Write-HtmlLine "  [ ] msdyn_teamsresourceaccount = (empty) on all flipped numbers" 'Gray'
    Write-HtmlLine "  [ ] Test inbound call routing via ACS end-to-end" 'Gray'
    Write-HtmlLine "  [ ] Allow 2-3 min for async CCaaS sync to reflect in D365 UI" 'Gray'
}

Write-Host ""
Write-Host "  HTML log saved: $script:HtmlLogPath" -ForegroundColor Cyan
Write-Host "  Open with: Start-Process $script:HtmlLogPath" -ForegroundColor DarkGray
Write-Host ""
Write-HtmlLine ""
Write-HtmlLine "  HTML log saved: $script:HtmlLogPath" 'Cyan'

# Build summary HTML footer
$failColor  = if ($failed.Count -gt 0) { '#ffd700' } else { '#4ec94e' }
$failListHtml = ''
if ($failed.Count -gt 0) {
    $failListHtml = '<ul style="margin:6px 0 0 16px;padding:0;color:#ffd700">' + (($failed | ForEach-Object { $e = $_ -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'; "<li>$e</li>" }) -join '') + '</ul>'
}
$escNums = ($numbersToFlip -join ', ') -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
$flipAcsFooter = @"
<div style="margin-top:20px;border-top:1px solid #333;padding-top:16px;font-family:Consolas,'Courier New',monospace;font-size:12px">
<div style="color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px">Flip To ACS Summary</div>
<table style="border-collapse:collapse">
<tr><td style="padding:4px 20px 4px 0;color:#888">Step A Toggle</td><td style="padding:4px 0;color:#4ec94e">$(if ($DryRun) { 'DRY RUN' } else { 'ACS active' })</td></tr>
<tr><td style="padding:4px 20px 4px 0;color:#888">Step B Unassign</td><td style="padding:4px 0;color:$(if ($removeSkipped) { '#ffd700' } else { '#4ec94e' })">$(if ($DryRun) { 'DRY RUN' } elseif ($removeSkipped) { 'Skipped' } else { 'Done' })</td></tr>
<tr><td style="padding:4px 20px 4px 0;color:#888">Step C D365</td><td style="padding:4px 0;color:$failColor">$($total - $failed.Count)/$total succeeded</td></tr>
</table>
$failListHtml
<div style="margin-top:10px;color:#888">Numbers: <span style="color:#d4d4d4">$escNums</span> &nbsp;|&nbsp; <a href="tpe-status.html" style="color:#00bfff">Open Dashboard</a></div>
</div>
"@

$result = if ($failed.Count -gt 0) { 'WARN' } else { 'OK' }
Write-TpeRunRecord -Type 'flip-acs' -PhoneNums @($numbersToFlip) -Result $result -Failures $failed.Count
Update-TpeStatusDashboard
Write-Host "  Open with: Start-Process .\tpe-status.html" -ForegroundColor DarkGray

$exitCode = if ($failed.Count -gt 0) { 1 } else { 0 }
Exit-Script $exitCode -FooterHtml $flipAcsFooter
