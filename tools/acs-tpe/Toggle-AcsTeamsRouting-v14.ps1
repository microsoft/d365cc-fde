#Requires -Version 5.1
<#
.SYNOPSIS
    Toggle SIP routing between ACS Direct Routing and Teams Direct Routing
    for a shared SBC FQDN. Auto-detects current direction and asks Y/N to proceed.

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.9.0    : Fix-AcsRoutePattern and Update-PhoneNumberType console banner
                 version strings corrected (were v14.6.0), migration HTML title
                 version added, README sections added for 5 missing scripts,
                 version strings bumped to v14.9.0.
    v14.8.0    : Dashboard state skips FAIL results when determining active system
                 (prevents misleading state after failed operation), Test-DomainRegistration
                 DryRun no longer sets $verified=$true (shows accurate DryRun behavior),
                 version strings bumped to v14.8.0.
    v14.6.0    : Update-PhoneNumberType msdyn_ocphonenumbersource parity + DryRun + sync,
                 Fix-AcsRoutePattern parameterized (no hardcoded FQDN/pattern) + DryRun,
                 Add-AcsTrunkDisabled DryRun switch, Set-AcsSbcFqdn blank FQDN validation,
                 Archive-TpeRuns Sort-Object dedup fix, Invoke-TeamsPhoneSync GUID validation,
                 version strings bumped to v14.6.0.
    v14.5.0    : $acsActive/$teamsActive null-as-active fix (-ne $false → -eq $true),
                 version strings bumped to v14.5.0.
    v14.4.0    : All exit paths use Exit-Script (HTML log closure guaranteed),
                 Write-TpeRunRecord on toggle error paths (failed toggles
                 appear in dashboard), version strings bumped to v14.4.0.
    v14.3.0    : Dashboard version parity (v14.2.0 → v14.3.0), HTML log for
                 state display, version strings bumped to v14.3.0.
    v14.2.0    : HTML run log added, stats/tpe-runs.jsonl record written,
                 tpe-status.html dashboard updated on completion, -AutoConfirm
                 parameter for non-interactive use (e.g. called from Step 10),
                 explicit exit 0 at end.
    v14.0.0    : Compatible with v10 migration (no ACS consent step).

.DESCRIPTION
    Reads live state from ACS and Teams, determines current routing direction,
    and offers to flip to the other side.

    AUTO-DETECT:
      - ACS enabled + Teams disabled  => current=ACS, will switch to TPE
      - Teams enabled + ACS disabled  => current=TPE, will switch to ACS
      - Both enabled / neither active => error -- cannot determine direction

    ACS -> TPE (cutover):
      1. Save current ACS routes from GET response
      2. PATCH: routes:[] + enabled:false  (one atomic call -- avoids HTTP 422)
      3. Wait 15s for ACS disable propagation
      4. Set-CsOnlinePSTNGateway -Enabled $true
      5. On Teams failure: restore routes + enabled:true, exit 1

    TPE -> ACS (rollback):
      1. Load routes from .\acs-export.json (falls back to [] if missing)
      2. Set-CsOnlinePSTNGateway -Enabled $false
      3. On Teams failure: exit 1  (ACS already disabled -- nothing to restore)
      4. PATCH: routes:[loaded] + enabled:true  (one atomic call)

.PARAMETER ConfigPath
    Path to acs-tpe-config-fromd365-local.json.
    Must contain: AcsConnectionString, SbcFqdn, TenantId, AdminUpn.

.PARAMETER Fqdn
    The shared SBC FQDN. Overrides SbcFqdn from config if provided.

.PARAMETER TenantId
    Entra ID Tenant ID. Overrides config if provided.

.PARAMETER AdminUpn
    Teams Admin UPN. Overrides config if provided.

.PARAMETER AutoConfirm
    Skip the Y/N confirmation prompt. Used when called from Step 10
    (the migration script already confirms before invoking Toggle).

.PARAMETER DryRun
    Show what would change without making any changes.

.EXAMPLE
    # Dry run -- check current state, no changes
    .\Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -DryRun

    # Cut over to TPE (or roll back to ACS) -- auto-detects direction, asks Y/N
    .\Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = '',
    [string]$Fqdn       = '',
    [string]$TenantId   = '',
    [string]$AdminUpn   = '',
    [switch]$AutoConfirm,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# HTML LOG SETUP
# ---------------------------------------------------------------------------

$script:HtmlLogPath = ".\tpe-toggle-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ACS TPE Toggle v14.11.0 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
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

function Exit-Script {
    param([int]$Code = 0, [string]$FooterHtml = '')
    try { Add-Content -Path $script:HtmlLogPath -Value "</pre>$FooterHtml</body></html>" -Encoding UTF8 } catch {}
    exit $Code
}

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
    } catch {}
}

# ---------------------------------------------------------------------------
# Run record + status dashboard (parity with Flip/Migration scripts)
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
        $html = "<!DOCTYPE html><html><head><meta charset=`"UTF-8`"><meta http-equiv=`"refresh`" content=`"60`"><title>ACS TPE Migration Status</title><style>*{box-sizing:border-box}body{background:#1e1e1e;color:#d4d4d4;font-family:Consolas,'Courier New',monospace;font-size:13px;padding:24px;margin:0}h1{color:#00bfff;font-size:16px;margin:0 0 2px 0}.sub{color:#555;font-size:11px;margin:0 0 20px 0}.state{border-left:4px solid $stateColor;background:#252526;padding:14px 18px;margin:16px 0;border-radius:0 4px 4px 0}.state .lbl{font-size:14px;font-weight:bold;color:$stateColor;margin-bottom:4px}.state .meta{color:#888;font-size:12px}.cards{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}.card{background:#252526;border:1px solid #333;border-radius:4px;padding:12px 16px;min-width:130px;text-align:center}.card .n{font-size:22px;font-weight:bold;margin-bottom:2px}.card .l{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:1px}table{width:100%;border-collapse:collapse}th{background:#252526;color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;padding:7px 10px;text-align:left;border-bottom:1px solid #333}td{padding:6px 10px;border-bottom:1px solid #222;font-size:12px}tr:hover td{background:#252526}a{color:#00bfff;text-decoration:none}a:hover{text-decoration:underline}.sh{color:#555;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin:20px 0 6px 0;border-bottom:1px solid #2a2a2a;padding-bottom:5px}.foot{margin-top:24px;color:#333;font-size:11px}</style></head><body><h1>ACS TPE Migration Status</h1><div class=`"sub`">v14.11.0 &nbsp;|&nbsp; $d365Url &nbsp;|&nbsp; Auto-refresh: 60s</div><div class=`"state`"><div class=`"lbl`">$stateLabel</div><div class=`"meta`">Last action: $lastTime &nbsp;|&nbsp; Numbers: $lastNums</div></div><div class=`"cards`"><div class=`"card`"><div class=`"n`" style=`"color:#d4d4d4`">$total</div><div class=`"l`">Total Runs</div></div><div class=`"card`"><div class=`"n`" style=`"color:#00bfff`">$migCount</div><div class=`"l`">Migrate</div></div><div class=`"card`"><div class=`"n`" style=`"color:#ff6b6b`">$undoCount</div><div class=`"l`">Undo</div></div></div><div class=`"sh`">Run History (last 30)</div><table><tr><th>Timestamp</th><th>Type</th><th>Steps</th><th>Numbers</th><th>Result</th><th>Log</th></tr>$rows</table><div class=`"foot`">Generated $generated &nbsp;|&nbsp; ACS TPE v14.11.0 &nbsp;|&nbsp; stats/tpe-runs.jsonl</div></body></html>"
        Set-Content -Path $dashPath -Value $html -Encoding UTF8
        Write-Host "  Status dashboard: $dashPath" -ForegroundColor DarkGray
    } catch {}
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Info { param([string]$m) Write-Host "  -- $m" -ForegroundColor Gray; Write-HtmlLine "  -- $m" 'Gray' }
function Write-Step { param([string]$m) Write-Host "  >> $m" -ForegroundColor Cyan; Write-HtmlLine "  >> $m" 'Cyan' }
function Write-OK   { param([string]$m) Write-Host "  OK $m" -ForegroundColor Green; Write-HtmlLine "  OK $m" 'Green' }
function Write-Warn { param([string]$m) Write-Host "  WARN $m" -ForegroundColor Yellow; Write-HtmlLine "  WARN $m" 'Yellow' }
function Write-Err  { param([string]$m) Write-Host "  ! $m" -ForegroundColor Red; Write-HtmlLine "  ! $m" 'Red' }

function Wait-WithMessage {
    param([int]$Seconds, [string]$Reason)
    if ($DryRun) { Write-Info "(DRY RUN) Would wait ${Seconds}s -- $Reason"; return }
    Write-Host "  -- Waiting ${Seconds}s -- $Reason " -ForegroundColor Gray -NoNewline
    for ($i = 0; $i -lt $Seconds; $i++) {
        Start-Sleep -Seconds 1
        if (($i+1) % 10 -eq 0) { Write-Host "$($i+1)s" -ForegroundColor DarkGray -NoNewline }
        else { Write-Host '.' -ForegroundColor DarkGray -NoNewline }
    }
    Write-Host " done." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
if ($ConfigPath) {
    if (-not (Test-Path $ConfigPath)) { Write-Err "Config not found: $ConfigPath"; Exit-Script 1 }
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $TenantId -and $cfg.PSObject.Properties['TenantId']) { $TenantId = $cfg.TenantId }
    if (-not $AdminUpn -and $cfg.PSObject.Properties['AdminUpn'])  { $AdminUpn = $cfg.AdminUpn }
    if (-not $Fqdn     -and $cfg.PSObject.Properties['SbcFqdn'])   { $Fqdn     = $cfg.SbcFqdn }
} else {
    Write-Err "Please provide -ConfigPath."; Exit-Script 1
}

if (-not $Fqdn)     { $Fqdn     = (Read-Host "  SBC FQDN").Trim() }
if (-not $TenantId) { $TenantId = (Read-Host "  Tenant ID").Trim() }
if (-not $AdminUpn) { $AdminUpn = (Read-Host "  Admin UPN").Trim() }

# Parse ACS connection string
if (-not $cfg.PSObject.Properties['AcsConnectionString'] -or -not $cfg.AcsConnectionString) {
    Write-Err "AcsConnectionString missing from config."; Exit-Script 1
}
$acsConn = @{}
$cfg.AcsConnectionString.Split(';') | ForEach-Object {
    $kv = $_ -split '=', 2
    if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
}
$acsEp   = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
$acsKey  = if ($acsConn['accesskey']) { $acsConn['accesskey'] } else { '' }
if (-not $acsEp -or -not $acsKey) {
    Write-Err "Could not parse ACS endpoint or access key from connection string. Check AcsConnectionString in config."; Exit-Script 1
}
$apiVer  = '2023-04-01-preview'
$pq      = "/sip?api-version=$apiVer"
$apiUrl  = "$acsEp$pq"
$apiHost = ([System.Uri]$apiUrl).Host
$EMPTY   = '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='

function Invoke-AcsGet {
    $date   = [System.DateTime]::UtcNow.ToString('r')
    $keyB   = [System.Convert]::FromBase64String($acsKey)
    $toSign = "GET`n$pq`n$date;$apiHost;$EMPTY"
    $hmac   = [System.Security.Cryptography.HMACSHA256]::new($keyB)
    try {
        $sig    = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
    } finally {
        $hmac.Dispose()
    }
    $hdrs   = @{
        'x-ms-date'           = $date
        'x-ms-content-sha256' = $EMPTY
        'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
    }
    Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $hdrs
}

function Invoke-AcsPatch([string]$body) {
    $date     = [System.DateTime]::UtcNow.ToString('r')
    $keyB     = [System.Convert]::FromBase64String($acsKey)
    $sha256   = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bodyHash = [System.Convert]::ToBase64String($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($body)))
    } finally {
        $sha256.Dispose()
    }
    $toSign   = "PATCH`n$pq`n$date;$apiHost;$bodyHash"
    $hmac     = [System.Security.Cryptography.HMACSHA256]::new($keyB)
    try {
        $sig      = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
    } finally {
        $hmac.Dispose()
    }
    $hdrs     = @{
        'x-ms-date'           = $date
        'x-ms-content-sha256' = $bodyHash
        'Authorization'       = "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=$sig"
        'Content-Type'        = 'application/merge-patch+json'
    }
    Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $hdrs -Body $body
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host "|   ACS <-> Teams Routing Toggle  v14.11.0  (auto-detect)         |" -ForegroundColor Cyan
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host "  FQDN      : $Fqdn" -ForegroundColor White
Write-Host "  Tenant    : $TenantId" -ForegroundColor White
Write-Host "  Mode      : $(if ($DryRun) { 'DRY RUN' } else { 'LIVE' })" -ForegroundColor Yellow
Write-Host ""

# ---------------------------------------------------------------------------
# Connect to Teams
# ---------------------------------------------------------------------------
Write-Step "Connecting to Microsoft Teams ..."
try {
    Connect-MicrosoftTeams -TenantId $TenantId -ErrorAction Stop | Out-Null
    Write-OK "Teams connected."
} catch {
    Write-Err "Could not connect to Microsoft Teams. Please check your credentials and try again."
    Exit-Script 1
}

# ---------------------------------------------------------------------------
# Read current state from ACS
# ---------------------------------------------------------------------------
Write-Step "Reading ACS Direct Routing state ..."
$acsTrunk   = $null
$acsEnabled = $null
$sipData    = $null
try {
    $sipData   = Invoke-AcsGet
    $trunkProp = $sipData.trunks.PSObject.Properties | Where-Object { $_.Name -eq $Fqdn }
    if ($trunkProp) {
        $acsTrunk   = $trunkProp.Value
        $acsEnabled = if ($trunkProp.Value.PSObject.Properties['enabled']) { [bool]$trunkProp.Value.enabled } else { $true }
    }
} catch {
    Write-Warn "Could not read ACS state. ACS trunk will show as NOT FOUND."
}

# Capture current ACS routes (needed for ACS->TPE save + TPE->ACS restore)
$acsCurrentRoutes = @()
if ($null -ne $sipData) {
    try {
        if ($sipData.PSObject.Properties['routes']) {
            $acsCurrentRoutes = @($sipData.routes)
        }
    } catch {}
}

# ---------------------------------------------------------------------------
# Read current state from Teams
# ---------------------------------------------------------------------------
Write-Step "Reading Teams Direct Routing state ..."
$teamsGw      = $null
$teamsEnabled = $null
try {
    $teamsGw = Get-CsOnlinePSTNGateway -Identity $Fqdn -ErrorAction SilentlyContinue
    if ($teamsGw) { $teamsEnabled = [bool]$teamsGw.Enabled }
} catch {
    Write-Warn "Could not read Teams gateway state."
}

# ---------------------------------------------------------------------------
# Display current state
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host "  |  Current State                                           |" -ForegroundColor DarkGray
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
Write-HtmlLine "" 'DarkGray'
Write-HtmlLine "  Current State" 'DarkGray'

if ($null -eq $acsTrunk) {
    Write-Host "  |  ACS   : $Fqdn" -ForegroundColor Gray
    Write-Host "  |          => NOT FOUND" -ForegroundColor DarkGray
    Write-HtmlLine "  ACS   : $Fqdn => NOT FOUND" 'DarkGray'
} else {
    $acsLabel = if ($acsEnabled) { 'ENABLED  <-- active' } else { 'DISABLED' }
    $acsColor = if ($acsEnabled) { 'Green' } else { 'DarkGray' }
    Write-Host "  |  ACS   : $Fqdn" -ForegroundColor White
    Write-Host "  |          => $acsLabel" -ForegroundColor $acsColor
    Write-HtmlLine "  ACS   : $Fqdn => $acsLabel" $acsColor
}

if ($null -eq $teamsGw) {
    Write-Host "  |  Teams : $Fqdn" -ForegroundColor Gray
    Write-Host "  |          => NOT FOUND in Teams Direct Routing" -ForegroundColor DarkGray
    Write-HtmlLine "  Teams : $Fqdn => NOT FOUND" 'DarkGray'
} else {
    $teamsLabel = if ($teamsEnabled) { 'ENABLED  <-- active' } else { 'DISABLED' }
    $teamsColor = if ($teamsEnabled) { 'Green' } else { 'DarkGray' }
    Write-Host "  |  Teams : $Fqdn" -ForegroundColor White
    Write-Host "  |          => $teamsLabel" -ForegroundColor $teamsColor
    Write-HtmlLine "  Teams : $Fqdn => $teamsLabel" $teamsColor
}

$acsActive   = ($null -ne $acsTrunk) -and ($acsEnabled   -eq $true)
$teamsActive = ($null -ne $teamsGw)  -and ($teamsEnabled  -eq $true)

Write-Host "  |" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Auto-detect direction
# ---------------------------------------------------------------------------
if ($acsActive -and $teamsActive) {
    Write-Host "  |  Active routing : BOTH ENABLED -- conflict" -ForegroundColor Red
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Err "Both ACS and Teams are enabled at the same time. Please disable one side manually before using this script."
    Exit-Script 1
}

if ($null -eq $acsTrunk -and $null -eq $teamsGw) {
    Write-Host "  |  Active routing : NOT FOUND on either side" -ForegroundColor Red
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Err "FQDN '$Fqdn' was not found in either ACS or Teams. Nothing to toggle."
    Exit-Script 1
}

if (-not $acsActive -and -not $teamsActive) {
    Write-Host "  |  Active routing : NEITHER ACTIVE -- no routing in effect" -ForegroundColor Red
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Err "Neither ACS nor Teams is currently enabled. Cannot auto-detect direction. Please check the config and try again."
    Exit-Script 1
}

# Current mode and intended target
$currentMode = if ($acsActive) { 'ACS' } else { 'TPE (Teams)' }
$targetMode  = if ($acsActive) { 'TPE (Teams)' } else { 'ACS' }
$targetLabel = if ($acsActive) { 'TPE' } else { 'ACS' }

Write-Host "  |  Active routing : $currentMode  -->  will switch to: $targetLabel" -ForegroundColor Yellow
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------------------
# Guard: target side must exist
# ---------------------------------------------------------------------------
if ($targetLabel -eq 'ACS' -and $null -eq $acsTrunk) {
    Write-Err "Cannot switch to ACS -- FQDN '$Fqdn' does not exist as an ACS trunk. Add it first."
    Exit-Script 1
}
if ($targetLabel -eq 'TPE' -and $null -eq $teamsGw) {
    Write-Err "Cannot switch to TPE -- FQDN '$Fqdn' does not exist as a Teams PSTN gateway. Add it first."
    Exit-Script 1
}

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
if ($DryRun) {
    Write-Info "(DRY RUN) Would switch routing from $currentMode to $targetLabel. Showing planned steps only."
    Write-Host ""
} elseif ($AutoConfirm) {
    Write-Info "AutoConfirm: proceeding with toggle from $currentMode to $targetLabel."
} else {
    $confirm = (Read-Host "  Proceed? Switch from $currentMode to $targetLabel [Y/n]").Trim()
    if ($confirm -ne '' -and $confirm -notmatch '^[Yy]') {
        Write-Info "Cancelled. No changes made."
        Exit-Script 0
    }
}

Write-Host ""
Write-Step "Switching from $currentMode to $targetLabel ..."

# ---------------------------------------------------------------------------
# ACS -> TPE (cutover)
# ---------------------------------------------------------------------------
if ($acsActive) {
    $acsSipPort = [int]$acsTrunk.sipSignalingPort

    # Determine saved routes from the live GET response
    $savedRoutes = $acsCurrentRoutes
    Write-Info "Saved $($savedRoutes.Count) ACS route(s) from live state."

    # Persist routes to acs-export.json so TPE->ACS rollback can restore them
    $acsExportPath = '.\acs-export.json'
    if ($DryRun) {
        Write-Info "(DRY RUN) Would persist $($savedRoutes.Count) route(s) to $acsExportPath"
    } else {
        try {
            [ordered]@{ trunks = $sipData.trunks; routes = $savedRoutes } |
                ConvertTo-Json -Depth 6 | Set-Content $acsExportPath -Encoding UTF8
            Write-Info "Routes persisted to $acsExportPath for future rollback."
        } catch {
            Write-Warn "Could not write $acsExportPath -- rollback will need routes restored manually."
        }
    }

    # Step 1: Atomic PATCH -- clear routes + disable trunk
    Write-Info "ACS: disabling trunk and clearing routes (atomic PATCH) ..."
    if ($DryRun) {
        Write-Info "(DRY RUN) Would PATCH ACS trunk '$Fqdn' => routes:[], enabled:false"
    } else {
        try {
            $disableBody = [ordered]@{
                trunks = [ordered]@{ $Fqdn = [ordered]@{ sipSignalingPort = $acsSipPort; enabled = $false } }
                routes = @()
            } | ConvertTo-Json -Depth 6 -Compress
            Invoke-AcsPatch $disableBody | Out-Null
            Write-OK "ACS trunk disabled and routes cleared."
        } catch {
            $errDetail = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { ($_.Exception.Message -split '\r?\n')[0] }
            Write-Err "Could not disable ACS trunk ($errDetail). No changes were made."
            $toggleType = if ($acsActive) { 'toggle-to-tpe' } else { 'toggle-to-acs' }
            Write-TpeRunRecord -Type $toggleType -PhoneNums @() -Result 'FAIL' -Failures 1
            Exit-Script 1
        }
    }

    # Step 2: Wait for propagation
    Wait-WithMessage -Seconds 15 -Reason 'ACS disable propagation'

    # Step 3: Enable Teams gateway
    Write-Info "Teams: enabling gateway '$Fqdn' ..."
    if ($DryRun) {
        Write-Info "(DRY RUN) Would call: Set-CsOnlinePSTNGateway -Identity '$Fqdn' -Enabled `$true"
    } else {
        try {
            Set-CsOnlinePSTNGateway -Identity $Fqdn -Enabled $true -ErrorAction Stop 6>$null | Out-Null
            Write-OK "Teams gateway '$Fqdn' enabled."
        } catch {
            $errMsg = $_.Exception.Message -replace '\r?\n.*', ''
            Write-Err "Could not enable Teams gateway: $errMsg"
            Write-Warn "Attempting to restore ACS trunk (routes + enabled:true) ..."
            try {
                $restoreBody = [ordered]@{
                    trunks = [ordered]@{ $Fqdn = [ordered]@{ sipSignalingPort = $acsSipPort; enabled = $true } }
                    routes = $savedRoutes
                } | ConvertTo-Json -Depth 6 -Compress
                Invoke-AcsPatch $restoreBody | Out-Null
                Write-Warn "ACS trunk restored (routes + enabled:true). No routing change was made."
            } catch {
                Write-Err "ACS trunk restore also failed. ACS trunk is currently DISABLED. Please re-enable it manually in the ACS portal."
            }
            $toggleType = if ($acsActive) { 'toggle-to-tpe' } else { 'toggle-to-acs' }
            Write-TpeRunRecord -Type $toggleType -PhoneNums @() -Result 'FAIL' -Failures 1
            Exit-Script 1
        }
    }
}

# ---------------------------------------------------------------------------
# TPE -> ACS (rollback)
# ---------------------------------------------------------------------------
else {
    # Step 1: Load routes from acs-export.json
    $restoredRoutes = @()
    $acsExportPath  = '.\acs-export.json'
    if (Test-Path $acsExportPath) {
        try {
            $exp = Get-Content $acsExportPath -Raw | ConvertFrom-Json
            $restoredRoutes = @($exp.routes)
            Write-Info "Loaded $($restoredRoutes.Count) route(s) from acs-export.json for ACS restore."
        } catch {
            Write-Warn "Could not parse acs-export.json -- will re-enable ACS trunk without routes."
        }
    } else {
        Write-Warn "acs-export.json not found -- will re-enable ACS trunk without routes."
    }

    # Determine ACS port (trunk exists but may be disabled; fall back to config)
    $acsSipPort = if ($null -ne $acsTrunk -and $acsTrunk.PSObject.Properties['sipSignalingPort']) {
        [int]$acsTrunk.sipSignalingPort
    } elseif ($cfg.PSObject.Properties['SbcPort'] -and $cfg.SbcPort) {
        [int]$cfg.SbcPort
    } else { 5075 }

    # Step 2: Disable Teams gateway
    Write-Info "Teams: disabling gateway '$Fqdn' ..."
    if ($DryRun) {
        Write-Info "(DRY RUN) Would call: Set-CsOnlinePSTNGateway -Identity '$Fqdn' -Enabled `$false"
    } else {
        try {
            Set-CsOnlinePSTNGateway -Identity $Fqdn -Enabled $false -ErrorAction Stop 6>$null | Out-Null
            Write-OK "Teams gateway '$Fqdn' disabled."
        } catch {
            $errMsg = $_.Exception.Message -replace '\r?\n.*', ''
            Write-Err "Could not disable Teams gateway: $errMsg"
            Write-Info "ACS trunk was not modified. No routing change was made."
            $toggleType = if ($acsActive) { 'toggle-to-tpe' } else { 'toggle-to-acs' }
            Write-TpeRunRecord -Type $toggleType -PhoneNums @() -Result 'FAIL' -Failures 1
            Exit-Script 1
        }
    }

    # Step 3: Atomic PATCH -- re-enable ACS trunk + restore routes
    Write-Info "ACS: re-enabling trunk and restoring routes (atomic PATCH) ..."
    if ($DryRun) {
        Write-Info "(DRY RUN) Would PATCH ACS trunk '$Fqdn' => routes:[$($restoredRoutes.Count) route(s)], enabled:true"
    } else {
        try {
            $enableBody = [ordered]@{
                trunks = [ordered]@{ $Fqdn = [ordered]@{ sipSignalingPort = $acsSipPort; enabled = $true } }
                routes = $restoredRoutes
            } | ConvertTo-Json -Depth 6 -Compress
            Invoke-AcsPatch $enableBody | Out-Null
            Write-OK "ACS trunk re-enabled with $($restoredRoutes.Count) route(s) restored."
        } catch {
            $errDetail = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { ($_.Exception.Message -split '\r?\n')[0] }
            Write-Err "Could not re-enable ACS trunk ($errDetail)."
            Write-Warn "Attempting to re-enable Teams gateway to restore routing ..."
            try {
                Set-CsOnlinePSTNGateway -Identity $Fqdn -Enabled $true -ErrorAction Stop 6>$null | Out-Null
                Write-Warn "Teams gateway re-enabled. Routing restored to TPE. Please fix ACS trunk manually."
            } catch {
                Write-Err "Teams re-enable also failed. NEITHER side is active. Please enable one manually."
            }
            $toggleType = if ($acsActive) { 'toggle-to-tpe' } else { 'toggle-to-acs' }
            Write-TpeRunRecord -Type $toggleType -PhoneNums @() -Result 'FAIL' -Failures 1
            Exit-Script 1
        }
    }
}

# ---------------------------------------------------------------------------
# Show new state
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host "  |  New State                                               |" -ForegroundColor DarkGray
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray

if ($DryRun) {
    $newAcsEnabled   = if ($targetLabel -eq 'ACS')  { $true } else { $false }
    $newTeamsEnabled = if ($targetLabel -eq 'TPE')  { $true } else { $false }
} else {
    try {
        $sipData2      = Invoke-AcsGet
        $tp2           = $sipData2.trunks.PSObject.Properties | Where-Object { $_.Name -eq $Fqdn }
        $newAcsEnabled = if ($tp2 -and $tp2.Value.PSObject.Properties['enabled']) { [bool]$tp2.Value.enabled } else { $true }
    } catch { $newAcsEnabled = $null }
    try {
        $gw2             = Get-CsOnlinePSTNGateway -Identity $Fqdn -ErrorAction SilentlyContinue
        $newTeamsEnabled = if ($gw2) { [bool]$gw2.Enabled } else { $null }
    } catch { $newTeamsEnabled = $null }
}

$fmtAcs   = if ($null -eq $newAcsEnabled)   { 'N/A' } elseif ($newAcsEnabled)   { 'ENABLED  <-- active' } else { 'DISABLED' }
$fmtTeams = if ($null -eq $newTeamsEnabled) { 'N/A' } elseif ($newTeamsEnabled) { 'ENABLED  <-- active' } else { 'DISABLED' }
$colAcs   = if ($newAcsEnabled)   { 'Green' } else { 'DarkGray' }
$colTeams = if ($newTeamsEnabled) { 'Green' } else { 'DarkGray' }

Write-Host "  |  ACS   : $Fqdn" -ForegroundColor White
Write-Host "  |          => $fmtAcs" -ForegroundColor $colAcs
Write-Host "  |  Teams : $Fqdn" -ForegroundColor White
Write-Host "  |          => $fmtTeams" -ForegroundColor $colTeams
Write-Host "  |" -ForegroundColor DarkGray
Write-Host "  |  Active routing : $targetLabel" -ForegroundColor Green
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host ""
Write-OK "Toggle complete. Routing is now: $targetLabel"
Write-HtmlLine ""
Write-HtmlLine "  New State: ACS=$fmtAcs  Teams=$fmtTeams" 'Green'
Write-HtmlLine "  Active routing: $targetLabel" 'Green'
Write-Host ""
Write-Host "  HTML log saved: $script:HtmlLogPath" -ForegroundColor DarkGray

# Write run record + update dashboard
$toggleType = if ($targetLabel -eq 'TPE') { 'toggle-to-tpe' } else { 'toggle-to-acs' }
Write-TpeRunRecord -Type $toggleType -PhoneNums @() -Result 'OK' -Completed 1
Update-TpeStatusDashboard

Exit-Script 0
