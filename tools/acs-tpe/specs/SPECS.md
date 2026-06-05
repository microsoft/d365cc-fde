# ACS-TPE Migration Tool — Specification Index

## Purpose

ACS-TPE (ACS to Teams Phone Extensibility) is an 18-script PowerShell suite for migrating phone numbers from Azure Communication Services (ACS) Direct Routing to Microsoft Teams Phone System (Teams Direct Routing + Teams Resource Accounts + Dynamics 365 CCaaS integration) without interrupting live calls. All scripts are at version 14.16.0 (code). Git tag: `acs-tpe-v14.17.0` (includes 854 Pester tests and specification suite).

The tool:
- Queries Dynamics 365 (D365) for active ACS phone numbers and auto-builds a migration plan
- Registers a Teams Direct Routing gateway reusing the existing SBC FQDN with zero ACS downtime
- Creates Teams PSTN usages, voice routes, and voice routing policies
- Registers and verifies the SBC domain in Microsoft Entra ID
- Creates Teams Resource Accounts (application instances) for each phone number
- Assigns Teams Phone Resource Account licenses
- Assigns Direct Routing phone numbers to resource accounts
- Performs atomic cutover (ACS→Teams) or rollback (Teams→ACS)
- Updates Dynamics 365 phone number type and triggers CCaaS sync
- Produces HTML run logs and a persistent stats dashboard for every operation

## Migration Flow (Quick Reference)

| Phase/Step | Action | Key Detail |
|------------|--------|------------|
| Phase 0 | Install and connect Teams + Graph modules | Interactive auth |
| Phase 0D | Query D365 for active ACS phone numbers | Filter by `IncludeNumbers`; auto-build ResourceAccounts |
| Step 1 | Export ACS SIP trunks and voice routes | Write `acs-export.json` |
| Step 2 | Zero-downtime Teams DR registration | Disable ACS → create Teams gateway (disabled) → re-enable ACS |
| Step 3 | Create PSTN usage, voice route, routing policy | E.164 alternation pattern from config ResourceAccounts |
| Step 4 | Register and verify SBC domain in Entra ID | DNS TXT verification |
| Step 5 | Validate SBC gateway, voice route, policy | Config objects only (not full ACS export) |
| Step 6 | Upload phone numbers into Teams tenant | `Set-CsPhoneNumberAssignment` type DirectRouting |
| Step 7 | Create resource accounts | `New-CsOnlineApplicationInstance`; write `ra-objectids.json` |
| Step 8 | Assign Teams Phone Resource Account licenses | Poll until licensed; guard against empty ObjectId |
| Step 9 | Assign phone numbers to resource accounts | D365 backup before mutations |
| Step 10 | Cutover: ACS→Teams | Call Toggle with `-AutoConfirm` |
| Step 11 | D365 update + CCaaS sync | PATCH type=1, source=TPS, bind RA |

## Key Concepts

- **Zero downtime**: ACS trunk disabled for ~15 seconds during Step 2 gateway registration, then 30 seconds for Teams propagation. ACS handles all calls through Steps 3–9. Atomic cutover in Step 10.
- **DryRun**: Every mutating script supports `-DryRun`. The orchestrator's DryRun exits immediately after the plan summary; individual scripts show planned actions without calling mutating APIs. HTML logs and JSONL records are still written.
- **IncludeNumbers**: Empty `[]` triggers interactive selection from D365 (hybrid row-number or phone-number input); populated array auto-selects without prompting.
- **Atomic flip**: Toggle auto-detects routing direction, validates target-side exists, and performs ACS↔Teams swap with restore-on-failure for the ACS trunk. Exits with "NEITHER side is active" if recovery also fails.
- **Resume support**: `-StartAtStep` / `-StopAfterStep` allow partial runs and resumption after failure. On resume, prompts for `AcsConnectionString` if excluded from saved config.
- **Config-driven**: Single JSON config file drives the entire migration, built by `New-AcsTpeConfig-v14.ps1` (8-phase auto-discovery) or Phase 0D.
- **Verification GET**: Three ACS-facing scripts verify PATCH results with a follow-up HMAC-signed GET; verification failure is non-fatal (warning only, does not exit).

## Specifications

| # | Spec | Description |
|---|------|-------------|
| 1 | [Architecture Overview](architecture-overview.md) | System architecture, script inventory (18 scripts), design principles (incl. Phase 0 license pre-check, Get-CsTenant session reuse, v14.13.0+ config-scoped operations, v14.16.0 partial-failure resilience), execution modes, DryRun early exit, 8-phase discovery flow, helper function categories (~19 functions, incl. Invoke-D365Discovery DR/DO classification), key artifacts (14 files with DryRun behavior), parameter validation attributes, prerequisites (4 Entra roles), module install (-Scope CurrentUser), versioning (inline embedding, .NOTES parity) |
| 2 | [Configuration](configuration.md) | Config JSON schema (orchestrator + auto-discovery), all fields with types and defaults, ResourceAccount object (incl. D365Name, Type fields), IncludeNumbers behavior, validation rules, resume mode guard, AcsConnectionString re-prompt on resume, Phase 0A interactive 16-prompt flow, cross-subscription ACS support, SBC port handling, AcsEndpoint auto-extraction, AcsConnectionString exclusion from auto-saved configs |
| 3 | [Migration Steps](migration-steps.md) | Phase 0 (module setup with -Scope CurrentUser, Get-CsTenant session check, license pre-check, Graph Organization.Read.All + Domain.ReadWrite.All scopes), Phase 0D (D365 discovery with FetchXML, DR/DO classification, hybrid selection), Steps 1–11 detailed specification with parameters and validation attributes, Step 1 ACS-unreachable fallback, Step 2 updated wait times (15s+30s), Step 5 Confirm-Continue prompt, Step 6 upload order + non-fatal timeout, Step 7 RA stamping/reuse/resume, Step 9 prior-assignment removal + InProgress retry status + D365 verification, DryRun early exit, HTML footer step summary, run record schema |
| 4 | [Flip and Rollback](flip-rollback.md) | FlipToACS (confirmation prompt, Teams reconnection fallback, post-rollback checklist, failure remediation commands, exit code 1), FlipToTeams (confirmation prompt, ra-objectids.json mandatory, Step A abort-on-failure, Step B double-confirmation, Step C explicit ObjectId, post-cutover checklist), Toggle (pre-flight guards, ConfigPath required, target-side existence check, not-found-on-either error, ACS route save failure handling, TPE→ACS parse fallback, NEITHER-active recovery, observability details) |
| 5 | [ACS REST API](acs-rest-api.md) | HMAC-SHA256 authentication, connection string parsing, /sip GET and PATCH endpoints (trunk `enabled` field handling), JSON Merge Patch atomicity, Invoke-AcsGet/Invoke-AcsPatch helpers, Build-HmacHeaders/Parse-ConnectionString (Set-AcsSbcFqdn), verification GET pattern (3 scripts, non-fatal), error detail extraction (ErrorDetails + response stream fallback), _raw field preservation, acs-trunk-disabled.json and acs-export.json artifacts, DryRun behavior |
| 6 | [D365 Integration](d365-integration.md) | OAuth2 + az CLI auth, D365 Global Discovery Service, OData v9.2 API (If-Match: * header, three header sets), FetchXML queries (provider settings, DynamicsAppId), phone number PATCH operations (ACS↔TPS, msdyn_teamsresourceaccount binding), CCaaS sync trigger, HTTP 204 handling, msdyn_TelephonyACSSyncPhoneNumbersAction (D365-to-Azure sync), D365 backup (18-field per-number snapshot keyed by phone number), Repair BYON DR awareness + record classification, summary blocks, per-script DryRun details |
| 7 | [Teams Integration](teams-integration.md) | MicrosoftTeams + Microsoft.Graph modules (-Scope CurrentUser install, Organization.Read.All + Domain.ReadWrite.All scopes, Get-CsTenant session reuse), required roles, Phase 0 license pre-check, DR gateway lifecycle, PSTN usages/routes/policies, resource account creation (retry logic, RA stamping, existing RA reuse, propagation polling), PHONESYSTEM_VIRTUALUSER licensing with polling, phone number assignment (prior-assignment removal, retry logic), bulk DR upload orders (non-fatal timeout), domain registration, undo operations |
| 8 | [Security](security.md) | XSS prevention (3-char and 5-char escape functions, v14.15.0 footer/failure-list hardening), crypto object disposal (HMACSHA256/SHA256 try/finally, verification GET disposal), credential handling (AcsConnectionString exclusion, SecureString re-prompt), error detail extraction (no credentials in output, v14.15.0 null guard), connection string validation (v14.15.0), OData update headers (If-Match: *, three header sets), E.164 validation regex, input validation summary, HTTP/TLS security, session file security |
| 9 | [Operational Requirements](operational-requirements.md) | #Requires directive, StrictMode, CmdletBinding (SupportsShouldProcess on 5 scripts incl. Set-AcsSbcFqdn + Test-DomainRegistration, bare param on 3 scripts), sub-script resolution, DryRun contract (orchestrator early exit), Exit-Script pattern, idempotency, dual-output helpers, interactive helpers (Prompt-Required secret masking/GUID validation, Prompt-Optional, Confirm-Continue, Wait-WithMessage), undo-specific helpers (Invoke-Undo, Confirm-Step, Invoke-D365SyncFromAzure, RA reconstruction), error handling (result threshold, undo RA reconstruction, ConvertFrom-Json null guard), resume support (AcsConnectionString re-prompt), module install (-Scope CurrentUser), verification GET pattern, versioning (inline embedding, .NOTES parity, milestone banner bumps) |
| 10 | [HTML Reporting](html-reporting.md) | HTML run logs (dark-theme, 9 color classes, title version lags .NOTES), Write-HtmlLine helper (error suppression), invocation line capture, HTML footer step summary, JSONL run records (7 types incl. logFile field, failure path records), stats dashboard (auto-refresh, state banner, pending failure detection, summary cards, 30-record history table, per-number state planned), post-operation checklists, Archive-TpeRuns (sort by Name) |
| 11 | [Testing](testing.md) | Pester 5.x test suite (~5,900 lines, 854 tests at v14.17.0), mock strategy, 10 pure function unit tests (77 tests), version parity (historical .NOTES parity + banner string parity via Should -Match), 3-tier HMAC dispose verification (incl. verification GET crypto), README content tests, Get-TeamsProviderSetting error handling, dashboard generation, step-by-step regression tests, DryRun behavior, v14.13.0 IncludeNumbers filter tests, v14.14.0 Step 3 config-only route tests, v14.15.0 Step 5 config-only validation tests, v14.16.0 Step 8 ObjectId guard tests, v14.17.0 41 new feature tests + 26 version string fixes, all 18 scripts referenced (14 deep + 4 lightweight coverage) |
| 12 | [Utility Scripts](utility-scripts.md) | 8 utility scripts (console-only output except Undo): New-AcsTpeConfig (8-phase auto-discovery, post-assembly validation), Set-AcsSbcFqdn (Build-HmacHeaders, _raw preservation, verification GET), Add-AcsTrunkDisabled (corrected: no -Fqdn param, direct PATCH, verification GET), Fix-AcsRoutePattern (verification GET, exit code 1), Get-TeamsProviderSetting (corrected: -OrgUrl + D365 REST, not Teams PowerShell), Test-DomainRegistration (domain guards, skip option, DryRun skips Graph), Archive-TpeRuns (sort by Name, catch-all JSON sweep), Undo-ACS-TPE-Migration (RA reconstruction, ACS endpoint fallback, result threshold, D365 restoration) |

## Script Inventory

| # | Script | Type | Description |
|---|--------|------|-------------|
| 1 | `Invoke-ACS-TPE-Full-Migration-v14.ps1` | Orchestrator | 11-step interactive migration with DryRun, step-range, UsageLocation |
| 2 | `Invoke-FlipToACS-v14.ps1` | Flip | Rollback Teams→ACS (3 steps: toggle + remove + D365) |
| 3 | `Invoke-FlipToTeams-v14.ps1` | Flip | Re-migrate ACS→Teams (3 steps: assign + toggle + D365) |
| 4 | `Toggle-AcsTeamsRouting-v14.ps1` | Flip | Atomic routing direction flip with auto-detection |
| 5 | `New-AcsTpeConfig-v14.ps1` | Config | Interactive 8-phase auto-discovery config builder |
| 6 | `Set-AcsSbcFqdn-v14.ps1` | Config | Updates SbcFqdn in existing config (rename/remove/list) |
| 7 | `Invoke-MigrateTpsPhoneNumber-v14.ps1` | D365 | PATCH single D365 phone record with auto-discovered provider |
| 8 | `Invoke-TeamsPhoneSync-v14.ps1` | D365 | Triggers CCaaS sync using explicit ProviderSettingId |
| 9 | `Repair-D365PhoneRecord-v14.ps1` | D365 | Detects and corrects corrupted D365 phone records |
| 10 | `Update-PhoneNumberType-v14.ps1` | D365 | Bulk update phone number type fields (explicit provider) |
| 11 | `Sync-TeamsPhoneNumbers-v14.ps1` | D365 | Auto-discovers provider and triggers CCaaS sync |
| 12 | `Add-AcsTrunkDisabled-v14.ps1` | SBC Utility | Temporarily disables ACS trunk via PATCH |
| 13 | `Fix-AcsRoutePattern-v14.ps1` | SBC Utility | Patches E.164 pattern on ACS voice route |
| 14 | `Get-TeamsProviderSetting-v14.ps1` | SBC Utility | Reads Teams provider/carrier config for CommsProviderId |
| 15 | `Test-DomainRegistration-v14.ps1` | SBC Utility | Validates/registers/removes Entra ID domain registration |
| 16 | `Undo-ACS-TPE-Migration-v14.ps1` | Operations | Full undo of Steps 9→1 with tracking counters |
| 17 | `Archive-TpeRuns-v14.ps1` | Operations | Archives old HTML run logs and JSON configs |
| 18 | `Test-ACS-TPE-Migration-v14.Tests.ps1` | Testing | Pester 5.x unit test suite (854 tests) |

## External Systems

| System | Protocol | Authentication | Used For |
|--------|----------|---------------|----------|
| ACS REST API | HTTPS + HMAC-SHA256 | Connection string (endpoint + accesskey) | SIP trunk and voice route management |
| Teams PowerShell | MicrosoftTeams module | Interactive (device code) | DR gateway, PSTN usages, routes, policies, resource accounts, phone assignment |
| Microsoft Graph | Microsoft.Graph module | Interactive (OAuth2 scopes) | Entra ID domain registration, user licensing |
| Dynamics 365 OData v9.2 | HTTPS | az CLI token / OAuth2 client_credentials / interactive | Phone number discovery, type PATCH, CCaaS sync |
| D365 Global Discovery | HTTPS | az CLI token | Auto-discover D365 org URL |
| Azure Management API | HTTPS | az CLI token | ACS resource discovery, connection string retrieval |
