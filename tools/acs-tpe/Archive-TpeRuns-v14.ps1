#Requires -Version 5.1
<#
.SYNOPSIS
    Archives old HTML run logs and JSON files to their backup folders. v14.11.0

.DESCRIPTION
    Moves old files into:
      backup-run/         -- old tpe-*-run-*.html files (keeps latest per type)
                            old acs-tpe-v*-status.html files
      backup-config-json/ -- *-backup-*.json, *-undooperation-*.json
                            old config JSON files (keeps newest per prefix)

    Files NEVER archived (always kept in root):
      tpe-status.html          -- live dashboard
      ra-objectids.json        -- needed by FlipToACS / FlipToTeams / Undo
      acs-export.json          -- needed by Toggle / Undo
      d365-phone-backup.json   -- needed by Undo
      acs-trunk-disabled.json  -- needed by Undo
      new-acs-tpe-config-*.json (newest)  -- active config

.PARAMETER DryRun
    Show what would be moved without moving anything.

.EXAMPLE
    .\Archive-TpeRuns-v14.ps1 -DryRun
    .\Archive-TpeRuns-v14.ps1
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root      = $PSScriptRoot
$backupRun = Join-Path $root 'backup-run'
$backupCfg = Join-Path $root 'backup-config-json'

function Write-Head { param([string]$m) Write-Host "" ; Write-Host "  $m" -ForegroundColor Cyan }
function Write-Move { param([string]$src,[string]$dst) Write-Host ("  -> {0,-55} => {1}" -f (Split-Path $src -Leaf), (Split-Path $dst -Parent | Split-Path -Leaf)) -ForegroundColor Gray }
function Write-Keep { param([string]$f) Write-Host "  -- KEEP  $(Split-Path $f -Leaf)" -ForegroundColor DarkGray }
function Write-Info { param([string]$m) Write-Host "  $m" -ForegroundColor DarkGray }

$movedCount = 0

function Move-File {
    param([string]$Src, [string]$Dst)
    if ($DryRun) {
        Write-Move $Src $Dst
    } else {
        if (-not (Test-Path (Split-Path $Dst))) {
            New-Item -ItemType Directory -Path (Split-Path $Dst) -Force | Out-Null
        }
        Move-Item -Path $Src -Destination $Dst -Force
        Write-Move $Src $Dst
        $script:movedCount++
    }
}

# ---------------------------------------------------------------------------
# Ensure backup folders exist
# ---------------------------------------------------------------------------
if (-not $DryRun) {
    @($backupRun, $backupCfg) | ForEach-Object {
        if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    }
}

# ===========================================================================
# SECTION 1 -- HTML RUN LOGS  ->  backup-run/
# ===========================================================================

Write-Head "HTML Run Logs  ->  backup-run/"

# Run log types: keep only the most recent file per type prefix
$runPrefixes = @(
    'tpe-migration-run-',
    'tpe-undo-run-',
    'tpe-flip-acs-run-',
    'tpe-flip-teams-run-',
    'tpe-toggle-run-'
)

foreach ($prefix in $runPrefixes) {
    $files = @(Get-ChildItem -Path $root -Filter "${prefix}*.html" -File |
               Sort-Object Name)   # yyyyMMdd-HHmmss sorts lexicographically = chronologically

    if ($files.Count -eq 0) { continue }

    $latest = $files[-1]   # keep the last (most recent)

    foreach ($f in $files) {
        if ($f.FullName -eq $latest.FullName) {
            Write-Keep $f.FullName
        } else {
            Move-File $f.FullName (Join-Path $backupRun $f.Name)
        }
    }
}

# Old versioned status pages (acs-tpe-v*-status.html) -- always archive
$oldStatus = @(Get-ChildItem -Path $root -Filter 'acs-tpe-v*-status.html' -File)
foreach ($f in $oldStatus) {
    Move-File $f.FullName (Join-Path $backupRun $f.Name)
}

# ===========================================================================
# SECTION 2 -- JSON FILES  ->  backup-config-json/
# ===========================================================================

Write-Head "JSON Files  ->  backup-config-json/"

# Files that must never be archived
$keepJson = @(
    'ra-objectids.json',
    'acs-export.json',
    'd365-phone-backup.json',
    'acs-trunk-disabled.json'
)

# Always archive: backup and undooperation artifacts
$artifactPatterns = @('*-backup-*.json', '*-undooperation-*.json')
foreach ($pat in $artifactPatterns) {
    $files = @(Get-ChildItem -Path $root -Filter $pat -File)
    foreach ($f in $files) {
        Move-File $f.FullName (Join-Path $backupCfg $f.Name)
    }
}

# Config files: find all, keep the newest of each prefix group, archive the rest
$configPatterns = @('new-acs-tpe-config-*.json', 'acs-tpe-config-*.json', 'acs-tpe-config.json')
$configFiles    = @()
foreach ($pat in $configPatterns) {
    $configFiles += @(Get-ChildItem -Path $root -Filter $pat -File)
}
$configFiles = @($configFiles | Sort-Object { $_.FullName } -Unique | Sort-Object LastWriteTime)

if ($configFiles.Count -gt 0) {
    $newestConfig = $configFiles[-1]   # most recently modified = active config
    foreach ($f in $configFiles) {
        if ($f.FullName -eq $newestConfig.FullName) {
            Write-Keep $f.FullName
        } else {
            Move-File $f.FullName (Join-Path $backupCfg $f.Name)
        }
    }
}

# Any other JSON in root not in the keep list and not already handled
$allJson = @(Get-ChildItem -Path $root -Filter '*.json' -File)
foreach ($f in $allJson) {
    # Skip if it's in the keep list
    if ($keepJson -contains $f.Name) { Write-Keep $f.FullName; continue }
    # Skip if already moved (no longer exists)
    if (-not (Test-Path $f.FullName)) { continue }
    # Skip the active config (already handled above -- still present)
    if ($configFiles.Count -gt 0 -and $f.FullName -eq $configFiles[-1].FullName) { continue }
    # Archive anything else
    Move-File $f.FullName (Join-Path $backupCfg $f.Name)
}

# ===========================================================================
# Summary
# ===========================================================================

Write-Host ""
Write-Host "  +--------------------------------------------------+" -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Green' })
if ($DryRun) {
    Write-Host "  |  DRY RUN -- no files were moved                  |" -ForegroundColor Yellow
} else {
    Write-Host "  |  Archive complete -- $movedCount file(s) moved$((' ' * [Math]::Max(0, 19 - $movedCount.ToString().Length)))|" -ForegroundColor Green
}
Write-Host "  |  backup-run/         HTML run logs               |" -ForegroundColor DarkGray
Write-Host "  |  backup-config-json/ old JSON configs/artifacts  |" -ForegroundColor DarkGray
Write-Host "  +--------------------------------------------------+" -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Green' })
Write-Host ""
