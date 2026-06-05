#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone test script for Step 4: Register and verify a custom domain in Microsoft Entra ID.

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.11.0   : Version string parity with all scripts.
    v14.9.0    : Version string parity with all scripts.
    v14.8.0    : Dashboard state skips FAIL results when determining active system
                 (prevents misleading state after failed operation), Test-DomainRegistration
                 DryRun no longer sets $verified=$true (shows accurate DryRun behavior),
                 version strings bumped to v14.8.0.
    v14.0.0    : Compatible with v10 migration (no ACS consent step).

.DESCRIPTION
    Extracted from Invoke-ACS-TPE-Full-Migration-v5.ps1 Step 4 for isolated testing.
    Supports three modes:
      - Register + verify a new domain (default)
      - Check status of an existing domain (-CheckOnly)
      - Remove a domain (-Remove) for cleanup after testing

    Auth: Microsoft Graph (Connect-MgGraph)

.PARAMETER Domain
    The domain to register/verify  e.g. contoso.com

.PARAMETER TenantId
    Microsoft Entra ID Tenant ID (GUID).

.PARAMETER AdminUpn
    Teams/Graph Admin UPN. Used to connect to Microsoft Graph.

.PARAMETER CheckOnly
    Only check if the domain is registered and verified. No changes made.

.PARAMETER Remove
    Remove the domain from Entra ID after testing (cleanup).

.PARAMETER DryRun
    Show what would be done without making any changes.

.EXAMPLE
    .\Test-DomainRegistration-v14.ps1 -Domain "test.contoso.com" -TenantId "xxxx" -AdminUpn "admin@contoso.com"
    .\Test-DomainRegistration-v14.ps1 -Domain "test.contoso.com" -TenantId "xxxx" -AdminUpn "admin@contoso.com" -CheckOnly
    .\Test-DomainRegistration-v14.ps1 -Domain "test.contoso.com" -TenantId "xxxx" -AdminUpn "admin@contoso.com" -Remove
    .\Test-DomainRegistration-v14.ps1 -ConfigPath .\acs-tpe-config-fromd365-local.json -Domain "test.contoso.com"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Domain    = '',
    [string]$TenantId  = '',
    [string]$AdminUpn  = '',
    [string]$ConfigPath = '',
    [switch]$CheckOnly,
    [switch]$Remove,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info  { param([string]$m) Write-Host "  -- $m" -ForegroundColor Gray }
function Write-Step  { param([string]$m) Write-Host "  >> $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "  OK $m" -ForegroundColor Green }
function Write-Warn  { param([string]$m) Write-Host "  WARN $m" -ForegroundColor Yellow }
function Write-Err   { param([string]$m) Write-Host "  ERR $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Load from config if provided
# ---------------------------------------------------------------------------
if ($ConfigPath) {
    if (-not (Test-Path $ConfigPath)) { Write-Err "Config not found: $ConfigPath"; exit 1 }
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $TenantId -and $cfg.PSObject.Properties['TenantId']) { $TenantId = $cfg.TenantId }
    if (-not $AdminUpn -and $cfg.PSObject.Properties['AdminUpn'])  { $AdminUpn = $cfg.AdminUpn }
    if (-not $Domain   -and $cfg.PSObject.Properties['Domain'])    { $Domain   = $cfg.Domain }
    Write-Info "Loaded TenantId, AdminUpn, Domain from config."
}

# ---------------------------------------------------------------------------
# Validate required params
# ---------------------------------------------------------------------------
if (-not $Domain)   { $Domain   = (Read-Host "  Domain to register (e.g. contoso.com)").Trim() }
if (-not $TenantId) { $TenantId = (Read-Host "  Tenant ID (GUID)").Trim() }
if (-not $AdminUpn) { $AdminUpn = (Read-Host "  Admin UPN").Trim() }

Write-Host ""
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host "|   Domain Registration Test                                       |" -ForegroundColor Cyan
Write-Host "+==================================================================+" -ForegroundColor Cyan
Write-Host "  Domain    : $Domain" -ForegroundColor White
Write-Host "  Tenant ID : $TenantId" -ForegroundColor White
Write-Host "  Admin UPN : $AdminUpn" -ForegroundColor White
Write-Host "  Mode      : $(if ($DryRun) { 'DRY RUN' } elseif ($CheckOnly) { 'CHECK ONLY' } elseif ($Remove) { 'REMOVE' } else { 'REGISTER + VERIFY' })" -ForegroundColor Yellow
Write-Host ""

# ---------------------------------------------------------------------------
# Connect to Microsoft Graph
# ---------------------------------------------------------------------------
Write-Step "Connecting to Microsoft Graph ..."
if ($DryRun) {
    Write-Info "(DRY RUN) Would connect: Connect-MgGraph -TenantId $TenantId"
} else {
    try {
        Connect-MgGraph -TenantId $TenantId -Scopes 'Domain.ReadWrite.All' -NoWelcome
        Write-OK "Graph connected."
    } catch {
        Write-Err "Graph connection failed: $_"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Check current domain status
# ---------------------------------------------------------------------------
Write-Step "Checking domain '$Domain' in Entra ID ..."
$domainObj = $null
if (-not $DryRun) {
    try { $domainObj = Get-MgDomain -DomainId $Domain -ErrorAction SilentlyContinue } catch {}
}

if ($domainObj) {
    $verifiedLabel = if ($domainObj.IsVerified) { 'VERIFIED' } else { 'NOT VERIFIED' }
    $color = if ($domainObj.IsVerified) { 'Green' } else { 'Yellow' }
    Write-Host "  Domain exists : $Domain  [$verifiedLabel]" -ForegroundColor $color
    Write-Host "  IsDefault     : $($domainObj.IsDefault)" -ForegroundColor Gray
    Write-Host "  IsInitial     : $($domainObj.IsInitial)" -ForegroundColor Gray
} else {
    Write-Info "Domain '$Domain' does NOT exist in this tenant."
}

if ($CheckOnly) {
    Write-Host ""
    Write-Info "(-CheckOnly) No changes made."
    exit 0
}

# ---------------------------------------------------------------------------
# -Remove: delete domain
# ---------------------------------------------------------------------------
if ($Remove) {
    if (-not $domainObj) { Write-Warn "Domain '$Domain' not found -- nothing to remove."; exit 0 }
    if ($domainObj.IsDefault -or $domainObj.IsInitial) {
        Write-Err "Cannot remove default or initial domain."
        exit 1
    }
    Write-Host ""
    Write-Host "  About to REMOVE domain: $Domain" -ForegroundColor Red
    $confirm = (Read-Host "  Proceed? [Y/n]").Trim()
    if ($confirm -ne '' -and $confirm -notmatch '^[Yy]') { Write-Info "Aborted."; exit 0 }
    if ($DryRun) {
        Write-Info "(DRY RUN) Would call: Remove-MgDomain -DomainId '$Domain'"
    } else {
        try {
            Remove-MgDomain -DomainId $Domain
            Write-OK "Domain '$Domain' removed from Entra ID."
        } catch {
            Write-Err "Remove failed: $_"
            exit 1
        }
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Register + Verify
# ---------------------------------------------------------------------------

# Step A: Register if not exists
if ($domainObj -and $domainObj.IsVerified) {
    Write-OK "Domain '$Domain' is already registered and verified. Nothing to do."
    exit 0
}

if (-not $domainObj) {
    Write-Step "Registering domain '$Domain' ..."
    if ($DryRun) {
        Write-Info "(DRY RUN) Would call: New-MgDomain -Id '$Domain'"
    } else {
        try {
            New-MgDomain -Id $Domain | Out-Null
            Write-OK "Domain '$Domain' registered."
        } catch {
            if ($_ -like '*already exists*' -or $_ -like '*ObjectConflict*') {
                Write-Warn "Domain already exists -- continuing to verification."
            } else {
                Write-Err "Failed to register domain: $_"
                exit 1
            }
        }
    }
} else {
    Write-Warn "Domain exists but is NOT verified -- proceeding to verification."
}

# Step B: Get verification DNS records
Write-Step "Retrieving verification DNS records for '$Domain' ..."
if ($DryRun) {
    Write-Info "(DRY RUN) Would call: Get-MgDomainVerificationDnsRecord -DomainId '$Domain'"
    Write-Info "(DRY RUN) TXT record would be displayed for DNS registrar entry."
} else {
    try {
        $dnsRecords = Get-MgDomainVerificationDnsRecord -DomainId $Domain
        if (-not $dnsRecords -or $dnsRecords.Count -eq 0) {
            Write-Warn "No DNS records returned. Domain may need a moment to initialize."
            Write-Warn "Wait 30s and re-run with -CheckOnly to see if records appear."
        } else {
            Write-OK "Add the following record at your DNS registrar:"
            Write-Host ""
            foreach ($rec in $dnsRecords) {
                Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
                Write-Host ("  Type       : {0}" -f $rec.RecordType) -ForegroundColor White
                Write-Host ("  Label      : {0}" -f $rec.Label)      -ForegroundColor White
                if ($rec.AdditionalProperties['text']) {
                    Write-Host ("  TXT Value  : {0}" -f $rec.AdditionalProperties['text']) -ForegroundColor Yellow
                }
                if ($rec.AdditionalProperties['canonicalName']) {
                    Write-Host ("  CNAME      : {0}" -f $rec.AdditionalProperties['canonicalName']) -ForegroundColor Yellow
                }
                Write-Host ("  TTL        : {0}" -f $rec.Ttl) -ForegroundColor White
            }
            Write-Host ""
        }
    } catch {
        Write-Warn "Could not retrieve DNS records: $_"
    }
}

# Step C: Wait for DNS, then verify
Write-Host ""
Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
Write-Host "  ACTION REQUIRED:" -ForegroundColor Yellow
Write-Host "  Add the TXT record above at your DNS registrar for '$Domain'." -ForegroundColor Yellow
Write-Host "  DNS propagation is usually a few minutes (up to 72h for some registrars)." -ForegroundColor Gray
Write-Host ""

$confirm = (Read-Host "  Press ENTER when DNS record is added (or type 'skip' to verify later)").Trim()
if ($confirm.ToLower() -eq 'skip') {
    Write-Warn "Skipped verification. Re-run this script (or the full migration with -StartAtStep 4) after DNS propagates."
    exit 0
}

Write-Step "Attempting automated verification (polling up to 5 min, every 30s) ..."
$verified    = $false
$maxAttempts = 10
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    Write-Info "  Attempt $attempt/$maxAttempts ..."
    if ($DryRun) {
        Write-Info "(DRY RUN) Would call: Confirm-MgDomain -DomainId '$Domain'"
        Write-Info "(DRY RUN) Skipping verification polling."
        break
    }
    try {
        Confirm-MgDomain -DomainId $Domain -ErrorAction Stop | Out-Null
        $domainCheck = Get-MgDomain -DomainId $Domain -ErrorAction SilentlyContinue
        if ($domainCheck -and $domainCheck.IsVerified) {
            Write-OK "Domain '$Domain' verified successfully!"
            $verified = $true; break
        }
    } catch { }
    if ($attempt -lt $maxAttempts) {
        Write-Info "  Not yet verified -- waiting 30s ..."
        Start-Sleep -Seconds 30
    }
}

if ($DryRun) {
    Write-OK "(DRY RUN) Verification would proceed after DNS records are configured."
} elseif (-not $verified) {
    Write-Warn "Auto-verification timed out after 5 min."
    Write-Warn "Re-run with -CheckOnly to check status, or run full migration with -StartAtStep 4 after DNS propagates."
    exit 1
}

Write-Host ""
Write-OK "Domain registration and verification complete. Ready to use in migration."

