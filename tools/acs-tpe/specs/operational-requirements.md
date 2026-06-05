# Operational Requirements

## Overview

Cross-cutting requirements that apply to all 18 ACS-TPE scripts. These define the runtime contract, error handling patterns, versioning rules, and DryRun semantics.

## PowerShell Runtime

### Version

All scripts require PowerShell 5.1 or later. No PowerShell 7-only features are used.

### #Requires Directive

All 18 scripts include the `#Requires -Version 5.1` directive at the top of the file. This is enforced by the test suite (`TC-RequiresDirective`).

### Strict Mode

Every script must set strict mode at the top of the main execution block:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

- `Set-StrictMode -Version Latest` — prevents use of uninitialized variables, prohibits references to non-existent properties, and enforces other strict evaluation rules
- `$ErrorActionPreference = 'Stop'` — converts non-terminating errors into terminating errors, ensuring fail-fast behavior

These two lines must appear before any logic executes. They are not optional.

## CmdletBinding

Scripts that perform external mutations use `[CmdletBinding(SupportsShouldProcess)]`:
- `Invoke-ACS-TPE-Full-Migration-v14.ps1`
- `Set-AcsSbcFqdn-v14.ps1`
- `Test-DomainRegistration-v14.ps1`
- `Toggle-AcsTeamsRouting-v14.ps1`
- `Undo-ACS-TPE-Migration-v14.ps1`

`SupportsShouldProcess` enables the implicit `-WhatIf` and `-Confirm` parameters from the PowerShell runtime, available to callers even though the scripts primarily use the custom `-DryRun` switch for mutation control.

Most other scripts use plain `[CmdletBinding()]` without `SupportsShouldProcess`. Three scripts (`Add-AcsTrunkDisabled-v14.ps1`, `Fix-AcsRoutePattern-v14.ps1`, `Repair-D365PhoneRecord-v14.ps1`) use a bare `param()` block without `[CmdletBinding()]`.

## Sub-Script Resolution

Flip scripts and the orchestrator locate sibling scripts using `$PSScriptRoot`:

```powershell
$scriptDir     = $PSScriptRoot
$toggleScript  = Join-Path $scriptDir "Toggle-AcsTeamsRouting-v14.ps1"
$migrateScript = Join-Path $scriptDir "Invoke-MigrateTpsPhoneNumber-v14.ps1"
```

Each resolved path is validated with `Test-Path` before invocation. Missing sub-scripts produce a clear error and exit.

## DryRun Contract

### Requirement

Every script that performs external mutations must support a `-DryRun` switch parameter.

### Semantics

When `-DryRun` is active:

| Action | Allowed in DryRun? |
|--------|-------------------|
| Read-only API calls (GET) | Yes |
| Module connections (Connect-MicrosoftTeams, Connect-MgGraph) | Yes |
| Mutating API calls (PATCH, POST, PUT, DELETE) | No |
| Teams cmdlets that create/modify/delete objects | No |
| Writing `acs-export.json` | No |
| Writing `ra-objectids.json` | No |
| Writing `d365-phone-backup.json` | No |
| Writing CSV output | No |
| Writing HTML run log | Yes |
| Writing `stats/tpe-runs.jsonl` record | Yes |
| Regenerating `tpe-status.html` dashboard | Yes |

### DryRun Output

DryRun actions are prefixed with `(DRY RUN)`:
```
(DRY RUN) Would PATCH ACS trunk: {"routes":[],"trunks":{...}}
(DRY RUN) Would create Teams DR gateway: sip-eastus-yt-00.staging.ivr.nuance.com
(DRY RUN) Would assign license to RA: ra_12202140029@tenant.onmicrosoft.com
```

### Run Records in DryRun

Run records (`stats/tpe-runs.jsonl`) are written even during dry runs. This allows the stats dashboard to show dry run attempts in the history. Dry run records are not distinguished by a separate `type` value — they appear with the same type as live runs.

### Orchestrator DryRun Early Exit

The orchestrator's DryRun mode exits immediately after displaying the step plan summary with `[DRY RUN COMPLETE] No changes were made.` — no steps execute. This differs from individual script DryRun behavior where read-only operations (GET calls, module connections) still execute while mutations are suppressed.

## Exit-Script Pattern

### Requirement

All script exit paths must go through the `Exit-Script` function. Direct `exit` calls are a bug.

### Implementation

```powershell
function Exit-Script {
    param([int]$Code = 0, [string]$FooterHtml = '')
    try {
        Add-Content -Path $script:HtmlLogPath -Value "</pre>$FooterHtml</body></html>" -Encoding UTF8
    } catch {}
    exit $Code
}
```

### Purpose

- Guarantees the HTML log footer (`</pre></body></html>`) is written on every exit path
- Ensures partial HTML logs are still valid HTML documents
- The `try/catch` around `Add-Content` prevents secondary failures during error cleanup from masking the original error

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Failure (one or more operations failed) |

### Footer HTML

The `$FooterHtml` parameter allows scripts to inject a summary box or final status message before the closing tags:

```powershell
Exit-Script -Code 0 -FooterHtml '<div class="summary">Migration complete</div>'
```

## Idempotency

### Requirement

Each migration step must check whether its target objects already exist before creating them. Re-running from any step must be safe.

### Pattern

```powershell
$existing = Get-CsOnlineVoiceRoute -Identity $cfg.RouteName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Log "WARN Route already exists -- skipped" -Color yellow
} else {
    New-CsOnlineVoiceRoute -Identity $cfg.RouteName ...
    Write-Log "OK Route created" -Color green
}
```

### Idempotent Steps

| Step | Object | Idempotent behavior |
|------|--------|-------------------|
| 2 | Teams DR gateway | Skip creation if exists; still re-enable ACS |
| 3 | PSTN usage | WARN if exists |
| 3 | Voice route | WARN if exists |
| 3 | Routing policy | WARN if exists |
| 4 | Entra ID domain | Skip if registered and verified |
| 6 | Phone number upload | WARN if already uploaded |
| 7 | Resource account | Error per RA (UPN conflict); continue to next |

## Versioning

### Version String Embedding

There is no standalone `$scriptVersion` variable. Version strings are embedded inline in three locations within each script:

1. **Console banner**: e.g. `Write-Host "=== Fix-AcsRoutePattern v14.11.0 ===" -ForegroundColor Cyan` or `Write-Host "|   ACS -> Teams Phone Extensibility (TPE) Migration  v14.16.0     |"`
2. **HTML `<title>` element**: e.g. `<title>ACS TPE Migration v14.15.0 - ...</title>`
3. **`.NOTES` changelog**: e.g. `v14.16.0 : Step 8 guards against empty ObjectId...`

The authoritative version is the latest `.NOTES` entry in the orchestrator script (`Invoke-ACS-TPE-Full-Migration-v14.ps1`). Utility script banners and HTML titles may lag behind the orchestrator version — they are bumped explicitly at milestone releases rather than on every patch. As of v14.16.0, utility script banners were last bumped to v14.11.0.

### Semantic Versioning

- **Major** (`14`): architecture generation (v14 = current suite)
- **Minor** (`16`): feature additions, new parameters, new steps
- **Patch** (`0`): bug fixes, guard additions, cosmetic changes

### Where Version Appears

1. Console banner at script start (e.g. `ACS TPE Full Migration v14.16.0`)
2. HTML log `<title>` element
3. HTML run header meta line
4. `.NOTES` changelog in every script
5. Git tag: `acs-tpe-v14.17.0` (latest; includes 854 Pester tests)

### Version Bump Rules

- Bug fix → patch bump (e.g. `14.15.0` → `14.16.0`)
- New parameter or feature → minor bump
- All 18 scripts receive a `.NOTES` changelog entry at each version; banner and HTML title strings are bumped at milestone releases
- Tests verify that `.NOTES` contains the expected version entries (historical parity)
- Tests must pass before a version tag is created
- Git tags follow the format `acs-tpe-vX.Y.Z` (latest: `acs-tpe-v14.17.0`)

### Changelog

Each script maintains a `.NOTES` section in its comment-based help with a changelog. Entries are listed newest-first so the most recent change is always at the top:

```powershell
.NOTES
    v14.16.0 : Step 8 guards against empty ObjectId when RA creation fails
    v14.15.0 : Step 5 validates only cfg SbcFqdn and RouteName
    v14.14.0 : Step 3 single route from config, not ACS export
```

## HTML Log Lifecycle

### Initialization

The HTML log file is created at the very start of script execution, before any actions:

```powershell
$script:HtmlLogPath = ".\tpe-migration-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
Set-Content -Path $script:HtmlLogPath -Value $htmlHeader -Encoding UTF8
```

This ensures that even a crash during early execution produces a partial (but valid after Exit-Script) HTML log.

### Appending

During execution, content is appended line-by-line:

```powershell
Add-Content -Path $script:HtmlLogPath -Value "<span class=`"$css`">$escaped</span>" -Encoding UTF8
```

### Closing

Handled by `Exit-Script` (see above). The closing sequence is:
```html
</pre></body></html>
```

### Encoding

All HTML files are written with UTF-8 encoding (`-Encoding UTF8`).

## File Artifacts

### Working Directory

All file artifacts are written to the current working directory (where the script is invoked from), not the script's own directory.

### Artifact Summary

| File | Written by | When | DryRun |
|------|-----------|------|--------|
| `acs-export.json` | Step 1, Toggle | After ACS GET / cutover | Skipped |
| `acs-trunk-disabled.json` | Step 2 | After trunk disable | Skipped |
| `ra-objectids.json` | Step 7 | After RA creation | Skipped |
| `d365-phone-backup.json` | Step 9 | Before D365 mutations | Skipped |
| `tpe-migration-results.csv` | Step 9 | After assignments | Skipped |
| `tpe-*-run-*.html` | All scripts | At start | Written |
| `stats/tpe-runs.jsonl` | All scripts | At end | Written |
| `tpe-status.html` | All scripts | At end | Written |

### stats/ Directory

The `stats/` subdirectory is created automatically if it does not exist when `Write-TpeRunRecord` runs.

## Error Handling Patterns

### Per-Item Continue

Operations that iterate over multiple phone numbers or resource accounts use per-item error handling:

```powershell
foreach ($ra in $cfg.ResourceAccounts) {
    try {
        # operation on $ra
        Write-Log "OK RA created: $($ra.UPN)" -Color green
    } catch {
        Write-Log "! RA creation failed for $($ra.UPN): $_" -Color red
        $failures++
    }
}
```

A failure on one item does not abort processing of remaining items.

### Partial Failure Guards (v14.16.0)

When a previous step may have partially failed, subsequent steps guard against missing data:

```powershell
# Step 8: filter to only UPNs where Step 7 produced an ObjectId
$pendingUPNs = @($cfg.ResourceAccounts | Where-Object { $raObjectIds[$_.UPN] } | ForEach-Object { $_.UPN })

# Step 8: in-loop guard — skip UPNs with no ObjectId, emit Write-Err, continue
foreach ($ra in $cfg.ResourceAccounts) {
    $objectId = $raObjectIds[$ra.UPN]
    if (-not $objectId) { Write-Err "Could not find ... -- skipping license assignment."; continue }
    # ... proceed with Update-MgUser, Set-MgUserLicense
}
```

The guard uses `continue` (non-fatal), not `throw` or `Exit-Script`, so that remaining UPNs with valid ObjectIds are still processed. Skipped UPNs emit `Write-Err` (not `Write-Warn`) to make the issue visible in HTML logs.

### ConvertFrom-Json Null Guard

PowerShell's `ConvertFrom-Json` returns `$null` for empty JSON arrays (`[]`), not an empty array. Code that wraps `ConvertFrom-Json` output into an array must include a three-branch null guard:

```powershell
$raw = Get-Content $path -Raw | ConvertFrom-Json
$items = @()
if ($null -eq $raw) { $items = @() }
elseif ($raw -is [System.Array]) { $items = @($raw) }
else { $items = @([string]$raw) }
```

Without the `$null` check, the `else` branch converts `$null` to `@("")` (a 1-element array with an empty string), which incorrectly triggers downstream loops. This pattern is used in `Undo-ACS-TPE-Migration-v14.ps1` for parsing `acs-trunk-disabled.json`.

### Undo Error Classification: Test-IsIgnorableUndoError

`Undo-ACS-TPE-Migration-v14.ps1` defines `Test-IsIgnorableUndoError()` to distinguish recoverable errors (object already removed) from real failures:

```powershell
function Test-IsIgnorableUndoError {
    param($ErrorRecord)
    $msg = if ($ErrorRecord.Exception.Message) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    return ($msg -match '(?i)\b(not\s+found|cannot\s+find|does\s+not\s+exist|already\s+(been\s+)?removed|could\s+not\s+be\s+found|Identity.*is\s+invalid)\b')
}
```

Matched patterns (case-insensitive, word-boundary):
- `not found`
- `cannot find`
- `does not exist`
- `already removed` / `already been removed`
- `could not be found`
- `Identity ... is invalid`

When an undo operation catches an error:
- If `Test-IsIgnorableUndoError` returns `$true` → classified as `undoAlreadyRemoved` (not a failure)
- If `$false` → classified as `undoFailures` (real error)

This prevents idempotent re-runs from reporting false failures.

### Undo Result Threshold

The Undo script uses a threshold-based result to determine exit severity:

| `undoFailures.Count` | Result | Exit Code |
|----------------------|--------|-----------|
| 0 | `OK` | 0 |
| 1-3 | `WARN` | 0 |
| >3 | `FAIL` | 1 |

This allows minor transient failures (e.g. a single API timeout on retry) to produce a warning rather than a hard failure.

### Undo RA Reconstruction

When `ResourceAccounts` is empty in the loaded config but a `ra-objectids.json` artifact exists, the Undo script reconstructs the resource account list by:
1. Reading object IDs from `ra-objectids.json`
2. Looking up phone assignments via `Get-CsPhoneNumberAssignment` and `Get-CsOnlineUser`
3. Falling back to `LineUri` if the standard lookup path returns no result

This allows Undo to work even when the config has been reset or modified after the original migration run.

### Undo Tracking Counters

Undo scripts track four outcome categories in script-scoped arrays:

| Counter | Meaning |
|---------|---------|
| `$script:undoCompleted` | Items successfully reversed this run |
| `$script:undoSkipped` | Items skipped (e.g. empty ObjectId) |
| `$script:undoFailures` | Items that failed with real errors |
| `$script:undoAlreadyRemoved` | Items already gone (not-found treated as success) |

The footer summary and run record reflect all four counts.

### Dual-Output Helper Functions

All orchestration scripts define a set of helper functions that write to both the console (`Write-Host`) and the HTML log (`Write-HtmlLine`) simultaneously:

```powershell
function Write-Step { param([string]$m) Write-Host "  >> $m" -ForegroundColor Cyan;    Write-HtmlLine "  >> $m" 'Cyan' }
function Write-OK   { param([string]$m) Write-Host "  OK $m"  -ForegroundColor Green;  Write-HtmlLine "  OK $m" 'Green' }
function Write-Warn { param([string]$m) Write-Host "  WARN $m" -ForegroundColor Yellow; Write-HtmlLine "  WARN $m" 'Yellow' }
function Write-Err  { param([string]$m) Write-Host "  ! $m"  -ForegroundColor Red;    Write-HtmlLine "  ! $m" 'Red' }
function Write-Info { param([string]$m) Write-Host "  -- $m"  -ForegroundColor Gray;   Write-HtmlLine "  -- $m" 'Gray' }
```

These ensure consistent formatting across console and HTML output. All scripts that produce HTML logs define the same set. See [HTML Reporting — Write-HtmlLine Helper](html-reporting.md) for the underlying function.

### Interactive Helpers (Orchestrator)

The orchestrator defines additional helpers for interactive mode:

| Function | Purpose |
|----------|---------|
| `Prompt-Required` | Interactive prompt for required values; supports GUID masking and secret input |
| `Prompt-Optional` | Interactive prompt with a default value shown in brackets |
| `Confirm-Continue` | Y/N confirmation prompt; returns `$true` on `Y`/`y` |
| `Write-Banner` | Displays section header banners in both console and HTML |
| `Write-PlanStep` | Displays the step execution plan before migration begins |
| `Wait-WithMessage` | Timed countdown with progress dots; respects DryRun (shows `(DRY RUN)` instead of waiting) |
| `Wait-UntilRAsReady` | Polls for RA visibility in Teams after creation; max 180s, interval 10s |

### Undo-Specific Helpers

`Undo-ACS-TPE-Migration-v14.ps1` defines additional helpers:

| Function | Purpose |
|----------|---------|
| `Invoke-Undo` | Wraps each undo step action in try-catch; tracks completed/skipped/failures counters |
| `Confirm-Step` | Per-step confirmation with Y/S/Q (Yes/Skip/Quit) options |
| `Invoke-AcsTrunkPatch` | Reusable HMAC-SHA256 ACS trunk PATCH helper for trunk re-enable |
| `Invoke-D365SyncFromAzure` | Triggers `msdyn_TelephonyACSSyncPhoneNumbersAction` to sync D365 from Azure |
| `Backup-JsonFile` | Creates timestamped backup copies with `undooperation-<timestamp>` suffix |

### Restore-on-Failure

Critical state changes (ACS trunk disable in Step 2 and Toggle) include catch blocks that restore the previous state:

```powershell
try {
    Invoke-AcsPatch $disableBody    # disable ACS
    New-CsOnlinePSTNGateway ...     # create Teams gateway
} catch {
    Invoke-AcsPatch $restoreBody    # restore ACS
    throw
}
```

## Resume Support

### -StartAtStep / -StopAfterStep

The orchestrator supports partial runs:

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\config.json -StartAtStep 5 -StopAfterStep 9
```

### Undo Step Direction (high-to-low)

The Undo script reverses this convention — steps run **high-to-low** (9 → 1):

```powershell
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\config.json -StartAtStep 9 -StopAfterStep 7
```

Step-range validation for undo enforces `-StartAtStep >= -StopAfterStep`:
```powershell
if ($StartAtStep -lt $StopAfterStep) {
    Write-Host "For Undo, steps run high-to-low" -ForegroundColor Red
    exit 1
}
```

### Reconnection

When `-StartAtStep > 0`, the script reconnects to Teams and Graph modules before continuing. Saved config from `-ConfigPath` provides all needed parameters.

### Artifact Dependencies

| Step | Requires | Source |
|------|----------|--------|
| 2+ | `acs-export.json` | Step 1 (or manual creation) |
| 8+ | `ra-objectids.json` | Step 7 |
| Toggle (TPE→ACS) | `acs-export.json` | Step 1 (for route restoration) |
| FlipToACS / FlipToTeams | `ra-objectids.json` | Step 7 (for number scoping) |

If a required artifact is missing when resuming, the script fails with a clear error message indicating which step needs to be re-run.

### AcsConnectionString Re-Prompt

When `-StartAtStep > 0` without `-ConfigPath`, the script exits with an error requiring a config file. When config is loaded but `AcsConnectionString` is missing (excluded from auto-saved configs for security), the orchestrator prompts interactively for the access key using `Read-Host -AsSecureString`. See [Security -- Credential Handling](security.md) for the masking mechanism.

## Module Dependencies

| Module | Installed by | Used by |
|--------|-------------|---------|
| `MicrosoftTeams` | Phase 0 | Steps 2-10, Toggle, Flip scripts, Undo |
| `Microsoft.Graph` | Phase 0 | Steps 4, 7, 8 |
| `Pester` (5.x) | Manual install | Test suite only |

Phase 0 installs missing modules with `Install-Module -Force -AllowClobber -Scope CurrentUser`. The `-Force` flag handles version upgrades; `-AllowClobber` prevents conflicts with pre-existing cmdlets; `-Scope CurrentUser` avoids requiring administrator elevation for module installation.

## Verification GET Pattern

Three ACS-facing scripts perform a full HMAC-signed verification GET after a successful PATCH to confirm ACS actually applied the requested change:

| Script | What it verifies |
|--------|-----------------|
| `Add-AcsTrunkDisabled-v14.ps1` | Trunk disabled state persisted |
| `Fix-AcsRoutePattern-v14.ps1` | Route pattern updated correctly |
| `Set-AcsSbcFqdn-v14.ps1` | SBC FQDN value applied |

Verification GET failure is **non-fatal** -- it produces a Yellow warning but does not cause the script to exit or set a failure exit code. The rationale is that the PATCH itself succeeded (HTTP 200); the verification is a belt-and-suspenders confirmation that can fail transiently without invalidating the mutation.
