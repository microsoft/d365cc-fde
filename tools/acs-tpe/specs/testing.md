# Testing

## Overview

`Test-ACS-TPE-Migration-v14.Tests.ps1` is a Pester 5.x test suite with 854 unit tests covering the ACS-TPE script suite.

> **Note on HTML log scope**: The utility-scripts.md overview states "All support `-DryRun` and produce HTML run logs." This is not fully accurate. The standalone utility scripts (`Add-AcsTrunkDisabled-v14.ps1`, `Fix-AcsRoutePattern-v14.ps1`, `Set-AcsSbcFqdn-v14.ps1`, `Get-TeamsProviderSetting-v14.ps1`, `Test-DomainRegistration-v14.ps1`, `Archive-TpeRuns-v14.ps1`) use `Write-Host` for console output only — they do NOT produce HTML run logs. Only the orchestrator (`Invoke-ACS-TPE-Full-Migration-v14.ps1`), flip scripts (`Invoke-FlipToACS-v14.ps1`, `Invoke-FlipToTeams-v14.ps1`), Toggle (`Toggle-AcsTeamsRouting-v14.ps1`), and Undo (`Undo-ACS-TPE-Migration-v14.ps1`) produce HTML run logs.

## Running the Tests

```powershell
# Run all tests
Invoke-Pester ./Test-ACS-TPE-Migration-v14.Tests.ps1 -Output Detailed

# Run with coverage summary
Invoke-Pester ./Test-ACS-TPE-Migration-v14.Tests.ps1 -Output Detailed -CI
```

All tests must pass before any version tag (`acs-tpe-vX.Y.Z`) is created.

## Test Framework

- **Pester 5.x** (`#Requires -Module Pester`)
- PowerShell 5.1+
- No live ACS, Teams, or D365 connections — all external calls are mocked
- Flat structure — no nested Context blocks; each Describe is a focused test group
- Tests organized chronologically by version release (v12 through v14.17.0)

## Mock Strategy

### External dependencies mocked

| Dependency | Mock approach |
|-----------|--------------|
| `Connect-MicrosoftTeams` | `Mock Connect-MicrosoftTeams {}` |
| `Connect-MgGraph` | `Mock Connect-MgGraph {}` |
| `New-CsOnlinePSTNGateway` | Returns fake gateway object |
| `Set-CsOnlinePSTNGateway` | `Mock Set-CsOnlinePSTNGateway {}` |
| `Get-CsOnlinePSTNGateway` | Returns configurable fake |
| `New-CsOnlineApplicationInstance` | Returns fake with ObjectId |
| `Set-CsPhoneNumberAssignment` | `Mock {}` or returns error |
| `Remove-CsPhoneNumberAssignment` | `Mock {}` |
| `Get-MgSubscribedSku` | Returns fake SKU with PHONESYSTEM_VIRTUALUSER |
| `Set-MgUserLicense` | `Mock {}` |
| `Get-MgUser` | Returns fake user with AssignedLicenses |
| `Get-MgDomain` | Returns fake domain object |
| `New-MgDomain` | `Mock {}` |
| `Invoke-RestMethod` | Returns configurable JSON responses |
| `Invoke-WebRequest` | Returns D365 OAuth token, ACS REST responses |

### ACS REST API mocking

ACS REST API calls use `Invoke-RestMethod` with HMAC-SHA256 auth. Tests mock `Invoke-RestMethod` to return JSON objects representing:
- GET trunks response: `{ value: [{ fqdn: "...", enabled: true, routes: [...] }] }`
- GET routes response: `{ value: [...] }`
- PATCH trunk: `{}` or HTTP error

### D365 API mocking

Tests mock `Invoke-WebRequest` or `Invoke-RestMethod` for:
- Token endpoint: returns `{ access_token: "fake-token" }`
- OData phone numbers: returns `{ value: [...] }`
- PATCH endpoint: returns HTTP 204

## Test Coverage Areas

### Version String Parity

Tests verify that all 18 scripts contain expected version entries in their `.NOTES` changelog sections and banner strings. There is no standalone `$scriptVersion` variable — versions are embedded inline.

Two categories of version parity tests exist:

1. **Historical `.NOTES` parity**: Tests verify that each script's `.NOTES` section contains a changelog entry for specific milestone versions (e.g., `v14.8.0`). This is tested via `Get-Content -Raw | Should -Match 'v14\.8\.0'` across all scripts. This ensures every script was updated at each milestone release.

2. **Banner string parity**: Tests verify that utility script banner strings (e.g., `=== Fix-AcsRoutePattern v14.11.0 ===`) contain the expected version. Utility banners are bumped at milestone releases, not on every patch.

Both test types use file content pattern matching (`Get-Content $path -Raw` with `Should -Match 'vX.Y.Z'`). The test file itself is included in the parity checks to ensure it stays in sync with the scripts it tests.

### Pure Function Unit Tests

The test suite defines 10 pure helper functions in a `BeforeAll` block and tests them in isolation (~77 total tests):

| Function | Tests | Coverage |
|----------|-------|----------|
| `Get-NumberPatternRegex()` | 7 | Empty arrays, single number, common prefix detection, E.164 fallback |
| `Build-RaList()` | 12 | Phone templates, sequential numbering, special char replacement, padding widths (D2/D3/D4), boundary at 999/1000 |
| `Test-IsIgnorableUndoError()` | 11 | "not found", "already removed", "does not exist", "cannot find", "Identity invalid"; rejects real errors |
| `Backup-JsonFile()` | 3 | File existence check, backup creation, content round-trip |
| `Parse-AcsConnectionString()` | 9 | Endpoint/key extraction, base64 handling, malformed strings, null guards |
| `New-AcsHmacSignature()` | 4 | Base64 encoding, determinism, body hash sensitivity, method differentiation |
| `Get-RoutingDirection()` | 16 | ACS/Teams enable/disable combinations, CONFLICT, NEITHER, NOT_FOUND states, ordering |
| `Extract-PhoneFromUpn()` | 11 | Prefix matching, digit extraction, sanitization, dot-prefix handling, no-@ fallback |
| `Get-MigrationResult()` | 4+ | FAIL/WARN/OK states based on failure/in-progress/Step 11 counts |
| `Test-E164Format()` | 5 | Plus prefix, space handling, length validation, international numbers |

### Banner and Output Format Consistency

Tests verify that all scripts produce consistent console banners:
- Version string appears in banner
- `>>` prefix for actions (cyan)
- `OK` prefix for success (green)
- `WARN` prefix for warnings (yellow)
- `!` prefix for errors (red)
- `--` prefix for detail lines (gray)

### HMAC/SHA256 Dispose Verification

Tests verify that all crypto objects (`HMACSHA256`, `SHA256`) are created within `try/finally` blocks and `Dispose()` is called in the `finally` block. Verified in three tiers:

1. **Individual script disposal** (v14.0.3): Toggle, Set-AcsSbcFqdn, Full-Migration, Undo, New-AcsTpeConfig (SHA256 + HMAC dual)
2. **Comprehensive audit** (v14.0.4): All 7 crypto-using scripts (Full-Migration, Undo, Toggle, Set-AcsSbcFqdn, Add-AcsTrunkDisabled, FlipToACS, New-AcsTpeConfig)
3. **Verification GET operations** (v14.11.0): Add-AcsTrunkDisabled and Fix-AcsRoutePattern verification GET cleanup

Tests use file content pattern matching (`Get-Content -Raw | Should -Match '\.Dispose\(\)'`) to verify Dispose calls exist in finally blocks.

### Verification GET Crypto Disposal

Tests verify disposal of additional crypto objects used in verification GET requests (separate from the primary PATCH/POST crypto objects). Specifically, tests check for `$getSha.Dispose()`, `$getHmac.Dispose()`, `$vSha.Dispose()`, and `$vHmac.Dispose()` calls in `Add-AcsTrunkDisabled-v14.ps1` and `Fix-AcsRoutePattern-v14.ps1`. These scripts create a second set of SHA256/HMAC objects for the verification GET that confirms the PATCH succeeded, and those objects must also be disposed in `finally` blocks.

### Dashboard Generation

Tests verify:
- JSONL records are parsed correctly by `Update-TpeStatusDashboard`
- Active system indicator logic: most recent non-FAIL routing record determines state
- FAIL records are skipped when determining active system (v14.7.0)
- HTML table rows are generated for all run types
- Phone numbers and URLs are XSS-escaped in dashboard cells

### README Content Tests

Tests verify that `README.md` contains specific content that must stay in sync with script changes:
- Parameter tables for `Fix-AcsRoutePattern` (ensuring documented parameters match actual script parameters)
- Version string (ensuring the README version matches the current `$scriptVersion`)
- Changelog entries (ensuring new versions have corresponding changelog documentation)

These tests catch documentation drift — if a script parameter is added or renamed without updating the README, the test fails.

### Configuration loading

- Valid config file loads all fields
- Missing required field → clear error message
- Invalid TenantId format → validation error
- AcsConnectionString missing `endpoint=` → error
- AcsConnectionString missing `accesskey=` → error
- SBC port extraction from FQDN (with and without port suffix)
- Non-numeric port → error
- `IncludeNumbers` empty → interactive prompt invoked
- `IncludeNumbers` populated → no prompt, auto-select

### Get-TeamsProviderSetting Error Handling

Tests verify that the `entriesResponse` query (used in Step 2 for DynamicsAppId lookup) is wrapped in `try-catch` with a fallback `@()` empty array. This ensures that a failure in `Get-TeamsProviderSetting` (e.g., D365 API timeout, auth failure) is non-fatal and does not abort the migration. The orchestrator continues with an empty provider list and logs a warning.

### E.164 validation (Test-E164Format)

- Valid E.164 numbers: `+12202140029`, `+14255550100`, `+447911123456`
- Invalid: no `+` prefix, too short, too long, non-digit characters
- Each invalid number emits a WARN and is excluded from migration

### Step 2 — Zero-downtime registration

- ACS trunk found for SbcFqdn → disabled, Teams gateway created, ACS restored
- ACS trunk NOT found → error; Teams gateway creation not attempted
- Teams gateway creation fails → ACS restored before exit
- Teams gateway already exists → WARN, ACS still restored
- DryRun: no PATCH, no New-CsOnlinePSTNGateway

### Step 3 — Route creation

- Single number → pattern `^\+12202140029$`
- Multiple numbers → joined alternation
- PSTN usage already exists → WARN (not error)
- Route already exists → WARN (not error)
- Policy already exists → WARN (not error)
- DryRun: no cmdlet calls

### Step 5 — Validation

- All three objects exist → OK
- SbcFqdn missing → error with "re-run from Step 2" message
- RouteName missing → error with "re-run from Step 3" message
- RoutingPolicyName missing → error with "re-run from Step 3" message
- Step 5 does NOT check ACS export trunks/routes (v14.15.0 regression guard)

### Step 7 — Resource account creation

- Successful creation → ObjectId stored in raObjectIds
- New-CsOnlineApplicationInstance returns error → logged; ObjectId remains empty; continue to next RA
- DryRun: no New-CsOnlineApplicationInstance calls; ra-objectids.json not written

### Step 8 — License assignment (v14.16.0 guard)

- ObjectId populated → UPN included in pendingUPNs
- ObjectId empty (Step 7 failed) → UPN excluded from pendingUPNs; no crash
- In-loop guard: if objectId empty → continue (belt-and-suspenders)
- License already assigned → polling exits immediately
- License not assigned after 20 attempts → WARN, continue
- DryRun: no Set-MgUserLicense calls

### Toggle direction detection

- ACS enabled + Teams disabled → detected as ACS active
- Teams enabled + ACS disabled → detected as Teams active
- Both enabled → error (ambiguous)
- Both disabled → error (ambiguous)
- `null` enabled state treated as inactive (not as active) — v14.5.0 regression guard

### Toggle ACS → TPE

- ACS PATCH (disable) succeeds, Teams cmdlet succeeds → OK
- ACS PATCH fails → error before any Teams change
- Teams cmdlet fails → ACS routes restored, exit 1

### Toggle TPE → ACS

- Teams cmdlet fails → exit 1 (ACS already disabled)
- ACS PATCH (restore) fails after Teams success → error logged

### FlipToACS scoping

- ra-objectids.json exists → only those numbers processed
- ra-objectids.json missing + PhoneNumbers provided → explicit list used
- ra-objectids.json missing + no PhoneNumbers → error
- D365 sync intentionally skipped (TPS_TO_ACS direction)

### FlipToTeams scoping

- Same scoping as FlipToACS
- D365 sync IS triggered (ACS_TO_TPS direction)

### HTML XSS escaping

- Phone numbers with `&`, `<`, `>` in edge cases are escaped
- FQDNs with `>` characters are escaped
- Command-line invocation string is escaped

### DryRun behavior (all scripts)

- DryRun does not call any mutating API
- DryRun does not write acs-export.json, ra-objectids.json, d365-phone-backup.json, or CSV
- DryRun DOES write HTML run log (audit trail of planned actions)
- DryRun DOES write tpe-runs.jsonl record

### Exit-Script

- All error exit paths call Exit-Script (not bare `exit`)
- HTML log footer is always written (even on crash)
- Exit code 0 on success, 1 on failure

### Update-PhoneNumberType

- E.164 validation applied per number
- Provider array bounds checked before access
- PATCH wrapped in try-catch; per-number failure does not abort remaining numbers

### Undo Step 2 FQDN JSON Wrapping (TC-UndoWrap)

- Single-string JSON produces 1-element array
- Array JSON produces correctly sized array
- Empty array JSON (`[]`) produces 0-count array — requires `$null` guard because PowerShell `ConvertFrom-Json` returns `$null` for `[]`, not an empty array; without the guard the `else` branch converts `$null` to `@("")` (count 1)

### Archive-TpeRuns

- Sort-Object dedup fix: no duplicate file moves
- Files grouped correctly by yyyyMMdd prefix
- DryRun: no file moves

## Adding Tests

When fixing a bug:
1. Add a failing test that reproduces the bug (TDD)
2. Fix the bug
3. Verify the test passes
4. Verify no other tests regressed

Test naming convention:
```
Describe "Script-Name" {
    Context "Step N — Description" {
        It "does X when Y" { ... }
        It "errors when Z" { ... }
    }
}
```

### Scripts with Deep Test Coverage

14 scripts have dedicated Describe blocks, mock-and-execute tests, or focused file content analysis beyond basic version parity:
1. `Invoke-ACS-TPE-Full-Migration-v14.ps1` — step regression tests, DryRun behavior, partial failure guards
2. `Undo-ACS-TPE-Migration-v14.ps1` — undo sequence, error classification, JSON null guard
3. `Toggle-AcsTeamsRouting-v14.ps1` — direction detection, flip sequences, restore-on-failure
4. `Invoke-FlipToACS-v14.ps1` — scoping, D365 sync skip, number resolution
5. `Invoke-FlipToTeams-v14.ps1` — scoping, abort-on-failure, ObjectId passing
6. `New-AcsTpeConfig-v14.ps1` — SHA256 dispose, config assembly
7. `Set-AcsSbcFqdn-v14.ps1` — HMAC dispose, verification GET
8. `Add-AcsTrunkDisabled-v14.ps1` — verification GET crypto disposal
9. `Fix-AcsRoutePattern-v14.ps1` — verification GET crypto disposal, PATCH failure exit
10. `Update-PhoneNumberType-v14.ps1` — E.164 validation, provider bounds check, PATCH try-catch
11. `Get-TeamsProviderSetting-v14.ps1` — entriesResponse try-catch fallback
12. `Archive-TpeRuns-v14.ps1` — sort dedup, file grouping
13. `Sync-TeamsPhoneNumbers-v14.ps1` — HTTP 204 handling, try-catch wrapper, banner version
14. `Test-DomainRegistration-v14.ps1` — DryRun file content verification (`TC-DomRegDryRun`)

### Scripts with Lightweight Test Coverage

4 scripts are tested via version parity, E.164 content assertions, StrictMode checks, and `#Requires` directive verification, but do not have dedicated Describe blocks with mock-and-execute logic:
1. `Invoke-MigrateTpsPhoneNumber-v14.ps1` — version parity, E.164 validation content check
2. `Invoke-TeamsPhoneSync-v14.ps1` — version parity, try-catch verification
3. `Repair-D365PhoneRecord-v14.ps1` — version parity, E.164 validation content check, StrictMode
4. `Test-ACS-TPE-Migration-v14.Tests.ps1` — self-referential version parity (the test file tests itself for version strings)

## Test Count

Current count: 854 tests (v14.17.0)

The authoritative count comes from `Invoke-Pester -PassThru` output:
```powershell
(Invoke-Pester ./Test-ACS-TPE-Migration-v14.Tests.ps1 -PassThru).TotalCount
```

Note: The test file header comment may claim a different count — always rely on the `Invoke-Pester -PassThru` output for the true count.

The test count increases with each version as new guards, features, and bug-fix regression tests are added. Major jumps:
- v14.0.0: initial suite (501 tests)
- v14.0.4: HMAC dispose comprehensive audit, dashboard flip types
- v14.5.0: E.164 validation, null-as-active, XSS escaping tests
- v14.6.0: parameterized Fix-AcsRoutePattern, GUID validation, archive dedup
- v14.8.0: dashboard state FAIL-skip, undo summary box alignment
- v14.11.0: verification GET tests, try-catch coverage, PATCH failure exits (690 tests)
- v14.16.0: version parity bumps for v14.13–v14.16 scripts (813 tests)
- v14.17.0: 41 new feature tests for v14.13.0–v14.16.0, 26 stale version string fixes (854 tests)

### v14.13.0–v14.16.0 Feature Test Coverage (added in v14.17.0)

41 new tests added in v14.17.0 for features shipped in v14.13.0 through v14.16.0, plus 26 stale version string tests fixed:

**v14.13.0 — IncludeNumbers filter (TC-V1413)**
- `Invoke-D365Discovery` has `[string[]]$IncludeNumbers` parameter
- `IncludeNumbers` filters `$d365Numbers` via `Where-Object { $_.Number -in $IncludeNumbers }`
- Phase 0D extracts `$cfgInclude` from `cfg.IncludeNumbers` and passes to discovery
- IncludeNumbers bypasses interactive selection prompt (filter line before Read-Host)
- Empty IncludeNumbers falls through to interactive prompt
- Step 2 filters `$acsTrunks` to `cfg.SbcFqdn` only; falls back to config values on mismatch

**v14.14.0 — Step 3 config-only voice route (TC-V1414)**
- `$vrName` from `cfg.RouteName`, `$vrSbcs` from `@($cfg.SbcFqdn)`, `$vrPattern` from `Get-NumberPatternRegex -Numbers $cfg.ResourceAccounts`
- `New-CsOnlineVoiceRoute` uses `$vrSbcs` and `$vrName` from config
- Step 3 does NOT reference `acs-export.json`
- PSTN usage from `cfg.UsageName`, routing policy from `cfg.PolicyName`

**v14.15.0 — Step 5 config-only validation (TC-V1415)**
- SBC gateway check uses `cfg.SbcFqdn` (not ACS export)
- Voice route check uses `cfg.RouteName`
- Routing policy check uses `cfg.PolicyName`
- Step 5 does NOT reference `acs-export.json`, `$acsTrunks`, or `$acsRoutes`
- `$validationPassed` set to `$false` on each missing resource
- Failed validation calls `Exit-Script 1`

**v14.16.0 — Step 8 ObjectId guard (TC-V1416)**
- License assignment loop: `if (-not $objectId) { continue }` before `Update-MgUser`
- Guard emits `Write-Err` (not `Write-Warn`) with UPN and "Re-run Step 7" advice
- `$pendingUPNs` filtered to only UPNs with non-empty ObjectId
- Polling loop has inner `if (-not $objectId) { continue }` guard
- Guard uses `continue` (non-fatal), not `throw` or `Exit-Script`

**Version and README tests (TC-V1416-Version, TC-V1416-ReadmeChangelog)**
- Migration script .NOTES has v14.16.0 entry
- Console banner has v14.16.0
- README has v14.13.0, v14.14.0, v14.15.0, v14.16.0 changelog sections
- Each changelog section documents the relevant feature

### File Size

The test file is approximately **5,900 lines** of PowerShell. All 18 scripts in the suite are referenced in test assertions (version parity, content analysis, or mock-and-execute tests).
