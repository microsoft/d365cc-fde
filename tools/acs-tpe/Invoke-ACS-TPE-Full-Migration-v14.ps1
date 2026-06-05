#Requires -Version 5.1
<#
.SYNOPSIS
    Full interactive ACS -> Teams Phone Extensibility (TPE) migration script. v14

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.16.0  : Step 8 license polling loop guards against empty ObjectId (crash when
                Step 7 RA creation fails due to authorization error), version bump.
    v14.15.0  : Step 5 validates only cfg.SbcFqdn and cfg.RouteName instead of all
                ACS export trunks/routes, version bump.
    v14.15.0  : Step 3 creates a single voice route from config (RouteName/SbcFqdn/
                selected numbers) instead of replicating all ACS export routes, version bump.
    v14.15.0  : Step 2 filters acsTrunks to SbcFqdn only -- prevents unrelated ACS
                trunks from being registered as Teams DR gateways, version bump.
    v14.15.0  : D365 discovery selection flipped from exclude to include model;
                IncludeNumbers config field auto-filters without interactive prompt,
                version bump.
    v14.15.0  : Connection string parsing validates endpoint/accesskey presence,
                error message null guard (Split→-split), HTML footer phone numbers
                XSS-escaped, version bump.
    v14.10.0  : Step 4 domain registration now guarded by -DryRun (was executing
                New-MgDomain even in DryRun mode), version bump.
    v14.9.0   : Fix-AcsRoutePattern and Update-PhoneNumberType console banner
                version strings corrected (were v14.6.0), migration HTML title
                version added, README sections added for 5 missing scripts,
                version strings bumped to v14.9.0.
    v14.8.0   : Version string parity across ALL 18 scripts (9 utility scripts
                were still at v14.6.0), Update-PhoneNumberType provider array bounds
                check before [0] access, Undo summary box alignment fix,
                Sync-TeamsPhoneNumbers/Get-TeamsProviderSetting version banners added,
                version strings bumped to v14.8.0.
    v14.7.0   : Dashboard state skips FAIL results when determining active system
                (prevents misleading state after failed operation), Test-DomainRegistration
                DryRun no longer sets $verified=$true (shows accurate DryRun behavior),
                version strings bumped to v14.7.0.
    v14.6.0   : Update-PhoneNumberType msdyn_ocphonenumbersource parity + DryRun + sync,
                Fix-AcsRoutePattern parameterized (no hardcoded FQDN/pattern) + DryRun,
                Add-AcsTrunkDisabled DryRun switch, Set-AcsSbcFqdn blank FQDN validation,
                Archive-TpeRuns Sort-Object dedup fix, Invoke-TeamsPhoneSync GUID validation,
                version strings bumped to v14.6.0.
    v14.5.0   : Toggle $acsActive null-as-active fix (-ne $false → -eq $true),
                Undo HTML failure-list XSS escaping, E.164 validation added to
                Update-PhoneNumberType / Invoke-MigrateTpsPhoneNumber / Repair-D365PhoneRecord,
                HTTP 204 handling in Sync-TeamsPhoneNumbers / Invoke-TeamsPhoneSync,
                Update-PhoneNumberType PATCH wrapped in try-catch, port validation in
                New-AcsTpeConfig / Add-AcsTrunkDisabled, ConfigPath param added to
                Fix-AcsRoutePattern, Get-TeamsProviderSetting try-catch on API call,
                version strings bumped to v14.5.0.
    v14.4.0   : Step 9 DryRun guard for D365 post-sync verification,
                migrate-partial run type for partial runs (Steps < 10),
                console banner version parity (v14→v14.4.0), version
                strings bumped to v14.4.0.
    v14.3.0   : Dashboard sub-header version parity (v14.1.0 → v14.3.0),
                Step 1 skip guard (acs-export.json missing → clear error),
                Step 9 DryRun guard on Export-Csv, version strings bumped.
    v14.2.0   : Toggle observability parity (HTML log, run record, dashboard),
                -AutoConfirm passed to Toggle in Step 10 (no double prompt),
                Test-E164Format validation in Phase 0D (warns on non-E.164),
                toggle-to-tpe/toggle-to-acs run types added to dashboard.
    v14.1.0   : Final consistency pass — Undo .NOTES version corrected
                (Version 9 → Version 14), dashboard sub-headers bumped to
                v14.1.0, HTML footer COMPLETE string bumped, README aligned.
    v14.0.8   : Dashboard $esc null guard for null phoneNumbers (strict-mode
                safe), DryRun guard on D365 backup token acquisition (Step 9
                no longer queries D365 in DryRun), version strings bumped to
                v14.0.8.
    v14.0.7   : Write-TpeRunRecord D365OrgUrl PSObject.Properties guard (prevents
                silent run-record loss in StrictMode), dashboard HTML-escape for
                phone numbers / URLs / log paths (XSS hardening), Phase 0
                interactive CommsProviderId prompt (prompt 16), version strings
                bumped to v14.0.7.
    v14.0.6   : Step 2 connection string null guard (TrimEnd on null endpoint),
                version strings bumped to v14.0.6.
    v14.0.5   : Dashboard stateLabel handles flip-teams/flip-acs types, dashboard
                row HTML handles all 4 run types, step11Failed initialized at script
                scope, version strings bumped to v14.0.5.
    v14.0.3   : #Requires -Version 5.1 added, DryRun guards on acs-export.json /
                ra-objectids.json / d365-phone-backup.json writes, dashboard version
                strings updated to v14.0.3, stale .NOTES "Version 12" corrected.
    v14 fixes : Version strings corrected to v14, Build-RaList dynamic padding
                for >99 numbers, HMAC objects disposed, Write-TpeRunRecord reports
                actual result (OK/WARN/FAIL), connection-string null guards,
                SHA256/HMAC Dispose() calls added, DryRun file-write guard for
                acs-trunk-disabled.json, cfg null guard for resume mode,
                banner/plan-step labels updated v12->v14.
    v10 change  : Removed Step 11 (ACS teamsExtension consent) — no longer required.
    v8 fixes  : HTML log footer on every exit, step-range validation, UsageLocation
                validated as 2-letter alpha, SBC port validated numeric, raObjectIds
                always plain string, Step 6 timeout warns instead of exit, acs-trunk-disabled.json
                written incrementally.
    v7 change : Step 2 uses a minimal-downtime pattern:
                  1. Temporarily disable ACS trunk (needed to register FQDN in Teams)
                  2. Create Teams DR gateway with same FQDN (disabled initially)
                  3. Immediately re-enable ACS trunk --> ACS resumes live calls
                ACS handles all production calls throughout Steps 3-10.
                Only at Step 10 does the user choose to Toggle to Teams.

.DESCRIPTION
    Phase 0:   Install and connect PS modules (MicrosoftTeams, Microsoft.Graph)
    Phase 0D:  Query D365 for active Direct Routing phone numbers -> auto-build RAs
    Step  1:   Export ACS SIP trunks + voice routes via REST API
    Step  2:   Temporarily disable ACS trunk -> create Teams DR gateway (disabled) ->
               re-enable ACS trunk.  Net result: zero call disruption.
    Step  3:   Configure PSTN usages, voice routes, and voice routing policy
    Step  4:   Register and verify custom domain in Microsoft Entra ID
    Step  5:   Validate SBC gateway exists, routes, and policies
    Step  6:   Upload discovered DR phone numbers into the Teams tenant
    Step  7:   Create resource accounts (RAs) as TPE application instances
    Step  8:   Assign Teams Phone Resource Account licenses to RAs
    Step  9:   Assign DR phone numbers to RAs
    Step 10:   Cutover -- runs Toggle-AcsTeamsRouting-v14.ps1 (ACS off, Teams on)
    Step 11:   D365 phone type update + sync via Invoke-MigrateTpsPhoneNumber-v14.ps1

.NOTES
    Generated by AI (Claude Sonnet 4.6) with human oversight.
    Review all steps carefully before running in production.
    Version 14: All version strings corrected, Build-RaList dynamic padding,
    HMAC/SHA256 disposed, run-record reports actual result. See changelog in README.md.

.PARAMETER DryRun
    Show planned actions without making any changes.

.PARAMETER ConfigPath
    Path to a previously saved config JSON (skips interactive prompts).

.PARAMETER StartAtStep
    Resume from a specific step (0-11) after a failed run.

.PARAMETER StopAfterStep
    Stop after this step completes.

.PARAMETER OutputPath
    CSV file path for migration results. Default: .\tpe-migration-results.csv

.PARAMETER UsageLocation
    Two-letter country code for usage location when assigning licenses. Default: US

.EXAMPLE
    .\Invoke-ACS-TPE-Full-Migration-v14.ps1 -DryRun
    .\Invoke-ACS-TPE-Full-Migration-v14.ps1
    .\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -DryRun
    .\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -StartAtStep 5
    .\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -StartAtStep 4 -StopAfterStep 4
    .\Invoke-ACS-TPE-Full-Migration-v14.ps1 -UsageLocation GB
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun,
    [string]$ConfigPath   = '',
    [ValidateRange(0, 11)]
    [int]$StartAtStep     = 0,
    [ValidateRange(0, 11)]
    [int]$StopAfterStep   = 11,
    [string]$OutputPath   = '.\tpe-migration-results.csv',
    [ValidatePattern('^[A-Za-z]{2}$')]
    [string]$UsageLocation = 'US'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Step-range validation (v12)
# ---------------------------------------------------------------------------

if ($StartAtStep -gt $StopAfterStep) {
    Write-Host "  ! -StartAtStep ($StartAtStep) cannot be greater than -StopAfterStep ($StopAfterStep)." -ForegroundColor Red
    Write-Host "  For Invoke, steps run low-to-high (e.g. -StartAtStep 2 -StopAfterStep 9)." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# HTML LOG SETUP
# ---------------------------------------------------------------------------

$script:HtmlLogPath = ".\tpe-migration-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ACS TPE Migration v14.15.0 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
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
# Exit-Script helper (v12) -- ensures HTML log footer is always written
# ---------------------------------------------------------------------------

function Exit-Script {
    param([int]$Code = 0, [string]$FooterHtml = '')
    try { Add-Content -Path $script:HtmlLogPath -Value "</pre>$FooterHtml</body></html>" -Encoding UTF8 } catch {}
    exit $Code
}

# ---------------------------------------------------------------------------
# Run record + status dashboard (v14.0.3)
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
            startStep    = $StartAtStep
            stopStep     = $StopAfterStep
            dryRun       = [bool]$DryRun
            phoneNumbers = @($PhoneNums | Where-Object { $_ })
            result       = $Result
            completed    = $Completed
            skipped      = $Skipped
            failures     = $Failures
            d365OrgUrl   = if ($cfg -and $cfg.PSObject.Properties['D365OrgUrl'] -and $cfg.D365OrgUrl) { $cfg.D365OrgUrl } else { '' }
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
        $html = "<!DOCTYPE html><html><head><meta charset=`"UTF-8`"><meta http-equiv=`"refresh`" content=`"60`"><title>ACS TPE Migration Status</title><style>*{box-sizing:border-box}body{background:#1e1e1e;color:#d4d4d4;font-family:Consolas,'Courier New',monospace;font-size:13px;padding:24px;margin:0}h1{color:#00bfff;font-size:16px;margin:0 0 2px 0}.sub{color:#555;font-size:11px;margin:0 0 20px 0}.state{border-left:4px solid $stateColor;background:#252526;padding:14px 18px;margin:16px 0;border-radius:0 4px 4px 0}.state .lbl{font-size:14px;font-weight:bold;color:$stateColor;margin-bottom:4px}.state .meta{color:#888;font-size:12px}.cards{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}.card{background:#252526;border:1px solid #333;border-radius:4px;padding:12px 16px;min-width:130px;text-align:center}.card .n{font-size:22px;font-weight:bold;margin-bottom:2px}.card .l{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:1px}table{width:100%;border-collapse:collapse}th{background:#252526;color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;padding:7px 10px;text-align:left;border-bottom:1px solid #333}td{padding:6px 10px;border-bottom:1px solid #222;font-size:12px}tr:hover td{background:#252526}a{color:#00bfff;text-decoration:none}a:hover{text-decoration:underline}.sh{color:#555;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin:20px 0 6px 0;border-bottom:1px solid #2a2a2a;padding-bottom:5px}.foot{margin-top:24px;color:#333;font-size:11px}</style></head><body><h1>ACS TPE Migration Status</h1><div class=`"sub`">v14.15.0 &nbsp;|&nbsp; $d365Url &nbsp;|&nbsp; Auto-refresh: 60s</div><div class=`"state`"><div class=`"lbl`">$stateLabel</div><div class=`"meta`">Last action: $lastTime &nbsp;|&nbsp; Numbers: $lastNums</div></div><div class=`"cards`"><div class=`"card`"><div class=`"n`" style=`"color:#d4d4d4`">$total</div><div class=`"l`">Total Runs</div></div><div class=`"card`"><div class=`"n`" style=`"color:#00bfff`">$migCount</div><div class=`"l`">Migrate</div></div><div class=`"card`"><div class=`"n`" style=`"color:#ff6b6b`">$undoCount</div><div class=`"l`">Undo</div></div></div><div class=`"sh`">Run History (last 30)</div><table><tr><th>Timestamp</th><th>Type</th><th>Steps</th><th>Numbers</th><th>Result</th><th>Log</th></tr>$rows</table><div class=`"foot`">Generated $generated &nbsp;|&nbsp; ACS TPE v14.15.0 &nbsp;|&nbsp; stats/tpe-runs.jsonl</div></body></html>"
        Set-Content -Path $dashPath -Value $html -Encoding UTF8
        Write-Host "  Status dashboard: $dashPath" -ForegroundColor DarkGray
    } catch {}
}

#region -----------------------------------------------------------------------
#  HELPERS
# ------------------------------------------------------------------------------

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
    try {
        Add-Content -Path $script:HtmlLogPath -Value "<span class=`"$css`">$escaped</span>" -Encoding UTF8
    } catch {
        # HTML log write errors must never crash the migration -- silently ignore
    }
}

function Write-Banner {
    param([string]$Title, [string]$Sub = '', [string]$Color = 'Cyan')
    $line = '-' * 66
    Write-Host "`n$line" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor $Color
    if ($Sub) { Write-Host "  $Sub" -ForegroundColor DarkGray }
    Write-Host "$line" -ForegroundColor DarkGray
    Write-HtmlLine ""
    Write-HtmlLine $line 'DarkGray'
    Write-HtmlLine "  $Title" $Color
    if ($Sub) { Write-HtmlLine "  $Sub" 'DarkGray' }
    Write-HtmlLine $line 'DarkGray'
}

function Write-Step {
    param([string]$m, [string]$c = 'Cyan')
    Write-Host "  >> $m" -ForegroundColor $c
    Write-HtmlLine "  >> $m" $c
}
function Write-OK {
    param([string]$m)
    Write-Host "  OK $m" -ForegroundColor Green
    Write-HtmlLine "  OK $m" 'Green'
}
function Write-Warn {
    param([string]$m)
    Write-Host "  WARN $m" -ForegroundColor Yellow
    Write-HtmlLine "  WARN $m" 'Yellow'
}
function Write-Err {
    param([string]$m)
    Write-Host "  ! $m" -ForegroundColor Red
    Write-HtmlLine "  ! $m" 'Red'
}
function Write-Info {
    param([string]$m)
    Write-Host "  -- $m" -ForegroundColor Gray
    Write-HtmlLine "  -- $m" 'Gray'
}

function Prompt-Required {
    param([string]$Label, [string]$Hint = '', [switch]$IsGuid, [switch]$IsSecret)
    while ($true) {
        if ($Hint) { Write-Host "    [$Hint]" -ForegroundColor DarkGray }
        if ($IsSecret) {
            $ss  = Read-Host -AsSecureString "  $Label"
            $val = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                       [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
        } else {
            $val = (Read-Host "  $Label").Trim()
        }
        if (-not $val) { Write-Err "Please enter a value to continue."; continue }
        if ($IsGuid) {
            try { [Guid]::Parse($val) | Out-Null }
            catch { Write-Err "Please enter a valid ID (format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)."; continue }
        }
        return $val
    }
}

function Prompt-Optional {
    param([string]$Label, [string]$Default = '', [string]$Hint = '')
    if ($Hint) { Write-Host "    [$Hint]" -ForegroundColor DarkGray }
    $val = (Read-Host "  $Label [$Default]").Trim()
    if (-not $val) { return $Default }
    return $val
}

function Confirm-Continue {
    param([string]$Prompt = 'Proceed?')
    $r = Read-Host "`n  $Prompt [Y/n]"
    return ($r -eq '' -or $r -match '^[Yy]')
}

function Wait-WithMessage {
    param([int]$Seconds, [string]$Reason)
    if ($DryRun) { Write-Info "(DRY RUN) Would wait ${Seconds}s -- $Reason"; return }
    Write-Host "  -- Waiting ${Seconds}s -- $Reason " -ForegroundColor Gray -NoNewline
    for ($i = 0; $i -lt $Seconds; $i++) {
        Start-Sleep -Seconds 1
        if (($i + 1) % 10 -eq 0) {
            Write-Host "$($i+1)s" -ForegroundColor DarkGray -NoNewline
        } else {
            Write-Host '.' -ForegroundColor DarkGray -NoNewline
        }
    }
    Write-Host " done." -ForegroundColor Gray
}

function Wait-UntilRAsReady {
    param(
        [string[]]$Upns,
        [int]$MaxSeconds   = 180,
        [int]$PollInterval = 10
    )
    if ($DryRun) { Write-Info "(DRY RUN) Would poll for RA propagation (max ${MaxSeconds}s)."; return }
    Write-Host "  -- Polling for Azure AD propagation of $($Upns.Count) RA(s) (max ${MaxSeconds}s, every ${PollInterval}s) ..." -ForegroundColor Gray
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    $elapsed  = 0
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollInterval
        $elapsed += $PollInterval
        $ready = @($Upns | Where-Object {
            $u = Get-CsOnlineUser -Identity $_ -ErrorAction SilentlyContinue
            $null -ne $u
        })
        Write-Host ("  -- [{0,3}s] {1}/{2} RA(s) visible in Teams ..." -f $elapsed, $ready.Count, $Upns.Count) -ForegroundColor DarkGray
        if ($ready.Count -eq $Upns.Count) {
            Write-OK "All $($Upns.Count) RA(s) confirmed visible in Teams (${elapsed}s elapsed)."
            return
        }
    }
    Write-Warn "Timed out after ${MaxSeconds}s -- some RAs may not yet be visible. Proceeding anyway; Step 8 will retry."
}

function Backup-JsonFile {
    param([string]$Path)
    if (Test-Path $Path) {
        $ts     = Get-Date -Format 'yyyyMMdd-HHmmss'
        $dir    = Split-Path $Path
        $base   = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $ext    = [System.IO.Path]::GetExtension($Path)
        $outDir = if ($dir) { $dir } else { '.' }
        $backup = Join-Path $outDir "${base}-backup-${ts}${ext}"
        Copy-Item -Path $Path -Destination $backup
        Write-Info "Backed up $Path -> $backup"
    }
}

function Get-D365DrNumbers {
    param(
        [Parameter(Mandatory)][string]$OrgUrl,
        [Parameter(Mandatory)][string]$TenantId
    )

    Write-Step "Acquiring D365 access token for $OrgUrl ..."
    try {
        $tokenJson = az account get-access-token --resource $OrgUrl --tenant $TenantId 2>&1
        $token = ($tokenJson | ConvertFrom-Json).accessToken
        if (-not $token) { throw "Could not get an access token. Please sign in first: az login --tenant $($cfg.TenantId)" }
        Write-OK "D365 token acquired."
    } catch {
        throw "Dynamics 365 sign-in needed. Please run: az login --tenant $TenantId, then re-run the script."
    }

    $headers = @{
        Authorization      = "Bearer $token"
        Accept             = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }

    $selectFields = "msdyn_name,msdyn_phonenumber,statecode,statuscode"
    $uri = ($OrgUrl.TrimEnd('/') +
            "/api/data/v9.2/msdyn_ocphonenumbers" +
            "?`$select=$selectFields" +
            "&`$filter=statecode eq 0" +
            "&`$orderby=msdyn_phonenumber")

    Write-Step "Querying D365 OC phone numbers ..."
    Write-Info $uri

    try {
        $result     = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        $allNumbers = @($result.value)
    } catch {
        throw "Could not reach Dynamics 365. Please check your connection and app permissions, then re-run."
    }

    if ($allNumbers.Count -eq 0) {
        throw "No active phone numbers were found in Dynamics 365. Please make sure phone numbers are configured and active in D365 before running this migration."
    }

    Write-OK "Found $($allNumbers.Count) active phone number(s) in D365."

    return $allNumbers | ForEach-Object {
        [PSCustomObject]@{
            Number = $_.msdyn_phonenumber
            Name   = $_.msdyn_name
        }
    }
}

function Build-RaList {
    param(
        [Parameter(Mandatory)][array]$Numbers,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Domain
    )

    $usePhoneTemplate = $Prefix -match '<phonenumber>'
    $upnPrefix = ($Prefix -replace '[^a-zA-Z0-9\-\.<>]', '-' -replace '-+', '-').ToLower().Trim('-')
    # v14: dynamic padding width for >99 numbers
    $padWidth = if ($Numbers.Count -gt 999) { 4 } elseif ($Numbers.Count -gt 99) { 3 } else { 2 }

    $raList = @()
    $idx    = 1
    foreach ($n in $Numbers) {
        if ($usePhoneTemplate) {
            $numSafe     = $n.Number -replace '[^0-9]', ''
            $displayName = $Prefix   -replace '<phonenumber>', $numSafe
            $upnLocal    = $upnPrefix -replace '<phonenumber>', $numSafe
            $upn         = "$upnLocal@$Domain"
        } else {
            $pad         = $idx.ToString("D$padWidth")
            $displayName = "$Prefix-$pad"
            $upn         = "$upnPrefix-$pad@$Domain"
        }
        $raList += [PSCustomObject]@{
            DisplayName = $displayName
            UPN         = $upn
            PhoneNumber = $n.Number
            D365Name    = $n.Name
        }
        $idx++
    }
    return $raList
}

function Test-E164Format {
    param([string]$Number)
    return $Number -match '^\+[1-9]\d{6,14}$'
}

function Get-NumberPatternRegex {
    param([string[]]$Numbers)

    if ($Numbers.Count -eq 0) { return '.*' }
    if ($Numbers.Count -eq 1) {
        $escaped = [regex]::Escape($Numbers[0])
        return "^$escaped$"
    }

    $first  = $Numbers[0]
    $minLen = ($Numbers | ForEach-Object { $_.Length } | Measure-Object -Minimum).Minimum
    $common = ''
    for ($i = 0; $i -lt $minLen; $i++) {
        $ch = $first[$i]
        if ($Numbers | Where-Object { $_[$i] -ne $ch }) { break }
        $common += $ch
    }

    if ($common.Length -le 1) { return '^\+\d+$' }
    $escapedPrefix = [regex]::Escape($common)
    return "^$escapedPrefix\d*$"
}

function Invoke-D365Discovery {
    param(
        [Parameter(Mandatory)][string]$OrgUrl,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Domain,
        [string[]]$IncludeNumbers = @()
    )

    $d365Numbers = $null
    try {
        $d365Numbers = Get-D365DrNumbers -OrgUrl $OrgUrl -TenantId $TenantId
    } catch {
        Write-Err "Dynamics 365 discovery did not complete. Please sign in with: az login --tenant $TenantId, then re-run."
        Write-Err "If already signed in, check that the App ID has access to the D365 org."
        Exit-Script 1
    }

    $acsRoutePatterns = @()
    try {
        if ($cfg -and $cfg.PSObject.Properties['AcsConnectionString'] -and $cfg.AcsConnectionString) {
            $parts = @{}
            $cfg.AcsConnectionString.Split(';') | ForEach-Object {
                $kv = $_ -split '=', 2
                if ($kv.Count -eq 2) { $parts[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
            }
            $ep      = $parts['endpoint']
            $key     = $parts['accesskey']
            $apiUrl  = "$($ep.TrimEnd('/'))/sip?api-version=2023-04-01-preview"
            $apiHost = ([System.Uri]$apiUrl).Host
            $date    = [System.DateTime]::UtcNow.ToString('r')
            $pq      = '/sip?api-version=2023-04-01-preview'
            $keyB    = [System.Convert]::FromBase64String($key)
            $toSign  = "GET`n$pq`n$date;$apiHost;47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
            $hmac    = [System.Security.Cryptography.HMACSHA256]::new($keyB)
            try {
                $sig = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
            } finally { $hmac.Dispose() }
            $hdrs    = @{
                'x-ms-date'           = $date
                'x-ms-content-sha256' = '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='
                'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
            }
            $sipData = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $hdrs
            $acsRoutePatterns = @($sipData.routes | ForEach-Object { $_.numberPattern })
            Write-Info "Fetched $($acsRoutePatterns.Count) ACS route pattern(s) for DR/DO classification."
        }
    } catch {
        Write-Warn "Could not fetch ACS routes for DR/DO classification: $_"
        $exportFallbackPath = '.\acs-export.json'
        if (-not (Test-Path $exportFallbackPath)) { $exportFallbackPath = Join-Path (Split-Path $ConfigPath) 'acs-export.json' }
        if (Test-Path $exportFallbackPath) {
            try {
                $exportFallback    = Get-Content $exportFallbackPath -Raw | ConvertFrom-Json
                $acsRoutePatterns  = @($exportFallback.routes | ForEach-Object { $_.numberPattern })
                Write-Info "Using acs-export.json fallback for DR/DO classification ($($acsRoutePatterns.Count) pattern(s))."
            } catch {
                Write-Warn "Could not read acs-export.json fallback -- all numbers will be classified as DO."
            }
        } else {
            Write-Info "No acs-export.json found -- all numbers will be classified as DO."
        }
    }

    $d365Numbers = $d365Numbers | ForEach-Object {
        $num = $_
        $isDR = $acsRoutePatterns | Where-Object { $num.Number -match $_ }
        $typeVal = if ($isDR) { 'DR' } else { 'DO' }
        $num | Add-Member -NotePropertyName 'Type' -NotePropertyValue $typeVal -Force
        $num
    }

    Write-Host ""
    Write-Host "  Numbers found in D365 ($($d365Numbers.Count) total):" -ForegroundColor White
    $d365Numbers | Format-Table `
        @{L='#';    E={[array]::IndexOf($d365Numbers,$_)+1}; W=4},
        @{L='Type'; E={$_.Type}; W=6},
        @{L='Phone Number';E={$_.Number}; W=18},
        @{L='D365 Name';   E={$_.Name};   W=60} -AutoSize | Out-Host

    if ($IncludeNumbers -and $IncludeNumbers.Count -gt 0) {
        $d365Numbers = @($d365Numbers | Where-Object { $_.Number -in $IncludeNumbers })
        Write-OK "Pre-filtered by IncludeNumbers: $($d365Numbers.Count) number(s) selected."
    } else {
        Write-Host "  Enter row numbers (e.g. 1,3,5) or phone numbers (e.g. +12065551234) to include, or press Enter for all." -ForegroundColor DarkGray
        $selectInput = (Read-Host "  Select? [Enter=all]").Trim()
        if ($selectInput) {
            $selectSet = @($selectInput -split '\s*,\s*' | ForEach-Object { $_.Trim() })
            $byRow  = @($selectSet | Where-Object { $_ -match '^\d+$' })
            $byNum  = @($selectSet | Where-Object { $_ -notmatch '^\d+$' })
            $rowIdx = @($byRow | ForEach-Object { [int]$_ - 1 })
            $d365Numbers = @($d365Numbers | Where-Object {
                $idx = [array]::IndexOf($d365Numbers, $_)
                $idx -in $rowIdx -or $_.Number -in $byNum
            })
            Write-OK "Selected: $($d365Numbers.Count) number(s) will be migrated."
        } else {
            Write-OK "All $($d365Numbers.Count) number(s) selected."
        }
    }

    if ($d365Numbers.Count -eq 0) { Write-Err "No phone numbers were selected for migration. Please re-run and select at least one number."; Exit-Script 1 }

    # v14.2.0: Validate E.164 format -- warn on any numbers that may fail Teams upload
    $nonE164 = @($d365Numbers | Where-Object { -not (Test-E164Format $_.Number) })
    if ($nonE164.Count -gt 0) {
        Write-Warn "$($nonE164.Count) number(s) are NOT in E.164 format (e.g. +12065551234):"
        foreach ($bad in $nonE164) { Write-Host "    $($bad.Number)  ($($bad.Name))" -ForegroundColor Yellow }
        Write-Warn "Step 6 (DR number upload) may fail for these numbers. Fix in D365 or exclude them."
    }

    $raRows = @(Build-RaList -Numbers $d365Numbers -Prefix $Prefix -Domain $Domain)

    Write-Host ""
    Write-Host "  Auto-generated Resource Accounts:" -ForegroundColor White
    $raRows | Format-Table `
        @{L='DisplayName'; E={$_.DisplayName}; W=28},
        @{L='UPN';         E={$_.UPN};         W=60},
        @{L='PhoneNumber'; E={$_.PhoneNumber}; W=16} -AutoSize | Out-Host

    if (-not (Confirm-Continue "Proceed with these $($raRows.Count) resource account(s)?")) {
        Write-Host "  Aborted by user." -ForegroundColor Yellow
        Exit-Script 0
    }

    return ,$raRows
}

# ---------------------------------------------------------------------------
# ACS HMAC PATCH helper (used in Step 2 for disable/re-enable)
# ---------------------------------------------------------------------------

function Invoke-AcsTrunkPatch {
    param(
        [string]$Fqdn,
        [bool]$Enabled,
        [int]$SipSignalingPort,
        [object[]]$Routes = @(),   # pass $acsRoutes when re-enabling to restore them; empty = clear routes when disabling
        [string]$AcsEp,
        [string]$AcsKey
    )
    $pq       = '/sip?api-version=2023-04-01-preview'
    $apiUrl   = "$AcsEp$pq"
    $apiHost  = ([System.Uri]$apiUrl).Host
    # ACS rejects enabled:false while routes reference this trunk ("MissingEnabledTrunkForRoute").
    # Fix: clear routes + set enabled:false in one PATCH so ACS validates the final state (no routes, no issue).
    # On re-enable: restore routes + enabled:true together.
    $trunkVal = [ordered]@{ sipSignalingPort = $SipSignalingPort; enabled = $Enabled }
    $body     = [ordered]@{ trunks = [ordered]@{ $Fqdn = $trunkVal }; routes = $Routes } | ConvertTo-Json -Depth 6 -Compress
    $date     = [System.DateTime]::UtcNow.ToString('r')
    $keyB     = [System.Convert]::FromBase64String($AcsKey)
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
    Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $hdrs -Body $body | Out-Null
}

#endregion

#region -----------------------------------------------------------------------
#  MAIN BANNER
# ------------------------------------------------------------------------------

$modeLabel = if ($DryRun) { 'DRY RUN  -- No changes will be made' } else { 'LIVE MODE -- Changes will apply to production' }
$modeColor = if ($DryRun) { 'Yellow' } else { 'Red' }

Write-Host ""
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host "|                                                                  |" -ForegroundColor Cyan
Write-Host "|   ACS -> Teams Phone Extensibility (TPE) Migration  v14.16.0     |" -ForegroundColor Cyan
Write-Host "|   Zero-downtime Step 2: ACS re-enabled after gateway creation   |" -ForegroundColor Cyan
Write-Host "|   ACS handles calls throughout Steps 3-9. Toggle at Step 10.    |" -ForegroundColor Cyan
Write-Host "|                                                                  |" -ForegroundColor Cyan
Write-Host ("|   Mode: " + $modeLabel.PadRight(57) + "|") -ForegroundColor $modeColor
Write-Host "|                                                                  |" -ForegroundColor Cyan
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host ""

if (-not $DryRun) {
    Write-Warn "LIVE MODE: This script will create SBCs, resource accounts, and assign phone numbers."
    Write-Warn "Run with -DryRun first to review all planned actions."
    Write-Host ""
}

#endregion

#region -----------------------------------------------------------------------
#  PHASE 0A -- GATHER INPUTS
# ------------------------------------------------------------------------------

$cfg = $null

if ($ConfigPath -and (Test-Path $ConfigPath)) {
    Write-Step "Loading saved config from: $ConfigPath"
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    Write-OK "Config loaded."

    $hasD365Url = $cfg.PSObject.Properties['D365OrgUrl'] -and $cfg.D365OrgUrl
    $hasPrefix  = $cfg.PSObject.Properties['RaPrefix']   -and $cfg.RaPrefix

    if (-not $hasD365Url) {
        Write-Warn "Config has no D365OrgUrl -- prompting for missing fields."
        Write-Host ""

        $d365OrgUrl = (Prompt-Required `
            -Label 'D365 Org URL' `
            -Hint  'e.g. https://contoso.crm10.dynamics.com').TrimEnd('/')

        $raPrefix = Prompt-Optional `
            -Label 'Resource Account Name Prefix' `
            -Default 'TPE-RA' `
            -Hint  'e.g. acs-tpe-ra-phonenumber-cbg-voice.sandbox.dev.microsoft'

        $cfg | Add-Member -NotePropertyName 'D365OrgUrl' -NotePropertyValue $d365OrgUrl -Force
        $cfg | Add-Member -NotePropertyName 'RaPrefix'   -NotePropertyValue $raPrefix   -Force
    } else {
        $raPrefix = $cfg.RaPrefix
    }

    Write-Banner 'PHASE 0D -- Discover Phone Numbers from Dynamics 365'

    $cfgInclude = if ($cfg.PSObject.Properties['IncludeNumbers'] -and $cfg.IncludeNumbers) { @($cfg.IncludeNumbers) } else { @() }
    $newRaRows = Invoke-D365Discovery `
        -OrgUrl          $cfg.D365OrgUrl `
        -TenantId        $cfg.TenantId `
        -Prefix          $raPrefix `
        -Domain          $cfg.Domain `
        -IncludeNumbers  $cfgInclude

    $cfg | Add-Member -NotePropertyName 'ResourceAccounts' -NotePropertyValue $newRaRows -Force
    Write-OK "ResourceAccounts set from D365: $($newRaRows.Count) real phone number(s)."
}

if (-not $cfg -and $StartAtStep -eq 0) {
    Write-Banner 'PHASE 0 -- Gather Required Information' 'Enter all values when prompted.'

    Write-Host ""
    Write-Host "  +-- TEAMS / AZURE TENANT -------------------------------------" -ForegroundColor DarkCyan

    $tenantId = Prompt-Required `
        -Label '1. Teams Tenant ID  (Microsoft Entra ID / Azure AD Tenant ID)' `
        -Hint  'Azure Portal > Microsoft Entra ID > Overview > Tenant ID (a GUID)' `
        -IsGuid

    $adminUpn = Prompt-Required `
        -Label '2. Teams Admin Account UPN  (must be Global Admin or Teams Administrator)' `
        -Hint  'e.g. admin@contoso.onmicrosoft.com'

    $domain = Prompt-Required `
        -Label '3. Domain for Resource Account UPNs' `
        -Hint  'e.g. contoso.com  (will be registered/verified in Step 4 if needed)'

    $dynamicsAppId = Prompt-Required `
        -Label '4. Dynamics 365 App Registration Client ID' `
        -Hint  'Azure Portal > App Registrations > your D365 app > Application (client) ID' `
        -IsGuid

    Write-Host ""
    Write-Host "  +-- AZURE COMMUNICATION SERVICES (ACS) -----------------------" -ForegroundColor DarkCyan

    $acsSubscriptionId = Prompt-Required `
        -Label '5. Azure Subscription ID  (hosting the ACS resource)' `
        -Hint  'Azure Portal > Subscriptions > Subscription ID (a GUID)' `
        -IsGuid

    $acsResourceId = Prompt-Required `
        -Label '6. ACS Resource ID  (immutable GUID, NOT the full ARM resource path)' `
        -Hint  'Azure Portal > ACS resource > Properties > Resource ID -- copy ONLY the last GUID segment' `
        -IsGuid

    $acsEndpoint = Prompt-Required `
        -Label '7. ACS Endpoint URL' `
        -Hint  'portal.azure.com -> ACS resource -> Keys -> Endpoint'

    $acsAccessKey = Prompt-Required `
        -Label '8. ACS Access Key (Key 1 or Key 2)' `
        -Hint  'portal.azure.com -> ACS resource -> Keys' `
        -IsSecret

    $acsConnectionString = "endpoint=$($acsEndpoint.TrimEnd('/'));accesskey=$acsAccessKey"

    Write-Host ""
    Write-Host "  +-- SESSION BORDER CONTROLLER (SBC) --------------------------" -ForegroundColor DarkCyan

    $sbcFqdn = Prompt-Required `
        -Label '9. SBC FQDN' `
        -Hint  'e.g. wynn-sbc.sip1-use1.audiocodes.io'

    $sbcPort = Prompt-Optional `
        -Label '10. SBC SIP Signaling Port' `
        -Default '5061' `
        -Hint  'Always 5061 for Teams Direct Routing'

    while (-not ($sbcPort -match '^\d+$' -and [int]$sbcPort -gt 0 -and [int]$sbcPort -le 65535)) {
        Write-Err "Port must be a number between 1 and 65535."
        $sbcPort = Prompt-Optional -Label '10. SBC SIP Signaling Port' -Default '5061'
    }

    Write-Host ""
    Write-Host "  +-- DYNAMICS 365 (phone number source) -----------------------" -ForegroundColor DarkCyan

    $d365OrgUrl = (Prompt-Required `
        -Label '11. Dynamics 365 Org URL' `
        -Hint  'e.g. https://contoso.crm10.dynamics.com').TrimEnd('/')

    Write-Host ""
    Write-Host "  +-- RESOURCE ACCOUNT NAMING ----------------------------------" -ForegroundColor DarkCyan

    $raPrefix = Prompt-Optional `
        -Label '12. Resource Account Name Prefix' `
        -Default 'TPE-RA' `
        -Hint  'e.g. Wynn-TPE or acs-tpe-ra-phonenumber-cbg-voice'

    Write-Host ""
    Write-Host "  +-- VOICE ROUTING POLICY NAMES (press Enter for defaults) ----" -ForegroundColor DarkCyan

    $policyName = Prompt-Optional -Label '13. Voice Routing Policy Name' -Default 'ACS-Migration-Policy'
    $usageName  = Prompt-Optional -Label '14. PSTN Usage Name'           -Default 'ACS-Migration-Usage'
    $routeName  = Prompt-Optional -Label '15. Voice Route Name'          -Default 'ACS-Migration-Route'

    Write-Host ""
    Write-Host "  +-- DYNAMICS 365 COMMS PROVIDER (optional) ---------------------" -ForegroundColor DarkCyan

    $commsProviderId = Prompt-Optional `
        -Label '16. Communications Provider Setting ID' `
        -Default '' `
        -Hint  'D365 CSAC > Channels > Phone numbers > Sync from Azure > DevTools: commsProviderId (a GUID, or press Enter to skip)'

    Write-Banner 'PHASE 0D -- Discover Phone Numbers from Dynamics 365'

    $raRows = Invoke-D365Discovery `
        -OrgUrl   $d365OrgUrl `
        -TenantId $tenantId `
        -Prefix   $raPrefix `
        -Domain   $domain

    $cfg = [PSCustomObject]@{
        TenantId            = $tenantId
        AdminUpn            = $adminUpn
        Domain              = $domain
        DynamicsAppId       = $dynamicsAppId
        D365OrgUrl          = $d365OrgUrl
        RaPrefix            = $raPrefix
        AcsSubscriptionId   = $acsSubscriptionId
        AcsResourceId       = $acsResourceId
        AcsEndpoint         = $acsEndpoint
        AcsConnectionString = $acsConnectionString
        SbcFqdn             = $sbcFqdn
        SbcPort             = [int]$sbcPort
        PolicyName          = $policyName
        UsageName           = $usageName
        RouteName           = $routeName
        CommsProviderId     = $commsProviderId
        ResourceAccounts    = $raRows
    }

    $cfgSafe     = $cfg | Select-Object * -ExcludeProperty AcsConnectionString
    $cfgSavePath = ".\acs-tpe-config-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $cfgSafe | ConvertTo-Json -Depth 5 | Set-Content $cfgSavePath -Encoding UTF8
    Write-OK "Config saved to: $cfgSavePath"
    Write-Info "Reuse with: -ConfigPath $cfgSavePath"
}

# v14: guard against resume mode without a loaded config
if (-not $cfg -and $StartAtStep -gt 0) {
    Write-Err "No config loaded. When using -StartAtStep $StartAtStep, you must also provide -ConfigPath."
    Exit-Script 1
}

$hasConnStr = $cfg -and ($cfg.PSObject.Properties['AcsConnectionString'] -ne $null) -and $cfg.AcsConnectionString
if ($cfg -and -not $hasConnStr -and -not $DryRun) {
    Write-Warn "ACS Access Key not in saved config (never persisted for security)."
    $acsAccessKey = Prompt-Required -Label 'Re-enter ACS Access Key' -IsSecret
    $acsConnStr   = "endpoint=$($cfg.AcsEndpoint.TrimEnd('/'));accesskey=$acsAccessKey"
    $cfg | Add-Member -NotePropertyName 'AcsConnectionString' -NotePropertyValue $acsConnStr -Force
}

#endregion

#region -----------------------------------------------------------------------
#  DRY-RUN SUMMARY
# ------------------------------------------------------------------------------

$allNumbers      = @($cfg.ResourceAccounts | ForEach-Object { [string]$_.PhoneNumber })
$numberPattern   = Get-NumberPatternRegex -Numbers $allNumbers
$d365UrlDisplay  = if ($cfg.PSObject.Properties['D365OrgUrl'])  { $cfg.D365OrgUrl  } else { '(not set)' }
$raPrefixDisplay = if ($cfg.PSObject.Properties['RaPrefix'])    { $cfg.RaPrefix    } else { '(not set)' }

Write-Banner 'DRY-RUN SUMMARY -- Review Planned Actions Before Proceeding'

Write-Host ""
Write-Host "  +-- MICROSOFT ENTRA ID TENANT ----------------------------------------+" -ForegroundColor White
Write-Host "  |  Tenant ID    : $($cfg.TenantId)  [Entra ID / Azure AD]" -ForegroundColor White
Write-Host "  |  Admin UPN    : $($cfg.AdminUpn)  [Teams & Graph auth]" -ForegroundColor White
Write-Host "  |  RA Domain    : $($cfg.Domain)  [Resource Account UPN domain]" -ForegroundColor White
Write-Host "  +-- ACS (SOURCE) -----------------------------------------------------+" -ForegroundColor White
Write-Host "  |  Subscription : $($cfg.AcsSubscriptionId)" -ForegroundColor White
Write-Host "  |  Resource ID  : $($cfg.AcsResourceId)" -ForegroundColor White
Write-Host "  |  Endpoint     : $($cfg.AcsEndpoint)" -ForegroundColor White
Write-Host "  +-- DYNAMICS 365 -------------------------------------------------------+" -ForegroundColor White
Write-Host "  |  Org URL      : $d365UrlDisplay" -ForegroundColor White
Write-Host "  |  App ID       : $($cfg.DynamicsAppId)" -ForegroundColor White
Write-Host "  |  RA Prefix    : $raPrefixDisplay" -ForegroundColor White
Write-Host "  +-- SBC ----------------------------------------------------------------+" -ForegroundColor White
Write-Host "  |  FQDN         : $($cfg.SbcFqdn)" -ForegroundColor White
Write-Host "  |  Port         : $($cfg.SbcPort)" -ForegroundColor White
Write-Host "  +-- VOICE ROUTING -------------------------------------------------------+" -ForegroundColor White
Write-Host "  |  Policy       : $($cfg.PolicyName)" -ForegroundColor White
Write-Host "  |  PSTN Usage   : $($cfg.UsageName)" -ForegroundColor White
Write-Host "  |  Route        : $($cfg.RouteName)" -ForegroundColor White
Write-Host "  |  Num Pattern  : $numberPattern  (auto-derived)" -ForegroundColor White
Write-Host "  +-- RESOURCE ACCOUNTS ($(@($cfg.ResourceAccounts).Count) -- sourced from D365) --------+" -ForegroundColor White

foreach ($ra in $cfg.ResourceAccounts) {
    $d365n = if ($ra.PSObject.Properties['D365Name'] -and $ra.D365Name) { " [D365: $($ra.D365Name)]" } else { '' }
    Write-Host ("  |  " + $ra.DisplayName.PadRight(25) + " | " + $ra.UPN.PadRight(45) + " | " + $ra.PhoneNumber + $d365n) -ForegroundColor Gray
}
Write-Host "  +--------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""
$rangeLabel = if ($StartAtStep -eq 0 -and $StopAfterStep -eq 11) { 'All steps' } `
              elseif ($StartAtStep -eq $StopAfterStep) { "Step $StartAtStep only" } `
              else { "Steps $StartAtStep - $StopAfterStep" }
Write-Host "  PLANNED STEPS (v14) -- $rangeLabel will execute" -ForegroundColor Gray

function Write-PlanStep {
    param([int]$StepNum, [string]$Label, [string]$Color = 'Gray')
    if ($StepNum -ge $StartAtStep -and $StepNum -le $StopAfterStep) {
        Write-Host "  [Step $($StepNum.ToString().PadLeft(2))]  $Label  <-- WILL RUN" -ForegroundColor $Color
    } else {
        Write-Host "  [Step $($StepNum.ToString().PadLeft(2))]  $Label  (skipped)" -ForegroundColor DarkGray
    }
}

if ($StartAtStep -le 0 -and $StopAfterStep -ge 0) {
    Write-Host "  [Phase 0 ]  Install-Module MicrosoftTeams, Microsoft.Graph  <-- WILL RUN" -ForegroundColor Gray
    Write-Host "  [Phase 0 ]  Connect-MicrosoftTeams, Connect-MgGraph  <-- WILL RUN" -ForegroundColor Gray
    Write-Host "  [Phase 0 ]  Verify PHONESYSTEM_VIRTUALUSER license count (hard exit if insufficient)  <-- WILL RUN" -ForegroundColor Gray
} else {
    Write-Host "  [Phase 0 ]  Install-Module / Connect / License check  (skipped)" -ForegroundColor DarkGray
}
Write-PlanStep  1 "Export ACS trunks + routes -> acs-export.json"
Write-PlanStep  2 "Disable ACS trunk (temp) -> create Teams gateway (disabled) -> re-enable ACS [~10s downtime]" 'Yellow'
Write-PlanStep  3 "Set-CsOnlinePstnUsage / New-CsOnlineVoiceRoute / New-CsOnlineVoiceRoutingPolicy"
Write-PlanStep  4 "Register and verify domain '$($cfg.Domain)' in Microsoft Entra ID" 'Yellow'
Write-PlanStep  5 "Validate SBC gateway exists, routes, policy"
Write-PlanStep  6 "Upload $(@($cfg.ResourceAccounts).Count) D365-sourced DR number(s)"
Write-PlanStep  7 "Create $(@($cfg.ResourceAccounts).Count) RAs as TPE application instances"
Write-PlanStep  8 "Assign PHONESYSTEM_VIRTUALUSER licenses (UsageLocation=$UsageLocation)"
Write-PlanStep  9 "Assign DR phone numbers to RAs"
Write-PlanStep 10 "Toggle-AcsTeamsRouting-v14.ps1 -- disable ACS, enable Teams gateway (cutover)" 'Yellow'
Write-PlanStep 11 "Invoke-MigrateTpsPhoneNumber-v14.ps1 -- update D365 phone type ACS->TPS + sync (per number)" 'Yellow'
Write-Host ""
Write-Host "  NOTE: ACS handles live calls throughout Steps 3-9. Cutover at Step 10. D365 sync at Step 11." -ForegroundColor DarkCyan
Write-Host "  Results CSV: $OutputPath" -ForegroundColor Gray
Write-Host ""

if ($DryRun) {
    Write-Host "  [DRY RUN COMPLETE] No changes were made." -ForegroundColor Yellow
    Write-Host "  Run without -DryRun to execute the migration." -ForegroundColor Yellow
    Exit-Script 0
}

if (-not (Confirm-Continue 'This will make LIVE changes to your Teams tenant and ACS. Confirm?')) {
    Write-Host "  Aborted by user." -ForegroundColor Yellow
    Exit-Script 0
}

#endregion

#region -----------------------------------------------------------------------
#  PHASE 0B -- INSTALL MODULES AND CONNECT
# ------------------------------------------------------------------------------

if ($StartAtStep -le 0 -and $StopAfterStep -ge 0) {
    Write-Banner 'PHASE 0 -- Install Modules and Connect' '' 'Yellow'

    foreach ($mod in @('MicrosoftTeams', 'Microsoft.Graph')) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Step "Installing $mod ..."
            Install-Module $mod -Force -AllowClobber -Scope CurrentUser
            Write-OK "$mod installed."
        } else {
            Write-OK "$mod already installed."
        }
    }

    Write-Step "Connecting to Microsoft Teams ..."
    $tenant = Get-CsTenant -ErrorAction SilentlyContinue
    if (-not $tenant) {
        Connect-MicrosoftTeams -TenantId $cfg.TenantId
        $tenant = Get-CsTenant
    }
    Write-OK "Connected to Teams: $($tenant.DisplayName) (Tenant: $($tenant.TenantId))"

    Write-Step "Connecting to Microsoft Graph ..."
    Connect-MgGraph -Scopes 'User.ReadWrite.All', 'Organization.Read.All', 'Directory.ReadWrite.All', 'Domain.ReadWrite.All' -TenantId $cfg.TenantId
    $ctx = Get-MgContext
    Write-OK "Connected to Graph as: $($ctx.Account)"

    Write-Step "Checking PHONESYSTEM_VIRTUALUSER license ..."
    $sku   = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER' }
    $skuId = $null
    if ($sku) {
        $avail = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
        $skuId = $sku.SkuId
        $raCount = @($cfg.ResourceAccounts).Count
        if ($avail -lt $raCount) {
            Write-Err "Not enough Teams Phone Resource Account licenses available ($avail available, $raCount needed)."
            Write-Err "Please add more licenses in Microsoft 365 Admin Center, then re-run."
            Exit-Script 1
        } else {
            Write-OK "Teams Phone Resource Account license: $avail available, $raCount needed -- OK"
        }
    } else {
        Write-Err "The Teams Phone Resource Account license plan was not found in this tenant."
        Write-Err "Please add it in Microsoft 365 Admin Center (search for 'Teams Phone Resource Account'), then re-run."
        Exit-Script 1
    }
    Write-OK 'Phase 0 complete.'
} else {
    Write-Step 'Reconnecting to Teams and Graph (resume mode) ...'
    if (-not (Get-CsTenant -ErrorAction SilentlyContinue)) { Connect-MicrosoftTeams -TenantId $cfg.TenantId }
    Connect-MgGraph -Scopes 'User.ReadWrite.All', 'Organization.Read.All', 'Directory.ReadWrite.All', 'Domain.ReadWrite.All' -TenantId $cfg.TenantId
    $sku   = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER' }
    $skuId = if ($sku) { $sku.SkuId } else { $null }
    Write-OK 'Reconnected.'
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 1 -- EXPORT ACS CONFIG
# ------------------------------------------------------------------------------

$acsExportPath = '.\acs-export.json'

if ($StartAtStep -le 1 -and $StopAfterStep -ge 1) {
    Write-Banner 'STEP 1 -- Export ACS SIP Trunks and Routes'

    $acsTrunks = @()
    $acsRoutes = @()

    try {
        $parts = @{}
        $cfg.AcsConnectionString.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $parts[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $ep        = $parts['endpoint']
        $key       = $parts['accesskey']
        if (-not $ep -or -not $key) {
            throw "AcsConnectionString is missing 'endpoint' or 'accesskey'. Check config."
        }
        $apiUrl    = "$($ep.TrimEnd('/'))/sip?api-version=2023-04-01-preview"
        $apiHost   = ([System.Uri]$apiUrl).Host
        $date      = [System.DateTime]::UtcNow.ToString('r')
        $pathQuery = '/sip?api-version=2023-04-01-preview'
        $keyBytes  = [System.Convert]::FromBase64String($key)
        $emptyHash = '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='
        $toSign    = "GET`n$pathQuery`n$date;$apiHost;$emptyHash"
        $hmac      = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
        try {
            $sig   = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
        } finally { $hmac.Dispose() }

        $headers = @{
            'x-ms-date'           = $date
            'x-ms-content-sha256' = $emptyHash
            'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
        }

        Write-Step 'Calling ACS SIP Routing API ...'
        $sipData   = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $headers

        $acsTrunks = @($sipData.trunks.PSObject.Properties | ForEach-Object {
            [PSCustomObject]@{ fqdn = $_.Name; sipSignalingPort = $_.Value.sipSignalingPort }
        })
        $acsRoutes = @($sipData.routes | ForEach-Object {
            [PSCustomObject]@{ name = $_.name; numberPattern = $_.numberPattern; trunks = $_.trunks }
        })
        Write-OK "Exported $($acsTrunks.Count) trunk(s) and $($acsRoutes.Count) route(s) from ACS."
    } catch {
        Write-Warn "Could not reach ACS to export trunks and routes. Using your config file values instead."
        $acsTrunks      = @([PSCustomObject]@{ fqdn=$cfg.SbcFqdn; sipSignalingPort=$cfg.SbcPort })
        $derivedPattern = Get-NumberPatternRegex -Numbers @($cfg.ResourceAccounts | ForEach-Object { [string]$_.PhoneNumber })
        $acsRoutes      = @([PSCustomObject]@{ name=$cfg.RouteName; numberPattern=$derivedPattern; trunks=@($cfg.SbcFqdn) })
        Write-OK "Synthetic: 1 trunk, 1 route (pattern: $derivedPattern)"
    }

    $export = [PSCustomObject]@{
        exportedAt = (Get-Date -Format 'o')
        trunks     = $acsTrunks
        routes     = $acsRoutes
        drNumbers  = @($cfg.ResourceAccounts | ForEach-Object { [string]$_.PhoneNumber })
    }
    if (-not $DryRun) {
        Backup-JsonFile -Path $acsExportPath
        $export | ConvertTo-Json -Depth 6 | Set-Content $acsExportPath -Encoding UTF8
    }
    Write-OK "Step 1 complete. Export written to: $acsExportPath"
} else {
    Write-Info "Step 1 skipped (StartAtStep=$StartAtStep). Loading $acsExportPath ..."
    if (-not (Test-Path $acsExportPath)) {
        Write-Warn "acs-export.json not found. Using config values as fallback."
        $acsTrunks = @([PSCustomObject]@{ fqdn=$cfg.SbcFqdn; sipSignalingPort=$cfg.SbcPort })
        $derivedPattern = Get-NumberPatternRegex -Numbers @($cfg.ResourceAccounts | ForEach-Object { [string]$_.PhoneNumber })
        $acsRoutes = @([PSCustomObject]@{ name=$cfg.RouteName; numberPattern=$derivedPattern; trunks=@($cfg.SbcFqdn) })
    } else {
        $export    = Get-Content $acsExportPath -Raw | ConvertFrom-Json
        $acsTrunks = @($export.trunks)
        $acsRoutes = @($export.routes)
    }
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 2 -- CREATE SBCs IN TEAMS (zero-downtime: disable ACS briefly, create gateway, re-enable ACS)
# ------------------------------------------------------------------------------

if ($StartAtStep -le 2 -and $StopAfterStep -ge 2) {
    Write-Banner 'STEP 2 -- Register Teams DR Gateway (Zero-Downtime ACS Disable/Re-enable)' `
                 'ACS disabled briefly for FQDN registration, then immediately re-enabled'

    # Only process the trunk matching SbcFqdn from config — ACS may have other trunks that
    # belong to unrelated deployments and should not be touched.
    $acsTrunks = @($acsTrunks | Where-Object { $_.fqdn -eq $cfg.SbcFqdn })
    if ($acsTrunks.Count -eq 0) {
        Write-Warn "SbcFqdn '$($cfg.SbcFqdn)' not found in ACS export. Using config values directly."
        $acsTrunks = @([PSCustomObject]@{ fqdn = $cfg.SbcFqdn; sipSignalingPort = $cfg.SbcPort })
    }

    # Teams refuses to register a PSTN gateway with an FQDN that is an active ACS SIP trunk.
    # Zero-downtime approach:
    #   1. PATCH ACS trunk enabled=false  (only to satisfy Teams FQDN uniqueness check)
    #   2. New-CsOnlinePSTNGateway        (disabled -- not yet active for calls)
    #   3. PATCH ACS trunk enabled=true   (ACS resumes handling live calls immediately)
    #
    # ACS handles production calls throughout Steps 3-10.
    # At Step 10, Toggle-AcsTeamsRouting-v14.ps1 is used to cut over when ready.
    #
    # acs-trunk-disabled.json tracks the FQDN list for undo (undo re-enables them in case
    # Toggle has disabled them between Step 2 and undo time).

    $acsDisabledFqdns = @()
    $acsEp  = ''
    $acsKey = ''

    if ($cfg.AcsConnectionString) {
        $acsConn  = @{}
        $cfg.AcsConnectionString.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $acsEp  = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
        $acsKey = if ($acsConn['accesskey']) { $acsConn['accesskey'] } else { '' }
    }

    foreach ($trunk in $acsTrunks) {
        Write-Host ""
        Write-Host "  [$($trunk.fqdn)]" -ForegroundColor White

        # --- 1. Temporarily disable ACS trunk ---
        if ($acsEp -and $acsKey) {
            Write-Step "  1/3 Temporarily disabling ACS trunk (to allow Teams FQDN registration) ..."
            if ($DryRun) {
                Write-Info "  (DRY RUN) Would PATCH ACS trunk '$($trunk.fqdn)' => enabled: false"
                $acsDisabledFqdns += $trunk.fqdn
            } else {
                try {
                    Invoke-AcsTrunkPatch -Fqdn $trunk.fqdn -Enabled $false -SipSignalingPort $trunk.sipSignalingPort -AcsEp $acsEp -AcsKey $acsKey
                    Write-Info "  ACS trunk disabled (temporary)."
                    $acsDisabledFqdns += $trunk.fqdn
                    @($acsDisabledFqdns) | ConvertTo-Json | Set-Content '.\acs-trunk-disabled.json'
                } catch {
                    $errDetail = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { ($_.Exception.Message -split '\r?\n')[0] }
                    $errBody   = ''
                    try {
                        $stream  = $_.Exception.Response.GetResponseStream()
                        $reader  = [System.IO.StreamReader]::new($stream)
                        $errBody = $reader.ReadToEnd(); $reader.Close()
                    } catch {}
                    Write-Warn "  Could not disable ACS trunk '$($trunk.fqdn)' ($errDetail). Teams gateway creation may fail if FQDN conflicts. Proceeding..."
                    if ($errBody) { Write-Warn "  ACS response: $errBody" }
                }
            }
        } else {
            Write-Warn "  AcsConnectionString not available -- skipping ACS disable. Teams gateway creation may fail if FQDN conflicts."
        }

        # Wait for ACS disable to propagate before Teams checks FQDN availability
        if ($acsDisabledFqdns -contains $trunk.fqdn) {
            Wait-WithMessage -Seconds 15 -Reason 'ACS disable propagation'
        }

        # --- 2. Create Teams DR gateway (disabled) ---
        Write-Step "  2/3 Creating Teams DR gateway '$($trunk.fqdn)' (Enabled=`$false) ..."
        if ($DryRun) {
            Write-Info "  (DRY RUN) Would call: New-CsOnlinePSTNGateway -Identity '$($trunk.fqdn)' -SipSignalingPort $($trunk.sipSignalingPort) -Enabled `$false"
        } else {
            $existing = Get-CsOnlinePSTNGateway -Identity $trunk.fqdn -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Info "  Gateway already exists -- skipping creation."
            } else {
                $teamsGwErr = $null
                New-CsOnlinePSTNGateway `
                    -Identity           $trunk.fqdn `
                    -SipSignalingPort   $trunk.sipSignalingPort `
                    -ForwardCallHistory $true `
                    -ForwardPai         $true `
                    -SendSipOptions     $true `
                    -MediaBypass        $false `
                    -Enabled            $false -ErrorAction SilentlyContinue -ErrorVariable teamsGwErr | Out-Null
                if ($teamsGwErr) { Write-Warn "  Teams error: $($teamsGwErr[0].Exception.Message -replace '\r?\n.*', '')" }
                $created = Get-CsOnlinePSTNGateway -Identity $trunk.fqdn -ErrorAction SilentlyContinue
                if ($created) {
                    Write-Info "  Teams gateway registered (Enabled=`$false -- stays dormant until Toggle activates it)."
                } else {
                    # Gateway creation failed. Re-enable ACS trunk before exiting to avoid call disruption.
                    if ($acsEp -and $acsKey -and ($acsDisabledFqdns -contains $trunk.fqdn)) {
                        Write-Warn "  Gateway creation failed. Re-enabling ACS trunk to restore call handling ..."
                        try {
                            Invoke-AcsTrunkPatch -Fqdn $trunk.fqdn -Enabled $true -SipSignalingPort $trunk.sipSignalingPort -Routes $acsRoutes -AcsEp $acsEp -AcsKey $acsKey
                            Write-OK "  ACS trunk re-enabled (routes restored). No call disruption."
                        } catch {
                            Write-Err "  Could not re-enable ACS trunk automatically. Please re-enable '$($trunk.fqdn)' in the ACS portal immediately."
                        }
                    }
                    Write-Err "The Teams gateway '$($trunk.fqdn)' could not be registered."
                    Write-Err "If the ACS trunk is still active, wait a moment and re-run with -StartAtStep 2."
                    Exit-Script 1
                }
            }
        }

        # --- 3. Re-enable ACS trunk (ACS resumes handling live calls) ---
        if ($acsEp -and $acsKey -and ($DryRun -or ($acsDisabledFqdns -contains $trunk.fqdn))) {
            Write-Step "  3/3 Re-enabling ACS trunk '$($trunk.fqdn)' (ACS resumes call handling) ..."
            if ($DryRun) {
                Write-Info "  (DRY RUN) Would PATCH ACS trunk '$($trunk.fqdn)' => enabled: true"
            } else {
                try {
                    Invoke-AcsTrunkPatch -Fqdn $trunk.fqdn -Enabled $true -SipSignalingPort $trunk.sipSignalingPort -Routes $acsRoutes -AcsEp $acsEp -AcsKey $acsKey
                    Write-OK "  ACS trunk re-enabled (routes restored). ACS is live and handling calls."
                } catch {
                    $errDetail = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { ($_.Exception.Message -split '\r?\n')[0] }
                    Write-Warn "  Could not re-enable ACS trunk '$($trunk.fqdn)' ($errDetail)."
                    Write-Warn "  ACS calls may be disrupted. Please re-enable the trunk manually in the ACS portal or run:"
                    Write-Warn "  Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath $ConfigPath"
                }
            }
        }
    }

    # Persist FQDN list for undo (undo reads this to know which trunks to re-enable if Toggle disabled them)
    if (-not $DryRun) {
        $acsDisabledFqdns | ConvertTo-Json | Set-Content '.\acs-trunk-disabled.json'
        Write-Info "FQDN tracking list saved to acs-trunk-disabled.json"
    } else {
        Write-Info "(DRY RUN) Would save FQDN tracking list: $($acsDisabledFqdns -join ', ')"
    }

    Write-Host ""
    Write-OK "Step 2 complete."
    Write-Info "  ACS trunk : enabled=true  (handling live calls)"
    Write-Info "  Teams gateway : Enabled=`$false  (dormant, ready for Toggle at Step 10)"
    if (-not $DryRun) { Wait-WithMessage -Seconds 30 -Reason 'SBC registration propagation' }
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 3 -- CONFIGURE CALL ROUTING
# ------------------------------------------------------------------------------

if ($StartAtStep -le 3 -and $StopAfterStep -ge 3) {
    Write-Banner 'STEP 3 -- Configure PSTN Usages, Voice Routes and Routing Policy'

    Write-Step "Setting PSTN usage: '$($cfg.UsageName)' ..."
    $currentUsages = (Get-CsOnlinePstnUsage).Usage
    if ($cfg.UsageName -notin $currentUsages) {
        Set-CsOnlinePstnUsage -Identity Global -Usage @{Add = $cfg.UsageName}
        Write-OK "  PSTN usage added."
    } else {
        Write-Warn "  PSTN usage already exists -- skipped."
    }

    $vrName    = $cfg.RouteName
    $vrPattern = Get-NumberPatternRegex -Numbers @($cfg.ResourceAccounts | ForEach-Object { [string]$_.PhoneNumber })
    $vrSbcs    = @($cfg.SbcFqdn)

    Write-Step "Voice route '$vrName'  pattern=$vrPattern  -> $($vrSbcs -join ', ')"
    if (Get-CsOnlineVoiceRoute -Identity $vrName -ErrorAction SilentlyContinue) {
        Write-Warn "  Route already exists -- skipped."
    } else {
        New-CsOnlineVoiceRoute `
            -Identity              $vrName `
            -NumberPattern         $vrPattern `
            -OnlinePstnGatewayList $vrSbcs `
            -OnlinePstnUsages      @($cfg.UsageName) | Out-Null
        Write-OK "  Route created."
    }

    Write-Step "Voice routing policy: '$($cfg.PolicyName)' ..."
    if (Get-CsOnlineVoiceRoutingPolicy -Identity $cfg.PolicyName -ErrorAction SilentlyContinue) {
        Write-Warn "  Policy already exists -- skipped."
    } else {
        New-CsOnlineVoiceRoutingPolicy `
            -Identity         $cfg.PolicyName `
            -OnlinePstnUsages @($cfg.UsageName) | Out-Null
        Write-OK "  Policy created."
    }

    Write-OK 'Step 3 complete.'
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 4 -- REGISTER AND VERIFY DOMAIN
# ------------------------------------------------------------------------------

if ($StartAtStep -le 4 -and $StopAfterStep -ge 4) {
    Write-Banner 'STEP 4 -- Register and Verify Domain in Microsoft Entra ID' '' 'Yellow'

    Write-Step "Checking domain '$($cfg.Domain)' ..."
    $domainObj = $null
    try {
        $domainObj = Get-MgDomain -DomainId $cfg.Domain -ErrorAction SilentlyContinue
    } catch {}

    if ($domainObj -and $domainObj.IsVerified) {
        Write-OK "Domain '$($cfg.Domain)' is already registered and verified. Skipping Step 4."
    } elseif ($DryRun) {
        Write-Info "(DRY RUN) Would register/verify domain '$($cfg.Domain)' — skipped."
    } else {
        if (-not $domainObj) {
            Write-Step "Registering domain '$($cfg.Domain)' ..."
            try {
                New-MgDomain -Id $cfg.Domain | Out-Null
                Write-OK "Domain '$($cfg.Domain)' registered."
            } catch {
                if ($_ -like '*already exists*' -or $_ -like '*ObjectConflict*') {
                    Write-Warn "Domain already exists -- continuing."
                } else {
                    Write-Err "Domain registration did not complete. Please check your admin permissions and try again with -StartAtStep 4."
                    Exit-Script 1
                }
            }
        } else {
            Write-Warn "Domain '$($cfg.Domain)' exists but is NOT yet verified."
        }

        Write-Step "Retrieving verification DNS records for '$($cfg.Domain)' ..."
        try {
            $dnsRecords = Get-MgDomainVerificationDnsRecord -DomainId $cfg.Domain
            if (-not $dnsRecords -or $dnsRecords.Count -eq 0) {
                Write-Warn 'No DNS records returned. Domain may need a moment to initialize -- try again in 30s.'
            } else {
                Write-OK "DNS records to add at your domain registrar:"
                Write-Host ''
                foreach ($rec in $dnsRecords) {
                    Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
                    Write-Host ("  Type       : {0}" -f $rec.RecordType)          -ForegroundColor White
                    Write-Host ("  Label      : {0}" -f $rec.Label)               -ForegroundColor White
                    if ($rec.AdditionalProperties['text']) {
                        Write-Host ("  Value      : {0}" -f $rec.AdditionalProperties['text']) -ForegroundColor Yellow
                    }
                    if ($rec.AdditionalProperties['canonicalName']) {
                        Write-Host ("  Canonical  : {0}" -f $rec.AdditionalProperties['canonicalName']) -ForegroundColor Yellow
                    }
                    Write-Host ("  TTL        : {0}" -f $rec.Ttl)                 -ForegroundColor White
                }
                Write-Host ''
            }
        } catch {
            Write-Warn "Could not retrieve DNS records: $_"
        }

        Write-Host ''
        Write-Host '  -----------------------------------------------' -ForegroundColor DarkGray
        Write-Host '  ACTION REQUIRED:' -ForegroundColor Yellow
        Write-Host "  Add the TXT record above to your DNS registrar for '$($cfg.Domain)'." -ForegroundColor Yellow
        Write-Host '  ACS continues handling calls while you wait for DNS propagation.' -ForegroundColor Gray
        Write-Host '  DNS propagation can take up to 72 hours (usually a few minutes).' -ForegroundColor Gray
        Write-Host ''

        $confirm = Read-Host "  Press ENTER when DNS record is added and propagated (or type 'skip' to verify later)"
        if ($confirm.ToLower() -eq 'skip') {
            Write-Warn "Skipped domain verification. Re-run with -StartAtStep 4 to retry."
        } else {
            Write-Step "Attempting automated domain verification (polling up to 5 min) ..."
            $verified = $false
            $maxAttempts = 10
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                Write-Info "  Verification attempt $attempt/$maxAttempts ..."
                try {
                    Confirm-MgDomain -DomainId $cfg.Domain -ErrorAction Stop | Out-Null
                    $domainCheck = Get-MgDomain -DomainId $cfg.Domain -ErrorAction SilentlyContinue
                    if ($domainCheck -and $domainCheck.IsVerified) {
                        Write-OK "Domain '$($cfg.Domain)' verified successfully."
                        $verified = $true; break
                    }
                } catch { }
                if ($attempt -lt $maxAttempts) {
                    Write-Info "  Not yet verified -- waiting 30s before retry ..."
                    Start-Sleep -Seconds 30
                }
            }
            if (-not $verified) {
                Write-Warn "Auto-verification timed out. Re-run with -StartAtStep 4 after DNS propagation (up to 72h)."
            }
        }
    }

    Write-OK 'Step 4 complete.'
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 5 -- VALIDATE
# ------------------------------------------------------------------------------

if ($StartAtStep -le 5 -and $StopAfterStep -ge 5) {
    Write-Banner 'STEP 5 -- Validate SBC, Routes and Policies'

    $validationPassed = $true

    Write-Step 'Checking SBC gateway exists ...'
    $gw = Get-CsOnlinePSTNGateway -Identity $cfg.SbcFqdn -ErrorAction SilentlyContinue
    if (-not $gw) {
        Write-Err "  SBC '$($cfg.SbcFqdn)' was not found in Teams. Please re-run from Step 2."; $validationPassed = $false
    } else {
        $enabledState = if ($gw.Enabled) { 'Enabled' } else { 'Disabled (expected -- will be enabled by Toggle at Step 10)' }
        Write-OK "  $($cfg.SbcFqdn) -- $enabledState"
    }

    Write-Step 'Checking voice routes ...'
    if (Get-CsOnlineVoiceRoute -Identity $cfg.RouteName -ErrorAction SilentlyContinue) { Write-OK "  Route '$($cfg.RouteName)' exists." }
    else { Write-Err "  Voice route '$($cfg.RouteName)' was not found. Please re-run from Step 3."; $validationPassed = $false }

    Write-Step 'Checking voice routing policy ...'
    if (Get-CsOnlineVoiceRoutingPolicy -Identity $cfg.PolicyName -ErrorAction SilentlyContinue) { Write-OK "  Policy exists." }
    else { Write-Err "  Voice routing policy '$($cfg.PolicyName)' was not found. Please re-run from Step 3."; $validationPassed = $false }

    if (-not $validationPassed) { Write-Err 'Some configuration items need attention (see above). Please review and re-run with -StartAtStep 2.'; Exit-Script 1 }

    Write-OK 'Step 5 complete -- all validations passed.'
    if (-not (Confirm-Continue 'Ready to proceed to Step 6?')) { Exit-Script 0 }
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 6 -- UPLOAD DR NUMBERS
# ------------------------------------------------------------------------------

if ($StartAtStep -le 6 -and $StopAfterStep -ge 6) {
    Write-Banner 'STEP 6 -- Upload Direct Routing Phone Numbers (sourced from D365)'

    $drNumbers = @($cfg.ResourceAccounts | ForEach-Object { [string]$_.PhoneNumber })
    Write-Step "Uploading $($drNumbers.Count) DR number(s) ..."
    Write-Info "Numbers: $($drNumbers -join ', ')"

    foreach ($num in $drNumbers) {
        try {
            New-CsOnlineDirectRoutingTelephoneNumberUploadOrder -TelephoneNumber $num | Out-Null
            Write-OK "  Uploaded: $num"
        } catch {
            Write-Warn "  $num -- failed or already exists: $_"
        }
    }

    Write-Step 'Verifying numbers as Unassigned DirectRouting (polling up to 2 min) ...'
    $maxWaitSec   = 120
    $pollInterval = 10
    $elapsed      = 0
    $pending      = @($drNumbers)
    while ($pending.Count -gt 0 -and $elapsed -lt $maxWaitSec) {
        $unassigned = @(Get-CsPhoneNumberAssignment -NumberType DirectRouting -PstnAssignmentStatus Unassigned |
                        Select-Object -ExpandProperty TelephoneNumber)
        $ready      = @($pending | Where-Object { $_ -in $unassigned })
        foreach ($num in $ready) { Write-OK "  $num -- ready" }
        $pending    = @($pending | Where-Object { $_ -notin $unassigned })
        if ($pending.Count -eq 0) { break }
        Write-Info "  Waiting ${pollInterval}s for $($pending.Count) number(s) to propagate ..."
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval
    }
    if ($pending.Count -gt 0) {
        Write-Warn "$($pending.Count) number(s) did not appear in Teams after ${maxWaitSec}s: $($pending -join ', ')"
        Write-Warn "Teams provisioning may still be in progress. Continuing -- re-run with -StartAtStep 6 if Step 9 fails."
    }

    Write-OK 'Step 6 complete.'
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 7 -- CREATE RESOURCE ACCOUNTS
# ------------------------------------------------------------------------------

$raObjectIds = @{}

if ($StartAtStep -le 7 -and $StopAfterStep -ge 7) {
    Write-Banner 'STEP 7 -- Create Resource Accounts (RAs) as TPE'

    $total = @($cfg.ResourceAccounts).Count
    Write-Step "Creating $total resource account(s) ..."
    $idx = 0

    foreach ($ra in $cfg.ResourceAccounts) {
        $idx++
        Write-Step "  [$idx/$total] $($ra.UPN) ..."
        if ($DryRun) {
            Write-Info "  (DRY RUN) Would call: New-CsOnlineApplicationInstance -UserPrincipalName '$($ra.UPN)' -DisplayName '$($ra.DisplayName)'"
            continue
        }
        try {
            $existing = Get-CsOnlineApplicationInstance -Identity $ra.UPN -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Warn "  Already exists -- using existing ObjectId."
                $raObjectIds[$ra.UPN] = [string]$existing.ObjectId
            } else {
                $newRA = New-CsOnlineApplicationInstance `
                    -UserPrincipalName $ra.UPN `
                    -DisplayName       $ra.DisplayName `
                    -ApplicationId     $cfg.DynamicsAppId 6>$null
                $raObjectIds[$ra.UPN] = [string]$newRA.ObjectId
                Write-OK "  Created -- ObjectId: $($newRA.ObjectId)"
            }
            $objectId = $raObjectIds[$ra.UPN]
            $stamped  = $false
            for ($i = 1; $i -le 5; $i++) {
                try {
                    Set-CsOnlineApplicationInstance `
                        -Identity      $objectId `
                        -ApplicationId $cfg.DynamicsAppId `
                        -AcsResourceId $cfg.AcsResourceId `
                        -ErrorAction Stop 6>$null | Out-Null
                    $stamped = $true; break
                } catch {
                    if ($i -lt 5) {
                        Write-Info "  Still setting up, retrying in 15s (attempt $i of 5) ..."
                        Start-Sleep 15
                    }
                }
            }
            Write-OK "  $($ra.UPN) -- ObjectId: $objectId$(if ($stamped) { ' [stamped]' } else { ' [stamp failed -- will retry on next run]' })"
        } catch {
            Write-Err "  Could not create resource account for $($ra.UPN): $($_.Exception.Message)"
        }
    }

    # NOTE: Sync-CsOnlineApplicationInstance runs after Step 9 (phone number assignment).
    # Running it here without a number assigned does nothing useful in D365 -- D365 still
    # shows ACS because there is no number-to-Teams binding to propagate yet.

    if (-not $DryRun) {
        Backup-JsonFile -Path '.\ra-objectids.json'
        $raObjectIds | ConvertTo-Json | Set-Content '.\ra-objectids.json' -Encoding UTF8
    }
    Write-OK 'Step 7 complete. ObjectIds saved to ra-objectids.json'
    $raUpns = @($cfg.ResourceAccounts | ForEach-Object { $_.UPN })
    Wait-UntilRAsReady -Upns $raUpns -MaxSeconds 180 -PollInterval 10
} else {
    if (Test-Path '.\ra-objectids.json') {
        $loaded = Get-Content '.\ra-objectids.json' -Raw | ConvertFrom-Json
        $loaded.PSObject.Properties | ForEach-Object {
            $raObjectIds[$_.Name] = if ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { $_.Value }
        }
        Write-Info "Loaded $($raObjectIds.Count) ObjectId(s) from ra-objectids.json"
    } else {
        foreach ($ra in $cfg.ResourceAccounts) {
            $existing = Get-CsOnlineApplicationInstance -Identity $ra.UPN -ErrorAction SilentlyContinue
            if ($existing) { $raObjectIds[$ra.UPN] = $existing.ObjectId }
            else { Write-Err "Could not find the resource account for $($ra.UPN). Please re-run Step 7 to recreate it." }
        }
    }
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 8 -- ASSIGN LICENSES
# ------------------------------------------------------------------------------

if ($StartAtStep -le 8 -and $StopAfterStep -ge 8) {
    Write-Banner 'STEP 8 -- Assign Teams Phone Resource Account Licenses'

    if (-not $skuId) {
        $sku   = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER' }
        $skuId = if ($sku) { $sku.SkuId } else { $null }
    }
    if (-not $skuId) {
        Write-Err 'The Teams Phone Resource Account license plan was not found. Please add it in Microsoft 365 Admin Center, then re-run with -StartAtStep 8.'
        Exit-Script 1
    }
    Write-OK "SKU ID: $skuId"

    foreach ($ra in $cfg.ResourceAccounts) {
        $objectId = $raObjectIds[$ra.UPN]
        if (-not $objectId) { Write-Err "Could not find the resource account for $($ra.UPN) -- skipping license assignment. Re-run Step 7 to recreate it."; continue }
        Write-Step "Assigning license -> $($ra.UPN) (UsageLocation: $UsageLocation) ..."
        Update-MgUser -UserId $objectId -UsageLocation $UsageLocation | Out-Null
        Set-MgUserLicense -UserId $objectId `
            -AddLicenses @(@{ SkuId = $skuId; DisabledPlans = @() }) `
            -RemoveLicenses @() | Out-Null
        Write-OK "  License assigned."
    }

    Write-Step 'Polling for license provisioning completion ...'
    $maxWaitSec   = 300
    $pollInterval = 15
    $elapsed      = 0
    $pendingUPNs  = @($cfg.ResourceAccounts | Where-Object { $raObjectIds[$_.UPN] } | ForEach-Object { $_.UPN })

    while ($pendingUPNs.Count -gt 0 -and $elapsed -lt $maxWaitSec) {
        $stillPending = @()
        foreach ($upn in $pendingUPNs) {
            $objectId = $raObjectIds[$upn]
            if (-not $objectId) { continue }
            $mgUser   = Get-MgUser -UserId $objectId -Property AssignedLicenses -ErrorAction SilentlyContinue
            $hasLic   = $mgUser -and ($mgUser.AssignedLicenses | Where-Object { $_.SkuId -eq $skuId })
            if ($hasLic) { Write-OK "  $upn -- license provisioned" }
            else { $stillPending += $upn }
        }
        $pendingUPNs = $stillPending
        if ($pendingUPNs.Count -eq 0) { break }
        Write-Info "  $($pendingUPNs.Count) UPN(s) still provisioning -- waiting ${pollInterval}s ..."
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval
    }
    if ($pendingUPNs.Count -gt 0) {
        Write-Warn "License provisioning still in progress for: $($pendingUPNs -join ', ')"
        Write-Warn "Phone number assignment (Step 9) may fail -- re-run with -StartAtStep 9 if needed."
    }

    Write-OK 'Step 8 complete.'
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 9 -- ASSIGN PHONE NUMBERS
# ------------------------------------------------------------------------------

$results = @()
$script:step11Failed = @()

if ($StartAtStep -le 9 -and $StopAfterStep -ge 9) {
    Write-Banner 'STEP 9 -- Assign Direct Routing Phone Numbers to RAs'

    $total = @($cfg.ResourceAccounts).Count
    $idx   = 0

    foreach ($ra in $cfg.ResourceAccounts) {
        $idx++
        Write-Host ""
        Write-Host "  [$idx/$total] $($ra.DisplayName) | $($ra.UPN) | $($ra.PhoneNumber)" -ForegroundColor White

        $status   = 'OK'
        $errMsg   = $null
        $objectId = $raObjectIds[$ra.UPN]

        try {
            $existingAssign = Get-CsPhoneNumberAssignment `
                -TelephoneNumber $ra.PhoneNumber `
                -ErrorAction SilentlyContinue
            if ($existingAssign -and $existingAssign.AssignedPstnTargetId) {
                Write-Info "  Number $($ra.PhoneNumber) already assigned to $($existingAssign.AssignedPstnTargetId) -- removing first."
                Remove-CsPhoneNumberAssignment `
                    -Identity        $existingAssign.AssignedPstnTargetId `
                    -PhoneNumber     $ra.PhoneNumber `
                    -PhoneNumberType DirectRouting `
                    -ErrorAction Stop
                Write-Info "  Prior assignment removed."
            }
        } catch {
            Write-Warn "  Could not remove prior assignment for $($ra.PhoneNumber): $_"
        }

        $assigned = $false
        for ($attempt = 1; $attempt -le 6; $attempt++) {
            try {
                Set-CsPhoneNumberAssignment `
                    -Identity        $ra.UPN `
                    -PhoneNumber     $ra.PhoneNumber `
                    -PhoneNumberType DirectRouting `
                    -ErrorAction Stop
                Write-OK "  Assigned $($ra.PhoneNumber) -> $($ra.UPN)"
                $assigned = $true
                break
            } catch {
                $errMsg = $_.Exception.Message
                if ($errMsg -match '(?i)license|provisioning|not\s+found') {
                    if ($attempt -lt 6) {
                        Write-Info "  License still activating (attempt $attempt/6) -- waiting 30s ..."
                        Wait-WithMessage -Seconds 30 -Reason 'license activation'
                    } else {
                        $status = 'InProgress'
                        Write-Warn "  License still not ready after 6 attempts. Re-run with -StartAtStep 9."
                    }
                } else {
                    $status = 'Pending'
                    Write-Err "  Phone number could not be assigned to $($ra.UPN): $($errMsg -replace '\r?\n.*','')"
                    break
                }
            }
        }

        $results += [PSCustomObject]@{
            DisplayName = $ra.DisplayName
            UPN         = $ra.UPN
            PhoneNumber = $ra.PhoneNumber
            ObjectId    = $objectId
            D365Name    = if ($ra.PSObject.Properties['D365Name']) { $ra.D365Name } else { '' }
            Status      = $status
            Error       = $errMsg
        }
    }

    if (-not $DryRun) {
        $results | Export-Csv $OutputPath -NoTypeInformation
        Write-Host ""
        Write-Host "  Results written to: $OutputPath" -ForegroundColor Cyan
    }
    $results | Format-Table DisplayName, UPN, PhoneNumber, Status -AutoSize

    $failed     = @($results | Where-Object { $_.Status -eq 'Pending' })
    $inProgress = @($results | Where-Object { $_.Status -eq 'InProgress' })
    if ($failed.Count -gt 0)     { Write-Warn "$($failed.Count) number(s) could not be assigned. Re-run with -StartAtStep 9." }
    if ($inProgress.Count -gt 0) { Write-Warn "$($inProgress.Count) number(s) still being processed -- re-run with -StartAtStep 9 in a few minutes." }
    if ($failed.Count -eq 0 -and $inProgress.Count -eq 0) { Write-OK "All $($results.Count) number(s) assigned successfully." }

    # BACKUP D365 phone records BEFORE Sync-CsOnlineApplicationInstance destroys them.
    # Sync recreates the D365 record as Teams DR. Without this backup, undo cannot restore
    # the original CSAC-visible state (e.g. BYON ACS numbers disappear after undo).
    Write-Step "Backing up D365 phone number states before sync (for undo restore) ..."
    $d365BackupDir  = Split-Path $ConfigPath
    $d365BackupPath = if ($d365BackupDir) { Join-Path $d365BackupDir 'd365-phone-backup.json' } else { '.\d365-phone-backup.json' }
    if ($DryRun) {
        Write-Info "(DRY RUN) Would query D365 and back up phone states to $d365BackupPath"
    } else {
    try {
        $bkpTokenJson = az account get-access-token --resource $cfg.D365OrgUrl --tenant $cfg.TenantId 2>&1
        $bkpToken     = ($bkpTokenJson | ConvertFrom-Json).accessToken
        if ($bkpToken) {
            $bkpHdrs = @{
                Authorization      = "Bearer $bkpToken"
                Accept             = "application/json"
                "OData-MaxVersion" = "4.0"
                "OData-Version"    = "4.0"
            }
            $backup = @{}
            foreach ($ra in $cfg.ResourceAccounts) {
                $num        = $ra.PhoneNumber
                $numEncoded = $num -replace '\+', '%2B'
                # Query WITHOUT statecode filter to capture inactive records too
                $bkpUri = ($cfg.D365OrgUrl.TrimEnd('/') +
                           "/api/data/v9.2/msdyn_ocphonenumbers" +
                           "?`$select=msdyn_ocphonenumberid,msdyn_phonenumber,msdyn_ocphonenumbersource," +
                           "msdyn_teamsresourceaccount,statecode,statuscode,msdyn_type,msdyn_phonenumbertype," +
                           "msdyn_countryisocode,msdyn_phoneoutboundenabled,msdyn_phoneinboundenabled," +
                           "msdyn_smsoutboundenabled,msdyn_smsinboundenabled,msdyn_objective,msdyn_appmodule," +
                           "_msdyn_carrierid_value,_msdyn_occommunicationprovidersettingid_value,msdyn_name" +
                           "&`$filter=msdyn_phonenumber eq '$numEncoded'&`$orderby=statecode asc&`$top=1")
                try {
                    $bkpR = Invoke-RestMethod -Uri $bkpUri -Headers $bkpHdrs -Method Get
                    if ($bkpR.value -and $bkpR.value.Count -gt 0) {
                        $backup[$num] = $bkpR.value[0]
                        Write-Info "  Backed up D365 record for $num (statecode=$($bkpR.value[0].statecode), source=$($bkpR.value[0].msdyn_ocphonenumbersource))"
                    } else {
                        Write-Info "  No D365 record found for $num -- will be created fresh by Sync."
                    }
                } catch {
                    Write-Warn "  Could not back up D365 record for $num : $($_.Exception.Message -replace '\r?\n.*','')"
                }
            }
            $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $d365BackupPath -Encoding UTF8
            Write-OK "D365 phone states backed up to $d365BackupPath ($($backup.Count) record(s))."
        } else {
            Write-Warn "  Could not get D365 token for backup -- undo will use fallback field values."
        }
    } catch {
        Write-Warn "  D365 backup failed: $($_.Exception.Message -replace '\r?\n.*','') -- undo will use fallback values."
    }
    } # end DryRun else block

    # Sync TPE binding to D365 NOW -- phone numbers are assigned so D365 will see Teams, not ACS.
    # This is what flips D365 from "ACS for Telephony" to "Teams" for each number.
    Write-Step "Syncing TPE application instances to D365 (post-number-assignment) ..."
    foreach ($ra in $cfg.ResourceAccounts) {
        # Always resolve ObjectId live from Teams -- ra-objectids.json may have a stale value
        # from a prior run, causing Sync to silently target the wrong RA and D365 to stay on ACS.
        $liveRA   = Get-CsOnlineApplicationInstance -Identity $ra.UPN -ErrorAction SilentlyContinue
        $objectId = if ($liveRA) {
            [string]$liveRA.ObjectId
        } elseif ($raObjectIds[$ra.UPN]) {
            Write-Warn "  Live lookup failed for $($ra.UPN) -- falling back to cached ObjectId."
            $raObjectIds[$ra.UPN]
        } else {
            $null
        }
        if (-not $objectId) { Write-Warn "  No ObjectId for $($ra.UPN) -- skipping sync."; continue }
        Write-Info "  ObjectId: $objectId$(if ($liveRA) { ' (live)' } else { ' (cached)' })"
        if ($DryRun) { Write-Info "  (DRY RUN) Would call: Sync-CsOnlineApplicationInstance -ObjectId $objectId"; continue }
        try {
            $syncResult = Sync-CsOnlineApplicationInstance `
                -ObjectId      $objectId `
                -ApplicationId $cfg.DynamicsAppId `
                -AcsResourceId $cfg.AcsResourceId `
                -ErrorAction Stop
            if ($syncResult) { Write-Info "  Sync response: $($syncResult | ConvertTo-Json -Compress)" }
            Write-OK "  Synced: $($ra.UPN) (ObjectId: $objectId)"
        } catch {
            Write-Warn "  Sync failed for $($ra.UPN): $($_.Exception.Message -replace '\r?\n.*','')"
            Write-Warn "  Re-run with -StartAtStep 9 -StopAfterStep 9 after a few minutes to retry."
        }
    }

    # Post-sync D365 verification: query msdyn_ocphonenumbers to confirm D365 sees the
    # correct telephony provider.  msdyn_teleprovider values: 1=None 2=ACS 3=Teams/DR
    if ($DryRun) {
        Write-Info "(DRY RUN) Would verify D365 phone number state post-sync."
    } else {
    Write-Step "Verifying D365 phone number state post-sync ..."
    try {
        $tokenJson2  = az account get-access-token --resource $cfg.D365OrgUrl --tenant $cfg.TenantId 2>&1
        $d365Token2  = ($tokenJson2 | ConvertFrom-Json).accessToken
        if ($d365Token2) {
            $d365Hdrs2 = @{
                Authorization      = "Bearer $d365Token2"
                Accept             = "application/json"
                "OData-MaxVersion" = "4.0"
                "OData-Version"    = "4.0"
            }
            foreach ($ra in $cfg.ResourceAccounts) {
                $num = $ra.PhoneNumber
                # URL-encode + as %2B so D365 OData filter does not treat it as a space
                $numEncoded = $num -replace '\+', '%2B'
                # msdyn_teamsresourceaccount = Teams RA ObjectId when Telephony = Teams, null when ACS.
                # msdyn_ocphonenumbersource  = 192350001 (Teams DR) or 192350000 (ACS).
                $uri = ($cfg.D365OrgUrl.TrimEnd('/') +
                        "/api/data/v9.2/msdyn_ocphonenumbers" +
                        "?`$select=msdyn_name,msdyn_phonenumber,msdyn_teamsresourceaccount,msdyn_ocphonenumbersource,statecode,statuscode" +
                        "&`$filter=msdyn_phonenumber eq '$numEncoded'")
                try {
                    $r = Invoke-RestMethod -Uri $uri -Headers $d365Hdrs2 -Method Get
                    if ($r.value -and $r.value.Count -gt 0) {
                        $rec = $r.value[0]
                        $teamsRa  = $rec.msdyn_teamsresourceaccount
                        $src      = $rec.msdyn_ocphonenumbersource
                        $srcLabel = switch ($src) { 192350001 { 'Teams DR' } 192350000 { 'ACS' } $null { '(null)' } default { "unknown($src)" } }
                        if ($teamsRa) {
                            Write-OK  "  D365 Telephony=Teams  teamsRA=$teamsRa  source=$srcLabel"
                        } else {
                            Write-Warn "  D365 Telephony=ACS  teamsRA=(empty)  source=$srcLabel -- Sync did not link a Teams RA."
                        }
                    } else {
                        Write-Warn "  D365: phone number $num not found in msdyn_ocphonenumbers."
                    }
                } catch {
                    Write-Warn "  D365 query failed for $num : $($_.Exception.Message -replace '\r?\n.*','')"
                }
            }
        } else {
            Write-Warn "  Could not acquire D365 token for post-sync verification -- skipping."
        }
    } catch {
        Write-Warn "  D365 post-sync verification failed: $($_.Exception.Message -replace '\r?\n.*','')"
    }
    }

    Write-OK 'Step 9 complete.'
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 10 -- CUTOVER: Toggle ACS -> Teams
# ------------------------------------------------------------------------------

if ($StartAtStep -le 10 -and $StopAfterStep -ge 10) {
    Write-Banner 'STEP 10 -- Cut Over to Teams' 'Runs Toggle-AcsTeamsRouting-v14.ps1 -- disables ACS, enables Teams gateway'

    Write-Host ""
    Write-Host "  CURRENT STATE:" -ForegroundColor DarkCyan
    Write-Host "    ACS trunk     : enabled=true  (handling live calls)" -ForegroundColor Green
    Write-Host "    Teams gateway : Enabled=`$false (ready, not yet active)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  CUTOVER CHECKLIST (complete before proceeding):" -ForegroundColor Gray
    Write-Host "  [ ] All Steps 1-9 validated and signed off" -ForegroundColor Gray
    Write-Host "  [ ] End-to-end call routing tested in sandbox/staging" -ForegroundColor Gray
    Write-Host "  [ ] Maintenance window confirmed with customer" -ForegroundColor Gray
    Write-Host "  [ ] SBC admin available and on call" -ForegroundColor Gray
    Write-Host ""

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would run: .\Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath '$ConfigPath'" -ForegroundColor Yellow
    } else {
        if (-not (Confirm-Continue 'Ready to cut over to Teams? This will disable the ACS trunk and enable the Teams gateway.')) {
            Write-Host "  Cutover skipped. Re-run with -StartAtStep 10 when ready." -ForegroundColor Yellow
            Exit-Script 0
        }

        Write-Step "Running Toggle-AcsTeamsRouting-v14.ps1 ..."
        & "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -ConfigPath $ConfigPath -AutoConfirm

        if ($LASTEXITCODE -ne 0) {
            Write-Err "Toggle script exited with code $LASTEXITCODE. Check output above and re-run with -StartAtStep 10."
            Exit-Script 1
        }

        Write-OK "Step 10 complete -- Teams is now active."
        Write-Host ""
        Write-Host "  TO ROLL BACK at any time:" -ForegroundColor Yellow
        Write-Host "    Run Toggle-AcsTeamsRouting-v14.ps1 -- it auto-detects direction." -ForegroundColor Gray
        Write-Host "    ACS trunk will be re-enabled, Teams gateway will be disabled." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Proceed to Step 11 to update D365 phone number types and sync." -ForegroundColor DarkCyan
    }
}

#endregion

#region -----------------------------------------------------------------------
#  STEP 11 -- D365 PHONE TYPE UPDATE + SYNC (per number, ACS -> TPS)
# ------------------------------------------------------------------------------

if ($StartAtStep -le 11 -and $StopAfterStep -ge 11) {
    Write-Banner 'STEP 11 -- Update D365 Phone Number Types and Sync' 'Calls Invoke-MigrateTpsPhoneNumber-v14.ps1 for each number (ACS -> TPS)'

    Write-Host ""
    Write-Host "  Numbers to migrate:" -ForegroundColor Gray
    foreach ($ra in $cfg.ResourceAccounts) {
        Write-Host ("    " + $ra.PhoneNumber.PadRight(20) + "->  " + $ra.UPN) -ForegroundColor Cyan
    }
    Write-Host ""

    $migrateScript = "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1"
    if (-not (Test-Path $migrateScript)) {
        Write-Err "Invoke-MigrateTpsPhoneNumber-v14.ps1 not found at: $migrateScript"
        Exit-Script 1
    }

    $total   = @($cfg.ResourceAccounts).Count
    $idx     = 0
    $script:step11Failed = @()

    foreach ($ra in $cfg.ResourceAccounts) {
        $idx++
        $phoneNumber = $ra.PhoneNumber
        $objectId    = if ($raObjectIds -and $raObjectIds[$ra.UPN]) { $raObjectIds[$ra.UPN] } else { $null }
        Write-Step "[$idx/$total] Migrating $phoneNumber ..."
        if ($objectId) {
            Write-Info "  RA ObjectId: $objectId (will be set explicitly in PATCH)"
        } else {
            Write-Warn "  RA ObjectId not found in ra-objectids.json for $($ra.UPN) -- relying on async CCaaS sync to link RA."
        }

        $invokeArgs = @{
            OrgUrl      = $cfg.D365OrgUrl
            PhoneNumber = $phoneNumber
            Direction   = 'ACS_TO_TPS'
        }
        if ($objectId) { $invokeArgs['TeamsResourceAccountObjectId'] = $objectId }
        if ($DryRun)   { $invokeArgs['DryRun'] = $true }

        & $migrateScript @invokeArgs

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "  [$phoneNumber] Invoke-MigrateTpsPhoneNumber returned exit code $LASTEXITCODE. Will continue with remaining numbers."
            $script:step11Failed += $phoneNumber
        } else {
            Write-OK "  [$phoneNumber] D365 type updated$(if ($objectId) { ' and RA linked' } else { ' and sync triggered' })."
        }
        Write-Host ""
    }

    if ($script:step11Failed.Count -gt 0) {
        Write-Warn "$($script:step11Failed.Count) number(s) failed D365 migration:"
        foreach ($f in $script:step11Failed) { Write-Host "    $f" -ForegroundColor Yellow }
        Write-Warn "Re-run with -StartAtStep 11 -StopAfterStep 11 to retry failed numbers."
    } else {
        Write-OK "Step 11 complete -- all $total number(s) submitted for D365 type update and sync."
        Write-Host "  NOTE: CCaaS_SynchronizePhoneNumbers is async. Allow a few minutes for D365 UI to reflect changes." -ForegroundColor DarkCyan
    }
    Write-Host ""
    Write-Host "  POST-CUTOVER checklist:" -ForegroundColor Yellow
    Write-Host "  [ ] D365 CSAC -> Channels -> Phone numbers: verify type = Teams Phone System" -ForegroundColor Gray
    Write-Host "  [ ] Test inbound call routing end-to-end" -ForegroundColor Gray
    Write-Host "  [ ] Keep ACS resource active 24-48h as rollback path" -ForegroundColor Gray
    Write-Host "  [ ] Decommission ACS only after full TPE validation" -ForegroundColor Gray
}

#endregion

#region -----------------------------------------------------------------------
#  FINAL SUMMARY
# ------------------------------------------------------------------------------

Write-Host ""
Write-Host "+==================================================================+" -ForegroundColor Green
Write-Host "|                                                                  |" -ForegroundColor Green
Write-Host "|  Migration Scripted Steps: COMPLETE  (v14.15.0)                   |" -ForegroundColor Green
Write-Host "|  Step 10: Toggle (cutover)  Step 11: D365 type update + sync     |" -ForegroundColor Green
Write-Host "|                                                                  |" -ForegroundColor Green
Write-Host ("|  Results CSV     : " + $OutputPath.PadRight(46) + "|") -ForegroundColor Green
Write-Host "|  ACS Export      : .\acs-export.json                             |" -ForegroundColor Green
Write-Host "|  RA ObjectIds    : .\ra-objectids.json                           |" -ForegroundColor Green
Write-Host "|  FQDN list       : .\acs-trunk-disabled.json                     |" -ForegroundColor Green
Write-Host "|                                                                  |" -ForegroundColor Green
if ($StopAfterStep -lt 10) {
Write-Host "|  NEXT: Step 10 runs Toggle. Step 11 updates D365 + syncs.        |" -ForegroundColor Green
}
Write-Host "+==================================================================+" -ForegroundColor Green
Write-Host ""

$htmlConsoleSummary = @"
<span class="green">+==================================================================+</span>
<span class="green">|  Migration Scripted Steps: COMPLETE (v14.15.0)                    |</span>
<span class="green">|  Step 10: Toggle (cutover)  Step 11: D365 type update + sync     |</span>
<span class="green">|  Results CSV     : $($OutputPath.PadRight(46))|</span>
<span class="green">|  HTML Log        : $($script:HtmlLogPath.PadRight(46))|</span>
$(if ($StopAfterStep -lt 10) { '<span class="green">|  NEXT: Step 10 runs Toggle. Step 11 updates D365 + syncs.        |</span>' })
<span class="green">+==================================================================+</span>
"@
Add-Content -Path $script:HtmlLogPath -Value $htmlConsoleSummary -Encoding UTF8

Write-Host "  HTML log saved: $script:HtmlLogPath" -ForegroundColor Cyan
Write-Host "  Open with: Start-Process $script:HtmlLogPath" -ForegroundColor DarkGray
Write-Host ""

# Build step summary HTML footer
$stepInfo = @{ 1='Export ACS trunks -> acs-export.json'; 2='Register Teams gateway (zero-downtime)'; 3='Create PSTN usage, voice route, routing policy'; 4='Register domain in Entra ID'; 5='Validate SBC gateway + routes + policies'; 6='Upload DR phone numbers to Teams'; 7='Create Resource Accounts (RAs)'; 8='Assign PHONESYSTEM_VIRTUALUSER licenses'; 9='Assign DR phone numbers + D365 backup/sync'; 10='Toggle-AcsTeamsRouting (cutover ACS -> Teams)'; 11='Invoke-MigrateTpsPhoneNumber per number (D365 type ACS->TPS + sync)' }
$stepRows = ''
foreach ($sn in 1..11) {
    $ran = ($sn -ge $StartAtStep -and $sn -le $StopAfterStep)
    $st  = if ($ran) { '<span style="color:#4ec94e">&#10003; RAN</span>' } else { '<span style="color:#444">&mdash; SKIPPED</span>' }
    $stepRows += "<tr$(if (-not $ran) { ' style=''opacity:0.4''' })><td style='padding:4px 10px;color:#666;white-space:nowrap'>Step $sn</td><td style='padding:4px 10px;color:#ccc'>$($stepInfo[$sn])</td><td style='padding:4px 10px;white-space:nowrap'>$st</td></tr>`n"
}
$numsList = (($cfg.ResourceAccounts | ForEach-Object { $_.PhoneNumber }) -join ', ') -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
$htmlFooter = @"
<div style="margin-top:20px;border-top:1px solid #333;padding-top:16px;font-family:Consolas,'Courier New',monospace;font-size:12px">
<div style="color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px">Step Summary</div>
<table style="width:100%;border-collapse:collapse">
<tr style="background:#252526"><th style="text-align:left;padding:6px 10px;color:#555;font-size:10px;text-transform:uppercase">Step</th><th style="text-align:left;padding:6px 10px;color:#555;font-size:10px;text-transform:uppercase">Action</th><th style="text-align:left;padding:6px 10px;color:#555;font-size:10px;text-transform:uppercase;white-space:nowrap">Status</th></tr>
$stepRows</table>
<div style="margin-top:10px;color:#888">Numbers: <span style="color:#d4d4d4">$numsList</span> &nbsp;|&nbsp; <a href="tpe-status.html" style="color:#00bfff">Open Dashboard</a></div>
</div>
"@

# Write run record + update dashboard (v12: actual result based on step outcomes)
$phoneNums     = @($cfg.ResourceAccounts | ForEach-Object { $_.PhoneNumber })
$failedCount   = @($results | Where-Object { $_.Status -eq 'Pending' }).Count + $(if ($script:step11Failed) { $script:step11Failed.Count } else { 0 })
$inProgCount   = @($results | Where-Object { $_.Status -eq 'InProgress' }).Count
$migrateResult = if ($failedCount -gt 0) { 'FAIL' } elseif ($inProgCount -gt 0) { 'WARN' } else { 'OK' }
$runType = if ($StopAfterStep -ge 10) { 'migrate' } else { 'migrate-partial' }
Write-TpeRunRecord -Type $runType -PhoneNums $phoneNums -Result $migrateResult `
    -Completed (@($results | Where-Object { $_.Status -eq 'OK' }).Count) `
    -Failures $failedCount
Update-TpeStatusDashboard
Write-Host "  Open with: Start-Process .\tpe-status.html" -ForegroundColor DarkGray

Exit-Script 0 -FooterHtml $htmlFooter

#endregion
