#Requires -Version 5.1
<#
.SYNOPSIS
    Flips routing from ACS Direct Routing to Teams Phone System. v14

.DESCRIPTION
    Three-step cutover:

      Step A -- Assign Teams phone numbers  (per RA)
        Calls Set-CsPhoneNumberAssignment for each number, linking it to its
        Teams Resource Account ObjectId (from ra-objectids.json).

      Step B -- Toggle routing  (ACS -> Teams)
        Calls Toggle-AcsTeamsRouting-v14.ps1 with the config path.
        Toggle auto-detects that ACS is active and flips:
          - ACS trunk:     Enabled=$false
          - Teams gateway: Enabled=$true

      Step C -- Update D365 phone type  (ACS -> TPS, per number)
        Calls Invoke-MigrateTpsPhoneNumber-v14.ps1 for each number with
        Direction=ACS_TO_TPS, which:
          - Sets msdyn_phonenumbertype = 1 (Teams)
          - Sets msdyn_ocphonenumbersource = 192350001 (Teams DR)
          - Sets msdyn_teamsresourceaccount = <ObjectId> (explicit, no sync needed)
          - Calls CCaaS_SynchronizePhoneNumbers (async, confirms Teams side)

    Phone numbers are discovered from ra-objectids.json (written by migration
    Step 7). Use -PhoneNumbers to override with a specific list.

.PARAMETER ConfigPath
    Path to the ACS-TPE config JSON, e.g. .\new-acs-tpe-config-v14.11.0.json
    Must contain: AcsConnectionString, SbcFqdn, TenantId, AdminUpn, D365OrgUrl.

.PARAMETER PhoneNumbers
    Optional. One or more phone numbers to flip (e.g. +12069990060,+14255550100).
    If omitted, reads ra-objectids.json to find numbers from this migration run.

.PARAMETER DryRun
    Show the plan without making any changes.

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
    v14.4.0: Write-Err function added (parity with FlipToACS), -Failed→-Failures
             param fix, dashboard version parity, version strings bumped to v14.4.0.
    v14.3.0: Dashboard parity with Toggle/Migration — $esc XSS escaping, toggle-to-tpe/
             toggle-to-acs type recognition, Steps column, Migrate/Undo card labels,
             run-record startStep/stopStep/completed/skipped fields, version strings bumped.
    v14.0.0
    v14.0.3: HTML run log added (mirrors Undo/Migration pattern), stats/tpe-runs.jsonl record,
             tpe-status.html dashboard update.

.EXAMPLE
    # Dry run -- see what would flip, no changes
    .\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\new-acs-tpe-config-v14.11.0.json -DryRun

.EXAMPLE
    # Flip numbers from this migration run (reads ra-objectids.json -- default)
    .\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\new-acs-tpe-config-v14.11.0.json

.EXAMPLE
    # Flip specific numbers only
    .\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\new-acs-tpe-config-v14.11.0.json -PhoneNumbers "+12069990070"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter()]
    [string[]]$PhoneNumbers,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# HTML LOG SETUP
# ---------------------------------------------------------------------------

$script:HtmlLogPath = ".\tpe-flip-teams-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ACS TPE Flip To Teams v14.11.0 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
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
Write-Host $line -ForegroundColor Cyan
Write-Host "|                                                                  |" -ForegroundColor Cyan
Write-Host "|   Flip To Teams  v14.11.0  --  ACS -> Teams Cutover                 |" -ForegroundColor Cyan
if ($DryRun) {
Write-Host "|   *** DRY RUN -- no changes will be made ***                    |" -ForegroundColor Cyan
}
Write-Host "|                                                                  |" -ForegroundColor Cyan
Write-Host $line -ForegroundColor Cyan
Write-Host ""

Write-HtmlLine ""
Write-HtmlLine $line 'Cyan'
Write-HtmlLine "|                                                                  |" 'Cyan'
Write-HtmlLine "|   Flip To Teams  v14.11.0  --  ACS -> Teams Cutover                 |" 'Cyan'
if ($DryRun) { Write-HtmlLine "|   *** DRY RUN -- no changes will be made ***                    |" 'Cyan' }
Write-HtmlLine "|                                                                  |" 'Cyan'
Write-HtmlLine $line 'Cyan'
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
    Write-Err "D365OrgUrl is missing from config."
    Exit-Script 1
}
$d365OrgUrl = $d365OrgUrl.TrimEnd('/')
$script:d365OrgUrlForRecord = $d365OrgUrl
Write-OK "Config loaded. D365OrgUrl: $d365OrgUrl"

# ---------------------------------------------------------------------------
# Resolve script paths
# ---------------------------------------------------------------------------
$scriptDir     = $PSScriptRoot
$toggleScript  = Join-Path $scriptDir "Toggle-AcsTeamsRouting-v14.ps1"
$migrateScript = Join-Path $scriptDir "Invoke-MigrateTpsPhoneNumber-v14.ps1"

foreach ($s in $toggleScript, $migrateScript) {
    if (-not (Test-Path $s)) {
        Write-Err "Required script not found: $s"
        Exit-Script 1
    }
}

# ---------------------------------------------------------------------------
# Load ra-objectids.json
# ---------------------------------------------------------------------------
$configDir  = Split-Path $ConfigPath -Parent
$raOidsPath = Join-Path $configDir "ra-objectids.json"

if (-not (Test-Path $raOidsPath)) {
    Write-Err "ra-objectids.json not found at: $raOidsPath"
    Write-Info "This file is written by the migration script (Step 7)."
    Write-Info "Use -PhoneNumbers to supply numbers explicitly."
    Exit-Script 1
}

Write-Step "Reading ra-objectids.json ..."
$raOidsRaw   = Get-Content $raOidsPath -Raw | ConvertFrom-Json
$raObjectIds = @{}
$raOidsRaw.PSObject.Properties | ForEach-Object { $raObjectIds[$_.Name] = $_.Value }
Write-OK "Loaded $($raObjectIds.Count) RA ObjectId(s)."

# ---------------------------------------------------------------------------
# Resolve phone numbers
# ---------------------------------------------------------------------------
if ($PhoneNumbers -and $PhoneNumbers.Count -gt 0) {
    $numbersToFlip = $PhoneNumbers
    Write-Info "Using $($numbersToFlip.Count) phone number(s) from -PhoneNumbers parameter."
} else {
    $raPrefix     = if ($cfg.PSObject.Properties['RaPrefix'] -and $cfg.RaPrefix) { $cfg.RaPrefix } else { '' }
    $prefixBefore = if ($raPrefix -match '<phonenumber>') { ($raPrefix -split '<phonenumber>')[0] } else { '' }

    $numbersToFlip = foreach ($upn in $raObjectIds.Keys) {
        $localPart = ($upn -split '@')[0]
        if ($prefixBefore -and $localPart.StartsWith($prefixBefore)) {
            $digits = $localPart.Substring($prefixBefore.Length)
            "+$digits"
        } else {
            if ($localPart -match '(\d{7,15})$') { "+$($Matches[1])" }
        }
    }
    $numbersToFlip = @($numbersToFlip | Where-Object { $_ })

    if ($numbersToFlip.Count -eq 0) {
        Write-Err "Could not parse any phone numbers from ra-objectids.json. Use -PhoneNumbers."
        Exit-Script 1
    }
    Write-OK "Found $($numbersToFlip.Count) number(s) from ra-objectids.json:"
    $i = 0
    foreach ($num in $numbersToFlip) {
        $i++
        $digits = $num -replace '\+',''
        $oid = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value
        $line2 = ("    {0,2}  {1,-22}  ObjectId: {2}" -f $i, $num, $(if ($oid) { $oid } else { '(not found)' }))
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
Write-Host "  Step A -- Set-CsPhoneNumberAssignment x $($numbersToFlip.Count) number(s)  (assign to Teams RA)" -ForegroundColor Gray
Write-Host "  Step B -- Toggle-AcsTeamsRouting-v14.ps1 (ACS -> Teams cutover)" -ForegroundColor Gray
Write-Host "  Step C -- Invoke-MigrateTpsPhoneNumber-v14.ps1 x $($numbersToFlip.Count) (D365 type ACS->TPS + RA link)" -ForegroundColor Gray
foreach ($num in $numbersToFlip) {
    $digits = $num -replace '\+',''
    $oid = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value
    Write-Host "           $num  ->  ACS_TO_TPS  ObjectId: $(if ($oid) { $oid } else { '(not found -- check ra-objectids.json)' })" -ForegroundColor Gray
}
Write-Host ""

Write-HtmlLine ""
Write-HtmlLine "  PLAN:" 'Gray'
Write-HtmlLine "  Step A -- Set-CsPhoneNumberAssignment x $($numbersToFlip.Count) number(s)  (assign to Teams RA)" 'Gray'
Write-HtmlLine "  Step B -- Toggle-AcsTeamsRouting-v14.ps1 (ACS -> Teams cutover)" 'Gray'
Write-HtmlLine "  Step C -- Invoke-MigrateTpsPhoneNumber-v14.ps1 x $($numbersToFlip.Count) (D365 type ACS->TPS + RA link)" 'Gray'
foreach ($num in $numbersToFlip) {
    $digits = $num -replace '\+',''
    $oid = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value
    Write-HtmlLine "           $num  ->  ACS_TO_TPS  ObjectId: $(if ($oid) { $oid } else { '(not found -- check ra-objectids.json)' })" 'Gray'
}
Write-HtmlLine ""

if ($DryRun) {
    Write-Host "  [DRY RUN] No changes will be made." -ForegroundColor Cyan
    Write-Host "  Run without -DryRun to execute." -ForegroundColor Cyan
    Write-Host ""
    Write-HtmlLine "  [DRY RUN] No changes will be made." 'Cyan'
    Write-HtmlLine "  Run without -DryRun to execute." 'Cyan'
    Write-HtmlLine ""
}

# Confirmation
if (-not $DryRun) {
    Write-Host "  This will assign numbers to Teams RAs, flip routing to Teams, and update D365 for $($numbersToFlip.Count) number(s)." -ForegroundColor Yellow
    Write-HtmlLine "  This will assign numbers to Teams RAs, flip routing to Teams, and update D365 for $($numbersToFlip.Count) number(s)." 'Yellow'
    $confirm = Read-Host "  Proceed? Flip from ACS to Teams [Y/n]"
    if ($confirm -and $confirm.Trim().ToUpper() -ne 'Y') {
        Write-Host "  Aborted." -ForegroundColor Yellow
        Write-HtmlLine "  Aborted." 'Yellow'
        Write-TpeRunRecord -Type 'flip-teams' -PhoneNums @($numbersToFlip) -Result 'FAIL' -Failures 0
        Exit-Script 0
    }
    Write-Host ""
    Write-HtmlLine ""
}

# ---------------------------------------------------------------------------
# STEP A -- Set-CsPhoneNumberAssignment (assign number to Teams RA)
# ---------------------------------------------------------------------------
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  STEP A -- Assign Teams Phone Numbers to Resource Accounts" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine "  STEP A -- Assign Teams Phone Numbers to Resource Accounts" 'Cyan'
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine ""

if (-not $DryRun) {
    Write-Step "Connecting to Microsoft Teams ..."
    try {
        Connect-MicrosoftTeams -TenantId $cfg.TenantId | Out-Null
        Write-OK "Teams connected."
    } catch {
        Write-Err "Could not connect to Teams: $($_.Exception.Message -replace '\r?\n.*','')"
        Write-Err "Aborting -- cannot assign numbers without Teams PS connection."
        Write-TpeRunRecord -Type 'flip-teams' -PhoneNums @($numbersToFlip) -Result 'FAIL' -Failures $numbersToFlip.Count
        Exit-Script 1
    }
}

$assignTotal  = $numbersToFlip.Count
$assignIdx    = 0
$assignFailed = @()

foreach ($num in $numbersToFlip) {
    $assignIdx++
    $digits   = $num -replace '\+',''
    $objectId = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value

    if (-not $objectId) {
        Write-Warn "[$assignIdx/$assignTotal] No ObjectId for $num in ra-objectids.json -- skipping."
        $assignFailed += $num
        continue
    }

    Write-Step "[$assignIdx/$assignTotal] Set-CsPhoneNumberAssignment: $num -> RA $objectId ..."
    if ($DryRun) {
        Write-Info "  (DRY RUN) Set-CsPhoneNumberAssignment -Identity '$objectId' -PhoneNumber '$num' -PhoneNumberType DirectRouting"
        continue
    }
    try {
        Set-CsPhoneNumberAssignment -Identity $objectId -PhoneNumber $num -PhoneNumberType DirectRouting -ErrorAction Stop
        Write-OK "  [$num] Assigned to Teams RA $objectId."
    } catch {
        Write-Warn "  [$num] Set-CsPhoneNumberAssignment failed: $($_.Exception.Message -replace '\r?\n.*','')"
        $assignFailed += $num
    }
}

if ($assignFailed.Count -gt 0) {
    Write-Host ""
    Write-HtmlLine ""
    Write-Warn "$($assignFailed.Count) number(s) failed Teams assignment. Aborting -- do not proceed with Toggle until assignments are fixed."
    foreach ($f in $assignFailed) {
        Write-Host "    $f" -ForegroundColor Yellow
        Write-HtmlLine "    $f" 'Yellow'
    }
    Write-TpeRunRecord -Type 'flip-teams' -PhoneNums @($numbersToFlip) -Result 'FAIL' -Failures $assignFailed.Count
    Exit-Script 1
}

Write-Host ""
Write-OK "Step A complete -- all numbers assigned to Teams RAs."
Write-Host ""
Write-HtmlLine ""

# ---------------------------------------------------------------------------
# STEP B -- Toggle ACS -> Teams
# ---------------------------------------------------------------------------
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  STEP B -- Toggle Routing  (ACS -> Teams)" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine "  STEP B -- Toggle Routing  (ACS -> Teams)" 'Cyan'
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine ""

$toggleArgs = @{ ConfigPath = $ConfigPath }
if ($DryRun) { $toggleArgs['DryRun'] = $true }

& $toggleScript @toggleArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-HtmlLine ""
    Write-Err "Toggle script failed (exit $LASTEXITCODE). D365 update NOT run."
    Write-Err "Numbers are assigned to Teams RAs but routing has NOT switched."
    Write-Err "Fix the toggle issue and re-run with -StartAtStep 2 equivalent (skip Step 1)."
    Write-TpeRunRecord -Type 'flip-teams' -PhoneNums @($numbersToFlip) -Result 'FAIL' -Failures $numbersToFlip.Count
    Exit-Script 1
}

Write-Host ""
Write-OK "Step B complete -- Teams is now active."
Write-Host ""
Write-HtmlLine ""

# ---------------------------------------------------------------------------
# STEP C -- D365 phone type update: ACS -> TPS, link RA (per number)
# ---------------------------------------------------------------------------
Write-Host $divider -ForegroundColor DarkGray
Write-Host "  STEP C -- Update D365 Phone Type  (ACS -> TPS, link RA)" -ForegroundColor Cyan
Write-Host $divider -ForegroundColor DarkGray
Write-Host ""
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine "  STEP C -- Update D365 Phone Type  (ACS -> TPS, link RA)" 'Cyan'
Write-HtmlLine $divider 'DarkGray'
Write-HtmlLine ""

$total  = $numbersToFlip.Count
$idx    = 0
$failed = @()

foreach ($num in $numbersToFlip) {
    $idx++
    $digits   = $num -replace '\+',''
    $objectId = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value

    Write-Step "[$idx/$total] $num  ->  ACS_TO_TPS ..."

    $migrateArgs = @{
        OrgUrl      = $d365OrgUrl
        PhoneNumber = $num
        Direction   = 'ACS_TO_TPS'
    }
    if ($objectId)  { $migrateArgs['TeamsResourceAccountObjectId'] = $objectId }
    if ($DryRun)    { $migrateArgs['DryRun'] = $true }

    & $migrateScript @migrateArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "  [$num] Invoke-MigrateTpsPhoneNumber returned exit code $LASTEXITCODE. Continuing."
        $failed += $num
    } else {
        Write-OK "  [$num] D365 type set to Teams, RA linked$(if ($objectId) { " ($objectId)" } else { '' })."
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
Write-Host "|  Flip To Teams Complete  v14.11.0                                    |" -ForegroundColor $summaryColor
Write-Host "|  Step A: Assign        $(if ($DryRun) { 'DRY RUN' } else { 'Done -- Teams RAs assigned' })$((' ' * (26 - $(if ($DryRun) { 7 } else { 26 }))))|" -ForegroundColor $summaryColor
Write-Host "|  Step B: Toggle        $(if ($DryRun) { 'DRY RUN' } else { 'Done -- Teams is live     ' })|" -ForegroundColor $summaryColor
Write-Host "|  Step C: D365 update   $($total - $failed.Count)/$total number(s) succeeded$((' ' * [Math]::Max(0, 20 - "$($total - $failed.Count)/$total number(s) succeeded".Length)))|" -ForegroundColor $summaryColor
Write-Host $sumLine -ForegroundColor $summaryColor

Write-HtmlLine ""
Write-HtmlLine $sumLine $summaryColor
Write-HtmlLine "|  Flip To Teams Complete  v14.11.0                                    |" $summaryColor
Write-HtmlLine "|  Step A: Assign        $(if ($DryRun) { 'DRY RUN' } else { 'Done -- Teams RAs assigned' })$((' ' * (26 - $(if ($DryRun) { 7 } else { 26 }))))|" $summaryColor
Write-HtmlLine "|  Step B: Toggle        $(if ($DryRun) { 'DRY RUN' } else { 'Done -- Teams is live     ' })|" $summaryColor
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
    Write-Host "  Re-run D365 update only for failed numbers:" -ForegroundColor Gray
    Write-HtmlLine "" ; Write-HtmlLine "  Re-run D365 update only for failed numbers:" 'Gray'
    foreach ($f in $failed) {
        $digits = $f -replace '\+',''
        $oid = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value
        $oidArg = if ($oid) { " -TeamsResourceAccountObjectId '$oid'" } else { "" }
        $cmd = "    .\Invoke-MigrateTpsPhoneNumber-v14.ps1 -OrgUrl '$d365OrgUrl' -PhoneNumber '$f' -Direction ACS_TO_TPS$oidArg"
        Write-Host $cmd -ForegroundColor Gray
        Write-HtmlLine $cmd 'Gray'
    }
} else {
    Write-Host ""
    Write-Host "  Post-cutover checklist:" -ForegroundColor Gray
    Write-Host "  [ ] D365 CSAC -> Channels -> Phone numbers: verify type = Teams Phone System" -ForegroundColor Gray
    Write-Host "  [ ] msdyn_teamsresourceaccount is set on all flipped numbers" -ForegroundColor Gray
    Write-Host "  [ ] Test inbound call routing via Teams end-to-end" -ForegroundColor Gray
    Write-Host "  [ ] Allow 2-3 min for async CCaaS sync to reflect in D365 UI" -ForegroundColor Gray
    Write-HtmlLine ""
    Write-HtmlLine "  Post-cutover checklist:" 'Gray'
    Write-HtmlLine "  [ ] D365 CSAC -> Channels -> Phone numbers: verify type = Teams Phone System" 'Gray'
    Write-HtmlLine "  [ ] msdyn_teamsresourceaccount is set on all flipped numbers" 'Gray'
    Write-HtmlLine "  [ ] Test inbound call routing via Teams end-to-end" 'Gray'
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
$flipTeamsFooter = @"
<div style="margin-top:20px;border-top:1px solid #333;padding-top:16px;font-family:Consolas,'Courier New',monospace;font-size:12px">
<div style="color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px">Flip To Teams Summary</div>
<table style="border-collapse:collapse">
<tr><td style="padding:4px 20px 4px 0;color:#888">Step A Assign</td><td style="padding:4px 0;color:#4ec94e">$(if ($DryRun) { 'DRY RUN' } else { 'Teams RAs assigned' })</td></tr>
<tr><td style="padding:4px 20px 4px 0;color:#888">Step B Toggle</td><td style="padding:4px 0;color:#4ec94e">$(if ($DryRun) { 'DRY RUN' } else { 'Teams active' })</td></tr>
<tr><td style="padding:4px 20px 4px 0;color:#888">Step C D365</td><td style="padding:4px 0;color:$failColor">$($total - $failed.Count)/$total succeeded</td></tr>
</table>
$failListHtml
<div style="margin-top:10px;color:#888">Numbers: <span style="color:#d4d4d4">$escNums</span> &nbsp;|&nbsp; <a href="tpe-status.html" style="color:#00bfff">Open Dashboard</a></div>
</div>
"@

$result = if ($failed.Count -gt 0) { 'WARN' } else { 'OK' }
Write-TpeRunRecord -Type 'flip-teams' -PhoneNums @($numbersToFlip) -Result $result -Failures $failed.Count
Update-TpeStatusDashboard
Write-Host "  Open with: Start-Process .\tpe-status.html" -ForegroundColor DarkGray

$exitCode = if ($failed.Count -gt 0) { 1 } else { 0 }
Exit-Script $exitCode -FooterHtml $flipTeamsFooter
