# HTML Reporting

## Overview

Every ACS-TPE script execution produces:
1. A **HTML run log** — timestamped dark-theme console replica
2. A **JSONL run record** — appended to `stats/tpe-runs.jsonl`
3. A **stats dashboard** — `tpe-status.html` rebuilt from the JSONL history

## HTML Run Log

### File naming

| Script | Pattern |
|--------|---------|
| `Invoke-ACS-TPE-Full-Migration-v14.ps1` | `tpe-migration-run-<yyyyMMdd-HHmmss>.html` |
| `Invoke-FlipToACS-v14.ps1` | `tpe-flip-acs-run-<yyyyMMdd-HHmmss>.html` |
| `Invoke-FlipToTeams-v14.ps1` | `tpe-flip-teams-run-<yyyyMMdd-HHmmss>.html` |
| `Toggle-AcsTeamsRouting-v14.ps1` | `tpe-toggle-run-<yyyyMMdd-HHmmss>.html` |
| `Undo-ACS-TPE-Migration-v14.ps1` | `tpe-undo-run-<yyyyMMdd-HHmmss>.html` |

### Structure

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ACS TPE Migration v14.15.0 - 2026-04-28 18:00:45</title>
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
<span class="darkgray">Run : .\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\config.json -StartAtStep 3</span>
<span class="darkgray">Date: 2026-04-28 18:00:45</span>
...
</pre></body></html>
```

**Note**: The HTML `<title>` version string and dashboard sub-header version (`v14.15.0`) may lag behind the authoritative `.NOTES` version (`v14.16.0`). These inline version strings are bumped at milestone releases, not on every patch. See [Operational Requirements — Versioning](operational-requirements.md#versioning) for the full versioning policy.

### Color conventions

| Class | Color | Meaning |
|-------|-------|---------|
| `.cyan` | `#00bfff` | Progress / action header |
| `.darkcyan` | `#00ced1` | Section header / step banner |
| `.darkgray` | `#808080` | Meta (Run/Date lines), skipped steps |
| `.green` | `#4ec94e` | Success (`OK`) |
| `.yellow` | `#ffd700` | Warning (`WARN`) |
| `.red` | `#ff6b6b` | Error (`!`) |
| `.gray` | `#aaaaaa` | Detail / secondary info |
| `.white` | `#ffffff; ` | Blank line spacers |
| `.magenta` | `#da70d6` | Dry-run specific output |

### Output prefix conventions

| Prefix | Span class | Meaning |
|--------|-----------|---------|
| `  >>` | cyan | Starting an action |
| `  OK` | green | Success |
| `  WARN` | yellow | Non-fatal warning |
| `  !` | red | Error / failure |
| `  --` | gray | Detail / URL / sub-info |
| (none) | darkgray | Meta lines (run/date/step banners) |

### Write-HtmlLine Helper

All scripts define a common `Write-HtmlLine` helper function for HTML output:

```powershell
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
```

Higher-level helpers wrap `Write-HtmlLine` for consistent console + HTML dual output:

| Helper | Prefix | Color | Purpose |
|--------|--------|-------|---------|
| `Write-Step` | `  >>` | Cyan | Starting an action |
| `Write-OK` | `  OK` | Green | Success |
| `Write-Warn` | `  WARN` | Yellow | Non-fatal warning |
| `Write-Err` | `  !` | Red | Error / failure |
| `Write-Info` | `  --` | Gray | Detail / sub-info |

Each helper writes to both `Write-Host` (console) and `Write-HtmlLine` (HTML log) in a single call.

### Write-HtmlLine Error Suppression

All `Write-HtmlLine` implementations wrap `Add-Content` in `try-catch {}` (empty catch block) to prevent HTML log write errors from crashing the migration. This is intentional: HTML log write errors (e.g., disk full, path locked) must never interrupt the actual migration operations. The same pattern applies to `Exit-Script` when writing the closing HTML tags.

### HTML Safety

All user-supplied strings embedded in HTML must be XSS-escaped before writing:
```powershell
$esc = $value -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
```

This applies to: phone numbers, FQDNs, URLs, display names, config path, command line.

### HTML Log Footer

Every script exit path (including error exits) must write the closing HTML:
```powershell
function Exit-Script {
    param([int]$Code = 0, [string]$FooterHtml = '')
    try { Add-Content -Path $script:HtmlLogPath -Value "</pre>$FooterHtml</body></html>" -Encoding UTF8 } catch {}
    exit $Code
}
```

All `exit` calls must go through `Exit-Script`. Direct `exit` calls are a bug.

### HTML Footer Step Summary

The orchestrator (`Invoke-ACS-TPE-Full-Migration-v14.ps1`) builds a detailed step summary table in the HTML footer showing which steps ran during the execution. Each step is listed with a checkmark (&#10003;) or skip indicator, along with its step name and outcome. This summary table is assembled as the script progresses, then injected into the closing HTML via the `$FooterHtml` parameter of `Exit-Script`. Flip and Toggle scripts do not produce a step summary table since they operate as single logical operations.

### Log initialization

```powershell
$script:HtmlLogPath = ".\tpe-migration-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
Set-Content -Path $script:HtmlLogPath -Value $htmlHeader -Encoding UTF8
```

The log is opened at script start (before any actions) so partial logs are always written even on crash.

### Invocation Line Capture

Every script that produces an HTML log captures the invocation command line in a variable (e.g., `$invokedAs`) at script startup. The invocation string is XSS-escaped (replacing `&`, `<`, `>` with HTML entities) and written to the HTML log header as a `<span class="darkgray">Run : ...</span>` line. This provides a full audit trail of how the script was called, including all parameters and their values. The invocation line appears as the first content line in every HTML run log (visible in the [Structure](#structure) example above).

## JSONL Run Record

### File: `stats/tpe-runs.jsonl`

Append-only file. One JSON object per line.

### Schema

```json
{
  "timestamp":    "2026-04-28T18:00:45Z",
  "type":         "migrate",
  "result":       "OK",
  "dryRun":       false,
  "startStep":    3,
  "stopStep":     11,
  "completed":    1,
  "skipped":      0,
  "failures":     0,
  "phoneNumbers": ["+12202140029"],
  "logFile":      "tpe-migration-run-20260428-180045.html",
  "configPath":   "acs-tpe-config-fromd365.json",
  "d365OrgUrl":   "https://ccaivrtest.crm.dynamics.com/"
}
```

### Type values

| type | Source script | Meaning |
|------|--------------|---------|
| `migrate` | Full-Migration (complete run, StopAfterStep ≥ 10) | Full migration completed (cutover included) |
| `migrate-partial` | Full-Migration (StopAfterStep < 10) | Partial migration (setup only, no cutover). Added v14.4.0 |
| `toggle-to-tpe` | Toggle (ACS → Teams) | Atomic routing flip: ACS disabled, Teams enabled |
| `toggle-to-acs` | Toggle (Teams → ACS) | Atomic routing flip: Teams disabled, ACS restored |
| `flip-teams` | Invoke-FlipToTeams | Re-migrate: assignment + toggle + D365 update |
| `flip-acs` | Invoke-FlipToACS | Rollback: toggle + removal + D365 revert |
| `undo` | Undo-ACS-TPE-Migration | Full reversal of Steps 9→1 |

### result values

| result | Meaning |
|--------|---------|
| `OK` | All operations succeeded |
| `WARN` | Completed with non-fatal warnings |
| `FAIL` | One or more operations failed |

### Write-TpeRunRecord

The `Write-TpeRunRecord` function is defined in each script that writes run records. It uses `PSObject.Properties` iteration for safe access (prevents strict-mode errors when D365OrgUrl is not a direct property).

```powershell
function Write-TpeRunRecord {
    param([hashtable]$Record)
    $json = $Record | ConvertTo-Json -Compress
    Add-Content -Path '.\stats\tpe-runs.jsonl' -Value $json -Encoding UTF8
}
```

### DryRun field

Run records include a `dryRun` boolean field. `Write-TpeRunRecord` is NOT guarded by DryRun — run records are written even for dry runs so dry run attempts appear in the dashboard history. Dry run records use the same `type` values as live runs (no separate `dryrun` type). The `dryRun` boolean distinguishes them and the dashboard displays a `(dry)` suffix in the Type column for dry-run records.

### Failure Path Records

`Write-TpeRunRecord` is called on every failure path (not just success) in Toggle, flip, and orchestrator scripts. When an operation fails, the record is written with `result=FAIL` before `Exit-Script` is called. This ensures the dashboard reflects failed attempts, which is critical for the [Pending Failure Detection](#pending-failure-detection) indicator that alerts operators when the most recent run did not succeed.

## Stats Dashboard (tpe-status.html)

### Purpose

A standalone HTML file rebuilt on every script completion showing:
- Active routing direction (ACS or Teams)
- Table of all historical runs
- Per-run: timestamp, type, result, steps, numbers, log link

### Auto-Refresh

The dashboard includes a `<meta http-equiv="refresh" content="60">` tag that auto-reloads the page every 60 seconds. This allows operators to keep the dashboard open during a migration and see state changes without manual refresh.

### Layout

The dashboard HTML has these sections (top to bottom):

1. **Title bar**: `ACS TPE Migration Status` with version string, D365OrgUrl, and auto-refresh indicator
2. **State banner**: Prominent left-bordered box showing active routing direction
3. **Summary cards**: Three metric cards — Total Runs, Migrate count, Undo count
4. **Run history table**: Last 30 runs in reverse-chronological order
5. **Footer**: Generation timestamp and version

### Active System Indicator

The state banner displays the current routing direction:
- **Teams active**: gold indicator (`#ffd700`) — `MIGRATED — Teams Active`
- **ACS active**: green indicator (`#4ec94e`) — `ROLLED BACK — ACS Active`
- **Unknown**: shown when no successful routing operation found in history
- **Failed overlay**: If the most recent non-dry-run record (regardless of type) has `result=FAIL`, appends `(last run FAILED)` in red to the state label

Detection logic scans `tpe-runs.jsonl` and finds the most recent non-FAIL, non-dry-run record:
- `migrate` or `toggle-to-tpe` or `flip-teams` → **Teams** active
- `toggle-to-acs` or `flip-acs` → **ACS** active
- FAIL records are skipped (they do not represent a stable routing state)
- Dry-run records are excluded from active system determination

### Pending Failure Detection

The dashboard uses dual-query logic for the state banner. First, it finds the last non-dry-run routing record that has a non-FAIL result to determine the active system state (ACS or Teams). Second, it separately checks the absolute last non-dry-run record (regardless of result) for pending failure indication. If the most recent non-dry-run record has `result=FAIL`, the state banner appends `(last run FAILED)` in red — even if a prior successful run determines the actual displayed routing direction. This design prevents a failed flip attempt from changing the displayed routing direction while still alerting operators to the failure.

### Dashboard 30-Record Limit

The run history table displays only the last 30 records. Records are reversed with `[array]::Reverse($recent)` to achieve reverse-chronological display (newest first). Older records remain in `tpe-runs.jsonl` and are included in summary card counts and active system detection, but they are not shown in the dashboard table.

### Summary Cards

Three inline metric cards:

| Card | Count Source | Color |
|------|-------------|-------|
| Total Runs | `$records.Count` | White |
| Migrate | Non-dry-run records with type `migrate`, `flip-teams`, or `toggle-to-tpe` | Cyan (`#00bfff`) |
| Undo | Non-dry-run records with type `undo`, `flip-acs`, or `toggle-to-acs` | Red (`#ff6b6b`) |

### Run History Table

Displays the **last 30** run records in reverse-chronological order. Each row shows:

| Column | Content |
|--------|---------|
| Timestamp | `$r.timestamp` |
| Type | `MIGRATE` (cyan) or `UNDO` (red), with `(dry)` suffix for dry runs |
| Steps | `Steps N→M` (migrate direction) or `Steps M←N` (undo direction) |
| Numbers | Comma-separated phone numbers, XSS-escaped |
| Result | OK (green), WARN (gold), FAIL (red), with failure count suffix |
| Log | Clickable HTML link to the run log file |

### Per-Number State (planned — not yet implemented)

A future enhancement: a per-number state table derived from the most recent run records. For each phone number that has appeared in any run:

| Column | Source |
|--------|--------|
| Phone Number | `phoneNumbers` array from run records |
| Current System | Derived from the most recent non-FAIL routing operation that included this number |
| Last Operation | Type and timestamp of the last run that included this number |
| Result | OK / WARN / FAIL from the last run |

This would allow operators to see at a glance which numbers are on Teams vs ACS. **Note**: The current `Update-TpeStatusDashboard` implementation does not generate this table — it only produces summary cards (Total Runs, Migrate, Undo) and the run history table.

### Dashboard regeneration

```powershell
function Update-TpeStatusDashboard {
    $runs = Get-Content '.\stats\tpe-runs.jsonl' | ForEach-Object { $_ | ConvertFrom-Json }
    # Build HTML table...
    Set-Content -Path '.\tpe-status.html' -Value $html -Encoding UTF8
}
```

Called at the end of every script (before Exit-Script).

## Archive-TpeRuns-v14.ps1

Moves old HTML run logs and JSON config artifacts into backup subdirectories to keep the working directory clean. See [Utility Scripts — Archive-TpeRuns](utility-scripts.md#archive-tperuns-v14ps1) for full specification.

### Actions

**HTML run log archiving** (`backup-run/`):
1. Collect HTML files matching: `tpe-migration-run-*`, `tpe-undo-run-*`, `tpe-flip-acs-run-*`, `tpe-flip-teams-run-*`, `tpe-toggle-run-*`
2. Sort by **Name** (lexicographic, not LastWriteTime) — relies on the `yyyyMMdd-HHmmss` timestamp in filenames for chronological ordering; keep the latest of each type in the working directory
3. Archive older versioned status pages
4. Move files into `backup-run/`

**JSON config archiving** (`backup-config-json/`):
- Keep active config (newest by Name sort)
- Archive old configs and backup artifacts (`*-backup-*`, `*-undooperation-*`)
- Move files into `backup-config-json/`

**Never archived** (essential working files): `ra-objectids.json`, `acs-export.json`, `d365-phone-backup.json`, `acs-trunk-disabled.json`

### DryRun

Shows planned moves without executing (`Would move <file> → <backup-dir>/<file>`).

## Post-Operation Checklists

Both flip scripts display post-operation verification checklists after completing their operations:

- **FlipToACS** (`Invoke-FlipToACS-v14.ps1`): Displays a 4-item rollback verification checklist (e.g., confirm ACS routing restored, Teams routes disabled, phone numbers reachable via ACS, D365 records reverted).
- **FlipToTeams** (`Invoke-FlipToTeams-v14.ps1`): Displays a 4-item cutover verification checklist specific to Teams (e.g., confirm Teams routing active, ACS routes disabled, phone numbers reachable via Teams, D365 records updated).
- **Orchestrator Step 10** (`Invoke-ACS-TPE-Full-Migration-v14.ps1`): Displays a pre-cutover checklist reminder (4 items) before executing the final cutover toggle.

These checklists are written to both console (`Write-Host`) and HTML log (`Write-HtmlLine`) so they appear in the operator's terminal and in the archived run log for audit purposes.
