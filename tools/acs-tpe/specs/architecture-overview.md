# Architecture Overview

## Purpose

ACS-TPE migrates phone numbers from Azure Communication Services (ACS) Direct Routing to Microsoft Teams Phone System (Teams Phone Extensibility / TPE). The migration reuses the existing SBC FQDN across both systems to achieve zero call downtime during the transition period.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ACS-TPE Tool (PowerShell)                       │
├──────────────────┬──────────────────┬───────────────────────────────┤
│  Orchestrator    │  Flip/Rollback   │  Configuration                │
│  ─────────────  │  ─────────────  │  ─────────────               │
│  Full-Migration  │  FlipToACS       │  New-AcsTpeConfig             │
│  (Steps 0-11)   │  FlipToTeams     │  Set-AcsSbcFqdn               │
│                  │  Toggle          │                               │
├──────────────────┴──────────────────┴───────────────────────────────┤
│  D365 Integration              │  SBC / Route Utilities             │
│  ─────────────────            │  ──────────────────                │
│  Invoke-MigrateTpsPhoneNumber  │  Add-AcsTrunkDisabled              │
│  Invoke-TeamsPhoneSync         │  Fix-AcsRoutePattern               │
│  Repair-D365PhoneRecord        │  Get-TeamsProviderSetting          │
│  Update-PhoneNumberType        │  Test-DomainRegistration           │
│  Sync-TeamsPhoneNumbers        │                                    │
├────────────────────────────────┴────────────────────────────────────┤
│  Operations                    │  Testing                           │
│  ──────────                   │  ───────                           │
│  Undo-ACS-TPE-Migration        │  Test-ACS-TPE-Migration.Tests      │
│  Archive-TpeRuns               │  (854 unit tests)                  │
└────────────────────────────────┴────────────────────────────────────┘
            │                                │
            ▼                                ▼
┌───────────────────┐            ┌───────────────────────┐
│  ACS REST API     │            │  Teams PowerShell      │
│  (HTTP + HMAC)    │            │  MicrosoftTeams module │
│  D365 OData v9.2  │            │  Microsoft.Graph module│
└───────────────────┘            └───────────────────────┘
```

## Script Inventory

| Script | Type | Description |
|--------|------|-------------|
| `Invoke-ACS-TPE-Full-Migration-v14.ps1` | Orchestrator | 11-step interactive migration with DryRun, step-range, UsageLocation |
| `Invoke-FlipToACS-v14.ps1` | Flip | Rollback Teams→ACS (3 steps: toggle + remove + D365) |
| `Invoke-FlipToTeams-v14.ps1` | Flip | Re-migrate ACS→Teams (3 steps: assign + toggle + D365) |
| `Toggle-AcsTeamsRouting-v14.ps1` | Flip | Atomic routing direction flip with auto-detection |
| `New-AcsTpeConfig-v14.ps1` | Config | Interactive 8-phase auto-discovery config builder |
| `Set-AcsSbcFqdn-v14.ps1` | Config | Updates SbcFqdn in existing config (rename/remove/list) |
| `Invoke-MigrateTpsPhoneNumber-v14.ps1` | D365 | PATCH single D365 phone record with auto-discovered provider |
| `Invoke-TeamsPhoneSync-v14.ps1` | D365 | Triggers CCaaS sync using explicit ProviderSettingId |
| `Repair-D365PhoneRecord-v14.ps1` | D365 | Detects and corrects corrupted D365 phone records |
| `Update-PhoneNumberType-v14.ps1` | D365 | Bulk update phone number type fields (explicit provider) |
| `Sync-TeamsPhoneNumbers-v14.ps1` | D365 | Auto-discovers provider and triggers CCaaS sync |
| `Add-AcsTrunkDisabled-v14.ps1` | SBC Utility | Temporarily disables ACS trunk via PATCH |
| `Fix-AcsRoutePattern-v14.ps1` | SBC Utility | Patches E.164 pattern on ACS voice route |
| `Get-TeamsProviderSetting-v14.ps1` | SBC Utility | Reads Teams provider/carrier config for CommsProviderId |
| `Test-DomainRegistration-v14.ps1` | SBC Utility | Validates/registers/removes Entra ID domain registration |
| `Undo-ACS-TPE-Migration-v14.ps1` | Operations | Full undo of Steps 9→1 with tracking counters |
| `Archive-TpeRuns-v14.ps1` | Operations | Archives old HTML run logs and JSON configs |
| `Test-ACS-TPE-Migration-v14.Tests.ps1` | Testing | Pester 5.x unit test suite (854 tests) |

## Design Principles

1. **Zero downtime**: ACS trunk is never left disabled for more than the minimum time needed to register the Teams DR gateway (seconds). ACS handles all production calls throughout Steps 3–9.
2. **Idempotent steps**: Each step checks whether objects already exist before creating them. Re-running from a given step is safe.
3. **DryRun first**: Every mutating script supports `-DryRun`; dry run produces identical console output without calling mutating APIs or writing files.
4. **Config-driven**: A single JSON config file (`acs-tpe-config-fromd365.json` or similar) drives the entire migration. Config is built by `New-AcsTpeConfig-v14.ps1` (8-phase auto-discovery) or inferred from D365 discovery in Phase 0D.
5. **Strict mode**: All scripts run with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
6. **HTML audit trail**: Every run produces a timestamped HTML log and appends a record to `stats/tpe-runs.jsonl`, which feeds the `tpe-status.html` dashboard.
7. **Phase 0 license pre-check**: Phase 0 compares available `PHONESYSTEM_VIRTUALUSER` license count against `ResourceAccounts` count and hard exits if insufficient.
8. **Session management**: `New-AcsTpeConfig-v14.ps1` uses `acs-tpe-session.json` (50-minute TTL) to cache validated login state, avoiding redundant authentication flows across script invocations.
9. **Config-scoped operations** (v14.13.0+): Step 2 filters ACS trunks to only `cfg.SbcFqdn` (prevents touching unrelated deployments). Step 3 builds the voice route from config (`cfg.RouteName`, `cfg.SbcFqdn`, phone numbers from `cfg.ResourceAccounts`) — not from `acs-export.json`. Step 5 validates only `cfg.SbcFqdn`, `cfg.RouteName`, and `cfg.PolicyName` in Teams — not the full ACS export.
10. **Partial-failure resilience** (v14.16.0): Step 8 guards against empty ObjectId values when Step 7 partially fails (e.g. authorization error for some UPNs). The license assignment loop uses `if (-not $objectId) { continue }` to skip broken entries rather than crashing.

## Execution Modes

### Full migration (interactive)
```powershell
# Dry run first
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -DryRun

# Full run
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-config.json

# Resume from Step 5
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-config.json -StartAtStep 5
```

### Rollback
```powershell
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-config.json -DryRun
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-config.json
```

### Re-migrate
```powershell
.\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\my-config.json -DryRun
.\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\my-config.json
```

### DryRun Early Exit

The orchestrator's DryRun mode exits immediately after displaying the plan summary with `[DRY RUN COMPLETE] No changes were made.` -- it never enters Phase 0B or any migration steps.

## Key Artifacts

| File | Created by | Purpose | DryRun |
|------|-----------|---------|--------|
| `acs-tpe-config-*.json` | `New-AcsTpeConfig-v14.ps1` or Phase 0A | Migration config; drives all steps | Skipped |
| `acs-export.json` | Step 1 | ACS trunks + routes snapshot; used by Toggle for rollback | Skipped |
| `acs-trunk-disabled.json` | Step 2 | FQDNs disabled during zero-downtime registration | Skipped |
| `ra-objectids.json` | Step 7 | UPN→ObjectId map; scopes flip scripts | Skipped |
| `d365-phone-backup.json` | Step 9 | D365 state before mutations | Skipped |
| `tpe-migration-results.csv` | Step 9 | Phone assignment results | Skipped |
| `tpe-migration-run-*.html` | Full-Migration | Per-run HTML console log | Written |
| `tpe-flip-acs-run-*.html` | FlipToACS | Rollback run log | Written |
| `tpe-flip-teams-run-*.html` | FlipToTeams | Re-migrate run log | Written |
| `tpe-toggle-run-*.html` | Toggle | Atomic flip run log | Written |
| `tpe-undo-run-*.html` | Undo | Full undo run log | Written |
| `tpe-status.html` | Every run | Regenerated stats dashboard | Written |
| `stats/tpe-runs.jsonl` | Every run | Append-only JSONL run history | Written |
| `acs-tpe-session.json` | `Invoke-AcsTpeLogin.ps1` | Cached login session with 50-minute TTL; contains TenantId, SubscriptionId, AdminUpn (no secrets) | N/A |

**Phase 0A config save**: When `-ConfigPath` is not supplied, the orchestrator saves the interactive config to `.\acs-tpe-config-<yyyyMMdd-HHmmss>.json` (excluding `AcsConnectionString` for security).

## Config Builder Discovery Flow

`New-AcsTpeConfig-v14.ps1` auto-discovers config fields through 8 phases:

```
Phase 1: Session ──► TenantId, SubscriptionId, AdminUpn
              │         (acs-tpe-session.json / Invoke-AcsTpeLogin)
              ▼
Phase 2: D365 Global Discovery ──► D365OrgUrl
              │         (globaldisco.crm.dynamics.com)
              ▼
Phase 3: D365 Web API (FetchXML) ──► CommsProviderId, DynamicsAppId, AcsResourceId
              │         (msdyn_occommunicationprovidersetting)
              ▼
Phase 4: Azure Management API ──► AcsEndpoint, AcsConnectionString
              │         (/providers/Microsoft.Communication/communicationServices)
              ▼
Phase 5: ACS SIP REST API ──► SbcFqdn, SbcPort
              │         (HMAC-SHA256 signed GET /sip)
              ▼
Phase 6: User Input ──► Domain, naming defaults
              │
              ▼
Phase 7: Assembly ──► Build config object (with _help), validate 10 required fields
              │
              ▼
Phase 8: Write / Preview ──► Write config JSON (or DryRun preview)
```

Post-assembly (Phase 7), the script validates 10 required fields and reports which ones are empty. Phase 8 writes the config file (guarded by `-DryRun`) and prints a suggested next command for running the migration.

See [Utility Scripts](utility-scripts.md) for detailed phase documentation.

## Helper Function Categories

The orchestrator script defines ~19 internal helper functions. Other scripts define subsets of these. The functions fall into these categories:

| Category | Functions | Purpose |
|----------|-----------|---------|
| Output | `Write-HtmlLine`, `Write-Banner`, `Write-Step`, `Write-OK`, `Write-Warn`, `Write-Err`, `Write-Info`, `Write-PlanStep` | Dual-output (console + HTML) with consistent prefixes and colors |
| Interactive | `Prompt-Required`, `Prompt-Optional`, `Confirm-Continue` | User input during interactive mode; `Prompt-Required` supports `-IsSecret` (uses `Read-Host -AsSecureString` with `Marshal::PtrToStringAuto` to unmask) and GUID validation via `[Guid]::Parse` |
| Lifecycle | `Exit-Script`, `Write-TpeRunRecord`, `Update-TpeStatusDashboard` | HTML log closure, JSONL records, dashboard regeneration |
| Timing | `Wait-WithMessage`, `Wait-UntilRAsReady` | Countdown timers with progress dots; RA propagation polling (max 180s, interval 10s) |
| Data | `Backup-JsonFile`, `Build-RaList`, `Get-NumberPatternRegex`, `Get-D365DrNumbers`, `Test-E164Format` | File backup, RA construction, route pattern generation, D365 query, phone validation |
| Discovery | `Invoke-D365Discovery` | Phase 0D: D365 query, IncludeNumbers filtering, RA auto-generation. Also fetches ACS route patterns via HMAC GET for DR/DO classification (falls back to `acs-export.json` if ACS unreachable), classifies numbers as DR (Direct Routing) vs DO (Direct Outward), displays a numbered table with DR/DO type, and supports hybrid selection by row number OR phone number |
| ACS | `Invoke-AcsTrunkPatch` | HMAC-SHA256 signed PATCH to ACS SIP API |

## Parameter Validation Attributes

PowerShell validation attributes are declared on key parameters and enforced by the runtime before the script body executes:

| Parameter | Attribute | Effect |
|-----------|-----------|--------|
| `StartAtStep` | `[ValidateRange(0, 11)]` | Rejects values outside 0-11 at invocation time |
| `StopAfterStep` | `[ValidateRange(0, 11)]` | Rejects values outside 0-11 at invocation time |
| `UsageLocation` | `[ValidatePattern('^[A-Za-z]{2}$')]` | Requires exactly two ASCII letters (ISO 3166-1 alpha-2 country code) |

Because these are declarative `[Validate*]` attributes, PowerShell raises a terminating `ParameterBindingValidationException` before any script logic runs. No custom error handling is needed.

## Prerequisites

- PowerShell 5.1+ (all scripts include `#Requires -Version 5.1`)
- `MicrosoftTeams` PowerShell module (installed by Phase 0)
- `Microsoft.Graph` PowerShell module (installed by Phase 0 with `-Scope CurrentUser`)
- Azure CLI (`az`) logged in (required by `New-AcsTpeConfig-v14.ps1` and D365 token acquisition)
- **Teams Administrator** role in the target tenant
- **User Administrator** role in Entra ID (required for Step 7 resource account creation)
- **License Administrator** role (required for Step 8 license assignment)
- **Global Administrator** or **Domain Name Administrator** (required for Step 4 domain registration)
- ACS connection string with read/write access to the ACS resource
- D365 service account with access to msdyn_ocphonenumbers and CCaaS actions

## Versioning

All 18 scripts share version parity enforced through `.NOTES` changelog entries. There is no standalone `$scriptVersion` variable — version strings are embedded inline in console banners, HTML `<title>` elements, and `.NOTES` sections. The authoritative version is the latest `.NOTES` entry in the orchestrator (currently `v14.16.0`). Utility script banners are bumped at milestone releases (last: v14.11.0). Version is displayed in:
- Console banner at script start
- HTML log `<title>` and run header
- `.NOTES` changelog in every script
- Git tag: `acs-tpe-v14.17.0` (latest; v14.17.0 added 41 Pester tests for v14.13.0–v14.16.0 coverage)
