#Requires -Version 5.1
<#
.SYNOPSIS
    Undo / Rollback script for ACS -> Teams TPE migration. v14

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v10 change  : Removed Step 11 undo (ACS teamsExtension consent) — no longer required.
    v14.20.0    : Three undo correctness fixes — (1) acs-export.json trunks field is a
                dict (FQDN as keys), not an array; iterate PSObject.Properties to parse
                correctly. (2) Step 2 now only removes cfg.SbcFqdn (the gateway created
                by the migration) and skips any gateway that existed before migration
                (present in acs-export.json). Previously all exported trunks were removed.
                (3) Step 3 now only removes cfg.RouteName (the route created by the
                migration). Previously all 7 routes from acs-export.json were deleted,
                wiping pre-existing ACS voice routes. Version bump.
    v14.20.0    : Invoke-AcsTrunkPatch try-catch added, D365 restore failure now
                increments undoFailures counter, HTML footer phone numbers XSS-escaped,
                error message null guard (Split→-split), version bump.
    v14.9.0     : Fix-AcsRoutePattern and Update-PhoneNumberType console banner
                version strings corrected (were v14.6.0), migration HTML title
                version added, README sections added for 5 missing scripts,
                version strings bumped to v14.9.0.
    v14.8.0     : Version string parity across ALL 18 scripts, Update-PhoneNumberType
                provider array bounds check, Undo summary box alignment fix,
                version strings bumped to v14.8.0.
    v14.7.0     : Dashboard state skips FAIL results when determining active system
                (prevents misleading state after failed operation), Test-DomainRegistration
                DryRun no longer sets $verified=$true (shows accurate DryRun behavior),
                version strings bumped to v14.7.0.
    v14.6.0     : Update-PhoneNumberType msdyn_ocphonenumbersource parity + DryRun + sync,
                Fix-AcsRoutePattern parameterized (no hardcoded FQDN/pattern) + DryRun,
                Add-AcsTrunkDisabled DryRun switch, Set-AcsSbcFqdn blank FQDN validation,
                Archive-TpeRuns Sort-Object dedup fix, Invoke-TeamsPhoneSync GUID validation,
                version strings bumped to v14.6.0.
    v14.5.0     : HTML failure-list XSS escaping in undo summary footer,
                version strings bumped to v14.5.0.
    v14.4.0     : Exit-Script parity for Toggle (raw exit→Exit-Script),
                FlipToACS/FlipToTeams -Failed→-Failures param fix,
                FlipToTeams Write-Err function added, version bump.
    v14.3.0     : Dashboard sub-header version parity (v14.1.0 → v14.3.0),
                version strings bumped to v14.3.0.
    v14.2.0     : Dashboard recognizes toggle-to-tpe/toggle-to-acs run types,
                version strings bumped to v14.2.0.
    v14.1.0     : Final consistency pass — .NOTES version corrected
                (Version 9 → Version 14), dashboard sub-headers bumped to
                v14.1.0, README aligned.
    v14.0.8     : Dashboard $esc null guard for null phoneNumbers (strict-mode
                safe), Undo Step 2 single-FQDN @() wrapping, version strings
                bumped to v14.0.8.
    v14.0.7     : Write-TpeRunRecord D365OrgUrl PSObject.Properties guard (prevents
                silent run-record loss in StrictMode), dashboard HTML-escape for
                phone numbers / URLs / log paths (XSS hardening), undo summary
                now displays "Already removed" count, version strings bumped to
                v14.0.7.
    v14.0.6     : Write-Step/Write-OK/Write-Info prefix parity with migration
                script (>> / OK / --), Write-Step $c color parameter added,
                Step 9 msdyn_appmodule fallback changed from '192350000' to
                $null for Step 6 parity, Step 9 msdyn_objective fallback
                changed from 192350000 to $null for Step 6 parity,
                .DESCRIPTION explains Step 5/10/11 omission, version strings
                bumped to v14.0.6.
    v14.0.5     : Dashboard stateLabel handles flip-teams/flip-acs types,
                dashboard row HTML handles all 4 run types, version strings
                bumped to v14.0.5.
    v14.0.3     : #Requires -Version 5.1 added, Write-Banner $Sub parity with
                migration script, exit code 1 on FAIL result, dashboard versions
                updated to v14.0.3.
    v14 fixes   : Version strings corrected to v14, HMAC Dispose(), Invoke-Undo
                counting fix, D365OrgUrl null guard, connection string null guards,
                Write-HtmlLine try/catch parity with migration script.
    Reverses Steps 1-9 in reverse order.

.DESCRIPTION
    Undo order (high to low):
      Step  9 - Remove phone number assignments
      Step  8 - Remove PHONESYSTEM_VIRTUALUSER licenses
      Step  7 - Remove resource accounts
      Step  6 - Remove DR phone numbers
      Step  4 - Remove registered domain from Entra ID
      Step  3 - Remove voice routing policy, routes, PSTN usage
      Step  2 - Remove PSTN Gateways (SBCs) and ensure ACS trunk is re-enabled
      Step  1 - Backup acs-export.json (file kept for reference)
    Steps 5, 10, 11 have no undo action (Step 5 is read-only validation,
    Steps 10-11 are reversed by Invoke-FlipToACS-v14.ps1).

.NOTES
    Generated by AI (Claude Sonnet 4.6) with human oversight.
    Review all steps carefully before running in production.
    Version 14: Removed Step 11 (ACS teamsExtension consent). HTML log footer on every exit,
    step-range validated, magenta CSS class, live-mode confirmation prompt, ACS endpoint GUID guard,
    ACS key prompt when missing.

.PARAMETER ConfigPath
    Path to the acs-tpe-config.json used during migration.

.PARAMETER DryRun
    Show what would be removed without making any changes.

.PARAMETER StartAtStep
    Undo from a specific step downward (default: 9).

.PARAMETER StopAfterStep
    Stop undoing at this step (do not go below it).
    e.g. -StartAtStep 9 -StopAfterStep 9 undoes ONLY Step 9.

.EXAMPLE
    .\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -DryRun
    .\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json
    .\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -StartAtStep 9
    .\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365.json -StartAtStep 9 -StopAfterStep 7
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [switch]$DryRun,
    [ValidateRange(1, 9)][int]$StartAtStep  = 9,
    [ValidateRange(1, 9)][int]$StopAfterStep = 1,
    [switch]$AutoConfirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Step-range validation (v12) -- undo goes high-to-low
# ---------------------------------------------------------------------------

if ($StartAtStep -lt $StopAfterStep) {
    Write-Host "  ! -StartAtStep ($StartAtStep) cannot be less than -StopAfterStep ($StopAfterStep)." -ForegroundColor Red
    Write-Host "  For Undo, steps run high-to-low (e.g. -StartAtStep 9 -StopAfterStep 1)." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Run tracking
# ---------------------------------------------------------------------------

$script:undoCompleted      = @()
$script:undoSkipped        = @()
$script:undoFailures       = @()
$script:undoAlreadyRemoved = @()

# ---------------------------------------------------------------------------
# HTML LOG SETUP
# ---------------------------------------------------------------------------

$script:HtmlLogPath = ".\tpe-undo-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ACS TPE Migration UNDO v14.20.0 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
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
        $html = "<!DOCTYPE html><html><head><meta charset=`"UTF-8`"><meta http-equiv=`"refresh`" content=`"60`"><title>ACS TPE Migration Status</title><style>*{box-sizing:border-box}body{background:#1e1e1e;color:#d4d4d4;font-family:Consolas,'Courier New',monospace;font-size:13px;padding:24px;margin:0}h1{color:#00bfff;font-size:16px;margin:0 0 2px 0}.sub{color:#555;font-size:11px;margin:0 0 20px 0}.state{border-left:4px solid $stateColor;background:#252526;padding:14px 18px;margin:16px 0;border-radius:0 4px 4px 0}.state .lbl{font-size:14px;font-weight:bold;color:$stateColor;margin-bottom:4px}.state .meta{color:#888;font-size:12px}.cards{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}.card{background:#252526;border:1px solid #333;border-radius:4px;padding:12px 16px;min-width:130px;text-align:center}.card .n{font-size:22px;font-weight:bold;margin-bottom:2px}.card .l{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:1px}table{width:100%;border-collapse:collapse}th{background:#252526;color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;padding:7px 10px;text-align:left;border-bottom:1px solid #333}td{padding:6px 10px;border-bottom:1px solid #222;font-size:12px}tr:hover td{background:#252526}a{color:#00bfff;text-decoration:none}a:hover{text-decoration:underline}.sh{color:#555;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin:20px 0 6px 0;border-bottom:1px solid #2a2a2a;padding-bottom:5px}.foot{margin-top:24px;color:#333;font-size:11px}</style></head><body><h1>ACS TPE Migration Status</h1><div class=`"sub`">v14.20.0 &nbsp;|&nbsp; $d365Url &nbsp;|&nbsp; Auto-refresh: 60s</div><div class=`"state`"><div class=`"lbl`">$stateLabel</div><div class=`"meta`">Last action: $lastTime &nbsp;|&nbsp; Numbers: $lastNums</div></div><div class=`"cards`"><div class=`"card`"><div class=`"n`" style=`"color:#d4d4d4`">$total</div><div class=`"l`">Total Runs</div></div><div class=`"card`"><div class=`"n`" style=`"color:#00bfff`">$migCount</div><div class=`"l`">Migrate</div></div><div class=`"card`"><div class=`"n`" style=`"color:#ff6b6b`">$undoCount</div><div class=`"l`">Undo</div></div></div><div class=`"sh`">Run History (last 30)</div><table><tr><th>Timestamp</th><th>Type</th><th>Steps</th><th>Numbers</th><th>Result</th><th>Log</th></tr>$rows</table><div class=`"foot`">Generated $generated &nbsp;|&nbsp; ACS TPE v14.20.0 &nbsp;|&nbsp; stats/tpe-runs.jsonl</div></body></html>"
        Set-Content -Path $dashPath -Value $html -Encoding UTF8
        Write-Host "  Status dashboard: $dashPath" -ForegroundColor DarkGray
    } catch {}
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
    try {
        Add-Content -Path $script:HtmlLogPath -Value "<span class=`"$css`">$escaped</span>" -Encoding UTF8
    } catch {
        # HTML log write errors must never crash the undo -- silently ignore
    }
}

function Write-Banner {
    param([string]$Title, [string]$Sub = '', [string]$Color = 'Cyan')
    $line = '-' * 66
    Write-Host ""
    Write-Host $line -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor $Color
    if ($Sub) { Write-Host "  $Sub" -ForegroundColor DarkGray }
    Write-Host $line -ForegroundColor DarkGray
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

function Test-IsIgnorableUndoError {
    param($ErrorRecord)
    $msg = if ($ErrorRecord.Exception.Message) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    return ($msg -match '(?i)\b(not\s+found|cannot\s+find|does\s+not\s+exist|already\s+(been\s+)?removed|could\s+not\s+be\s+found|Identity.*is\s+invalid)\b')
}

function Invoke-Undo {
    param([string]$Description, [scriptblock]$Action)
    Write-Step $Description
    if ($DryRun) { Write-Info "(DRY RUN) skipped."; return }
    try {
        & $Action
        Write-OK "Done."
        $script:undoCompleted += $Description
    }
    catch {
        if (Test-IsIgnorableUndoError $_) {
            Write-Info "Already removed or not found -- nothing to do here."
            $script:undoAlreadyRemoved += $Description
        } else {
            Write-Warn "Could not complete this step automatically. It has been logged for your review -- please check manually if needed."
            $script:undoFailures += $Description
        }
    }
}

# ---------------------------------------------------------------------------
# ACS trunk PATCH helper (reused from Invoke-ACS-TPE-Full-Migration-v14.ps1)
# ---------------------------------------------------------------------------

function Invoke-AcsTrunkPatch {
    param(
        [string]$Fqdn,
        [bool]$Enabled,
        [string]$AcsEp,
        [string]$AcsKey,
        [int]$SipSignalingPort = 0,
        [object[]]$Routes = @()
    )
    if (-not $AcsEp -or -not $AcsKey) { Write-Warn "ACS endpoint or key not available -- skipping trunk patch."; return }
    $pq       = '/sip?api-version=2023-04-01-preview'
    $apiUrl   = "$AcsEp$pq"
    $apiHost  = ([System.Uri]$apiUrl).Host
    $trunkBody = if ($SipSignalingPort -gt 0) { [ordered]@{ sipSignalingPort = $SipSignalingPort; enabled = $Enabled } } else { [ordered]@{ enabled = $Enabled } }
    $body     = [ordered]@{ trunks = [ordered]@{ $Fqdn = $trunkBody }; routes = $Routes } | ConvertTo-Json -Depth 6 -Compress
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
    try {
        Invoke-RestMethod -Uri $apiUrl -Method PATCH -Headers $hdrs -Body $body | Out-Null
    } catch {
        Write-Warn "ACS trunk PATCH failed for $Fqdn : $($_.Exception.Message -replace '\r?\n.*','')"
        throw
    }
}

# ---------------------------------------------------------------------------
# D365 'Sync from Azure' helper
# ---------------------------------------------------------------------------
function Invoke-D365SyncFromAzure {
    param(
        [string]$OrgUrl,
        [string]$Token,
        [string]$AcsEndpoint,
        [string]$CommsProviderId
    )
    if (-not $CommsProviderId -or -not $AcsEndpoint) {
        Write-Warn "  CommsProviderId or AcsEndpoint not set in config -- skipping auto Sync from Azure."
        Write-Warn "  Manually click 'Sync from Azure' on the Manage telephony panel in D365 CSAC."
        return
    }
    Write-Step "Triggering D365 Sync from Azure (msdyn_TelephonyACSSyncPhoneNumbersAction) ..."
    try {
        $resourceName  = ([System.Uri]$AcsEndpoint).Host.Split('.')[0]
        $correlationId = [System.Guid]::NewGuid().ToString()
        $actionReqObj  = [ordered]@{
            ResourceName    = $resourceName
            commsProviderId = $CommsProviderId
            CorrelationId   = $correlationId
        }
        $actionReqStr  = $actionReqObj | ConvertTo-Json -Compress
        $syncBody      = @{ ActionRequest = $actionReqStr } | ConvertTo-Json -Compress
        $syncUri       = "$($OrgUrl.TrimEnd('/'))/api/data/v9.2/msdyn_TelephonyACSSyncPhoneNumbersAction"
        $syncHdrs      = @{
            Authorization      = "Bearer $Token"
            "Content-Type"     = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }
        $syncResult  = Invoke-RestMethod -Uri $syncUri -Method POST -Headers $syncHdrs -Body $syncBody
        $resultStr   = if ($syncResult.ActionResult) { $syncResult.ActionResult } else { '(no ActionResult)' }
        Write-OK "  Sync from Azure triggered. Result: $resultStr"
        Write-Info "  Refresh D365 CSAC browser tab (Ctrl+Shift+R) to see updated phone numbers."
    } catch {
        Write-Warn "  Sync from Azure failed: $($_.Exception.Message -replace '\r?\n.*','')"
        Write-Warn "  Manually click 'Sync from Azure' on the Manage telephony panel in D365 CSAC."
    }
}

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------

if (-not (Test-Path $ConfigPath)) { Write-Host "  ! Config file not found: $ConfigPath. Please check the path and try again." -ForegroundColor Red; Exit-Script 1 }
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "  ACS -> TPE Migration UNDO v14.20.0" -ForegroundColor Red
Write-Host "  Config : $ConfigPath" -ForegroundColor Gray
Write-Host "  Range  : Step $StartAtStep -> Step $StopAfterStep" -ForegroundColor Gray
Write-Host "  Mode   : $(if ($DryRun) { 'DRY RUN' } else { 'LIVE - changes WILL be made' })" `
    -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Red' })
Write-Host ""

Write-HtmlLine ""
Write-HtmlLine "  ACS -> TPE Migration UNDO v14.20.0" 'Red'
Write-HtmlLine "  Config : $ConfigPath" 'Gray'
Write-HtmlLine "  Range  : Step $StartAtStep -> Step $StopAfterStep" 'Gray'
Write-HtmlLine "  Mode   : $(if ($DryRun) { 'DRY RUN' } else { 'LIVE - changes WILL be made' })" `
    $(if ($DryRun) { 'Yellow' } else { 'Red' })
Write-HtmlLine ""

# v10: Live-mode confirmation before destructive changes
if (-not $DryRun -and -not $AutoConfirm) {
    Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "  !!  WARNING: This will DELETE Teams resources (gateways,  !!" -ForegroundColor Red
    Write-Host "  !!  resource accounts, phone assignments, etc.)            !!" -ForegroundColor Red
    Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host ""
    $confirm = (Read-Host "  Type YES to proceed with LIVE undo, or press Enter to abort").Trim()
    if ($confirm -ne 'YES') {
        Write-Host "  Aborted." -ForegroundColor Yellow
        Exit-Script 0
    }
}

# ---------------------------------------------------------------------------
# Backup helper
# ---------------------------------------------------------------------------

function Backup-JsonFile {
    param([string]$Path)
    if (Test-Path $Path) {
        $ts     = Get-Date -Format 'yyyyMMdd-HHmmss'
        $dir    = Split-Path $Path
        $base   = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $ext    = [System.IO.Path]::GetExtension($Path)
        $outDir = if ($dir) { $dir } else { '.' }
        $backup = Join-Path $outDir "${base}-undooperation-${ts}${ext}"
        Copy-Item -Path $Path -Destination $backup
        Write-Info "Backed up $Path -> $backup"
    }
}

# ---------------------------------------------------------------------------
# Step confirmation prompt
# ---------------------------------------------------------------------------

function Confirm-Step {
    param([string]$StepName, [string]$Description)
    if ($DryRun -or $AutoConfirm) { return $true }
    Write-Host ""
    Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  |  CONFIRM: $($StepName.PadRight(51))|" -ForegroundColor Yellow
    Write-Host "  |  $($Description.PadRight(60))|" -ForegroundColor Gray
    Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  [Y] Proceed   [S] Skip this step   [Q] Quit" -ForegroundColor Cyan
    Write-Host ""
    while ($true) {
        $ans = (Read-Host "  Your choice").Trim().ToUpper()
        switch ($ans) {
            'Y' { return $true }
            'S' {
                Write-Host "  Skipped." -ForegroundColor DarkGray
                $script:undoSkipped += $StepName
                return $false
            }
            'Q' { Write-Host "  Aborted by user." -ForegroundColor Red; Exit-Script 0 }
            default { Write-Host "  Enter Y, S, or Q." -ForegroundColor Yellow }
        }
    }
}

# ---------------------------------------------------------------------------
# Resolve ACS endpoint + key
# ---------------------------------------------------------------------------

# v10: removed AcsResourceId fallback (a GUID produces a broken URL like https://aaaa-bbbb-...)
$acsEndpointResolved = if ($cfg.PSObject.Properties['AcsEndpoint'] -and $cfg.AcsEndpoint) { $cfg.AcsEndpoint }
                        elseif ($cfg.PSObject.Properties['AcsResourceName'] -and $cfg.AcsResourceName) { $cfg.AcsResourceName }
                        else { '' }
if ($acsEndpointResolved -and $acsEndpointResolved -notmatch '^https?://') {
    $acsEndpointResolved = "https://$($acsEndpointResolved.TrimEnd('/'))"
} else {
    $acsEndpointResolved = $acsEndpointResolved.TrimEnd('/')
}

$acsKeyResolved = ''
if ($cfg.PSObject.Properties['AcsConnectionString'] -and $cfg.AcsConnectionString) {
    $raw = $cfg.AcsConnectionString
    if ($raw -match '(?i)accesskey=([^;]+)') { $acsKeyResolved = $Matches[1].Trim() }
    else { $acsKeyResolved = $raw }
}

# v10: Prompt for ACS access key when missing and Step 2 is in scope
$needsAcsKey = (-not $acsKeyResolved) -and ($StartAtStep -ge 2 -and $StopAfterStep -le 2)
if ($needsAcsKey -and -not $DryRun) {
    Write-Warn "ACS access key not found in config (connection string missing or incomplete)."
    Write-Warn "Step 2 needs the ACS key to re-enable trunks."
    $manualKey = Read-Host "  Enter ACS Access Key (or press Enter to skip ACS operations)"
    if ($manualKey) {
        $acsKeyResolved = $manualKey.Trim()
        if (-not $acsEndpointResolved -and $cfg.PSObject.Properties['AcsEndpoint'] -and $cfg.AcsEndpoint) {
            $acsEndpointResolved = $cfg.AcsEndpoint.TrimEnd('/')
        }
        Write-OK "ACS key provided."
    } else {
        Write-Warn "No ACS key provided -- ACS trunk re-enable will be skipped."
    }
}

# ---------------------------------------------------------------------------
# Load ObjectIds from ra-objectids.json
# ---------------------------------------------------------------------------

$raObjectIds = @{}
$raObjectIdsPath = Join-Path (Split-Path $ConfigPath) 'ra-objectids.json'
if (-not (Test-Path $raObjectIdsPath)) { $raObjectIdsPath = '.\ra-objectids.json' }
if (Test-Path $raObjectIdsPath) {
    $loaded = Get-Content $raObjectIdsPath -Raw | ConvertFrom-Json
    $loaded.PSObject.Properties | ForEach-Object {
        $raObjectIds[$_.Name] = if ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { $_.Value }
    }
    Write-Info "Loaded $($raObjectIds.Count) ObjectId(s) from ra-objectids.json"
} else {
    Write-Warn "ra-objectids.json not found - will look up ObjectIds from Teams live."
}

# ---------------------------------------------------------------------------
# Connect to Teams and Graph
# ---------------------------------------------------------------------------

Write-Step "Connecting to Microsoft Teams ..."
$tenant = Get-CsTenant -ErrorAction SilentlyContinue
if (-not $tenant) {
    Connect-MicrosoftTeams -TenantId $cfg.TenantId
    $tenant = Get-CsTenant
}
Write-OK "Connected: $($tenant.DisplayName)"

Write-Step "Connecting to Microsoft Graph ..."
Connect-MgGraph -Scopes 'User.ReadWrite.All', 'Directory.ReadWrite.All', 'Domain.ReadWrite.All' -TenantId $cfg.TenantId | Out-Null
Write-OK "Graph connected."

# ---------------------------------------------------------------------------
# Reconstruct ResourceAccounts if needed
# ---------------------------------------------------------------------------

$effectiveRAs = @()

if (@($cfg.ResourceAccounts).Count -gt 0) {
    $effectiveRAs = @($cfg.ResourceAccounts)
    Write-Info "Using $($effectiveRAs.Count) ResourceAccount(s) from config file."
} elseif ($raObjectIds.Count -gt 0) {
    Write-Banner "Reconstructing RA list from ra-objectids.json + Teams"
    Write-Info "$($raObjectIds.Count) UPN(s) found in ra-objectids.json - looking up phone assignments..."

    foreach ($upn in $raObjectIds.Keys) {
        $phoneNumber = $null
        try {
            $assignment = Get-CsPhoneNumberAssignment -AssignedPstnTargetId $raObjectIds[$upn] `
                -ErrorAction SilentlyContinue
            if ($assignment) { $phoneNumber = $assignment.TelephoneNumber }
        } catch {
            Write-Warn "Could not look up phone assignment for $upn -- will try alternate method."
        }

        if (-not $phoneNumber) {
            try {
                $userInfo = Get-CsOnlineUser -Identity $upn -ErrorAction SilentlyContinue
                if ($userInfo -and $userInfo.LineUri) {
                    $phoneNumber = ($userInfo.LineUri -replace '^tel:', '')
                }
            } catch {
                Write-Warn "Could not look up Teams user for $upn -- phone number will be set to blank for undo."
            }
        }

        if ($phoneNumber) {
            Write-Info "  $upn => $phoneNumber"
            $effectiveRAs += [PSCustomObject]@{
                DisplayName = $upn.Split('@')[0]
                UPN         = $upn
                PhoneNumber = $phoneNumber
            }
        } else {
            Write-Info "  $upn => no phone number assigned (already removed or not yet assigned)"
            $effectiveRAs += [PSCustomObject]@{
                DisplayName = $upn.Split('@')[0]
                UPN         = $upn
                PhoneNumber = $null
            }
        }
    }

    Write-Info "Reconstructed $($effectiveRAs.Count) RA(s) for undo operations."
} else {
    Write-Warn "ResourceAccounts is empty and ra-objectids.json not found."
    Write-Warn "Steps 7-9 will be skipped. Only Steps 2-3 (SBC/routes) will run."
}

# ---------------------------------------------------------------------------
# Load acs-export.json
# ---------------------------------------------------------------------------

$acsExportPath = Join-Path (Split-Path $ConfigPath) 'acs-export.json'
if (-not (Test-Path $acsExportPath)) { $acsExportPath = '.\acs-export.json' }
$exportedTrunks = @()
$exportedRoutes = @()
if (Test-Path $acsExportPath) {
    $acsExport = Get-Content $acsExportPath -Raw | ConvertFrom-Json
    # trunks is stored as a dict (FQDN keys) — convert to array of objects with .fqdn property
    $exportedTrunks = @($acsExport.trunks.PSObject.Properties | ForEach-Object {
        [PSCustomObject]@{ fqdn = $_.Name; sipSignalingPort = $_.Value.sipSignalingPort; enabled = $_.Value.enabled }
    })
    $exportedRoutes = @($acsExport.routes)
    Write-Info "Loaded acs-export.json: $($exportedTrunks.Count) trunk(s), $($exportedRoutes.Count) route(s)"
} else {
    Write-Warn "acs-export.json not found - Step 2/3 undo will fall back to config values."
    $exportedTrunks = @([PSCustomObject]@{ fqdn = $cfg.SbcFqdn })
    $exportedRoutes = @([PSCustomObject]@{ name = $cfg.RouteName })
}

# ---------------------------------------------------------------------------
# SKU ID for license removal
# ---------------------------------------------------------------------------

$sku   = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER' }
$skuId = if ($sku) { $sku.SkuId } else { $null }

# ===========================================================================
# UNDO STEPS
# ===========================================================================

# ---------------------------------------------------------------------------
# UNDO STEP 9 - Remove phone number assignments
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 9 -and $StopAfterStep -le 9) {
    Write-Banner 'UNDO STEP 9 - Remove Phone Number Assignments'
    if (Confirm-Step 'UNDO STEP 9' "Remove phone number assignments from $($effectiveRAs.Count) RA(s)") {
        $rasWithPhone = @($effectiveRAs | Where-Object { $_.PhoneNumber })
        if ($rasWithPhone.Count -eq 0) {
            Write-Warn "No RAs with phone numbers to process."
        } else {
            foreach ($ra in $rasWithPhone) {
                $raUpn   = $ra.UPN
                $raPhone = $ra.PhoneNumber
                Invoke-Undo "Remove $raPhone from $raUpn" {
                    Remove-CsPhoneNumberAssignment `
                        -Identity        $raUpn `
                        -PhoneNumber     $raPhone `
                        -PhoneNumberType DirectRouting
                }
            }

            # Restore D365 phone records to pre-migration state.
            # Sync-CsOnlineApplicationInstance in Step 9 destroys the original D365 record and
            # recreates it as Teams DR. The migration now backs up the original state to
            # d365-phone-backup.json. Undo reads that backup and restores ALL fields so the
            # numbers reappear in D365 CSAC exactly as they were before migration.
            Write-Step "Restoring D365 phone number states from pre-migration backup ..."
            $d365BackupDir  = Split-Path $ConfigPath
            $d365BackupPath = if ($d365BackupDir) { Join-Path $d365BackupDir 'd365-phone-backup.json' } else { '.\d365-phone-backup.json' }
            $d365Backup = $null
            if (Test-Path $d365BackupPath) {
                try {
                    $d365Backup = Get-Content $d365BackupPath -Raw | ConvertFrom-Json
                    Write-OK "  Loaded d365-phone-backup.json."
                } catch {
                    Write-Warn "  Could not parse d365-phone-backup.json -- will use fallback field values."
                }
            } else {
                Write-Warn "  d365-phone-backup.json not found (migration predates this feature)."
                Write-Warn "  Falling back to hardcoded ACS field values (may not fully restore CSAC visibility)."
            }

            if (-not $cfg.PSObject.Properties['D365OrgUrl'] -or -not $cfg.D365OrgUrl) {
                Write-Warn "D365OrgUrl not in config -- skipping D365 restore."
            } else {

            try {
                $undoTokenJson = az account get-access-token --resource $cfg.D365OrgUrl --tenant $cfg.TenantId 2>&1
                $undoD365Token = ($undoTokenJson | ConvertFrom-Json).accessToken
            } catch { $undoD365Token = $null }

            if ($undoD365Token) {
                $undoD365Hdrs = @{
                    Authorization      = "Bearer $undoD365Token"
                    Accept             = "application/json"
                    "Content-Type"     = "application/json"
                    "OData-MaxVersion" = "4.0"
                    "OData-Version"    = "4.0"
                    "If-Match"         = "*"
                }
                foreach ($ra in $rasWithPhone) {
                    $num        = $ra.PhoneNumber
                    $numEncoded = $num -replace '\+', '%2B'
                    # Query without statecode filter to find inactive records too
                    $getUri = ($cfg.D365OrgUrl.TrimEnd('/') +
                               "/api/data/v9.2/msdyn_ocphonenumbers" +
                               "?`$select=msdyn_ocphonenumberid,msdyn_teamsresourceaccount,msdyn_ocphonenumbersource,statecode" +
                               "&`$filter=msdyn_phonenumber eq '$numEncoded'&`$orderby=statecode asc&`$top=1")
                    try {
                        $getR = Invoke-RestMethod -Uri $getUri -Headers $undoD365Hdrs -Method Get
                        if ($getR.value -and $getR.value.Count -gt 0) {
                            $recId = $getR.value[0].msdyn_ocphonenumberid

                            # Build PATCH body: use backup if available, else hardcoded fallback
                            $bkpEntry = if ($d365Backup -and $d365Backup.PSObject.Properties[$num]) {
                                $d365Backup.PSObject.Properties[$num].Value
                            } else { $null }

                            if ($bkpEntry) {
                                # Restore ALL backed-up fields including carrier/provider bindings
                                $patchFields = [ordered]@{
                                    statecode                  = if ($bkpEntry.statecode -ne $null) { $bkpEntry.statecode } else { 0 }
                                    statuscode                 = if ($bkpEntry.statuscode -ne $null) { $bkpEntry.statuscode } else { 1 }
                                    msdyn_ocphonenumbersource  = if ($bkpEntry.msdyn_ocphonenumbersource -ne $null) { $bkpEntry.msdyn_ocphonenumbersource } else { 192350000 }
                                    msdyn_teamsresourceaccount = $bkpEntry.msdyn_teamsresourceaccount
                                    msdyn_type                 = if ($bkpEntry.msdyn_type -ne $null) { $bkpEntry.msdyn_type } else { 192350000 }
                                    msdyn_phonenumbertype      = if ($bkpEntry.msdyn_phonenumbertype -ne $null) { $bkpEntry.msdyn_phonenumbertype } else { 1 }
                                    msdyn_objective            = if ($bkpEntry.msdyn_objective -ne $null) { $bkpEntry.msdyn_objective } else { $null }
                                    msdyn_appmodule            = if ($bkpEntry.msdyn_appmodule -ne $null) { $bkpEntry.msdyn_appmodule } else { $null }
                                }
                                # Note: carrier and provider setting lookups are NOT patched --
                                # they don't change during migration and @odata.bind causes 400 errors.
                                $patchBody = $patchFields | ConvertTo-Json -Compress
                                $srcLabel  = if ($patchFields.msdyn_ocphonenumbersource -eq 192350000) { 'ACS' } elseif ($patchFields.msdyn_ocphonenumbersource -eq 192350001) { 'Teams DR' } else { "src=$($patchFields.msdyn_ocphonenumbersource)" }
                                Write-Info "  Restoring $num from backup (source=$srcLabel, statecode=$($patchFields.statecode), type=$($patchFields.msdyn_type))"
                            } else {
                                # Fallback: hardcoded ACS values (pre-backup migration runs)
                                $patchBody = '{"statecode": 0, "statuscode": 1, "msdyn_teamsresourceaccount": null, "msdyn_ocphonenumbersource": 192350000}'
                                Write-Info "  No backup for $num -- applying fallback ACS values."
                            }

                            if ($DryRun) {
                                Write-Info "  (DRY RUN) Would PATCH msdyn_ocphonenumbers($recId): $patchBody"
                            } else {
                                $patchUri = ($cfg.D365OrgUrl.TrimEnd('/') + "/api/data/v9.2/msdyn_ocphonenumbers($recId)")
                                Invoke-RestMethod -Uri $patchUri -Headers $undoD365Hdrs -Method PATCH -Body $patchBody | Out-Null
                                Write-OK "  D365 record restored for $num"
                            }
                        } else {
                            Write-Warn "  $num not found in D365 -- record may have been deleted. Run Repair-D365PhoneRecord-v14.ps1 if needed."
                        }
                    } catch {
                        Write-Warn "  D365 restore failed for $num : $($_.Exception.Message -replace '\r?\n.*','')"
                        $script:undoFailures += "D365 restore failed: $num"
                    }
                }
            } else {
                Write-Warn "  Could not get D365 token -- skipping D365 restore."
                Write-Warn "  Run Repair-D365PhoneRecord-v14.ps1 -Fix to restore phone numbers manually."
            }

            # Trigger D365 Sync from Azure so restored numbers appear in CSAC
            if (-not $DryRun -and $undoD365Token) {
                $commsProvId = if ($cfg.PSObject.Properties['CommsProviderId']) { $cfg.CommsProviderId } else { $null }
                $acsEpStr    = if ($cfg.PSObject.Properties['AcsEndpoint'])     { $cfg.AcsEndpoint }     else { $null }
                Invoke-D365SyncFromAzure -OrgUrl $cfg.D365OrgUrl -Token $undoD365Token `
                    -AcsEndpoint $acsEpStr -CommsProviderId $commsProvId
            }

            } # end D365OrgUrl null guard
        }
    }
}

# ---------------------------------------------------------------------------
# UNDO STEP 8 - Remove licenses
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 8 -and $StopAfterStep -le 8) {
    Write-Banner 'UNDO STEP 8 - Remove PHONESYSTEM_VIRTUALUSER Licenses'
    if (Confirm-Step 'UNDO STEP 8' "Remove PHONESYSTEM_VIRTUALUSER license from $($effectiveRAs.Count) RA(s)") {
        if (-not $skuId) {
            Write-Warn "SKU not found - skipping license removal."
        } elseif ($effectiveRAs.Count -eq 0) {
            Write-Warn "No RAs to process."
        } else {
            foreach ($ra in $effectiveRAs) {
                $raUpn    = $ra.UPN
                $objectId = $raObjectIds[$raUpn]
                if (-not $objectId) {
                    $existing = Get-CsOnlineApplicationInstance -Identity $raUpn -ErrorAction SilentlyContinue
                    $objectId = if ($existing) { $existing.ObjectId } else { $null }
                }
                if (-not $objectId) { Write-Warn "No ObjectId for $raUpn - skipping."; continue }
                $oidLocal = $objectId
                Invoke-Undo "Remove license from $raUpn" {
                    Set-MgUserLicense -UserId $oidLocal `
                        -RemoveLicenses @($skuId) `
                        -AddLicenses @() | Out-Null
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# UNDO STEP 7 - Remove resource accounts
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 7 -and $StopAfterStep -le 7) {
    Write-Banner 'UNDO STEP 7 - Remove Resource Accounts'
    if (Confirm-Step 'UNDO STEP 7' "Delete $($effectiveRAs.Count) Resource Account(s) from the tenant") {
        if ($effectiveRAs.Count -eq 0) {
            Write-Warn "No RAs to process."
        } else {
            foreach ($ra in $effectiveRAs) {
                $raUpn    = $ra.UPN
                $raName   = $ra.DisplayName
                $objectId = $raObjectIds[$raUpn]
                if (-not $objectId) {
                    $existing = Get-CsOnlineApplicationInstance -Identity $raUpn -ErrorAction SilentlyContinue
                    $objectId = if ($existing) { $existing.ObjectId } else { $null }
                }
                if (-not $objectId) { Write-Warn "RA $raUpn not found - skipping."; continue }
                $oidLocal = $objectId
                Invoke-Undo "Remove RA $raName ($raUpn)" {
                    Remove-MgUser -UserId $oidLocal
                }
            }

            if (Test-Path $raObjectIdsPath) {
                if ($DryRun) {
                    Write-Info "(DRY RUN) Would backup ra-objectids.json with undooperation timestamp (file kept)"
                } else {
                    Backup-JsonFile -Path $raObjectIdsPath
                    Write-OK "ra-objectids.json backed up (not deleted -- kept for reference)"
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# UNDO STEP 6 - Remove DR phone numbers
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 6 -and $StopAfterStep -le 6) {
    Write-Banner 'UNDO STEP 6 - Remove Direct Routing Phone Numbers'
    if (Confirm-Step 'UNDO STEP 6' 'Remove uploaded Direct Routing phone numbers from Teams') {
        $drNumbers = @($effectiveRAs | Where-Object { $_.PhoneNumber } | ForEach-Object { [string]$_.PhoneNumber })
        if ($drNumbers.Count -eq 0) {
            Write-Warn "No DR phone numbers to remove."
        } else {
            foreach ($num in $drNumbers) {
                $numLocal = $num
                Invoke-Undo "Remove DR number $numLocal" {
                    Remove-CsOnlineTelephoneNumber -TelephoneNumber $numLocal | Out-Null
                }
            }

            # Post-Step-6 D365 re-patch: Remove-CsOnlineTelephoneNumber can trigger a Teams->D365 sync
            # that deactivates the phone record (statecode=1) or leaves it in an orphaned state.
            # Step 9's D365 restore ran BEFORE this step and may have been overridden by that sync.
            # Re-apply the backup restore here (after the removal) to guarantee the correct final state.
            # This query includes inactive records (no statecode filter) so it finds deactivated records.
            Write-Step "Re-patching D365 phone records after DR number removal (restoring pre-migration state) ..."
            # Guard: D365OrgUrl must be present for D365 re-patch
            $step6D365Token = $null
            if (-not $cfg.PSObject.Properties['D365OrgUrl'] -or -not $cfg.D365OrgUrl) {
                Write-Warn "D365OrgUrl missing from config -- skipping D365 re-patch after DR number removal."
                Write-Warn "If numbers are missing from D365 CSAC, run: .\Repair-D365PhoneRecord-v14.ps1 -ConfigPath $ConfigPath -Fix"
            } else {
            # Re-load backup if available
            $d365BackupDir6  = Split-Path $ConfigPath
            $d365BackupPath6 = if ($d365BackupDir6) { Join-Path $d365BackupDir6 'd365-phone-backup.json' } else { '.\d365-phone-backup.json' }
            $d365Backup6 = $null
            if (Test-Path $d365BackupPath6) {
                try { $d365Backup6 = Get-Content $d365BackupPath6 -Raw | ConvertFrom-Json } catch {}
            }
            try {
                $step6TokenJson = az account get-access-token --resource $cfg.D365OrgUrl --tenant $cfg.TenantId 2>&1
                $step6D365Token = ($step6TokenJson | ConvertFrom-Json).accessToken
            } catch { $step6D365Token = $null }

            if ($step6D365Token) {
                $step6D365Hdrs = @{
                    Authorization      = "Bearer $step6D365Token"
                    Accept             = "application/json"
                    "Content-Type"     = "application/json"
                    "OData-MaxVersion" = "4.0"
                    "OData-Version"    = "4.0"
                    "If-Match"         = "*"
                }
                foreach ($num in $drNumbers) {
                    $numEncoded = $num -replace '\+', '%2B'
                    # Include statecode ne 2 (deleted) but allow inactive (statecode=1) records
                    $getUri = ($cfg.D365OrgUrl.TrimEnd('/') +
                               "/api/data/v9.2/msdyn_ocphonenumbers" +
                               "?`$select=msdyn_ocphonenumberid,msdyn_teamsresourceaccount,msdyn_ocphonenumbersource,statecode" +
                               "&`$filter=msdyn_phonenumber eq '$numEncoded'" +
                               "&`$orderby=statecode asc&`$top=1")
                    try {
                        $getR = Invoke-RestMethod -Uri $getUri -Headers $step6D365Hdrs -Method Get
                        if ($getR.value -and $getR.value.Count -gt 0) {
                            $rec    = $getR.value[0]
                            $recId  = $rec.msdyn_ocphonenumberid
                            $state  = $rec.statecode
                            $src    = $rec.msdyn_ocphonenumbersource
                            $ra     = $rec.msdyn_teamsresourceaccount
                            # Needs patch if inactive OR Teams RA still linked.
                            # Do NOT flag source=192350001 alone -- that is correct BYON pre-migration state.
                            $needsPatch = ($state -ne 0) -or ($ra)
                            if ($needsPatch) {
                                # Use backup if available, else hardcoded fallback
                                $bkpEntry6 = if ($d365Backup6 -and $d365Backup6.PSObject.Properties[$num]) { $d365Backup6.PSObject.Properties[$num].Value } else { $null }
                                if ($bkpEntry6) {
                                    $patchFields6 = [ordered]@{
                                        statecode                  = if ($bkpEntry6.statecode -ne $null) { $bkpEntry6.statecode } else { 0 }
                                        statuscode                 = if ($bkpEntry6.statuscode -ne $null) { $bkpEntry6.statuscode } else { 1 }
                                        msdyn_ocphonenumbersource  = if ($bkpEntry6.msdyn_ocphonenumbersource -ne $null) { $bkpEntry6.msdyn_ocphonenumbersource } else { 192350000 }
                                        msdyn_teamsresourceaccount = $bkpEntry6.msdyn_teamsresourceaccount
                                        msdyn_type                 = if ($bkpEntry6.msdyn_type -ne $null) { $bkpEntry6.msdyn_type } else { 192350000 }
                                        msdyn_phonenumbertype      = if ($bkpEntry6.msdyn_phonenumbertype -ne $null) { $bkpEntry6.msdyn_phonenumbertype } else { 1 }
                                        msdyn_objective            = if ($bkpEntry6.msdyn_objective -ne $null) { $bkpEntry6.msdyn_objective } else { $null }
                                        msdyn_appmodule            = if ($bkpEntry6.msdyn_appmodule -ne $null) { $bkpEntry6.msdyn_appmodule } else { $null }
                                    }
                                    $step6PatchBody = $patchFields6 | ConvertTo-Json -Compress
                                } else {
                                    $step6PatchBody = '{"statecode": 0, "statuscode": 1, "msdyn_teamsresourceaccount": null, "msdyn_ocphonenumbersource": 192350000}'
                                }
                                if ($DryRun) {
                                    Write-Info "  (DRY RUN) Would re-patch $num (statecode=$state, source=$src)"
                                } else {
                                    $patchUri  = ($cfg.D365OrgUrl.TrimEnd('/') + "/api/data/v9.2/msdyn_ocphonenumbers($recId)")
                                    Invoke-RestMethod -Uri $patchUri -Headers $step6D365Hdrs -Method PATCH -Body $step6PatchBody | Out-Null
                                    Write-OK "  $num re-patched to pre-migration state"
                                }
                            } else {
                                Write-Info "  $num D365 record already in correct ACS state -- no re-patch needed."
                            }
                        } else {
                            Write-Warn "  $num not found in D365 (may have been deleted by Teams sync)."
                            Write-Warn "  If number is missing from D365 CSAC, run Repair-D365PhoneRecord-v14.ps1"
                            Write-Warn "  or click 'Sync from Azure' on the Manage telephony panel in D365 CSAC."
                        }
                    } catch {
                        Write-Warn "  D365 re-patch failed for $num : $($_.Exception.Message -replace '\r?\n.*','')"
                    }
                }
            } else {
                Write-Warn "  Could not get D365 token for post-removal re-patch."
                Write-Warn "  If numbers are missing from D365 CSAC, run: .\Repair-D365PhoneRecord-v14.ps1 -ConfigPath $ConfigPath -Fix"
            }

            # Trigger D365 Sync from Azure so restored numbers appear in CSAC
            if (-not $DryRun -and $step6D365Token) {
                $commsProvId6 = if ($cfg.PSObject.Properties['CommsProviderId']) { $cfg.CommsProviderId } else { $null }
                $acsEpStr6    = if ($cfg.PSObject.Properties['AcsEndpoint'])     { $cfg.AcsEndpoint }     else { $null }
                Invoke-D365SyncFromAzure -OrgUrl $cfg.D365OrgUrl -Token $step6D365Token `
                    -AcsEndpoint $acsEpStr6 -CommsProviderId $commsProvId6
            }
            } # end D365OrgUrl else block
        }
    }
}

# ---------------------------------------------------------------------------
# UNDO STEP 4 - Remove registered domain
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 4 -and $StopAfterStep -le 4) {
    Write-Banner 'UNDO STEP 4 - Remove Registered Domain from Entra ID' 'Yellow'
    if (Confirm-Step 'UNDO STEP 4' "Remove domain '$($cfg.Domain)' from Entra ID") {

    $domainToRemove = $cfg.Domain

    if (-not $domainToRemove) {
        Write-Warn "Domain not found in config -- skipping Step 4 undo."
    } elseif ($domainToRemove -like '*.onmicrosoft.com') {
        Write-Info "Domain '$domainToRemove' is an onmicrosoft.com domain -- cannot remove. Skipping."
    } else {
        $domainObj = $null
        try {
            $domainObj = Get-MgDomain -DomainId $domainToRemove -ErrorAction SilentlyContinue
        } catch {}

        if (-not $domainObj) {
            Write-Info "Domain '$domainToRemove' not found in tenant -- already removed or never registered."
        } elseif ($domainObj.IsDefault) {
            Write-Warn "Domain '$domainToRemove' is the DEFAULT domain -- cannot remove."
        } else {
            Write-Step "Removing domain '$domainToRemove' from Entra ID ..."
            if ($DryRun) {
                Write-Info "(DRY RUN) Would call: Remove-MgDomain -DomainId '$domainToRemove'"
            } else {
                Write-Host ""
                Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
                Write-Host "  !!  WARNING: You are about to permanently DELETE a domain !!" -ForegroundColor Red
                Write-Host "  !!  Domain : $domainToRemove" -ForegroundColor Red
                Write-Host "  !!  This cannot be undone without re-registering the domain." -ForegroundColor Red
                Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
                Write-Host ""
                $confirm = (Read-Host "  Type DELETE to confirm, or press Enter to skip").Trim()
                if ($confirm -ne 'DELETE') {
                    Write-Info "Domain removal skipped."
                } else {
                    try {
                        Remove-MgDomain -DomainId $domainToRemove -Confirm:$false -ErrorAction Stop
                        Write-OK "Domain '$domainToRemove' removed."
                    } catch {
                        $errMsg = $_.ToString()
                        if ($errMsg -like '*in use*' -or $errMsg -like '*referenced*' -or $errMsg -like '*dependent*' -or $errMsg -like '*BadRequest*') {
                            Write-Warn "Domain '$domainToRemove' still has users or services assigned to it -- cannot remove yet."
                            Write-Info "Remove all users with UPNs on this domain first, then try again."
                        } else {
                            Write-Warn "Domain removal did not complete. You can remove it manually from the Microsoft Entra ID portal."
                        }
                    }
                }
            }
        }
    }
    } # end Confirm-Step 4
}

# ---------------------------------------------------------------------------
# UNDO STEP 3 - Remove voice routing policy, routes, PSTN usage
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 3 -and $StopAfterStep -le 3) {
    Write-Banner 'UNDO STEP 3 - Remove Voice Routing Policy, Routes & PSTN Usage'
    if (Confirm-Step 'UNDO STEP 3' 'Remove voice routing policy, routes, and PSTN usage') {
        Invoke-Undo "Remove Voice Routing Policy '$($cfg.PolicyName)'" {
            Remove-CsOnlineVoiceRoutingPolicy -Identity $cfg.PolicyName
        }

        # Only remove the voice route created during migration (cfg.RouteName).
        # exportedRoutes are pre-existing ACS routes from acs-export.json — must not be removed.
        Invoke-Undo "Remove Voice Route '$($cfg.RouteName)'" {
            Remove-CsOnlineVoiceRoute -Identity $cfg.RouteName
        }

        Invoke-Undo "Remove PSTN Usage '$($cfg.UsageName)'" {
            Set-CsOnlinePstnUsage -Identity Global -Usage @{ Remove = $cfg.UsageName }
        }
    }
}

# ---------------------------------------------------------------------------
# UNDO STEP 2 - Remove PSTN Gateways (SBCs) and ensure ACS trunk is enabled
# ---------------------------------------------------------------------------
#
# Note: In the migration, ACS trunk was only disabled briefly (~5-10s) during
# Step 2 to allow Teams gateway registration, then immediately re-enabled. So by
# the time you run undo, ACS may already be enabled. The re-enable below is safe
# (idempotent) and also handles the case where Toggle-AcsTeamsRouting-v14.ps1 was run
# after migration (which would have re-disabled ACS to route calls to Teams).
#
# acs-trunk-disabled.json contains the FQDNs that were involved in Step 2. These
# are the FQDNs to ensure are re-enabled after removing the Teams gateways.
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 2 -and $StopAfterStep -le 2) {
    Write-Banner 'UNDO STEP 2 - Remove PSTN Gateways (SBCs) and Ensure ACS Trunk is Enabled'
    if (Confirm-Step 'UNDO STEP 2' 'Remove Teams PSTN gateways and ensure ACS trunks are enabled (enabled=true)') {

        # Remove only the Teams DR gateway that was added during migration (cfg.SbcFqdn).
        # acs-export.json contains ALL ACS trunks (existing before migration) — we must
        # not remove those; only remove the one registered as a Teams DR gateway in Step 2.
        $gatewaysToRemove = @()
        if ($cfg.PSObject.Properties['SbcFqdn'] -and $cfg.SbcFqdn) {
            $gatewaysToRemove = @([PSCustomObject]@{ fqdn = $cfg.SbcFqdn })
        } else {
            # Fallback: filter exported trunks to only the one matching SbcFqdn (legacy behaviour)
            $gatewaysToRemove = @($exportedTrunks)
        }
        foreach ($trunk in $gatewaysToRemove) {
            $fqdn = $trunk.fqdn
            # Skip if this FQDN was already in acs-export.json before migration ran —
            # that means it was a pre-existing gateway we must not remove.
            $preExisting = $exportedTrunks | Where-Object { $_.fqdn -eq $fqdn }
            if ($preExisting) {
                Write-Info "Skipping '$fqdn' -- pre-existing gateway (in acs-export.json before migration). Leave it in place."
                continue
            }
            $fqdnLocal = $fqdn
            Invoke-Undo "Remove PSTN Gateway '$fqdnLocal'" {
                Remove-CsOnlinePSTNGateway -Identity $fqdnLocal
            }
        }

        # Ensure ACS trunks are enabled.
        # Reads acs-trunk-disabled.json written during migration Step 2.
        # ACS was re-enabled right after gateway creation, so it may already be enabled.
        # We re-enable anyway (idempotent). This also handles the case where Toggle was run.
        $disabledListPath = '.\acs-trunk-disabled.json'
        if (Test-Path $disabledListPath) {
            Write-Step "Ensuring ACS trunks are enabled (from acs-trunk-disabled.json) ..."
            Write-Info "(ACS may already be enabled; this is a safety re-enable in case Toggle was run)"

            $disabledFqdns = @()
            try {
                $raw = Get-Content $disabledListPath -Raw | ConvertFrom-Json
                if ($null -eq $raw) { $disabledFqdns = @() }
                elseif ($raw -is [System.Array]) { $disabledFqdns = @($raw) }
                else { $disabledFqdns = @([string]$raw) }
            } catch {
                Write-Warn "Could not parse acs-trunk-disabled.json -- skipping ACS trunk re-enable."
            }

            if ($disabledFqdns.Count -gt 0 -and $cfg.PSObject.Properties['AcsConnectionString'] -and $cfg.AcsConnectionString) {
                $acsConn = @{}
                $cfg.AcsConnectionString.Split(';') | ForEach-Object {
                    $kv = $_ -split '=', 2
                    if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
                }
                $acsEp  = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
                $acsKey = if ($acsConn['accesskey']) { $acsConn['accesskey'] } else { '' }
                if (-not $acsEp -or -not $acsKey) {
                    Write-Warn "Could not parse ACS endpoint or access key from connection string -- skipping ACS trunk re-enable."
                    Write-Warn "Use Toggle-AcsTeamsRouting-v14.ps1 to re-enable manually."
                    $disabledFqdns = @()  # skip the foreach loop below
                }

                # Load routes from acs-export.json to restore alongside trunk enable
                $acsExportRoutes = @()
                $acsExportPath2 = '.\acs-export.json'
                if (Test-Path $acsExportPath2) {
                    try {
                        $exp = Get-Content $acsExportPath2 -Raw | ConvertFrom-Json
                        $acsExportRoutes = @($exp.routes)
                        Write-Info "Loaded $($acsExportRoutes.Count) route(s) from acs-export.json for ACS restore."
                    } catch { Write-Warn "Could not load routes from acs-export.json -- will re-enable trunk without routes." }
                } else {
                    Write-Info "acs-export.json not found -- will re-enable ACS trunk without routes."
                }

                foreach ($fqdn in $disabledFqdns) {
                    $trunkPort = ($exportedTrunks | Where-Object { $_.fqdn -eq $fqdn } | Select-Object -First 1).sipSignalingPort
                    if (-not $trunkPort) { $trunkPort = $cfg.SbcPort }
                    Write-Info "Enabling ACS trunk '$fqdn' (sipSignalingPort=$trunkPort, enabled=true, routes=$($acsExportRoutes.Count)) ..."
                    if ($DryRun) {
                        Write-Info "(DRY RUN) Would PATCH ACS trunk '$fqdn' => sipSignalingPort=$trunkPort, enabled:true, routes:[$($acsExportRoutes.Count) route(s)]"
                    } else {
                        try {
                            Invoke-AcsTrunkPatch -Fqdn $fqdn -Enabled $true -AcsEp $acsEp -AcsKey $acsKey -SipSignalingPort $trunkPort -Routes $acsExportRoutes
                            Write-OK "ACS trunk '$fqdn' is now enabled (routes restored)."
                        } catch {
                            $errDetail = if ($_.Exception.Response) { "HTTP $([int]$_.Exception.Response.StatusCode)" } else { ($_.Exception.Message -split '\r?\n')[0] }
                            Write-Warn "Could not enable ACS trunk '$fqdn' ($errDetail). Please enable it manually in the ACS portal or use Toggle-AcsTeamsRouting-v14.ps1."
                        }
                    }
                }
            } elseif ($disabledFqdns.Count -gt 0) {
                Write-Warn "AcsConnectionString not in config -- cannot re-enable ACS trunks. Use Toggle-AcsTeamsRouting-v14.ps1 to re-enable manually."
            }
        } else {
            Write-Info "No acs-trunk-disabled.json found -- ACS trunk was not modified by migration (or already cleaned up)."
        }
    }
}

# ---------------------------------------------------------------------------
# UNDO STEP 1 - Backup acs-export.json (kept for reference)
# ---------------------------------------------------------------------------

if ($StartAtStep -ge 1 -and $StopAfterStep -le 1) {
    Write-Banner 'UNDO STEP 1 - Backup acs-export.json (file kept for reference)'
    if (Confirm-Step 'UNDO STEP 1' 'Backup acs-export.json with undooperation timestamp') {
        if (Test-Path $acsExportPath) {
            if ($DryRun) {
                Write-Info "(DRY RUN) Would backup $acsExportPath with undooperation timestamp (file kept)"
            } else {
                Backup-JsonFile -Path $acsExportPath
                Write-OK "acs-export.json backed up (not deleted -- kept for reference)"
            }
        } else {
            Write-Info "acs-export.json not found - nothing to backup."
        }
    }
}

# ---------------------------------------------------------------------------
# Run Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host "|        ACS TPE Migration UNDO v14.20.0 -- Run Summary           |" -ForegroundColor Cyan
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host "  Completed : $($script:undoCompleted.Count) operation(s)" -ForegroundColor Green
Write-Host "  Skipped   : $($script:undoSkipped.Count) step(s)" -ForegroundColor Yellow
Write-Host "  Already removed : $($script:undoAlreadyRemoved.Count) item(s)" -ForegroundColor DarkGray
Write-Host "  Needs attention : $($script:undoFailures.Count) item(s)" -ForegroundColor $(if ($script:undoFailures.Count -gt 0) { 'Yellow' } else { 'Green' })
if ($script:undoSkipped.Count -gt 0) {
    Write-Host ""
    Write-Host "  Skipped steps:" -ForegroundColor Yellow
    foreach ($s in $script:undoSkipped) { Write-Host "    - $s" -ForegroundColor DarkGray }
}
if ($script:undoFailures.Count -gt 0) {
    Write-Host ""
    Write-Host "  The following items could not be completed automatically." -ForegroundColor Yellow
    Write-Host "  Please review and complete them manually if needed:" -ForegroundColor Yellow
    foreach ($f in $script:undoFailures) { Write-Host "    - $f" -ForegroundColor DarkYellow }
}
Write-Host "+==================================================================+" -ForegroundColor Cyan

$summaryText = if ($DryRun) { 'DRY RUN complete.' } else { 'Undo complete.' }
$summaryColor = if ($DryRun) { 'Yellow' } else { 'Green' }

Write-Host ""
Write-Host "  $summaryText" -ForegroundColor $summaryColor
Write-Host "  Steps undone: $StartAtStep -> $StopAfterStep" -ForegroundColor Gray
Write-Host ""
Write-Host "  HTML log saved: $script:HtmlLogPath" -ForegroundColor Cyan
Write-Host "  Open with: Start-Process $script:HtmlLogPath" -ForegroundColor DarkGray
Write-Host ""

Write-HtmlLine ""
Write-HtmlLine "  $summaryText" $summaryColor
Write-HtmlLine "  Steps undone: $StartAtStep -> $StopAfterStep" 'Gray'
Write-HtmlLine ""
Write-HtmlLine "  HTML log saved: $script:HtmlLogPath" 'Cyan'

# Build undo summary HTML footer
$failColor6   = if ($script:undoFailures.Count -gt 0) { '#ffd700' } else { '#4ec94e' }
$failListHtml = ''
if ($script:undoFailures.Count -gt 0) {
    $failListHtml = '<ul style="margin:6px 0 0 16px;padding:0;color:#ffd700">' + (($script:undoFailures | ForEach-Object { $e = $_ -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'; "<li>$e</li>" }) -join '') + '</ul>'
}
$undoHtmlFooter = @"
<div style="margin-top:20px;border-top:1px solid #333;padding-top:16px;font-family:Consolas,'Courier New',monospace;font-size:12px">
<div style="color:#555;font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px">Undo Summary &mdash; Steps $StartAtStep &#8592; $StopAfterStep</div>
<table style="border-collapse:collapse">
<tr><td style="padding:4px 20px 4px 0;color:#888">Completed</td><td style="padding:4px 0;color:#4ec94e">$($script:undoCompleted.Count) operation(s)</td></tr>
<tr><td style="padding:4px 20px 4px 0;color:#888">Skipped</td><td style="padding:4px 0;color:#ffd700">$($script:undoSkipped.Count) step(s)</td></tr>
<tr><td style="padding:4px 20px 4px 0;color:#888">Already removed</td><td style="padding:4px 0;color:#666">$($script:undoAlreadyRemoved.Count) item(s)</td></tr>
<tr><td style="padding:4px 20px 4px 0;color:#888">Needs attention</td><td style="padding:4px 0;color:$failColor6">$($script:undoFailures.Count) item(s)</td></tr>
</table>
$failListHtml
<div style="margin-top:10px;color:#888">Numbers: <span style="color:#d4d4d4">$((($effectiveRAs | Where-Object { $_.PhoneNumber } | ForEach-Object { $_.PhoneNumber }) -join ', ') -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;')</span> &nbsp;|&nbsp; <a href="tpe-status.html" style="color:#00bfff">Open Dashboard</a></div>
</div>
"@

# Write run record + update dashboard
$undoPhoneNums = @($effectiveRAs | Where-Object { $_.PhoneNumber } | ForEach-Object { [string]$_.PhoneNumber })
$undoResult    = if ($script:undoFailures.Count -gt 3) { 'FAIL' } elseif ($script:undoFailures.Count -gt 0) { 'WARN' } else { 'OK' }
Write-TpeRunRecord -Type 'undo' -PhoneNums $undoPhoneNums -Result $undoResult `
    -Completed $script:undoCompleted.Count -Skipped $script:undoSkipped.Count -Failures $script:undoFailures.Count
Update-TpeStatusDashboard
Write-Host "  Open with: Start-Process .\tpe-status.html" -ForegroundColor DarkGray

$undoExitCode = if ($undoResult -eq 'FAIL') { 1 } else { 0 }
Exit-Script $undoExitCode -FooterHtml $undoHtmlFooter
