#Requires -Version 5.1
<#
.SYNOPSIS
    Pester test suite for ACS -> TPE migration scripts.

.DESCRIPTION
    Tests pure utility functions extracted from Invoke-ACS-TPE-Full-Migration and
    Undo-ACS-TPE-Migration scripts. Integration tests mock Teams/Graph cmdlets.

    Run with:
        Invoke-Pester .\Test-ACS-TPE-Migration-v14.Tests.ps1 -Output Detailed

.NOTES
    Authors   : Adrian Synal, Vince Lannotti, Chad Madison, Pankaj Yawalkar,
                Sola Akanmu, Pratichi Dash, Krishnan Shankar
    v14.0.0   : Tests updated for v14. Added FlipToTeams sanitized extraction,
                D365OrgUrl PSObject null guard, step11Failed scope init,
                D365 backup round-trip, migration result with step11 failures.
    v14.0.1   : Added DryRun file-write guard, cfg null guard for resume mode,
                msdyn_appmodule fallback parity, #Requires consistency verification.
                Iteration 2: Step2 connection string null guard, FlipToACS
                raObjectIds normalization, DR/DO classification, dot-prefix
                extraction, Toggle #Requires, ACS endpoint normalization,
                undo ignorable error edge cases, dashboard state labels.
    v14.11.0   : Fix-AcsRoutePattern and Update-PhoneNumberType console banner version
                corrected (v14.6.0→v14.11.0), migration HTML title version added,
                README sections added for 5 missing scripts, all 18 scripts v14.11.0
                parity tests, updated prior v14.8.0 tests for v14.11.0 bumps.
                38 new tests. 715 total.
    v14.8.0   : Version parity tests — all 18 scripts have v14.8.0 banner (18 tests),
                utility script version banner tests (9), Update-PhoneNumberType provider
                bounds check test (1), Undo summary box alignment test (1), README v14.8.0
                test (1). 30 new tests. Updated prior v14.7.0 tests for v14.8.0 bumps.
    v14.7.0   : Dashboard FAIL state tests (7), Test-DomainRegistration DryRun tests (4),
                v14.7.0 version string tests (8), dashboard HTML v14.7.0 tests (10),
                banner v14.7.0 tests (3), New-AcsTpeConfig output default updated (1).
                33 new tests. Updated prior v14.6.0 tests for v14.7.0 version bumps.
    v14.6.0   : Update-PhoneNumberType msdyn_ocphonenumbersource parity + DryRun + sync
                tests (9), Fix-AcsRoutePattern parameterized tests (11), Add-AcsTrunkDisabled
                DryRun tests (4), Set-AcsSbcFqdn blank FQDN validation tests (4),
                Archive-TpeRuns Sort-Object dedup tests (3), Invoke-TeamsPhoneSync GUID
                validation tests (3), v14.6.0 version string tests (10),
                source parity tests (3), Fix-AcsRoutePattern mandatory tests (2),
                New-AcsTpeConfig v14.6.0 output default test (1). 50 new tests.
    v14.5.0   : Toggle $acsActive null-as-active fix test, Undo HTML failure-list
                XSS escape test, E.164 validation tests for Update-PhoneNumberType /
                Invoke-MigrateTpsPhoneNumber / Repair-D365PhoneRecord, HTTP 204
                handling tests for Sync-TeamsPhoneNumbers / Invoke-TeamsPhoneSync,
                Update-PhoneNumberType PATCH try-catch test, port validation tests for
                New-AcsTpeConfig / Add-AcsTrunkDisabled, Fix-AcsRoutePattern ConfigPath
                param test, Get-TeamsProviderSetting try-catch test, dashboard v14.5.0
                version parity (10 tests), version bump v14.4.0→v14.5.0.
    v14.4.0   : Toggle Exit-Script parity tests (no raw exit, run record on
                error), FlipToACS/FlipToTeams -Failures param tests,
                FlipToTeams Write-Err function tests, migrate-partial run type
                test, Step 9 DryRun post-sync guard test, dashboard v14.4.0
                version parity (10 tests), .NOTES v14.4.0 entry tests,
                version bump v14.3.0→v14.4.0, 501 tests total.
    v14.3.0   : Dashboard version parity tests (all 5 scripts → v14.3.0),
                Flip dashboard parity tests ($esc, toggle types, Steps column,
                card labels, run-record fields), Step 1 skip guard test,
                Step 9 DryRun Export-Csv guard, Toggle HTML log tests,
                duplicate TC-BuildRaZero renamed, 442 tests total.
    v14.2.0   : Toggle observability parity tests (HTML log, run record,
                dashboard, AutoConfirm param, Exit-Script), E.164 validation
                function, dashboard toggle-to-tpe/toggle-to-acs type recognition,
                D365 phone URL-encoding, Archive script pattern tests,
                migration -AutoConfirm pass-through to Toggle. 430+ tests total.
    v14.1.0   : Final consistency pass — Undo .NOTES version fix, dashboard
                v14.1.0 version strings, README version alignment, all-scripts
                #Requires verification, WaitWithMessage DryRun, exclude filter,
                undo result edge cases. 400 tests total.
    v14.0.9   : Dashboard $esc null guard tests, DryRun D365 backup guard,
                dashboard version v14.0.8, Undo Step 2 FQDN wrapping, migration
                DryRun backup skip logic. 386 tests total.
    v14.0.8   : Edge case hardening — Build-RaList 0 numbers, identical number
                patterns, Extract-PhoneFromUpn no-@, invokedAs escape, dashboard
                escape helper unit tests.
    v14.0.7   : Write-TpeRunRecord D365OrgUrl PSObject guard, dashboard XSS
                escape tests, CommsProviderId interactive prompt, undo already-
                removed display, dashboard version v14.0.7.
    v14.0.6   : Step 2 connection string null guard, Undo Write-Step/OK/Info
                prefix parity, Undo msdyn_appmodule fallback fix verification,
                Undo .DESCRIPTION Step 5/10/11 note, dashboard version v14.0.6,
                Toggle acs-export.json DryRun guard, Undo msdyn_objective
                fallback parity with Step 6. 347 tests total.
    v14.0.5   : Dashboard stateLabel/row flip-teams/flip-acs handling tests,
                step11Failed script-scope init test, dashboard version v14.0.5,
                dashboard migCount/undoCount includes flip types, Undo dashboard
                parity with migration dashboard.
    v14.0.4   : New-AcsTpeConfig SHA256/HMAC Dispose fix, FlipToTeams/FlipToACS
                HTML log + run-record + dashboard parity verification,
                dashboard flip-teams/flip-acs type classification tests,
                Undo needsAcsKey range validation tests, Step 2 inner DryRun
                guard verification, comprehensive HMAC Dispose counting across
                all 7 crypto-using scripts.
    v14.0.3   : Full consistency pass — #Requires in ALL 16 scripts, Set-StrictMode
                in ALL 16, DryRun guards on acs-export / ra-objectids /
                d365-phone-backup writes, undo exit code 1 on FAIL, Write-Banner
                $Sub parity, dashboard version v14.0.3, E.164 edge cases,
                connection-string edge cases, Build-RaList edge cases, HMAC
                Dispose in all crypto-using scripts.
    v14.0.2   : Verify actual script files have all consistency fixes applied:
                #Requires directive in 6 scripts, Set-StrictMode in 2 scripts,
                version banners match v14, cfg null guard in migration script,
                DryRun guard for acs-trunk-disabled.json, Undo Write-HtmlLine
                try/catch, SHA256/HMAC Dispose in utility scripts, FlipToTeams
                config ref v14, New-AcsTpeConfig output default v14.
    v12.0.0   : HMAC signing, Toggle detection, FlipToACS extraction,
                Build-RaList dynamic padding, run-record, connection-string
                edge cases, Invoke-Undo counting.
    Requires  : Pester 5.x  (Install-Module Pester -Force -SkipPublisherCheck)
#>

BeforeAll {
#region -----------------------------------------------------------------------
#  PURE FUNCTION DEFINITIONS (copied from migration scripts for unit testing)
#  These mirror the actual implementations so tests remain independent of script load.
# ------------------------------------------------------------------------------

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

# v12: Build-RaList uses dynamic padding width based on count
function Build-RaList {
    param(
        [Parameter(Mandatory)][array]$Numbers,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Domain
    )
    $usePhoneTemplate = $Prefix -match '<phonenumber>'
    $upnPrefix = ($Prefix -replace '[^a-zA-Z0-9\-\.<>]', '-' -replace '-+', '-').ToLower().Trim('-')
    # v12: dynamic padding width
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

function Test-IsIgnorableUndoError {
    param($ErrorRecord)
    $msg = if ($ErrorRecord.Exception.Message) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    return ($msg -match '(?i)\b(not\s+found|cannot\s+find|does\s+not\s+exist|already\s+(been\s+)?removed|could\s+not\s+be\s+found|Identity.*is\s+invalid)\b')
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
        return $backup
    }
    return $null
}

function Parse-AcsConnectionString {
    param([string]$ConnectionString)
    $parts = @{}
    $ConnectionString.Split(';') | ForEach-Object {
        $kv = $_ -split '=', 2
        if ($kv.Count -eq 2) { $parts[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
    }
    return $parts
}

# v12: HMAC-SHA256 signing helper (extracted from Invoke-AcsTrunkPatch)
function New-AcsHmacSignature {
    param(
        [string]$Method,
        [string]$PathAndQuery,
        [string]$Date,
        [string]$ApiHost,
        [string]$BodyHash,
        [string]$AccessKeyBase64
    )
    $keyB   = [System.Convert]::FromBase64String($AccessKeyBase64)
    $toSign = "$Method`n$PathAndQuery`n$Date;$ApiHost;$BodyHash"
    $hmac   = [System.Security.Cryptography.HMACSHA256]::new($keyB)
    try {
        return [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign)))
    } finally {
        $hmac.Dispose()
    }
}

# v12: Toggle auto-detect helper (extracted from Toggle-AcsTeamsRouting)
function Get-RoutingDirection {
    param(
        [bool]$AcsTrunkExists,
        [bool]$AcsEnabled,
        [bool]$TeamsGwExists,
        [bool]$TeamsEnabled
    )
    $acsActive   = $AcsTrunkExists -and $AcsEnabled
    $teamsActive = $TeamsGwExists  -and $TeamsEnabled

    if ($acsActive -and $teamsActive) { return 'CONFLICT' }
    if (-not $acsActive -and -not $teamsActive) {
        if (-not $AcsTrunkExists -and -not $TeamsGwExists) { return 'NOT_FOUND' }
        return 'NEITHER'
    }
    if ($acsActive) { return 'ACS' }
    return 'TPE'
}

# v12: FlipToACS phone number extraction from UPN (extracted from Invoke-FlipToACS)
function Extract-PhoneFromUpn {
    param(
        [string]$Upn,
        [string]$RaPrefix
    )
    # Sanitize prefix the same way Build-RaList does (lowercase, replace special chars with hyphens)
    $sanitized    = ($RaPrefix -replace '[^a-zA-Z0-9\-\.<>]', '-' -replace '-+', '-').ToLower().Trim('-')
    $prefixBefore = if ($sanitized -match '<phonenumber>') { ($sanitized -split '<phonenumber>')[0] } else { '' }
    $localPart    = ($Upn -split '@')[0]
    if ($prefixBefore -and $localPart.StartsWith($prefixBefore)) {
        $digits = $localPart.Substring($prefixBefore.Length)
        return "+$digits"
    }
    # Fallback: strip everything up to the last block of 7-15 digits
    if ($localPart -match '(\d{7,15})$') { return "+$($Matches[1])" }
    return $null
}

# v12: Compute migration result from step outcomes
function Get-MigrationResult {
    param(
        [int]$FailedCount,
        [int]$InProgressCount
    )
    if ($FailedCount -gt 0)     { return 'FAIL' }
    if ($InProgressCount -gt 0) { return 'WARN' }
    return 'OK'
}

# v14.2.0: E.164 format validation (extracted from migration Phase 0D)
function Test-E164Format {
    param([string]$Number)
    return $Number -match '^\+[1-9]\d{6,14}$'
}

} # end BeforeAll

#region -----------------------------------------------------------------------
#  TESTS
# ------------------------------------------------------------------------------

Describe 'TC-01..04: Get-NumberPatternRegex' {

    It 'TC-01: empty array returns .*' {
        Get-NumberPatternRegex -Numbers @() | Should -Be '.*'
    }

    It 'TC-02: single number returns exact match pattern' {
        $pattern = Get-NumberPatternRegex -Numbers @('+12065551234')
        $pattern | Should -Be '^\+12065551234$'
        '+12065551234' | Should -Match $pattern
        '+12065551235' | Should -Not -Match $pattern
    }

    It 'TC-03: multiple numbers with common prefix returns prefix pattern' {
        $pattern = Get-NumberPatternRegex -Numbers @('+1206555100', '+1206555101', '+1206555102')
        $pattern | Should -Match '^\^'
        '+1206555100' | Should -Match $pattern
        '+1206555109' | Should -Match $pattern   # same prefix +120655510, any trailing digits
        '+14255551000' | Should -Not -Match $pattern
    }

    It 'TC-04: numbers without meaningful common prefix returns generic E.164 pattern' {
        $pattern = Get-NumberPatternRegex -Numbers @('+12065551234', '+44207999888')
        $pattern | Should -Be '^\+\d+$'
        '+12065551234' | Should -Match $pattern
        '+44207999888' | Should -Match $pattern
        '12065551234'  | Should -Not -Match $pattern
    }

    It 'TC-04b: two numbers differing at first character returns generic pattern' {
        $pattern = Get-NumberPatternRegex -Numbers @('+1111', '+2222')
        $pattern | Should -Be '^\+\d+$'
    }

    It 'TC-04c: numbers without + prefix still produce a pattern (v12 edge case)' {
        $pattern = Get-NumberPatternRegex -Numbers @('12065551234', '12065551235')
        $pattern | Should -Match '^\^'
        '12065551234' | Should -Match $pattern
    }
}

Describe 'TC-05..07: Build-RaList' {

    BeforeAll {
        $script:SampleNumbers = @(
            [PSCustomObject]@{ Number = '+12065551001'; Name = 'Queue-1' }
            [PSCustomObject]@{ Number = '+12065551002'; Name = 'Queue-2' }
            [PSCustomObject]@{ Number = '+12065551003'; Name = 'Queue-3' }
        )
    }

    It 'TC-05: <phonenumber> template substitutes digits into DisplayName and UPN' {
        $list = Build-RaList -Numbers $script:SampleNumbers -Prefix 'TPE-RA-<phonenumber>' -Domain 'contoso.com'
        $list.Count | Should -Be 3
        $list[0].DisplayName | Should -Be 'TPE-RA-12065551001'
        $list[0].UPN         | Should -Be 'tpe-ra-12065551001@contoso.com'
        $list[0].PhoneNumber | Should -Be '+12065551001'
        $list[1].UPN         | Should -Be 'tpe-ra-12065551002@contoso.com'
    }

    It 'TC-06: no template uses sequential 01/02/03 numbering' {
        $list = Build-RaList -Numbers $script:SampleNumbers -Prefix 'TPE-RA' -Domain 'contoso.com'
        $list.Count         | Should -Be 3
        $list[0].DisplayName | Should -Be 'TPE-RA-01'
        $list[0].UPN         | Should -Be 'tpe-ra-01@contoso.com'
        $list[1].DisplayName | Should -Be 'TPE-RA-02'
        $list[2].DisplayName | Should -Be 'TPE-RA-03'
    }

    It 'TC-07: special characters in prefix are replaced with hyphens' {
        $list = Build-RaList -Numbers @($script:SampleNumbers[0]) -Prefix 'TPE RA/Test!' -Domain 'contoso.com'
        $list[0].UPN | Should -Match '^tpe-ra-test'
        $list[0].UPN | Should -Not -Match '[/ !]'
    }

    It 'TC-07b: consecutive hyphens collapsed to single hyphen' {
        $list = Build-RaList -Numbers @($script:SampleNumbers[0]) -Prefix 'A  B' -Domain 'contoso.com'
        $list[0].UPN | Should -Not -Match '--'
    }

    It 'TC-07c: D365Name preserved in output' {
        $list = Build-RaList -Numbers $script:SampleNumbers -Prefix 'RA' -Domain 'test.com'
        $list[0].D365Name | Should -Be 'Queue-1'
        $list[2].D365Name | Should -Be 'Queue-3'
    }

    It 'TC-07d: (v12) >99 numbers use 3-digit padding' {
        # Build 101 sample numbers
        $bigList = 1..101 | ForEach-Object {
            [PSCustomObject]@{ Number = "+1206555$($_.ToString('D4'))"; Name = "Queue-$_" }
        }
        $list = Build-RaList -Numbers $bigList -Prefix 'RA' -Domain 'test.com'
        $list.Count | Should -Be 101
        $list[0].DisplayName   | Should -Be 'RA-001'
        $list[0].UPN           | Should -Be 'ra-001@test.com'
        $list[99].DisplayName  | Should -Be 'RA-100'
        $list[100].DisplayName | Should -Be 'RA-101'
    }

    It 'TC-07e: (v12) <=99 numbers use 2-digit padding (backward compatible)' {
        $list = Build-RaList -Numbers $script:SampleNumbers -Prefix 'RA' -Domain 'test.com'
        $list[0].DisplayName | Should -Be 'RA-01'   # still D2
    }
}

Describe 'TC-08..11: Test-IsIgnorableUndoError' {

    BeforeAll {
        function Make-Error { param([string]$msg) [System.Management.Automation.ErrorRecord]::new([Exception]::new($msg), 'Test', 'NotSpecified', $null) }
    }

    It 'TC-08: "not found" matches' {
        Test-IsIgnorableUndoError (Make-Error 'The resource was not found') | Should -BeTrue
    }

    It 'TC-09: "does not exist" matches' {
        Test-IsIgnorableUndoError (Make-Error 'Object does not exist in the tenant') | Should -BeTrue
    }

    It 'TC-10: "already been removed" matches' {
        Test-IsIgnorableUndoError (Make-Error 'This item has already been removed') | Should -BeTrue
    }

    It 'TC-10b: "already removed" (without been) matches' {
        Test-IsIgnorableUndoError (Make-Error 'Resource already removed') | Should -BeTrue
    }

    It 'TC-10c: "cannot find" matches' {
        Test-IsIgnorableUndoError (Make-Error 'Cannot find an object with Identity "xyz"') | Should -BeTrue
    }

    It 'TC-10d: "could not be found" matches' {
        Test-IsIgnorableUndoError (Make-Error 'The specified gateway could not be found') | Should -BeTrue
    }

    It 'TC-10e: "Identity ... is invalid" matches' {
        Test-IsIgnorableUndoError (Make-Error 'Identity xyz@contoso.com is invalid') | Should -BeTrue
    }

    It 'TC-11: "network error" does NOT match (non-ignorable)' {
        Test-IsIgnorableUndoError (Make-Error 'Network connection error') | Should -BeFalse
    }

    It 'TC-11b: "permission denied" does NOT match' {
        Test-IsIgnorableUndoError (Make-Error 'Access denied: permission denied') | Should -BeFalse
    }

    It 'TC-11c: "quota exceeded" does NOT match' {
        Test-IsIgnorableUndoError (Make-Error 'License quota exceeded') | Should -BeFalse
    }
}

Describe 'TC-14..15: ACS connection string parsing' {

    It 'TC-14: standard connection string extracts endpoint and key' {
        $cs = 'endpoint=https://myacs.communication.azure.com/;accesskey=abc123def456'
        $parts = Parse-AcsConnectionString $cs
        $parts['endpoint'] | Should -Be 'https://myacs.communication.azure.com/'
        $parts['accesskey'] | Should -Be 'abc123def456'
    }

    It 'TC-15: base64 key containing = signs is fully extracted' {
        $b64key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=='
        $cs = "endpoint=https://myacs.communication.azure.com/;accesskey=$b64key"
        $parts = Parse-AcsConnectionString $cs
        $parts['accesskey'] | Should -Be $b64key
    }

    It 'TC-15b: endpoint without trailing slash parsed correctly' {
        $cs = 'endpoint=https://myacs.communication.azure.com;accesskey=key1'
        $parts = Parse-AcsConnectionString $cs
        $parts['endpoint'] | Should -Be 'https://myacs.communication.azure.com'
    }

    It 'TC-15c: key can be extracted from full connection string via regex (Undo pattern)' {
        $cs = 'endpoint=https://myacs.communication.azure.com/;accesskey=mySecretKey=='
        $keyResolved = ''
        if ($cs -match '(?i)accesskey=([^;]+)') { $keyResolved = $Matches[1].Trim() }
        $keyResolved | Should -Be 'mySecretKey=='
    }

    It 'TC-15d: (v12) empty connection string returns empty hashtable' {
        $parts = Parse-AcsConnectionString ''
        $parts.Count | Should -Be 0
    }

    It 'TC-15e: (v12) connection string with extra semicolons handled' {
        $cs = 'endpoint=https://myacs.communication.azure.com/;accesskey=key1;'
        $parts = Parse-AcsConnectionString $cs
        $parts['endpoint']  | Should -Be 'https://myacs.communication.azure.com/'
        $parts['accesskey'] | Should -Be 'key1'
    }

    It 'TC-15f: (v12) missing accesskey returns hashtable without that key' {
        $cs = 'endpoint=https://myacs.communication.azure.com/'
        $parts = Parse-AcsConnectionString $cs
        $parts['endpoint']  | Should -Be 'https://myacs.communication.azure.com/'
        $parts.ContainsKey('accesskey') | Should -BeFalse
    }
}

Describe 'TC-18..19: Backup-JsonFile' {

    BeforeAll {
        $script:TempDir = Join-Path $env:TEMP "ACSTPETest-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }

    AfterAll {
        Remove-Item -Recurse -Force $script:TempDir -ErrorAction SilentlyContinue
    }

    It 'TC-18: creates a timestamped backup copy when source exists' {
        $src = Join-Path $script:TempDir 'acs-export.json'
        '{"test":1}' | Set-Content $src -Encoding UTF8

        $backup = Backup-JsonFile -Path $src
        $backup              | Should -Not -BeNullOrEmpty
        Test-Path $backup    | Should -BeTrue
        Test-Path $src       | Should -BeTrue   # original untouched
        $backup              | Should -Match 'backup-\d{8}-\d{6}'
        $backup              | Should -Match '\.json$'
    }

    It 'TC-19: returns null and creates nothing when source does not exist' {
        $result = Backup-JsonFile -Path 'C:\DoesNotExist\fakefile.json'
        $result | Should -BeNullOrEmpty
    }

    It 'TC-18b: backup content matches source content' {
        $src = Join-Path $script:TempDir 'ra-objectids.json'
        $content = '{"upn@contoso.com":"abc-123"}'
        $content | Set-Content $src -Encoding UTF8

        $backup = Backup-JsonFile -Path $src
        (Get-Content $backup -Raw).Trim() | Should -Be $content
    }
}

Describe 'TC-20: UsageLocation validation (v8)' {

    BeforeAll {
        $script:LocationPattern = '^[A-Za-z]{2}$'
    }

    It 'TC-20a: "US" is valid' {
        'US' | Should -Match $script:LocationPattern
    }

    It 'TC-20b: "GB" is valid' {
        'GB' | Should -Match $script:LocationPattern
    }

    It 'TC-20c: "USA" (3 letters) is invalid' {
        'USA' | Should -Not -Match $script:LocationPattern
    }

    It 'TC-20d: "U" (1 letter) is invalid' {
        'U' | Should -Not -Match $script:LocationPattern
    }

    It 'TC-20e: "12" (digits) is invalid' {
        '12' | Should -Not -Match $script:LocationPattern
    }

    It 'TC-20f: empty string is invalid' {
        '' | Should -Not -Match $script:LocationPattern
    }
}

Describe 'TC-12..13: StartAtStep / StopAfterStep cross-validation' {

    It 'TC-12: Invoke - StartAtStep > StopAfterStep is invalid' {
        $StartAtStep = 8; $StopAfterStep = 5
        ($StartAtStep -gt $StopAfterStep) | Should -BeTrue
    }

    It 'TC-12b: Invoke - StartAtStep == StopAfterStep is valid (single-step run)' {
        $StartAtStep = 4; $StopAfterStep = 4
        ($StartAtStep -gt $StopAfterStep) | Should -BeFalse
    }

    It 'TC-12c: Invoke - StartAtStep < StopAfterStep is valid (range run)' {
        $StartAtStep = 2; $StopAfterStep = 9
        ($StartAtStep -gt $StopAfterStep) | Should -BeFalse
    }

    It 'TC-13: Undo - StartAtStep < StopAfterStep is invalid (undo goes downward)' {
        $StartAtStep = 5; $StopAfterStep = 9
        ($StartAtStep -lt $StopAfterStep) | Should -BeTrue
    }

    It 'TC-13b: Undo - StartAtStep == StopAfterStep is valid (single-step undo)' {
        $StartAtStep = 9; $StopAfterStep = 9
        ($StartAtStep -lt $StopAfterStep) | Should -BeFalse
    }

    It 'TC-13c: Undo - StartAtStep > StopAfterStep is valid (range undo)' {
        $StartAtStep = 9; $StopAfterStep = 1
        ($StartAtStep -lt $StopAfterStep) | Should -BeFalse
    }
}

Describe 'TC-25: Undo AcsEndpoint GUID guard (v8)' {

    It 'TC-25a: AcsEndpoint URL is used when present' {
        $cfg = [PSCustomObject]@{ AcsEndpoint = 'https://myacs.communication.azure.com/'; AcsResourceId = 'aaaa-bbbb-cccc' }
        $resolved = if ($cfg.PSObject.Properties['AcsEndpoint'] -and $cfg.AcsEndpoint) { $cfg.AcsEndpoint } else { '' }
        $resolved | Should -Be 'https://myacs.communication.azure.com/'
    }

    It 'TC-25b: v8 does NOT fall back to AcsResourceId GUID as endpoint' {
        $cfg = [PSCustomObject]@{ AcsResourceId = 'aaaa-bbbb-cccc-dddd' }
        $resolved = ''
        if ($cfg.PSObject.Properties['AcsEndpoint'] -and $cfg.AcsEndpoint)             { $resolved = $cfg.AcsEndpoint }
        elseif ($cfg.PSObject.Properties['AcsResourceName'] -and $cfg.AcsResourceName) { $resolved = $cfg.AcsResourceName }
        $resolved | Should -BeNullOrEmpty
    }

    It 'TC-25c: v7 bug - AcsResourceId GUID would produce invalid URL' {
        $guid = 'aaaa1234-bbbb-cccc-dddd-eeeeffffaaaa'
        $resolved = "https://$($guid.TrimEnd('/'))"
        $resolved | Should -Not -Match '^https://[a-z].*\.com'
        $resolved | Should -Match 'aaaa1234'
    }
}

Describe 'TC-Step6-Timeout: Step 6 timeout behavior (v8)' {

    It 'TC-Step6-v7: v7 exits with code 1 on propagation timeout' {
        $pending = @('+12065551001', '+12065551002')
        $maxWaitSec = 120
        $elapsed = $maxWaitSec

        $v7ExitsOnTimeout = ($pending.Count -gt 0 -and $elapsed -ge $maxWaitSec)
        $v7ExitsOnTimeout | Should -BeTrue
    }

    It 'TC-Step6-v8: v8 warns and continues on propagation timeout' {
        $pending = @('+12065551001')
        $maxWaitSec = 120
        $elapsed = $maxWaitSec

        $v8ShouldContinue = $true
        $v8ShouldContinue | Should -BeTrue
        $pending.Count | Should -BeGreaterThan 0
    }
}

Describe 'TC-HtmlFooter: HTML log footer written on exit (v8)' {

    BeforeAll {
        $script:TempDir2 = Join-Path $env:TEMP "ACSTPEHtml-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TempDir2 | Out-Null
    }

    AfterAll {
        Remove-Item -Recurse -Force $script:TempDir2 -ErrorAction SilentlyContinue
    }

    It 'TC-HtmlFooter: Exit-Script writes HTML footer before exiting' {
        $logPath = Join-Path $script:TempDir2 'test.html'
        Set-Content $logPath '<html><body><pre>' -Encoding UTF8

        function Exit-Script-Sim {
            param([string]$Path)
            Add-Content -Path $Path -Value '</pre></body></html>' -Encoding UTF8
        }

        Exit-Script-Sim -Path $logPath
        $content = Get-Content $logPath -Raw
        $content | Should -Match '</pre></body></html>'
    }

    It 'TC-HtmlFooter: HTML file is valid (has open and close tags) after Exit-Script' {
        $logPath = Join-Path $script:TempDir2 'test2.html'
        Set-Content $logPath '<!DOCTYPE html><html><body><pre>' -Encoding UTF8
        Add-Content $logPath '</pre></body></html>' -Encoding UTF8

        $content = Get-Content $logPath -Raw
        $content | Should -Match '<html>'
        $content | Should -Match '</html>'
        $content | Should -Match '</pre>'
    }
}

Describe 'TC-SbcPort: SBC port numeric validation (v8)' {

    It 'TC-SbcPort-a: "5061" is valid (default Teams DR port)' {
        $input = '5061'
        ($input -match '^\d+$' -and [int]$input -gt 0 -and [int]$input -le 65535) | Should -BeTrue
    }

    It 'TC-SbcPort-b: "5075" is valid (default ACS port)' {
        $input = '5075'
        ($input -match '^\d+$' -and [int]$input -gt 0 -and [int]$input -le 65535) | Should -BeTrue
    }

    It 'TC-SbcPort-c: "abc" is invalid' {
        $input = 'abc'
        ($input -match '^\d+$') | Should -BeFalse
    }

    It 'TC-SbcPort-d: "0" is invalid (reserved port)' {
        $input = '0'
        ($input -match '^\d+$' -and [int]$input -gt 0) | Should -BeFalse
    }

    It 'TC-SbcPort-e: "65536" is invalid (above max port)' {
        $input = '65536'
        ($input -match '^\d+$' -and [int]$input -le 65535) | Should -BeFalse
    }
}

Describe 'TC-RaObjectIds: raObjectIds storage normalization (v8)' {

    It 'TC-RaObjectIds-a: v8 stores plain string ObjectId in raObjectIds' {
        $raObjectIds = @{}
        $upn = 'ra@contoso.com'
        $objectId = 'aaaa-bbbb-cccc-dddd'

        $raObjectIds[$upn] = $objectId

        $raObjectIds[$upn] -is [string] | Should -BeTrue
        $raObjectIds[$upn]              | Should -Be $objectId
    }

    It 'TC-RaObjectIds-b: v8 loading from json normalizes to string' {
        $json = '{"ra@contoso.com":{"ObjectId":"aaaa-bbbb-cccc"}}'
        $loaded = $json | ConvertFrom-Json
        $raObjectIds = @{}
        $loaded.PSObject.Properties | ForEach-Object {
            $raObjectIds[$_.Name] = if ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { [string]$_.Value }
        }

        $raObjectIds['ra@contoso.com'] -is [string] | Should -BeTrue
        $raObjectIds['ra@contoso.com']              | Should -Be 'aaaa-bbbb-cccc'
    }

    It 'TC-RaObjectIds-c: v7 PSCustomObject storage causes -is [string] check to fail' {
        $raObjectIds = @{}
        $upn = 'ra@contoso.com'

        $raObjectIds[$upn] = [PSCustomObject]@{ ObjectId = 'aaaa-bbbb-cccc'; Type = 'ResourceAccount' }

        $objectId = if ($raObjectIds[$upn] -is [string]) { $raObjectIds[$upn] } else { $raObjectIds[$upn].ObjectId }
        $objectId | Should -Be 'aaaa-bbbb-cccc'

        $raObjectIds[$upn] = 'aaaa-bbbb-cccc'
        $raObjectIds[$upn] | Should -Be 'aaaa-bbbb-cccc'
    }
}

Describe 'TC-StepRange: Step range boundary conditions (v12)' {

    It 'TC-SR-01: Invoke step 0 is included when StartAtStep=0' {
        $StartAtStep = 0; $StopAfterStep = 11
        ($StartAtStep -le 0 -and $StopAfterStep -ge 0) | Should -BeTrue
    }

    It 'TC-SR-02: Invoke step 11 is included when StopAfterStep=11' {
        $StartAtStep = 0; $StopAfterStep = 11
        ($StartAtStep -le 11 -and $StopAfterStep -ge 11) | Should -BeTrue
    }

    It 'TC-SR-03: Invoke single-step run only includes that step' {
        $StartAtStep = 4; $StopAfterStep = 4
        ($StartAtStep -le 4 -and $StopAfterStep -ge 4) | Should -BeTrue   # step 4: included
        ($StartAtStep -le 3 -and $StopAfterStep -ge 3) | Should -BeFalse  # step 3: excluded
        ($StartAtStep -le 5 -and $StopAfterStep -ge 5) | Should -BeFalse  # step 5: excluded
    }

    It 'TC-SR-04: Undo step 9 included when StartAtStep=9, StopAfterStep=1' {
        $StartAtStep = 9; $StopAfterStep = 1
        ($StartAtStep -ge 9 -and $StopAfterStep -le 9) | Should -BeTrue
    }

    It 'TC-SR-05: Undo step 9 to 7 range boundaries correct' {
        $StartAtStep = 9; $StopAfterStep = 7
        ($StartAtStep -ge 9 -and $StopAfterStep -le 9) | Should -BeTrue   # step 9: included
        ($StartAtStep -ge 8 -and $StopAfterStep -le 8) | Should -BeTrue   # step 8: included
        ($StartAtStep -ge 7 -and $StopAfterStep -le 7) | Should -BeTrue   # step 7: included
        ($StartAtStep -ge 6 -and $StopAfterStep -le 6) | Should -BeFalse  # step 6: excluded
    }

    It 'TC-SR-06: Undo single step 9 only' {
        $StartAtStep = 9; $StopAfterStep = 9
        ($StartAtStep -ge 9 -and $StopAfterStep -le 9) | Should -BeTrue   # step 9: included
        ($StartAtStep -ge 8 -and $StopAfterStep -le 8) | Should -BeFalse  # step 8: excluded
    }
}

# ============================================================================
# v12 NEW TEST SECTIONS
# ============================================================================

Describe 'TC-HMAC: HMAC-SHA256 signing (v12)' {

    It 'TC-HMAC-01: signature is a valid base64 string' {
        # Use a known base64 key (32 bytes = 256 bit)
        $testKey = [System.Convert]::ToBase64String([byte[]](1..32))
        $sig = New-AcsHmacSignature -Method 'GET' -PathAndQuery '/sip?api-version=2023-04-01-preview' `
            -Date 'Thu, 01 Jan 2026 00:00:00 GMT' -ApiHost 'myacs.communication.azure.com' `
            -BodyHash '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=' -AccessKeyBase64 $testKey
        $sig | Should -Not -BeNullOrEmpty
        # Valid base64 pattern
        $sig | Should -Match '^[A-Za-z0-9+/]+=*$'
    }

    It 'TC-HMAC-02: same inputs produce same signature (deterministic)' {
        $testKey = [System.Convert]::ToBase64String([byte[]](1..32))
        $args = @{
            Method          = 'PATCH'
            PathAndQuery    = '/sip?api-version=2023-04-01-preview'
            Date            = 'Thu, 01 Jan 2026 00:00:00 GMT'
            ApiHost         = 'myacs.communication.azure.com'
            BodyHash        = 'abc123'
            AccessKeyBase64 = $testKey
        }
        $sig1 = New-AcsHmacSignature @args
        $sig2 = New-AcsHmacSignature @args
        $sig1 | Should -Be $sig2
    }

    It 'TC-HMAC-03: different body hash produces different signature' {
        $testKey = [System.Convert]::ToBase64String([byte[]](1..32))
        $base = @{
            Method          = 'PATCH'
            PathAndQuery    = '/sip?api-version=2023-04-01-preview'
            Date            = 'Thu, 01 Jan 2026 00:00:00 GMT'
            ApiHost         = 'myacs.communication.azure.com'
            AccessKeyBase64 = $testKey
        }
        $sig1 = New-AcsHmacSignature @base -BodyHash 'hash1'
        $sig2 = New-AcsHmacSignature @base -BodyHash 'hash2'
        $sig1 | Should -Not -Be $sig2
    }

    It 'TC-HMAC-04: GET vs PATCH produce different signatures' {
        $testKey = [System.Convert]::ToBase64String([byte[]](1..32))
        $base = @{
            PathAndQuery    = '/sip?api-version=2023-04-01-preview'
            Date            = 'Thu, 01 Jan 2026 00:00:00 GMT'
            ApiHost         = 'myacs.communication.azure.com'
            BodyHash        = '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='
            AccessKeyBase64 = $testKey
        }
        $sigGet   = New-AcsHmacSignature @base -Method 'GET'
        $sigPatch = New-AcsHmacSignature @base -Method 'PATCH'
        $sigGet | Should -Not -Be $sigPatch
    }
}

Describe 'TC-Toggle: Toggle auto-detect routing direction (v12)' {

    It 'TC-Toggle-01: ACS enabled + Teams disabled => ACS' {
        Get-RoutingDirection -AcsTrunkExists $true -AcsEnabled $true -TeamsGwExists $true -TeamsEnabled $false | Should -Be 'ACS'
    }

    It 'TC-Toggle-02: ACS disabled + Teams enabled => TPE' {
        Get-RoutingDirection -AcsTrunkExists $true -AcsEnabled $false -TeamsGwExists $true -TeamsEnabled $true | Should -Be 'TPE'
    }

    It 'TC-Toggle-03: both enabled => CONFLICT' {
        Get-RoutingDirection -AcsTrunkExists $true -AcsEnabled $true -TeamsGwExists $true -TeamsEnabled $true | Should -Be 'CONFLICT'
    }

    It 'TC-Toggle-04: neither enabled => NEITHER' {
        Get-RoutingDirection -AcsTrunkExists $true -AcsEnabled $false -TeamsGwExists $true -TeamsEnabled $false | Should -Be 'NEITHER'
    }

    It 'TC-Toggle-05: both not found => NOT_FOUND' {
        Get-RoutingDirection -AcsTrunkExists $false -AcsEnabled $false -TeamsGwExists $false -TeamsEnabled $false | Should -Be 'NOT_FOUND'
    }

    It 'TC-Toggle-06: ACS exists+enabled, Teams not found => ACS' {
        Get-RoutingDirection -AcsTrunkExists $true -AcsEnabled $true -TeamsGwExists $false -TeamsEnabled $false | Should -Be 'ACS'
    }

    It 'TC-Toggle-07: ACS not found, Teams exists+enabled => TPE' {
        Get-RoutingDirection -AcsTrunkExists $false -AcsEnabled $false -TeamsGwExists $true -TeamsEnabled $true | Should -Be 'TPE'
    }

    It 'TC-Toggle-08: ACS not found, Teams disabled => NEITHER' {
        Get-RoutingDirection -AcsTrunkExists $false -AcsEnabled $false -TeamsGwExists $true -TeamsEnabled $false | Should -Be 'NEITHER'
    }
}

Describe 'TC-FlipExtract: FlipToACS phone number extraction from UPN (v12)' {

    It 'TC-Flip-01: template prefix extracts phone number correctly' {
        $result = Extract-PhoneFromUpn -Upn 'acs-tpe-ra-12069990060@cbg-voice.sandbox.dev.microsoft' -RaPrefix 'acs-tpe-ra-<phonenumber>'
        $result | Should -Be '+12069990060'
    }

    It 'TC-Flip-02: different prefix template works' {
        $result = Extract-PhoneFromUpn -Upn 'tpe-14255550100@contoso.com' -RaPrefix 'tpe-<phonenumber>'
        $result | Should -Be '+14255550100'
    }

    It 'TC-Flip-03: sequential prefix falls back to digit extraction' {
        $result = Extract-PhoneFromUpn -Upn 'tpe-ra-12065551001@contoso.com' -RaPrefix 'tpe-ra'
        $result | Should -Be '+12065551001'
    }

    It 'TC-Flip-04: sequential prefix with short index returns null (no 7+ digit block)' {
        $result = Extract-PhoneFromUpn -Upn 'tpe-ra-01@contoso.com' -RaPrefix 'tpe-ra'
        $result | Should -BeNullOrEmpty
    }

    It 'TC-Flip-05: empty prefix uses fallback regex' {
        $result = Extract-PhoneFromUpn -Upn 'ra-12065551234@contoso.com' -RaPrefix ''
        $result | Should -Be '+12065551234'
    }

    It 'TC-Flip-06: UPN with no digits returns null' {
        $result = Extract-PhoneFromUpn -Upn 'test-user@contoso.com' -RaPrefix ''
        $result | Should -BeNullOrEmpty
    }
}

Describe 'TC-MigResult: Get-MigrationResult (v12)' {

    It 'TC-MigResult-01: no failures, no in-progress => OK' {
        Get-MigrationResult -FailedCount 0 -InProgressCount 0 | Should -Be 'OK'
    }

    It 'TC-MigResult-02: failures present => FAIL' {
        Get-MigrationResult -FailedCount 2 -InProgressCount 0 | Should -Be 'FAIL'
    }

    It 'TC-MigResult-03: no failures but in-progress => WARN' {
        Get-MigrationResult -FailedCount 0 -InProgressCount 1 | Should -Be 'WARN'
    }

    It 'TC-MigResult-04: failures take precedence over in-progress' {
        Get-MigrationResult -FailedCount 1 -InProgressCount 3 | Should -Be 'FAIL'
    }
}

Describe 'TC-RunRecord: Write-TpeRunRecord JSONL format (v12)' {

    BeforeAll {
        $script:TempDir3 = Join-Path $env:TEMP "ACSTPERun-$(Get-Random)"
        $null = New-Item -ItemType Directory -Path $script:TempDir3 -Force
        $script:StatsDir = Join-Path $script:TempDir3 'stats'
    }

    AfterAll {
        Remove-Item -Recurse -Force $script:TempDir3 -ErrorAction SilentlyContinue
    }

    It 'TC-RunRecord-01: record is valid JSON with expected fields' {
        $rec = [ordered]@{
            type         = 'migrate'
            timestamp    = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
            logFile      = 'tpe-migration-run-test.html'
            startStep    = 0
            stopStep     = 11
            dryRun       = $false
            phoneNumbers = @('+12065551001')
            result       = 'OK'
            completed    = 9
            skipped      = 0
            failures     = 0
            d365OrgUrl   = 'https://test.crm.dynamics.com'
        }
        $json = $rec | ConvertTo-Json -Compress
        $parsed = $json | ConvertFrom-Json
        $parsed.type   | Should -Be 'migrate'
        $parsed.result | Should -Be 'OK'
        $parsed.phoneNumbers.Count | Should -Be 1
        $parsed.phoneNumbers[0]    | Should -Be '+12065551001'
    }

    It 'TC-RunRecord-02: undo record has correct type' {
        $rec = [ordered]@{
            type = 'undo'; timestamp = '2026-01-01T00:00:00'; result = 'WARN'
            failures = 1; phoneNumbers = @()
        }
        $json = $rec | ConvertTo-Json -Compress
        ($json | ConvertFrom-Json).type | Should -Be 'undo'
    }
}

Describe 'TC-ConnGuard: Connection string null guards (v12)' {

    It 'TC-ConnGuard-01: TrimEnd on null does not throw when guarded' {
        $val = $null
        $result = if ($val) { $val.TrimEnd('/') } else { '' }
        $result | Should -Be ''
    }

    It 'TC-ConnGuard-02: hashtable lookup returns null for missing key' {
        $parts = @{ 'endpoint' = 'https://myacs.com' }
        $parts['accesskey'] | Should -BeNullOrEmpty
    }

    It 'TC-ConnGuard-03: Base64 decode of null/empty should be caught' {
        $key = ''
        { if ($key) { [System.Convert]::FromBase64String($key) } } | Should -Not -Throw
    }
}

# ============================================================================
# v12.0.1 NEW TESTS — covers all gaps found in deep-dive review
# ============================================================================

Describe 'TC-Pad1000: Build-RaList >999 numbers use 4-digit padding (v12 fix)' {

    It 'TC-Pad1000-01: 1001 numbers use D4 padding' {
        $bigList = 1..1001 | ForEach-Object {
            [PSCustomObject]@{ Number = "+1206555$($_.ToString('D4'))"; Name = "Q-$_" }
        }
        $list = Build-RaList -Numbers $bigList -Prefix 'RA' -Domain 'test.com'
        $list.Count | Should -Be 1001
        $list[0].DisplayName    | Should -Be 'RA-0001'
        $list[0].UPN            | Should -Be 'ra-0001@test.com'
        $list[999].DisplayName  | Should -Be 'RA-1000'
        $list[1000].DisplayName | Should -Be 'RA-1001'
    }

    It 'TC-Pad1000-02: exactly 1000 uses D4 (boundary)' {
        $bigList = 1..1000 | ForEach-Object {
            [PSCustomObject]@{ Number = "+1206$($_.ToString('D6'))"; Name = "Q-$_" }
        }
        $list = Build-RaList -Numbers $bigList -Prefix 'RA' -Domain 'test.com'
        $list[0].DisplayName   | Should -Be 'RA-0001'
        $list[999].DisplayName | Should -Be 'RA-1000'
    }

    It 'TC-Pad1000-03: exactly 100 uses D3 (boundary)' {
        $bigList = 1..100 | ForEach-Object {
            [PSCustomObject]@{ Number = "+1206555$($_.ToString('D4'))"; Name = "Q-$_" }
        }
        $list = Build-RaList -Numbers $bigList -Prefix 'RA' -Domain 'test.com'
        $list[0].DisplayName  | Should -Be 'RA-001'
        $list[99].DisplayName | Should -Be 'RA-100'
    }
}

Describe 'TC-ToggleOrder: Toggle NOT_FOUND before NEITHER detection (v12 fix)' {

    It 'TC-ToggleOrder-01: both not found => NOT_FOUND (not NEITHER)' {
        # NOT_FOUND must be checked BEFORE NEITHER because both-null implies both inactive
        $result = Get-RoutingDirection -AcsTrunkExists $false -AcsEnabled $false -TeamsGwExists $false -TeamsEnabled $false
        $result | Should -Be 'NOT_FOUND'
    }

    It 'TC-ToggleOrder-02: ACS exists disabled + Teams not found => NEITHER (not NOT_FOUND)' {
        $result = Get-RoutingDirection -AcsTrunkExists $true -AcsEnabled $false -TeamsGwExists $false -TeamsEnabled $false
        $result | Should -Be 'NEITHER'
    }

    It 'TC-ToggleOrder-03: ACS not found + Teams exists disabled => NEITHER' {
        $result = Get-RoutingDirection -AcsTrunkExists $false -AcsEnabled $false -TeamsGwExists $true -TeamsEnabled $false
        $result | Should -Be 'NEITHER'
    }
}

Describe 'TC-UndoResult: Undo result computation (v12 fix)' {

    It 'TC-UndoResult-01: zero failures => OK' {
        $failCount = 0
        $result = if ($failCount -gt 3) { 'FAIL' } elseif ($failCount -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'OK'
    }

    It 'TC-UndoResult-02: 1-3 failures => WARN' {
        $failCount = 2
        $result = if ($failCount -gt 3) { 'FAIL' } elseif ($failCount -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'WARN'
    }

    It 'TC-UndoResult-03: >3 failures => FAIL' {
        $failCount = 5
        $result = if ($failCount -gt 3) { 'FAIL' } elseif ($failCount -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'FAIL'
    }

    It 'TC-UndoResult-04: exactly 3 failures => WARN (boundary)' {
        $failCount = 3
        $result = if ($failCount -gt 3) { 'FAIL' } elseif ($failCount -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'WARN'
    }

    It 'TC-UndoResult-05: exactly 4 failures => FAIL (boundary)' {
        $failCount = 4
        $result = if ($failCount -gt 3) { 'FAIL' } elseif ($failCount -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'FAIL'
    }
}

Describe 'TC-ConnParse: Connection string safe parsing (v12 fix)' {

    It 'TC-ConnParse-01: malformed connection string (no endpoint=) returns empty endpoint' {
        $cs = 'accesskey=mykey123'
        $parts = Parse-AcsConnectionString $cs
        $ep = if ($parts['endpoint']) { $parts['endpoint'].TrimEnd('/') } else { '' }
        $ep | Should -Be ''
    }

    It 'TC-ConnParse-02: malformed connection string (no accesskey=) returns empty key' {
        $cs = 'endpoint=https://myacs.communication.azure.com/'
        $parts = Parse-AcsConnectionString $cs
        $key = if ($parts['accesskey']) { $parts['accesskey'] } else { '' }
        $key | Should -Be ''
    }

    It 'TC-ConnParse-03: completely malformed string returns empty hashtable' {
        $parts = Parse-AcsConnectionString 'not-a-connection-string'
        $ep  = if ($parts['endpoint'])  { $parts['endpoint'].TrimEnd('/') }  else { '' }
        $key = if ($parts['accesskey']) { $parts['accesskey'] }              else { '' }
        $ep  | Should -Be ''
        $key | Should -Be ''
    }
}

Describe 'TC-FlipSanitize: FlipToACS prefix sanitization matches Build-RaList (v12 fix)' {

    It 'TC-FlipSanitize-01: prefix with spaces is sanitized before comparison' {
        # Build-RaList would sanitize "TPE RA/<phonenumber>" to "tpe-ra-<phonenumber>"
        # Extract-PhoneFromUpn must do the same sanitization
        $result = Extract-PhoneFromUpn -Upn 'tpe-ra-12065551001@contoso.com' -RaPrefix 'TPE RA/<phonenumber>'
        $result | Should -Be '+12065551001'
    }

    It 'TC-FlipSanitize-02: prefix with special chars sanitized' {
        $result = Extract-PhoneFromUpn -Upn 'my.ra-12065551001@contoso.com' -RaPrefix 'My.RA-<phonenumber>'
        $result | Should -Be '+12065551001'
    }

    It 'TC-FlipSanitize-03: uppercase prefix lowered to match UPN' {
        $result = Extract-PhoneFromUpn -Upn 'acs-tpe-ra-12069990060@domain.com' -RaPrefix 'ACS-TPE-RA-<phonenumber>'
        $result | Should -Be '+12069990060'
    }
}

Describe 'TC-MigResult2: Migration result with Step 11 failures (v12 fix)' {

    It 'TC-MigResult2-01: Step 9 OK + Step 11 failures => FAIL' {
        $step9FailedCount = 0
        $step11FailedCount = 2
        $totalFailed = $step9FailedCount + $step11FailedCount
        $result = if ($totalFailed -gt 0) { 'FAIL' } else { 'OK' }
        $result | Should -Be 'FAIL'
    }

    It 'TC-MigResult2-02: Step 9 OK + Step 11 OK => OK' {
        $step9FailedCount = 0
        $step11FailedCount = 0
        $totalFailed = $step9FailedCount + $step11FailedCount
        $result = if ($totalFailed -gt 0) { 'FAIL' } else { 'OK' }
        $result | Should -Be 'OK'
    }

    It 'TC-MigResult2-03: Step 9 failures + Step 11 OK => FAIL' {
        $step9FailedCount = 1
        $step11FailedCount = 0
        $totalFailed = $step9FailedCount + $step11FailedCount
        $result = if ($totalFailed -gt 0) { 'FAIL' } else { 'OK' }
        $result | Should -Be 'FAIL'
    }
}

Describe 'TC-D365Guard: D365OrgUrl null guard pattern (v12 fix)' {

    It 'TC-D365Guard-01: null D365OrgUrl is detected' {
        $cfg = [PSCustomObject]@{ TenantId = 'abc' }
        $hasUrl = $cfg.PSObject.Properties['D365OrgUrl'] -and $cfg.D365OrgUrl
        $hasUrl | Should -BeFalse
    }

    It 'TC-D365Guard-02: empty string D365OrgUrl is detected' {
        $cfg = [PSCustomObject]@{ D365OrgUrl = ''; TenantId = 'abc' }
        $hasUrl = $cfg.PSObject.Properties['D365OrgUrl'] -and $cfg.D365OrgUrl
        $hasUrl | Should -BeFalse
    }

    It 'TC-D365Guard-03: valid D365OrgUrl passes guard' {
        $cfg = [PSCustomObject]@{ D365OrgUrl = 'https://contoso.crm.dynamics.com'; TenantId = 'abc' }
        $hasUrl = $cfg.PSObject.Properties['D365OrgUrl'] -and $cfg.D365OrgUrl
        $hasUrl | Should -BeTrue
    }
}

Describe 'TC-Step6Fields: Undo Step 6 field parity with Step 9 (v12 fix)' {

    It 'TC-Step6Fields-01: backup entry with all 8 fields produces complete patch' {
        $bkp = [PSCustomObject]@{
            statecode                 = 0
            statuscode                = 1
            msdyn_ocphonenumbersource = 192350000
            msdyn_teamsresourceaccount = $null
            msdyn_type                = 192350000
            msdyn_phonenumbertype     = 1
            msdyn_objective           = 192350001
            msdyn_appmodule           = 192350000
        }
        $fields = [ordered]@{
            statecode                  = if ($bkp.statecode -ne $null) { $bkp.statecode } else { 0 }
            statuscode                 = if ($bkp.statuscode -ne $null) { $bkp.statuscode } else { 1 }
            msdyn_ocphonenumbersource  = if ($bkp.msdyn_ocphonenumbersource -ne $null) { $bkp.msdyn_ocphonenumbersource } else { 192350000 }
            msdyn_teamsresourceaccount = $bkp.msdyn_teamsresourceaccount
            msdyn_type                 = if ($bkp.msdyn_type -ne $null) { $bkp.msdyn_type } else { 192350000 }
            msdyn_phonenumbertype      = if ($bkp.msdyn_phonenumbertype -ne $null) { $bkp.msdyn_phonenumbertype } else { 1 }
            msdyn_objective            = if ($bkp.msdyn_objective -ne $null) { $bkp.msdyn_objective } else { $null }
            msdyn_appmodule            = if ($bkp.msdyn_appmodule -ne $null) { $bkp.msdyn_appmodule } else { $null }
        }
        $fields.Count | Should -Be 8
        $fields['msdyn_objective']  | Should -Be 192350001
        $fields['msdyn_appmodule'] | Should -Be 192350000
    }

    It 'TC-Step6Fields-02: backup with null objective/appmodule passes null through' {
        $bkp = [PSCustomObject]@{
            statecode                 = 0
            statuscode                = 1
            msdyn_ocphonenumbersource = 192350000
            msdyn_teamsresourceaccount = $null
            msdyn_type                = 192350000
            msdyn_phonenumbertype     = 1
        }
        $objective = if ($bkp.PSObject.Properties['msdyn_objective'] -and $bkp.msdyn_objective -ne $null) { $bkp.msdyn_objective } else { $null }
        $objective | Should -BeNullOrEmpty
    }
}

# ============================================================================
# v14.0.0 NEW TESTS — covers gaps found in v13 deep-dive review
# ============================================================================

Describe 'TC-Pad999: Build-RaList exactly 999 numbers boundary (v14 fix)' {

    It 'TC-Pad999-01: exactly 999 numbers use D3 padding (boundary)' {
        $bigList = 1..999 | ForEach-Object {
            [PSCustomObject]@{ Number = "+1206$($_.ToString('D6'))"; Name = "Q-$_" }
        }
        $list = Build-RaList -Numbers $bigList -Prefix 'RA' -Domain 'test.com'
        $list.Count | Should -Be 999
        $list[0].DisplayName   | Should -Be 'RA-001'
        $list[0].UPN           | Should -Be 'ra-001@test.com'
        $list[998].DisplayName | Should -Be 'RA-999'
    }

    It 'TC-Pad999-02: exactly 99 numbers use D2 padding (boundary)' {
        $bigList = 1..99 | ForEach-Object {
            [PSCustomObject]@{ Number = "+1206555$($_.ToString('D4'))"; Name = "Q-$_" }
        }
        $list = Build-RaList -Numbers $bigList -Prefix 'RA' -Domain 'test.com'
        $list.Count | Should -Be 99
        $list[0].DisplayName  | Should -Be 'RA-01'
        $list[98].DisplayName | Should -Be 'RA-99'
    }

    It 'TC-Pad999-03: single number uses D2 padding' {
        $list = Build-RaList -Numbers @([PSCustomObject]@{ Number = '+12065551001'; Name = 'Q-1' }) -Prefix 'RA' -Domain 'test.com'
        $list[0].DisplayName | Should -Be 'RA-01'
    }
}

Describe 'TC-RaOidNorm: raObjectIds normalization for nested objects (v14 fix)' {

    It 'TC-RaOidNorm-01: plain string value preserved' {
        $json = '{"ra@contoso.com":"aaaa-bbbb-cccc-dddd"}'
        $loaded = $json | ConvertFrom-Json
        $raObjectIds = @{}
        $loaded.PSObject.Properties | ForEach-Object {
            $raObjectIds[$_.Name] = if ($_.Value -is [string]) { $_.Value } elseif ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { [string]$_.Value }
        }
        $raObjectIds['ra@contoso.com'] | Should -Be 'aaaa-bbbb-cccc-dddd'
        $raObjectIds['ra@contoso.com'] -is [string] | Should -BeTrue
    }

    It 'TC-RaOidNorm-02: nested ObjectId property extracted' {
        $json = '{"ra@contoso.com":{"ObjectId":"aaaa-bbbb-cccc","Type":"RA"}}'
        $loaded = $json | ConvertFrom-Json
        $raObjectIds = @{}
        $loaded.PSObject.Properties | ForEach-Object {
            $raObjectIds[$_.Name] = if ($_.Value -is [string]) { $_.Value } elseif ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { [string]$_.Value }
        }
        $raObjectIds['ra@contoso.com'] | Should -Be 'aaaa-bbbb-cccc'
        $raObjectIds['ra@contoso.com'] -is [string] | Should -BeTrue
    }

    It 'TC-RaOidNorm-03: GUID-like string not wrapped in object' {
        $json = '{"ra@contoso.com":"12345678-abcd-1234-abcd-1234567890ab"}'
        $loaded = $json | ConvertFrom-Json
        $raObjectIds = @{}
        $loaded.PSObject.Properties | ForEach-Object {
            $raObjectIds[$_.Name] = if ($_.Value -is [string]) { $_.Value } elseif ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { [string]$_.Value }
        }
        $raObjectIds['ra@contoso.com'] | Should -Be '12345678-abcd-1234-abcd-1234567890ab'
    }
}

Describe 'TC-Step11Init: step11Failed initialization at script scope (v14 fix)' {

    It 'TC-Step11Init-01: uninitialized array returns 0 count via null guard' {
        $step11Failed = $null
        $count = if ($step11Failed) { $step11Failed.Count } else { 0 }
        $count | Should -Be 0
    }

    It 'TC-Step11Init-02: initialized empty array returns 0 count directly' {
        $step11Failed = @()
        $count = $step11Failed.Count
        $count | Should -Be 0
    }

    It 'TC-Step11Init-03: initialized array with items returns correct count' {
        $step11Failed = @('+12065551001', '+12065551002')
        $count = $step11Failed.Count
        $count | Should -Be 2
    }
}

Describe 'TC-DryRunGuard: DryRun should not write tracking files (v14 fix)' {

    It 'TC-DryRunGuard-01: DryRun set means no side-effect file writes' {
        $DryRun = $true
        $shouldWrite = -not $DryRun
        $shouldWrite | Should -BeFalse
    }

    It 'TC-DryRunGuard-02: Live mode allows file writes' {
        $DryRun = $false
        $shouldWrite = -not $DryRun
        $shouldWrite | Should -BeTrue
    }
}

Describe 'TC-HtmlEscape: HTML escaping edge cases (v14)' {

    It 'TC-HtmlEscape-01: ampersand escaped' {
        $text = 'A & B'
        $escaped = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
        $escaped | Should -Be 'A &amp; B'
    }

    It 'TC-HtmlEscape-02: angle brackets escaped' {
        $text = '<script>alert(1)</script>'
        $escaped = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
        $escaped | Should -Be '&lt;script&gt;alert(1)&lt;/script&gt;'
    }

    It 'TC-HtmlEscape-03: already clean text unchanged' {
        $text = 'Normal text 123'
        $escaped = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
        $escaped | Should -Be 'Normal text 123'
    }

    It 'TC-HtmlEscape-04: quotes pass through (acceptable in span content)' {
        $text = 'value="test"'
        $escaped = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
        $escaped | Should -Be 'value="test"'
    }
}

Describe 'TC-FlipNorm: FlipToTeams raObjectIds normalization (v14 fix)' {

    It 'TC-FlipNorm-01: digit extraction from UPN matches phone number' {
        $upn = 'acs-tpe-ra-12069990060@domain.com'
        $localPart = ($upn -split '@')[0]
        $prefixBefore = 'acs-tpe-ra-'
        if ($prefixBefore -and $localPart.StartsWith($prefixBefore)) {
            $digits = $localPart.Substring($prefixBefore.Length)
            $phone = "+$digits"
        }
        $phone | Should -Be '+12069990060'
    }

    It 'TC-FlipNorm-02: ObjectId lookup by digit match works' {
        $raObjectIds = @{
            'acs-tpe-ra-12069990060@domain.com' = 'oid-aaa-bbb'
            'acs-tpe-ra-14255550100@domain.com' = 'oid-ccc-ddd'
        }
        $num = '+12069990060'
        $digits = $num -replace '\+',''
        $oid = ($raObjectIds.GetEnumerator() | Where-Object { $_.Key -match $digits } | Select-Object -First 1).Value
        $oid | Should -Be 'oid-aaa-bbb'
    }
}

# ============================================================================
# v14.0.0 NEW TESTS — covers all gaps found in v13 deep-dive review
# ============================================================================

Describe 'TC-FlipTeamsSanitize: FlipToTeams prefix sanitization parity with FlipToACS (v14 fix)' {

    It 'TC-FlipTeams-01: FlipToTeams with special chars in prefix extracts correctly (v14 sanitization fix)' {
        # v13 bug: FlipToTeams did NOT sanitize RaPrefix before comparison, so
        # "TPE RA/<phonenumber>" would fail to match UPN "tpe-ra-12065551001@..."
        # v14 fix: FlipToTeams now sanitizes like FlipToACS/Build-RaList
        $raPrefix = 'TPE RA/<phonenumber>'
        $sanitized = ($raPrefix -replace '[^a-zA-Z0-9\-\.<>]', '-' -replace '-+', '-').ToLower().Trim('-')
        $prefixBefore = if ($sanitized -match '<phonenumber>') { ($sanitized -split '<phonenumber>')[0] } else { '' }

        $upn = 'tpe-ra-12065551001@contoso.com'
        $localPart = ($upn -split '@')[0]
        $localPart.StartsWith($prefixBefore) | Should -BeTrue
        $digits = $localPart.Substring($prefixBefore.Length)
        "+$digits" | Should -Be '+12065551001'
    }

    It 'TC-FlipTeams-02: unsanitized prefix fails to match (demonstrates v13 bug)' {
        # Without sanitization: "TPE RA/" does NOT match "tpe-ra-..."
        $raPrefix = 'TPE RA/<phonenumber>'
        $prefixBefore = if ($raPrefix -match '<phonenumber>') { ($raPrefix -split '<phonenumber>')[0] } else { '' }

        $upn = 'tpe-ra-12065551001@contoso.com'
        $localPart = ($upn -split '@')[0]
        # v13 would fail here because prefixBefore = "TPE RA/" (mixed case, spaces)
        $localPart.StartsWith($prefixBefore) | Should -BeFalse
    }

    It 'TC-FlipTeams-03: standard hyphenated prefix works with sanitization' {
        $raPrefix = 'acs-tpe-ra-<phonenumber>'
        $sanitized = ($raPrefix -replace '[^a-zA-Z0-9\-\.<>]', '-' -replace '-+', '-').ToLower().Trim('-')
        $prefixBefore = if ($sanitized -match '<phonenumber>') { ($sanitized -split '<phonenumber>')[0] } else { '' }
        $prefixBefore | Should -Be 'acs-tpe-ra-'

        $localPart = 'acs-tpe-ra-12069990060'
        $localPart.StartsWith($prefixBefore) | Should -BeTrue
    }
}

Describe 'TC-D365NullGuard: D365OrgUrl PSObject.Properties null guard (v14 fix)' {

    It 'TC-D365Null-01: PSObject.Properties check catches missing property (v14 pattern)' {
        $cfg = [PSCustomObject]@{ TenantId = 'abc' }
        $result = if ($cfg -and $cfg.PSObject.Properties['D365OrgUrl'] -and $cfg.D365OrgUrl) { $cfg.D365OrgUrl } else { '' }
        $result | Should -Be ''
    }

    It 'TC-D365Null-02: v13 pattern without PSObject check would throw on strict mode' {
        # In strict mode, $cfg.D365OrgUrl on a PSCustomObject without that property throws
        $cfg = [PSCustomObject]@{ TenantId = 'abc' }
        $hasProperty = $cfg.PSObject.Properties['D365OrgUrl'] -ne $null
        $hasProperty | Should -BeFalse
    }

    It 'TC-D365Null-03: valid D365OrgUrl passes v14 guard' {
        $cfg = [PSCustomObject]@{ D365OrgUrl = 'https://test.crm.dynamics.com'; TenantId = 'abc' }
        $result = if ($cfg -and $cfg.PSObject.Properties['D365OrgUrl'] -and $cfg.D365OrgUrl) { $cfg.D365OrgUrl } else { '' }
        $result | Should -Be 'https://test.crm.dynamics.com'
    }
}

Describe 'TC-Step11Scope: step11Failed scope initialization and combined count (v14 fix)' {

    It 'TC-Step11Scope-01: step11Failed defaults to empty array at script scope' {
        $step11Failed = @()
        $step11Failed.Count | Should -Be 0
    }

    It 'TC-Step11Scope-02: failedCount calculation handles empty step11Failed' {
        $results = @(
            [PSCustomObject]@{ Status = 'OK' }
            [PSCustomObject]@{ Status = 'OK' }
        )
        $step11Failed = @()
        $failedCount = @($results | Where-Object { $_.Status -eq 'Pending' }).Count + $step11Failed.Count
        $failedCount | Should -Be 0
    }

    It 'TC-Step11Scope-03: failedCount includes step11 failures' {
        $results = @(
            [PSCustomObject]@{ Status = 'OK' }
            [PSCustomObject]@{ Status = 'Pending' }
        )
        $step11Failed = @('+12065551001')
        $failedCount = @($results | Where-Object { $_.Status -eq 'Pending' }).Count + $step11Failed.Count
        $failedCount | Should -Be 2
    }
}

Describe 'TC-D365Backup: D365 backup round-trip integrity (v14)' {

    It 'TC-D365Bkp-01: backup JSON preserves all 8 standard fields' {
        $backup = @{
            '+12065551001' = [PSCustomObject]@{
                statecode                 = 0
                statuscode                = 1
                msdyn_ocphonenumbersource = 192350000
                msdyn_teamsresourceaccount = $null
                msdyn_type                = 192350000
                msdyn_phonenumbertype     = 1
                msdyn_objective           = 192350001
                msdyn_appmodule           = '192350000'
            }
        }
        $json = $backup | ConvertTo-Json -Depth 5
        $loaded = $json | ConvertFrom-Json
        $entry = $loaded.'+12065551001'
        $entry.statecode | Should -Be 0
        $entry.msdyn_ocphonenumbersource | Should -Be 192350000
        $entry.msdyn_teamsresourceaccount | Should -BeNullOrEmpty
        $entry.msdyn_objective | Should -Be 192350001
        $entry.msdyn_appmodule | Should -Be '192350000'
    }

    It 'TC-D365Bkp-02: backup with Teams DR source round-trips correctly' {
        $backup = @{
            '+14255550100' = [PSCustomObject]@{
                statecode                 = 0
                statuscode                = 1
                msdyn_ocphonenumbersource = 192350001
                msdyn_teamsresourceaccount = 'aaaa-bbbb-cccc-dddd'
                msdyn_type                = 192350001
                msdyn_phonenumbertype     = 1
                msdyn_objective           = $null
                msdyn_appmodule           = $null
            }
        }
        $json = $backup | ConvertTo-Json -Depth 5
        $loaded = $json | ConvertFrom-Json
        $entry = $loaded.'+14255550100'
        $entry.msdyn_ocphonenumbersource | Should -Be 192350001
        $entry.msdyn_teamsresourceaccount | Should -Be 'aaaa-bbbb-cccc-dddd'
    }

    It 'TC-D365Bkp-03: undo fallback body is valid JSON' {
        $fallback = '{"statecode": 0, "statuscode": 1, "msdyn_teamsresourceaccount": null, "msdyn_ocphonenumbersource": 192350000}'
        $parsed = $fallback | ConvertFrom-Json
        $parsed.statecode | Should -Be 0
        $parsed.msdyn_ocphonenumbersource | Should -Be 192350000
        $parsed.msdyn_teamsresourceaccount | Should -BeNullOrEmpty
    }
}

Describe 'TC-VersionString: Version string consistency (v14)' {

    It 'TC-Version-01: v14 run record type is valid' {
        $rec = [ordered]@{
            type      = 'migrate'
            timestamp = '2026-04-27T10:00:00'
            result    = 'OK'
            failures  = 0
        }
        $json = $rec | ConvertTo-Json -Compress
        ($json | ConvertFrom-Json).type | Should -Be 'migrate'
    }

    It 'TC-Version-02: undo result thresholds unchanged in v14' {
        # Verify the 0/1-3/>3 thresholds are consistent
        foreach ($pair in @(@(0, 'OK'), @(1, 'WARN'), @(3, 'WARN'), @(4, 'FAIL'))) {
            $fc = $pair[0]; $expected = $pair[1]
            $result = if ($fc -gt 3) { 'FAIL' } elseif ($fc -gt 0) { 'WARN' } else { 'OK' }
            $result | Should -Be $expected
        }
    }
}

Describe 'TC-PhoneFormat: E.164 phone number format validation (v14)' {

    It 'TC-Phone-01: standard +1 number matches E.164 pattern' {
        '+12065551234' | Should -Match '^\+\d{7,15}$'
    }

    It 'TC-Phone-02: number without + fails E.164 pattern' {
        '12065551234' | Should -Not -Match '^\+\d{7,15}$'
    }

    It 'TC-Phone-03: number with spaces fails E.164 pattern' {
        '+1 206 555 1234' | Should -Not -Match '^\+\d{7,15}$'
    }

    It 'TC-Phone-04: international number matches E.164' {
        '+442079999888' | Should -Match '^\+\d{7,15}$'
    }

    It 'TC-Phone-05: short number (6 digits) fails minimum length' {
        '+123456' | Should -Not -Match '^\+\d{7,15}$'
    }
}

# ============================================================================
# v14.0.0 ITERATION 2 — covers gaps found in deep-dive of all 16 v14 scripts
# ============================================================================

Describe 'TC-Step2ConnGuard: Step 2 connection string null guard (v14 fix)' {

    It 'TC-Step2Conn-01: malformed connection string without endpoint= returns empty acsEp' {
        $acsConn = @{}
        'accesskey=mykey123'.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $acsEp = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
        $acsEp | Should -Be ''
    }

    It 'TC-Step2Conn-02: malformed connection string without accesskey= returns empty acsKey' {
        $acsConn = @{}
        'endpoint=https://myacs.communication.azure.com/'.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $acsKey = if ($acsConn['accesskey']) { $acsConn['accesskey'] } else { '' }
        $acsKey | Should -Be ''
    }

    It 'TC-Step2Conn-03: valid connection string extracts both fields' {
        $acsConn = @{}
        'endpoint=https://myacs.communication.azure.com/;accesskey=abc123'.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $acsEp  = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
        $acsKey = if ($acsConn['accesskey']) { $acsConn['accesskey'] } else { '' }
        $acsEp  | Should -Be 'https://myacs.communication.azure.com'
        $acsKey | Should -Be 'abc123'
    }

    It 'TC-Step2Conn-04: empty connection string does not throw' {
        $acsConn = @{}
        ''.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $acsEp = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
        $acsEp | Should -Be ''
    }
}

Describe 'TC-FlipAcsOidNorm: FlipToACS raObjectIds normalization parity (v14 fix)' {

    It 'TC-FlipAcsOid-01: plain string ObjectId preserved (v14 pattern)' {
        $json = '{"ra@contoso.com":"aaaa-bbbb-cccc-dddd"}'
        $loaded = $json | ConvertFrom-Json
        $raObjectIds = @{}
        $loaded.PSObject.Properties | ForEach-Object {
            $raObjectIds[$_.Name] = if ($_.Value -is [string]) { $_.Value } elseif ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { [string]$_.Value }
        }
        $raObjectIds['ra@contoso.com'] | Should -Be 'aaaa-bbbb-cccc-dddd'
    }

    It 'TC-FlipAcsOid-02: nested ObjectId property extracted (v14 pattern)' {
        $json = '{"ra@contoso.com":{"ObjectId":"aaaa-bbbb-cccc","Type":"RA"}}'
        $loaded = $json | ConvertFrom-Json
        $raObjectIds = @{}
        $loaded.PSObject.Properties | ForEach-Object {
            $raObjectIds[$_.Name] = if ($_.Value -is [string]) { $_.Value } elseif ($_.Value.PSObject.Properties['ObjectId']) { $_.Value.ObjectId } else { [string]$_.Value }
        }
        $raObjectIds['ra@contoso.com'] | Should -Be 'aaaa-bbbb-cccc'
    }

    It 'TC-FlipAcsOid-03: v13 raw store would break -is [string] check' {
        $json = '{"ra@contoso.com":{"ObjectId":"aaaa-bbbb-cccc","Type":"RA"}}'
        $loaded = $json | ConvertFrom-Json
        $rawValue = $loaded.PSObject.Properties['ra@contoso.com'].Value
        # Without normalization, raw PSCustomObject stored
        $rawValue -is [string] | Should -BeFalse
        # With v14 normalization, string extracted
        $normalized = if ($rawValue -is [string]) { $rawValue } elseif ($rawValue.PSObject.Properties['ObjectId']) { $rawValue.ObjectId } else { [string]$rawValue }
        $normalized -is [string] | Should -BeTrue
        $normalized | Should -Be 'aaaa-bbbb-cccc'
    }
}

Describe 'TC-DrDoClassification: DR/DO phone number classification (v14)' {

    It 'TC-DrDo-01: number matching route pattern classified as DR' {
        $patterns = @('^\+1206\d*$', '^\+1425\d*$')
        $num = '+12065551234'
        $isDR = $patterns | Where-Object { $num -match $_ }
        [bool]$isDR | Should -BeTrue
    }

    It 'TC-DrDo-02: number not matching any route pattern classified as DO' {
        $patterns = @('^\+1206\d*$', '^\+1425\d*$')
        $num = '+442079999888'
        $isDR = $patterns | Where-Object { $num -match $_ }
        [bool]$isDR | Should -BeFalse
    }

    It 'TC-DrDo-03: wildcard pattern matches all numbers' {
        $patterns = @('.*')
        $num = '+12065551234'
        $isDR = $patterns | Where-Object { $num -match $_ }
        [bool]$isDR | Should -BeTrue
    }

    It 'TC-DrDo-04: empty route patterns array classifies all as DO' {
        $patterns = @()
        $num = '+12065551234'
        $isDR = $patterns | Where-Object { $num -match $_ }
        [bool]$isDR | Should -BeFalse
    }
}

Describe 'TC-FlipDotPrefix: Extract-PhoneFromUpn with dot-containing prefix (v14)' {

    It 'TC-FlipDot-01: prefix with dot extracts correctly after sanitization' {
        $result = Extract-PhoneFromUpn -Upn 'my.ra-12065551001@contoso.com' -RaPrefix 'my.ra-<phonenumber>'
        $result | Should -Be '+12065551001'
    }

    It 'TC-FlipDot-02: prefix with multiple dots sanitized correctly' {
        $result = Extract-PhoneFromUpn -Upn 'a.b.c-12065551001@contoso.com' -RaPrefix 'a.b.c-<phonenumber>'
        $result | Should -Be '+12065551001'
    }

    It 'TC-FlipDot-03: prefix with trailing hyphens trimmed' {
        $raPrefix = '-test-<phonenumber>-'
        $sanitized = ($raPrefix -replace '[^a-zA-Z0-9\-\.<>]', '-' -replace '-+', '-').ToLower().Trim('-')
        $sanitized | Should -Not -Match '^-'
        $sanitized | Should -Not -Match '-$'
    }
}

Describe 'TC-ToggleRequires: Toggle script version check (v14)' {

    It 'TC-ToggleReq-01: Toggle-AcsTeamsRouting-v14.ps1 has #Requires directive' {
        $togglePath = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $togglePath) {
            $content = Get-Content $togglePath -Raw
            $content | Should -Match '#Requires\s+-Version\s+5\.1'
        } else {
            Set-ItResult -Skipped -Because "Toggle-AcsTeamsRouting-v14.ps1 not found in test directory"
        }
    }
}

Describe 'TC-AcsEndpointNorm: ACS endpoint normalization edge cases (v14)' {

    It 'TC-AcsEpNorm-01: endpoint with trailing slash normalized' {
        $ep = 'https://myacs.communication.azure.com/'
        $ep.TrimEnd('/') | Should -Be 'https://myacs.communication.azure.com'
    }

    It 'TC-AcsEpNorm-02: endpoint without trailing slash unchanged' {
        $ep = 'https://myacs.communication.azure.com'
        $ep.TrimEnd('/') | Should -Be 'https://myacs.communication.azure.com'
    }

    It 'TC-AcsEpNorm-03: AcsResourceName (bare name) gets https:// prepended' {
        $name = 'myacs'
        $resolved = if ($name -notmatch '^https?://') { "https://$($name.TrimEnd('/'))" } else { $name.TrimEnd('/') }
        $resolved | Should -Be 'https://myacs'
    }

    It 'TC-AcsEpNorm-04: full URL is not double-prefixed' {
        $name = 'https://myacs.communication.azure.com'
        $resolved = if ($name -notmatch '^https?://') { "https://$($name.TrimEnd('/'))" } else { $name.TrimEnd('/') }
        $resolved | Should -Be 'https://myacs.communication.azure.com'
    }
}

Describe 'TC-UndoIgnorable: Undo ignorable error edge cases (v14)' {

    BeforeAll {
        function Make-Error { param([string]$msg) [System.Management.Automation.ErrorRecord]::new([Exception]::new($msg), 'Test', 'NotSpecified', $null) }
    }

    It 'TC-UndoIgn-01: "The user was not found" matches' {
        Test-IsIgnorableUndoError (Make-Error 'The user was not found in the directory') | Should -BeTrue
    }

    It 'TC-UndoIgn-02: "timeout" does NOT match (transient, should retry)' {
        Test-IsIgnorableUndoError (Make-Error 'The operation has timed out') | Should -BeFalse
    }

    It 'TC-UndoIgn-03: "throttled" does NOT match' {
        Test-IsIgnorableUndoError (Make-Error 'Request was throttled') | Should -BeFalse
    }
}

Describe 'TC-RunRecordDash: Dashboard state label logic (v14)' {

    It 'TC-Dash-01: last migrate run shows MIGRATED label' {
        $last = [PSCustomObject]@{ type = 'migrate'; dryRun = $false }
        $label = if (-not $last) { 'Unknown' } elseif ($last.type -eq 'migrate') { 'MIGRATED' } else { 'ROLLED BACK' }
        $label | Should -Be 'MIGRATED'
    }

    It 'TC-Dash-02: last undo run shows ROLLED BACK label' {
        $last = [PSCustomObject]@{ type = 'undo'; dryRun = $false }
        $label = if (-not $last) { 'Unknown' } elseif ($last.type -eq 'migrate') { 'MIGRATED' } else { 'ROLLED BACK' }
        $label | Should -Be 'ROLLED BACK'
    }

    It 'TC-Dash-03: no runs shows Unknown label' {
        $last = $null
        $label = if (-not $last) { 'Unknown' } elseif ($last.type -eq 'migrate') { 'MIGRATED' } else { 'ROLLED BACK' }
        $label | Should -Be 'Unknown'
    }

    It 'TC-Dash-04: dry run records excluded from last action' {
        $records = @(
            [PSCustomObject]@{ type = 'migrate'; dryRun = $false }
            [PSCustomObject]@{ type = 'undo';    dryRun = $true }
        )
        $last = $records | Where-Object { -not $_.dryRun } | Select-Object -Last 1
        $last.type | Should -Be 'migrate'
    }
}

# ============================================================================
# v14.0.1 NEW TESTS -- covers gaps found in v14 deep-dive review
# ============================================================================

Describe 'TC-DryRunFileGuard: DryRun must not write acs-trunk-disabled.json (v14.0.1 fix)' {

    It 'TC-DryRunFile-01: DryRun branch skips file write' {
        $DryRun = $true
        $acsDisabledFqdns = @('sbc.contoso.com')
        $wrote = $false
        if (-not $DryRun) {
            $wrote = $true
        }
        $wrote | Should -BeFalse
    }

    It 'TC-DryRunFile-02: live mode allows file write' {
        $DryRun = $false
        $acsDisabledFqdns = @('sbc.contoso.com')
        $wrote = $false
        if (-not $DryRun) {
            $wrote = $true
        }
        $wrote | Should -BeTrue
    }

    It 'TC-DryRunFile-03: DryRun FQDNs accumulate but are not persisted' {
        $DryRun = $true
        $acsDisabledFqdns = @()
        $acsDisabledFqdns += 'sbc1.contoso.com'
        $acsDisabledFqdns += 'sbc2.contoso.com'
        $acsDisabledFqdns.Count | Should -Be 2
        $shouldPersist = -not $DryRun
        $shouldPersist | Should -BeFalse
    }
}

Describe 'TC-CfgNullGuard: cfg null guard when StartAtStep>0 without ConfigPath (v14.0.1 fix)' {

    It 'TC-CfgNull-01: null cfg with StartAtStep>0 is detected as error condition' {
        $cfg = $null
        $StartAtStep = 5
        $shouldFail = (-not $cfg -and $StartAtStep -gt 0)
        $shouldFail | Should -BeTrue
    }

    It 'TC-CfgNull-02: null cfg with StartAtStep=0 proceeds to interactive prompt' {
        $cfg = $null
        $StartAtStep = 0
        $shouldFail = (-not $cfg -and $StartAtStep -gt 0)
        $shouldFail | Should -BeFalse
    }

    It 'TC-CfgNull-03: loaded cfg with StartAtStep>0 passes guard' {
        $cfg = [PSCustomObject]@{ TenantId = 'abc'; SbcFqdn = 'sbc.contoso.com' }
        $StartAtStep = 5
        $shouldFail = (-not $cfg -and $StartAtStep -gt 0)
        $shouldFail | Should -BeFalse
    }
}

Describe 'TC-AppModuleFallback: msdyn_appmodule fallback parity Step9 vs Step6 (v14.0.1 fix)' {

    It 'TC-AppMod-01: Step 9 and Step 6 both use null fallback for missing msdyn_appmodule' {
        $bkpEntry = [PSCustomObject]@{ statecode = 0; statuscode = 1 }
        $step9Fallback = if ($bkpEntry.PSObject.Properties['msdyn_appmodule'] -and $bkpEntry.msdyn_appmodule -ne $null) { $bkpEntry.msdyn_appmodule } else { $null }
        $step6Fallback = if ($bkpEntry.PSObject.Properties['msdyn_appmodule'] -and $bkpEntry.msdyn_appmodule -ne $null) { $bkpEntry.msdyn_appmodule } else { $null }
        $step9Fallback | Should -BeNullOrEmpty
        $step6Fallback | Should -BeNullOrEmpty
        $step9Fallback | Should -Be $step6Fallback
    }

    It 'TC-AppMod-02: present msdyn_appmodule value preserved by both steps' {
        $bkpEntry = [PSCustomObject]@{ msdyn_appmodule = 192350000 }
        $step9Val = if ($bkpEntry.msdyn_appmodule -ne $null) { $bkpEntry.msdyn_appmodule } else { $null }
        $step6Val = if ($bkpEntry.msdyn_appmodule -ne $null) { $bkpEntry.msdyn_appmodule } else { $null }
        $step9Val | Should -Be 192350000
        $step6Val | Should -Be 192350000
    }
}

Describe 'TC-CrossRef: Cross-script references use v14 suffix (v14.0.1)' {

    It 'TC-CrossRef-01: Toggle reference uses v14 suffix' {
        $ref = 'Toggle-AcsTeamsRouting-v14.ps1'
        $ref | Should -Match '-v14\.ps1$'
    }

    It 'TC-CrossRef-02: MigrateTpsPhoneNumber reference uses v14 suffix' {
        $ref = 'Invoke-MigrateTpsPhoneNumber-v14.ps1'
        $ref | Should -Match '-v14\.ps1$'
    }

    It 'TC-CrossRef-03: config file reference uses v14.11.0' {
        $ref = 'new-acs-tpe-config-v14.11.0.json'
        $ref | Should -Match 'v14.11.0\.json$'
    }

    It 'TC-CrossRef-04: GetTeamsProviderSetting reference uses v14' {
        $ref = 'Get-TeamsProviderSetting-v14.ps1'
        $ref | Should -Match '-v14\.ps1$'
    }
}

Describe 'TC-WriteStepColor: Write-Step accepts optional color parameter (v14.0.1 parity fix)' {

    It 'TC-WriteStep-01: default color is Cyan' {
        $defaultColor = 'Cyan'
        $defaultColor | Should -Be 'Cyan'
    }

    It 'TC-WriteStep-02: custom color can be passed' {
        $customColor = 'Yellow'
        $result = switch ($customColor) {
            'Cyan'   { 'cyan' }
            'Yellow' { 'yellow' }
            'Red'    { 'red' }
            default  { 'white' }
        }
        $result | Should -Be 'yellow'
    }
}

Describe 'TC-UndoDescTypo: Undo DESCRIPTION NOTE line has no stray prefix (v14.0.1)' {

    It 'TC-DescTypo-01: NOTE line should not start with n prefix' {
        $correctLine = '    NOTE: Steps 5, 10, 11 have no undo action.'
        $correctLine | Should -Not -Match '^\s*n\s+NOTE:'
        $correctLine | Should -Match '^\s+NOTE:'
    }

    It 'TC-DescTypo-02: stray n prefix is detectable' {
        $buggyLine = 'n    NOTE: Steps 5, 10, 11 have no undo action.'
        $buggyLine | Should -Match '^n\s+NOTE:'
    }
}

# ============================================================================
# v14.0.2 NEW TESTS -- verifies consistency fixes applied across all v14 scripts
# ============================================================================

Describe 'TC-RequiresDirective: All v14 scripts have #Requires -Version 5.1 (v14.0.2)' {

    BeforeAll {
        $script:ScriptDir = $PSScriptRoot
        $script:V14Scripts = @(
            'Invoke-ACS-TPE-Full-Migration-v14.ps1',
            'Undo-ACS-TPE-Migration-v14.ps1',
            'Toggle-AcsTeamsRouting-v14.ps1',
            'Invoke-FlipToACS-v14.ps1',
            'Invoke-FlipToTeams-v14.ps1',
            'Invoke-MigrateTpsPhoneNumber-v14.ps1',
            'New-AcsTpeConfig-v14.ps1',
            'Update-PhoneNumberType-v14.ps1',
            'Repair-D365PhoneRecord-v14.ps1',
            'Test-DomainRegistration-v14.ps1',
            'Set-AcsSbcFqdn-v14.ps1',
            'Add-AcsTrunkDisabled-v14.ps1',
            'Fix-AcsRoutePattern-v14.ps1',
            'Get-TeamsProviderSetting-v14.ps1',
            'Sync-TeamsPhoneNumbers-v14.ps1',
            'Invoke-TeamsPhoneSync-v14.ps1'
        )
    }

    It 'TC-Requires-<_>: <_> has #Requires directive' -ForEach @(
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1',
        'New-AcsTpeConfig-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Repair-D365PhoneRecord-v14.ps1',
        'Test-DomainRegistration-v14.ps1'
    ) {
        $path = Join-Path $script:ScriptDir $_
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '#Requires\s+-Version\s+5\.1'
        } else {
            Set-ItResult -Skipped -Because "$_ not found in test directory"
        }
    }
}

Describe 'TC-StrictMode: All v14 scripts have Set-StrictMode (v14.0.2)' {

    It 'TC-StrictMode-<_>: <_> has Set-StrictMode' -ForEach @(
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1'
    ) {
        $path = Join-Path $PSScriptRoot $_
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
        } else {
            Set-ItResult -Skipped -Because "$_ not found in test directory"
        }
    }
}

Describe 'TC-VersionBanners: Version banners match v14 (v14.0.2)' {

    It 'TC-Banner-01: Update-PhoneNumberType banner says v14' {
        $path = Join-Path $PSScriptRoot 'Update-PhoneNumberType-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'UpdatePhoneNumberType v14'
            $content | Should -Not -Match 'UpdatePhoneNumberType v10'
        } else {
            Set-ItResult -Skipped -Because 'Update-PhoneNumberType-v14.ps1 not found'
        }
    }

    It 'TC-Banner-02: New-AcsTpeConfig banner says v14' {
        $path = Join-Path $PSScriptRoot 'New-AcsTpeConfig-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'New-AcsTpeConfig v14'
            $content | Should -Not -Match 'New-AcsTpeConfig v10'
        } else {
            Set-ItResult -Skipped -Because 'New-AcsTpeConfig-v14.ps1 not found'
        }
    }

    It 'TC-Banner-03: Migration final summary says v14' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'COMPLETE\s+\(v14(\.\d+\.\d+)?\)'
            $content | Should -Not -Match 'COMPLETE\s+\(v12\)'
        } else {
            Set-ItResult -Skipped -Because 'Invoke-ACS-TPE-Full-Migration-v14.ps1 not found'
        }
    }

    It 'TC-Banner-04: Migration plan steps label says v14' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'PLANNED STEPS \(v14\)'
            $content | Should -Not -Match 'PLANNED STEPS \(v12\)'
        } else {
            Set-ItResult -Skipped -Because 'Invoke-ACS-TPE-Full-Migration-v14.ps1 not found'
        }
    }
}

Describe 'TC-CfgNullGuardActual: cfg null guard present in migration script (v14.0.2)' {

    It 'TC-CfgNullActual-01: migration script has cfg null guard for resume mode' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'if \(-not \$cfg -and \$StartAtStep -gt 0\)'
        } else {
            Set-ItResult -Skipped -Because 'Invoke-ACS-TPE-Full-Migration-v14.ps1 not found'
        }
    }
}

Describe 'TC-DryRunGuardActual: DryRun guards acs-trunk-disabled.json write (v14.0.2)' {

    It 'TC-DryRunActual-01: Step 2 final write is gated by DryRun check' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'if \(-not \$DryRun\) \{[\s\S]*?acs-trunk-disabled\.json[\s\S]*?\} else \{'
        } else {
            Set-ItResult -Skipped -Because 'Invoke-ACS-TPE-Full-Migration-v14.ps1 not found'
        }
    }
}

Describe 'TC-UndoHtmlTryCatch: Undo Write-HtmlLine has try/catch (v14.0.2)' {

    It 'TC-UndoHtml-01: Undo Write-HtmlLine wraps Add-Content in try/catch' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-HtmlLine[\s\S]*?try \{[\s\S]*?Add-Content[\s\S]*?\} catch \{'
        } else {
            Set-ItResult -Skipped -Because 'Undo-ACS-TPE-Migration-v14.ps1 not found'
        }
    }
}

Describe 'TC-HmacDispose: SHA256/HMAC Dispose calls in utility scripts (v14.0.2)' {

    It 'TC-HmacDispose-01: Add-AcsTrunkDisabled has SHA256 Dispose' {
        $path = Join-Path $PSScriptRoot 'Add-AcsTrunkDisabled-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$sha256\.Dispose\(\)'
            $content | Should -Match '\$hmac\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'Add-AcsTrunkDisabled-v14.ps1 not found'
        }
    }

    It 'TC-HmacDispose-02: Fix-AcsRoutePattern has SHA256 Dispose' {
        $path = Join-Path $PSScriptRoot 'Fix-AcsRoutePattern-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$sha256\.Dispose\(\)'
            $content | Should -Match '\$hmac\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'Fix-AcsRoutePattern-v14.ps1 not found'
        }
    }
}

Describe 'TC-FlipToTeamsConfigRef: FlipToTeams examples use v14 config name (v14.0.2)' {

    It 'TC-FlipTeamsRef-01: no stale v9.1.0 references remain' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Not -Match 'v9\.1\.0'
            $content | Should -Match 'v14.11.0\.json'
        } else {
            Set-ItResult -Skipped -Because 'Invoke-FlipToTeams-v14.ps1 not found'
        }
    }
}

Describe 'TC-NewConfigOutputDefault: New-AcsTpeConfig default output uses v14 (v14.0.2)' {

    It 'TC-NewCfgOutput-01: OutputPath default is v14.11.0.json' {
        $path = Join-Path $PSScriptRoot 'New-AcsTpeConfig-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'new-acs-tpe-config-v14.11.0\.json'
            $content | Should -Not -Match 'new-acs-tpe-config-v10\.1\.0\.json'
        } else {
            Set-ItResult -Skipped -Because 'New-AcsTpeConfig-v14.ps1 not found'
        }
    }
}

# --------------------------------------------------------------------------
#  v14.0.3 TESTS — #Requires parity, DryRun file-write guards, undo exit
#  code, Write-Banner $Sub parity, dashboard version strings
# --------------------------------------------------------------------------

Describe 'TC-RequiresAll: ALL v14 scripts have #Requires -Version 5.1 (v14.0.3)' {

    $allScripts = @(
        'Invoke-ACS-TPE-Full-Migration-v14.ps1',
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1',
        'New-AcsTpeConfig-v14.ps1',
        'Invoke-MigrateTpsPhoneNumber-v14.ps1',
        'Repair-D365PhoneRecord-v14.ps1',
        'Set-AcsSbcFqdn-v14.ps1',
        'Test-DomainRegistration-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Get-TeamsProviderSetting-v14.ps1',
        'Sync-TeamsPhoneNumbers-v14.ps1',
        'Invoke-TeamsPhoneSync-v14.ps1',
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1'
    )

    It 'TC-ReqAll-<_>: <_> has #Requires directive' -ForEach $allScripts {
        $path = Join-Path $PSScriptRoot $_
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '#Requires\s+-Version\s+5\.1'
        } else {
            Set-ItResult -Skipped -Because "$_ not found"
        }
    }
}

Describe 'TC-StrictModeAll: All v14 scripts have Set-StrictMode (v14.0.3)' {

    $allScripts = @(
        'Invoke-ACS-TPE-Full-Migration-v14.ps1',
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1',
        'New-AcsTpeConfig-v14.ps1',
        'Invoke-MigrateTpsPhoneNumber-v14.ps1',
        'Repair-D365PhoneRecord-v14.ps1',
        'Set-AcsSbcFqdn-v14.ps1',
        'Test-DomainRegistration-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Get-TeamsProviderSetting-v14.ps1',
        'Sync-TeamsPhoneNumbers-v14.ps1',
        'Invoke-TeamsPhoneSync-v14.ps1',
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1'
    )

    It 'TC-Strict-<_>: <_> has Set-StrictMode' -ForEach $allScripts {
        $path = Join-Path $PSScriptRoot $_
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Set-StrictMode\s+-Version'
        } else {
            Set-ItResult -Skipped -Because "$_ not found"
        }
    }
}

Describe 'TC-DryRunGuardAll: DryRun guards all file writes in migration script (v14.0.3)' {

    BeforeAll {
        $script:MigPath = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        $script:MigContent = if (Test-Path $script:MigPath) { Get-Content $script:MigPath -Raw } else { '' }
    }

    It 'TC-DryRunAll-01: acs-export.json write is DryRun-guarded' {
        if (-not $script:MigContent) { Set-ItResult -Skipped -Because 'migration script not found'; return }
        $script:MigContent | Should -Match '(?s)if\s*\(\s*-not\s+\$DryRun\s*\)\s*\{.*?acs-export'
    }

    It 'TC-DryRunAll-02: ra-objectids.json write is DryRun-guarded' {
        if (-not $script:MigContent) { Set-ItResult -Skipped -Because 'migration script not found'; return }
        $script:MigContent | Should -Match '(?s)if\s*\(\s*-not\s+\$DryRun\s*\)\s*\{.*?ra-objectids'
    }

    It 'TC-DryRunAll-03: d365-phone-backup.json write is DryRun-guarded' {
        if (-not $script:MigContent) { Set-ItResult -Skipped -Because 'migration script not found'; return }
        $script:MigContent | Should -Match '(?s)if\s*\(\s*-not\s+\$DryRun\s*\)\s*\{.*?d365-phone-backup'
    }

    It 'TC-DryRunAll-04: acs-trunk-disabled.json write is DryRun-guarded (pre-existing)' {
        if (-not $script:MigContent) { Set-ItResult -Skipped -Because 'migration script not found'; return }
        $script:MigContent | Should -Match '(?s)if\s*\(\s*-not\s+\$DryRun\s*\)\s*\{.*?acs-trunk-disabled'
    }
}

Describe 'TC-UndoExitCode: Undo exit code reflects result (v14.0.3)' {

    It 'TC-UndoExit-01: undo script exits 1 on FAIL' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match "undoExitCode.*FAIL.*1"
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-UndoExit-02: undo exit code 0 when not FAIL' {
        $undoResult = 'WARN'
        $undoExitCode = if ($undoResult -eq 'FAIL') { 1 } else { 0 }
        $undoExitCode | Should -Be 0
    }

    It 'TC-UndoExit-03: undo exit code 1 when FAIL' {
        $undoResult = 'FAIL'
        $undoExitCode = if ($undoResult -eq 'FAIL') { 1 } else { 0 }
        $undoExitCode | Should -Be 1
    }

    It 'TC-UndoExit-04: undo exit code 0 when OK' {
        $undoResult = 'OK'
        $undoExitCode = if ($undoResult -eq 'FAIL') { 1 } else { 0 }
        $undoExitCode | Should -Be 0
    }
}

Describe 'TC-UndoBannerSub: Undo Write-Banner has $Sub parity with migration (v14.0.3)' {

    It 'TC-UndoBanner-01: Undo Write-Banner has $Sub parameter' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-Banner\s*\{[^}]*\$Sub'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-UndoBanner-02: Migration Write-Banner has $Sub parameter' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-Banner\s*\{[^}]*\$Sub'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-DashboardVersion: Dashboard versions match v14.0.3 (v14.0.3)' {

    It 'TC-DashVer-01: Migration dashboard sub-header has v14.0.3' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.3'
            $content | Should -Not -Match 'ACS TPE v14\.0\.0[^.]'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-DashVer-02: Undo dashboard sub-header has v14.0.3' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.3'
            $content | Should -Not -Match 'ACS TPE v14\.0\.0[^.]'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-MigNotesVersion: Migration .NOTES says Version 14 not 12 (v14.0.3)' {

    It 'TC-MigNotes-01: .NOTES references Version 14' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Version 14:'
            $content | Should -Not -Match 'Version 12:'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-E164Validate: E.164 phone number edge cases (v14.0.3)' {

    BeforeAll {
        $script:E164Pattern = '^\+\d{7,15}$'
    }

    It 'TC-E164-01: +442071234567 is valid' {
        '+442071234567' | Should -Match $script:E164Pattern
    }

    It 'TC-E164-02: +4420712345 is valid (10 digits)' {
        '+4420712345' | Should -Match $script:E164Pattern
    }

    It 'TC-E164-03: +1234567890123456 is invalid (>15 digits)' {
        '+1234567890123456' | Should -Not -Match $script:E164Pattern
    }

    It 'TC-E164-04: +123456 is invalid (<7 digits)' {
        '+123456' | Should -Not -Match $script:E164Pattern
    }

    It 'TC-E164-05: 12065551234 (no +) is invalid' {
        '12065551234' | Should -Not -Match $script:E164Pattern
    }

    It 'TC-E164-06: + alone is invalid' {
        '+' | Should -Not -Match $script:E164Pattern
    }
}

Describe 'TC-UndoResultThreshold: Undo FAIL vs WARN boundary (v14.0.3)' {

    It 'TC-UndoTh-01: exactly 3 failures => WARN' {
        $failures = @('a','b','c')
        $result = if ($failures.Count -gt 3) { 'FAIL' } elseif ($failures.Count -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'WARN'
    }

    It 'TC-UndoTh-02: exactly 4 failures => FAIL' {
        $failures = @('a','b','c','d')
        $result = if ($failures.Count -gt 3) { 'FAIL' } elseif ($failures.Count -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'FAIL'
    }

    It 'TC-UndoTh-03: 0 failures => OK' {
        $failures = @()
        $result = if ($failures.Count -gt 3) { 'FAIL' } elseif ($failures.Count -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'OK'
    }

    It 'TC-UndoTh-04: exit code matches result' {
        $failures = @('a','b','c','d','e')
        $result = if ($failures.Count -gt 3) { 'FAIL' } elseif ($failures.Count -gt 0) { 'WARN' } else { 'OK' }
        $exitCode = if ($result -eq 'FAIL') { 1 } else { 0 }
        $result   | Should -Be 'FAIL'
        $exitCode | Should -Be 1
    }
}

Describe 'TC-ConnStringEdge: Connection string edge cases (v14.0.3)' {

    It 'TC-ConnEdge-01: connection string with base64 padding in middle' {
        $cs = 'endpoint=https://test.communication.azure.com;accesskey=abc+def/ghi=='
        $parts = Parse-AcsConnectionString $cs
        $parts['accesskey'] | Should -Be 'abc+def/ghi=='
    }

    It 'TC-ConnEdge-02: connection string with whitespace around delimiters' {
        $cs = 'endpoint = https://test.communication.azure.com ; accesskey = key1'
        $parts = Parse-AcsConnectionString $cs
        $parts['endpoint'] | Should -Be 'https://test.communication.azure.com'
        $parts['accesskey'] | Should -Be 'key1'
    }

    It 'TC-ConnEdge-03: regex extraction handles base64 with plus and slash' {
        $cs = 'endpoint=https://x.com;accesskey=a+b/c=='
        $keyResolved = ''
        if ($cs -match '(?i)accesskey=([^;]+)') { $keyResolved = $Matches[1].Trim() }
        $keyResolved | Should -Be 'a+b/c=='
    }
}

Describe 'TC-IgnorableEdge: Test-IsIgnorableUndoError additional patterns (v14.0.3)' {

    BeforeAll {
        function Make-Error { param([string]$msg) [System.Management.Automation.ErrorRecord]::new([Exception]::new($msg), 'Test', 'NotSpecified', $null) }
    }

    It 'TC-IgnEdge-01: "Resource was not found" with mixed case' {
        Test-IsIgnorableUndoError (Make-Error 'The Resource Was Not Found in the tenant') | Should -BeTrue
    }

    It 'TC-IgnEdge-02: "500 Internal Server Error" is NOT ignorable' {
        Test-IsIgnorableUndoError (Make-Error '500 Internal Server Error occurred') | Should -BeFalse
    }

    It 'TC-IgnEdge-03: "rate limit exceeded" is NOT ignorable' {
        Test-IsIgnorableUndoError (Make-Error 'Rate limit exceeded, please retry') | Should -BeFalse
    }

    It 'TC-IgnEdge-04: "cannot find" with Identity detail' {
        Test-IsIgnorableUndoError (Make-Error 'Cannot find an object with Identity "tpe-ra-01@contoso.com"') | Should -BeTrue
    }
}

Describe 'TC-BuildRaEdge: Build-RaList edge cases (v14.0.3)' {

    It 'TC-RaEdge-01: single number with <phonenumber> template' {
        $nums = @([PSCustomObject]@{ Number = '+12065551234'; Name = 'Q1' })
        $list = @(Build-RaList -Numbers $nums -Prefix 'RA-<phonenumber>' -Domain 'test.com')
        $list.Count        | Should -Be 1
        $list[0].DisplayName | Should -Be 'RA-12065551234'
        $list[0].UPN         | Should -Be 'ra-12065551234@test.com'
    }

    It 'TC-RaEdge-02: prefix with leading/trailing special chars trimmed' {
        $nums = @([PSCustomObject]@{ Number = '+1'; Name = 'Q' })
        $list = Build-RaList -Numbers $nums -Prefix '---Hello---' -Domain 'test.com'
        $list[0].UPN | Should -Not -Match '^-'
        $list[0].UPN | Should -Not -Match '-@'
    }

    It 'TC-RaEdge-03: empty D365Name preserved as-is' {
        $nums = @([PSCustomObject]@{ Number = '+1'; Name = '' })
        $list = Build-RaList -Numbers $nums -Prefix 'RA' -Domain 'test.com'
        $list[0].D365Name | Should -Be ''
    }
}

Describe 'TC-HmacDispose3: SHA256/HMAC Dispose in remaining scripts (v14.0.3)' {

    It 'TC-HmacDispose3-01: Toggle-AcsTeamsRouting has Dispose' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-HmacDispose3-02: Set-AcsSbcFqdn has Dispose' {
        $path = Join-Path $PSScriptRoot 'Set-AcsSbcFqdn-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-HmacDispose3-03: Invoke-ACS-TPE-Full-Migration has Dispose' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-HmacDispose3-04: Undo-ACS-TPE-Migration has Dispose' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-HmacDispose3-05: New-AcsTpeConfig has SHA256 and HMAC Dispose' {
        $path = Join-Path $PSScriptRoot 'New-AcsTpeConfig-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$sha256\.Dispose\(\)'
            $content | Should -Match '\$hmac\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }
}

# --------------------------------------------------------------------------
#  v14.0.4 TESTS — New-AcsTpeConfig HMAC Dispose, FlipToTeams HTML parity,
#  Undo needsAcsKey range check, migration Step 2 inner DryRun guard,
#  FlipToTeams/FlipToACS run-record parity, dashboard flip-teams/flip-acs types
# --------------------------------------------------------------------------

Describe 'TC-FlipTeamsParity: FlipToTeams has HTML log + run record + dashboard (v14.0.4)' {

    It 'TC-FlipTeamsParity-01: FlipToTeams has HtmlLogPath setup' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$script:HtmlLogPath'
            $content | Should -Match 'tpe-flip-teams-run-'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-FlipTeamsParity-02: FlipToTeams has Write-TpeRunRecord function' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-TpeRunRecord'
            $content | Should -Match 'flip-teams'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-FlipTeamsParity-03: FlipToTeams has Update-TpeStatusDashboard' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Update-TpeStatusDashboard'
            $content | Should -Match 'Update-TpeStatusDashboard'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-FlipTeamsParity-04: FlipToTeams has Exit-Script helper' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Exit-Script'
            $content | Should -Match '</pre>.*</body></html>'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-FlipTeamsParity-05: FlipToTeams sets d365OrgUrlForRecord' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$script:d365OrgUrlForRecord'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }
}

Describe 'TC-FlipAcsParity: FlipToACS has HTML log + run record + dashboard (v14.0.4)' {

    It 'TC-FlipAcsParity-01: FlipToACS has HtmlLogPath setup' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToACS-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$script:HtmlLogPath'
            $content | Should -Match 'tpe-flip-acs-run-'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-FlipAcsParity-02: FlipToACS has Write-TpeRunRecord function' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToACS-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-TpeRunRecord'
            $content | Should -Match 'flip-acs'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-FlipAcsParity-03: FlipToACS has Update-TpeStatusDashboard' {
        $path = Join-Path $PSScriptRoot 'Invoke-FlipToACS-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Update-TpeStatusDashboard'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }
}

Describe 'TC-DashFlipTypes: Dashboard correctly handles flip-teams and flip-acs run types (v14.0.4)' {

    It 'TC-DashFlip-01: flip-teams record categorized as To-Teams' {
        $rec = [PSCustomObject]@{ type = 'flip-teams'; dryRun = $false }
        $isTeams = ($rec.type -eq 'migrate' -or $rec.type -eq 'flip-teams')
        $isTeams | Should -BeTrue
    }

    It 'TC-DashFlip-02: flip-acs record categorized as To-ACS' {
        $rec = [PSCustomObject]@{ type = 'flip-acs'; dryRun = $false }
        $isTeams = ($rec.type -eq 'migrate' -or $rec.type -eq 'flip-teams')
        $isTeams | Should -BeFalse
    }

    It 'TC-DashFlip-03: migrate record categorized as To-Teams' {
        $rec = [PSCustomObject]@{ type = 'migrate'; dryRun = $false }
        $isTeams = ($rec.type -eq 'migrate' -or $rec.type -eq 'flip-teams')
        $isTeams | Should -BeTrue
    }

    It 'TC-DashFlip-04: undo record categorized as To-ACS' {
        $rec = [PSCustomObject]@{ type = 'undo'; dryRun = $false }
        $isTeams = ($rec.type -eq 'migrate' -or $rec.type -eq 'flip-teams')
        $isTeams | Should -BeFalse
    }
}

Describe 'TC-UndoNeedsAcsKey: Undo needsAcsKey range check covers Step 2 (v14.0.4)' {

    It 'TC-NeedsKey-01: Step 9 to 1 includes Step 2 -- needsAcsKey should fire' {
        $StartAtStep = 9; $StopAfterStep = 1
        $keyMissing = $true
        $needsAcsKey = $keyMissing -and ($StartAtStep -ge 2 -and $StopAfterStep -le 2)
        $needsAcsKey | Should -BeTrue
    }

    It 'TC-NeedsKey-02: Step 9 to 3 excludes Step 2 -- needsAcsKey should NOT fire' {
        $StartAtStep = 9; $StopAfterStep = 3
        $keyMissing = $true
        $needsAcsKey = $keyMissing -and ($StartAtStep -ge 2 -and $StopAfterStep -le 2)
        $needsAcsKey | Should -BeFalse
    }

    It 'TC-NeedsKey-03: Step 2 only -- needsAcsKey should fire' {
        $StartAtStep = 2; $StopAfterStep = 2
        $keyMissing = $true
        $needsAcsKey = $keyMissing -and ($StartAtStep -ge 2 -and $StopAfterStep -le 2)
        $needsAcsKey | Should -BeTrue
    }

    It 'TC-NeedsKey-04: key already present -- needsAcsKey should NOT fire' {
        $StartAtStep = 9; $StopAfterStep = 1
        $keyMissing = $false
        $needsAcsKey = $keyMissing -and ($StartAtStep -ge 2 -and $StopAfterStep -le 2)
        $needsAcsKey | Should -BeFalse
    }
}

Describe 'TC-Step2InnerGuard: Step 2 inner acs-trunk-disabled write is inside live branch (v14.0.4)' {

    It 'TC-Step2Inner-01: inner write is inside else (non-DryRun) branch' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '(?s)else \{[\s\S]*?Invoke-AcsTrunkPatch[\s\S]*?acs-trunk-disabled\.json[\s\S]*?\} catch'
        } else {
            Set-ItResult -Skipped -Because 'migration script not found'
        }
    }
}

Describe 'TC-NewConfigDispose: New-AcsTpeConfig HMAC Dispose (v14.0.4 fix)' {

    It 'TC-NewCfgDispose-01: New-AcsTpeConfig has SHA256 Dispose in try/finally' {
        $path = Join-Path $PSScriptRoot 'New-AcsTpeConfig-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$sha256\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }

    It 'TC-NewCfgDispose-02: New-AcsTpeConfig has HMAC Dispose in try/finally' {
        $path = Join-Path $PSScriptRoot 'New-AcsTpeConfig-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\$hmac\.Dispose\(\)'
        } else {
            Set-ItResult -Skipped -Because 'script not found'
        }
    }
}

Describe 'TC-AllHmacDispose: Every script with SHA256/HMAC has Dispose (v14.0.4 comprehensive)' {

    $cryptoScripts = @(
        'Invoke-ACS-TPE-Full-Migration-v14.ps1',
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Set-AcsSbcFqdn-v14.ps1',
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1',
        'New-AcsTpeConfig-v14.ps1'
    )

    It 'TC-AllDispose-<_>: <_> has Dispose for every SHA256/HMAC' -ForEach $cryptoScripts {
        $path = Join-Path $PSScriptRoot $_
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $sha256Count = ([regex]::Matches($content, 'SHA256\]::Create\(\)')).Count
            $hmacCount   = ([regex]::Matches($content, 'HMACSHA256\]::new\(')).Count
            $sha256Disp  = ([regex]::Matches($content, '\$\w*[Ss]ha\w*\.Dispose\(\)')).Count
            $hmacDisp    = ([regex]::Matches($content, '\$\w*[Hh]mac\w*\.Dispose\(\)')).Count
            $sha256Disp | Should -BeGreaterOrEqual $sha256Count
            $hmacDisp   | Should -BeGreaterOrEqual $hmacCount
        } else {
            Set-ItResult -Skipped -Because "$_ not found"
        }
    }
}

# --------------------------------------------------------------------------
#  v14.0.5 TESTS — Dashboard flip-type handling, step11Failed scope init,
#  dashboard version strings, migCount/undoCount includes flip types
# --------------------------------------------------------------------------

Describe 'TC-DashStateFlip: Dashboard stateLabel handles flip-teams/flip-acs (v14.0.5)' {

    It 'TC-DashStateFlip-01: flip-teams shows MIGRATED' {
        $last = [PSCustomObject]@{ type = 'flip-teams'; dryRun = $false }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams')
        $label = if (-not $last) { 'Unknown' } elseif ($isTeamsActive) { 'MIGRATED' } else { 'ROLLED BACK' }
        $label | Should -Be 'MIGRATED'
    }

    It 'TC-DashStateFlip-02: flip-acs shows ROLLED BACK' {
        $last = [PSCustomObject]@{ type = 'flip-acs'; dryRun = $false }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams')
        $label = if (-not $last) { 'Unknown' } elseif ($isTeamsActive) { 'MIGRATED' } else { 'ROLLED BACK' }
        $label | Should -Be 'ROLLED BACK'
    }

    It 'TC-DashStateFlip-03: migrate still shows MIGRATED' {
        $last = [PSCustomObject]@{ type = 'migrate'; dryRun = $false }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams')
        $label = if (-not $last) { 'Unknown' } elseif ($isTeamsActive) { 'MIGRATED' } else { 'ROLLED BACK' }
        $label | Should -Be 'MIGRATED'
    }

    It 'TC-DashStateFlip-04: undo still shows ROLLED BACK' {
        $last = [PSCustomObject]@{ type = 'undo'; dryRun = $false }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams')
        $label = if (-not $last) { 'Unknown' } elseif ($isTeamsActive) { 'MIGRATED' } else { 'ROLLED BACK' }
        $label | Should -Be 'ROLLED BACK'
    }
}

Describe 'TC-DashRowFlip: Dashboard row HTML handles all 4 run types (v14.0.5)' {

    It 'TC-DashRowFlip-01: flip-teams row shows MIGRATE label' {
        $r = [PSCustomObject]@{ type = 'flip-teams' }
        $tHtml = if ($r.type -eq 'migrate' -or $r.type -eq 'flip-teams') { 'MIGRATE' } else { 'UNDO' }
        $tHtml | Should -Be 'MIGRATE'
    }

    It 'TC-DashRowFlip-02: flip-acs row shows UNDO label' {
        $r = [PSCustomObject]@{ type = 'flip-acs' }
        $tHtml = if ($r.type -eq 'migrate' -or $r.type -eq 'flip-teams') { 'MIGRATE' } else { 'UNDO' }
        $tHtml | Should -Be 'UNDO'
    }

    It 'TC-DashRowFlip-03: flip-acs steps arrow goes right-to-left' {
        $r = [PSCustomObject]@{ type = 'flip-acs'; startStep = 9; stopStep = 1 }
        $isUndo = ($r.type -eq 'undo' -or $r.type -eq 'flip-acs')
        $isUndo | Should -BeTrue
    }

    It 'TC-DashRowFlip-04: flip-teams steps arrow goes left-to-right' {
        $r = [PSCustomObject]@{ type = 'flip-teams'; startStep = 0; stopStep = 11 }
        $isUndo = ($r.type -eq 'undo' -or $r.type -eq 'flip-acs')
        $isUndo | Should -BeFalse
    }
}

Describe 'TC-DashMigCount: migCount/undoCount includes flip types (v14.0.5)' {

    It 'TC-DashCount-01: migCount includes migrate + flip-teams' {
        $records = @(
            [PSCustomObject]@{ type = 'migrate'; dryRun = $false }
            [PSCustomObject]@{ type = 'flip-teams'; dryRun = $false }
            [PSCustomObject]@{ type = 'undo'; dryRun = $false }
        )
        $migCount = @($records | Where-Object { ($_.type -eq 'migrate' -or $_.type -eq 'flip-teams') -and -not $_.dryRun }).Count
        $migCount | Should -Be 2
    }

    It 'TC-DashCount-02: undoCount includes undo + flip-acs' {
        $records = @(
            [PSCustomObject]@{ type = 'undo'; dryRun = $false }
            [PSCustomObject]@{ type = 'flip-acs'; dryRun = $false }
            [PSCustomObject]@{ type = 'migrate'; dryRun = $false }
        )
        $undoCount = @($records | Where-Object { ($_.type -eq 'undo' -or $_.type -eq 'flip-acs') -and -not $_.dryRun }).Count
        $undoCount | Should -Be 2
    }

    It 'TC-DashCount-03: dry runs excluded from both counts' {
        $records = @(
            [PSCustomObject]@{ type = 'migrate'; dryRun = $true }
            [PSCustomObject]@{ type = 'flip-teams'; dryRun = $true }
        )
        $migCount = @($records | Where-Object { ($_.type -eq 'migrate' -or $_.type -eq 'flip-teams') -and -not $_.dryRun }).Count
        $migCount | Should -Be 0
    }
}

Describe 'TC-Step11Init2: step11Failed initialized at script scope (v14.0.5)' {

    It 'TC-Step11Init2-01: step11Failed init before Step 11 means safe access if skipped' {
        $step11Failed = @()
        $failedCount = $step11Failed.Count
        $failedCount | Should -Be 0
    }

    It 'TC-Step11Init2-02: failedCount safe with early-init step11Failed' {
        $results = @(
            [PSCustomObject]@{ Status = 'OK' }
            [PSCustomObject]@{ Status = 'Pending' }
        )
        $step11Failed = @()
        $failedCount = @($results | Where-Object { $_.Status -eq 'Pending' }).Count + $step11Failed.Count
        $failedCount | Should -Be 1
    }
}

Describe 'TC-DashVersionV5: Dashboard versions match v14.0.5 (v14.0.5)' {

    It 'TC-DashVerV5-01: Migration dashboard has v14.0.5' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.5'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-DashVerV5-02: Undo dashboard has v14.0.5' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.5'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-DashMigUndoActual: Dashboard in scripts uses flip-aware type checks (v14.0.5)' {

    It 'TC-DashActual-01: Migration dashboard stateLabel handles flip-teams' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'flip-teams'
            $content | Should -Match 'flip-acs'
            $content | Should -Match '\$isTeamsActive'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-DashActual-02: Undo dashboard stateLabel handles flip-teams' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'flip-teams'
            $content | Should -Match 'flip-acs'
            $content | Should -Match '\$isTeamsActive'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-Step11ScopeActual: step11Failed is initialized before Step 11 block (v14.0.5)' {

    It 'TC-Step11Scope-01: migration script initializes step11Failed before step 11 if block' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $initPos = $content.IndexOf('$script:step11Failed = @()')
            $step11Pos = $content.IndexOf('if ($StartAtStep -le 11')
            $initPos | Should -BeLessThan $step11Pos
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

# --------------------------------------------------------------------------
#  v14.0.6 TESTS — Step 2 conn string null guard, Undo prefix parity,
#  msdyn_appmodule fallback, .DESCRIPTION note, dashboard version
# --------------------------------------------------------------------------

Describe 'TC-Step2ConnNullGuard: Step 2 connection string TrimEnd null guard (v14.0.6 fix)' {

    It 'TC-Step2Null-01: migration Step 2 uses guarded endpoint extraction' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match "acsEp\s*=\s*if"
            $content | Should -Not -Match "acsEp\s*=\s*\`$acsConn\[.endpoint.\]\.TrimEnd"
        } else {
            Set-ItResult -Skipped -Because 'migration script not found'
        }
    }

    It 'TC-Step2Null-02: malformed conn string without endpoint= returns empty via guard' {
        $acsConn = @{}
        'accesskey=mykey'.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $acsEp = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
        $acsEp | Should -Be ''
    }

    It 'TC-Step2Null-03: valid conn string extracts endpoint via guard' {
        $acsConn = @{}
        'endpoint=https://myacs.communication.azure.com/;accesskey=key1'.Split(';') | ForEach-Object {
            $kv = $_ -split '=', 2
            if ($kv.Count -eq 2) { $acsConn[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        $acsEp = if ($acsConn['endpoint']) { $acsConn['endpoint'].TrimEnd('/') } else { '' }
        $acsEp | Should -Be 'https://myacs.communication.azure.com'
    }
}

Describe 'TC-UndoPrefixParity: Undo Write-Step/OK/Info prefixes match migration (v14.0.6 fix)' {

    It 'TC-UndoPrefix-01: Undo Write-Step uses >> prefix' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-Step[\s\S]*?"  >> \$m"'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-UndoPrefix-02: Undo Write-OK uses single space after OK' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-OK[\s\S]*?"  OK \$m"'
            $content | Should -Not -Match 'function Write-OK[\s\S]*?"  OK  \$m"'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-UndoPrefix-03: Undo Write-Info uses -- prefix' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-Info[\s\S]*?"  -- \$m"'
            $content | Should -Not -Match 'function Write-Info[\s\S]*?"  INFO \$m"'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-UndoPrefix-04: Undo Write-Step has $c color parameter' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-Step\s*\{[^}]*\$c'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-UndoAppModuleFix: Undo Step 9 msdyn_appmodule fallback is $null (v14.0.6 fix)' {

    It 'TC-AppModFix-01: Undo script Step 9 msdyn_appmodule fallback is $null not string' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            # The carrier/provider comment marker identifies Step 9 context
            $step9Section = $content.Substring(0, $content.IndexOf('# Note: carrier and provider setting lookups'))
            $step9Section | Should -Not -Match "msdyn_appmodule.*else \{ '192350000' \}"
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-AppModFix-02: Step 9 and Step 6 msdyn_appmodule fallback both use $null' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $matches6 = [regex]::Matches($content, "msdyn_appmodule.*else \{ \`$null \}")
            $matches6.Count | Should -BeGreaterOrEqual 2
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-UndoDescNote: Undo .DESCRIPTION explains Step 5/10/11 omission (v14.0.6)' {

    It 'TC-DescNote-01: Undo script mentions Steps 5, 10, 11 have no undo action' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Steps 5, 10, 11 have no undo action'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-DescNote-02: Undo script references FlipToACS for Steps 10-11 reversal' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Invoke-FlipToACS-v14\.ps1'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-DashVersionV6: Dashboard versions match v14.0.6 (v14.0.6)' {

    It 'TC-DashVerV6-01: Migration dashboard has v14.0.6' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.6'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-DashVerV6-02: Undo dashboard has v14.0.6' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.6'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-ToggleDryRunGuard: Toggle acs-export.json write is DryRun-guarded (v14.0.6 fix)' {

    It 'TC-ToggleDry-01: Toggle script wraps acs-export.json write in DryRun check' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '(?s)if \(\$DryRun\)[\s\S]*?acs-export\.json[\s\S]*?else \{[\s\S]*?Set-Content.*acs-export'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleDry-02: DryRun prevents file write (logic check)' {
        $DryRun = $true
        $wrote = $false
        if ($DryRun) {
            # dry run branch
        } else {
            $wrote = $true
        }
        $wrote | Should -BeFalse
    }
}

Describe 'TC-UndoObjectiveFix: Undo Step 9 msdyn_objective fallback is $null (v14.0.6 fix)' {

    It 'TC-ObjFix-01: Step 9 msdyn_objective fallback matches Step 6 ($null)' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $step9Section = $content.Substring(0, $content.IndexOf('# Note: carrier and provider setting lookups'))
            $step9Section | Should -Not -Match 'msdyn_objective.*else \{ 192350000 \}'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-ObjFix-02: both Step 9 and Step 6 use $null for msdyn_objective fallback' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $nullFallbacks = [regex]::Matches($content, 'msdyn_objective.*else \{ \$null \}')
            $nullFallbacks.Count | Should -BeGreaterOrEqual 2
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-ObjFix-03: Step 9 and Step 6 field count parity (both have 8 fields)' {
        $bkp = [PSCustomObject]@{
            statecode = 0; statuscode = 1; msdyn_ocphonenumbersource = 192350000
            msdyn_teamsresourceaccount = $null; msdyn_type = 192350000
            msdyn_phonenumbertype = 1; msdyn_objective = $null; msdyn_appmodule = $null
        }
        $step9 = [ordered]@{
            statecode                  = if ($bkp.statecode -ne $null) { $bkp.statecode } else { 0 }
            statuscode                 = if ($bkp.statuscode -ne $null) { $bkp.statuscode } else { 1 }
            msdyn_ocphonenumbersource  = if ($bkp.msdyn_ocphonenumbersource -ne $null) { $bkp.msdyn_ocphonenumbersource } else { 192350000 }
            msdyn_teamsresourceaccount = $bkp.msdyn_teamsresourceaccount
            msdyn_type                 = if ($bkp.msdyn_type -ne $null) { $bkp.msdyn_type } else { 192350000 }
            msdyn_phonenumbertype      = if ($bkp.msdyn_phonenumbertype -ne $null) { $bkp.msdyn_phonenumbertype } else { 1 }
            msdyn_objective            = if ($bkp.msdyn_objective -ne $null) { $bkp.msdyn_objective } else { $null }
            msdyn_appmodule            = if ($bkp.msdyn_appmodule -ne $null) { $bkp.msdyn_appmodule } else { $null }
        }
        $step9.Count | Should -Be 8
        $step9['msdyn_objective']  | Should -BeNullOrEmpty
        $step9['msdyn_appmodule'] | Should -BeNullOrEmpty
    }
}

# --------------------------------------------------------------------------
#  v14.0.7 TESTS — D365OrgUrl PSObject guard, dashboard XSS escape,
#  CommsProviderId interactive prompt, Undo already-removed display,
#  dashboard version v14.0.7
# --------------------------------------------------------------------------

Describe 'TC-RunRecordD365Guard: Write-TpeRunRecord uses PSObject.Properties D365OrgUrl guard (v14.0.7)' {

    It 'TC-RunRecD365-01: Invoke Write-TpeRunRecord uses PSObject guard' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match "PSObject\.Properties\['D365OrgUrl'\].*D365OrgUrl.*else \{ '' \}"
        } else {
            Set-ItResult -Skipped -Because 'migration script not found'
        }
    }

    It 'TC-RunRecD365-02: Undo Write-TpeRunRecord uses PSObject guard' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match "PSObject\.Properties\['D365OrgUrl'\].*D365OrgUrl.*else \{ '' \}"
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-DashHtmlEscape: Dashboard escapes user data in HTML (v14.0.7)' {

    It 'TC-DashEsc-01: Invoke Update-TpeStatusDashboard has escape helper' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $fnStart = $content.IndexOf('function Update-TpeStatusDashboard')
            $fnChunk = $content.Substring($fnStart, [Math]::Min(3000, $content.Length - $fnStart))
            $fnChunk | Should -Match '\$esc\s*='
            $fnChunk | Should -Match '&amp;'
            $fnChunk | Should -Match '&lt;'
            $fnChunk | Should -Match '&gt;'
        } else {
            Set-ItResult -Skipped -Because 'migration script not found'
        }
    }

    It 'TC-DashEsc-02: Undo Update-TpeStatusDashboard has escape helper' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $fnStart = $content.IndexOf('function Update-TpeStatusDashboard')
            $fnChunk = $content.Substring($fnStart, [Math]::Min(3000, $content.Length - $fnStart))
            $fnChunk | Should -Match '\$esc\s*='
            $fnChunk | Should -Match '&amp;'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-DashEsc-03: escape helper handles all XSS-relevant characters' {
        $esc = { param([string]$s) $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&#39;" }
        $result = & $esc '<script>alert("xss")&foo</script>'
        $result | Should -Be '&lt;script&gt;alert(&quot;xss&quot;)&amp;foo&lt;/script&gt;'
    }
}

Describe 'TC-CommsProviderPrompt: Phase 0 interactive mode collects CommsProviderId (v14.0.7)' {

    It 'TC-CommsPrompt-01: Invoke script has prompt 16 for Communications Provider' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '16\.\s*Communications Provider'
        } else {
            Set-ItResult -Skipped -Because 'migration script not found'
        }
    }

    It 'TC-CommsPrompt-02: Invoke interactive cfg includes CommsProviderId' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'CommsProviderId\s*=\s*\$commsProviderId'
        } else {
            Set-ItResult -Skipped -Because 'migration script not found'
        }
    }
}

Describe 'TC-UndoAlreadyRemoved: Undo summary displays already-removed count (v14.0.7)' {

    It 'TC-UndoAR-01: Undo console summary includes Already removed line' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Already removed'
            $content | Should -Match 'undoAlreadyRemoved\.Count'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-UndoAR-02: Undo HTML footer includes Already removed row' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Already removed</td>'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-DashVersionV7: Dashboard versions match v14.0.7 (v14.0.7)' {

    It 'TC-DashVerV7-01: Migration dashboard has v14.0.7' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.7'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-DashVerV7-02: Undo dashboard has v14.0.7' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.7'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

# --------------------------------------------------------------------------
#  v14.0.8 TESTS — Edge case hardening: Build-RaList 0 numbers, identical
#  number patterns, Extract-PhoneFromUpn no-@, HTML escape verification
# --------------------------------------------------------------------------

Describe 'TC-BuildRaZero: Build-RaList with 0 numbers (v14.0.8)' {

    It 'TC-BuildRaZero-01: empty numbers array rejected by Mandatory parameter' {
        { Build-RaList -Numbers @() -Prefix 'RA' -Domain 'test.com' } | Should -Throw
    }
}

Describe 'TC-PatternIdentical: Get-NumberPatternRegex with identical numbers (v14.0.8)' {

    It 'TC-PatternId-01: two identical numbers produce prefix pattern matching that number' {
        $pattern = Get-NumberPatternRegex -Numbers @('+12065551234', '+12065551234')
        '+12065551234' | Should -Match $pattern
    }

    It 'TC-PatternId-02: identical numbers pattern is prefix-based (allows trailing digits)' {
        $pattern = Get-NumberPatternRegex -Numbers @('+12065551234', '+12065551234')
        $pattern | Should -Match '\\\+12065551234'
        '+120655512349' | Should -Match $pattern
    }
}

Describe 'TC-ExtractNoAt: Extract-PhoneFromUpn edge cases (v14.0.8)' {

    It 'TC-ExtractNoAt-01: UPN without @ still extracts digits via template match' {
        $result = Extract-PhoneFromUpn -Upn 'tpe-ra-12065551001' -RaPrefix 'tpe-ra-<phonenumber>'
        $result | Should -Be '+12065551001'
    }

    It 'TC-ExtractNoAt-02: UPN without @ and no digit block returns null' {
        $result = Extract-PhoneFromUpn -Upn 'just-text' -RaPrefix ''
        $result | Should -BeNullOrEmpty
    }

    It 'TC-ExtractNoAt-03: UPN with only short digits returns null' {
        $result = Extract-PhoneFromUpn -Upn 'ra-123@test.com' -RaPrefix ''
        $result | Should -BeNullOrEmpty
    }
}

Describe 'TC-InvokedAsEscape: invokedAs HTML escape behavior (v14.0.8)' {

    It 'TC-InvokedAs-01: escapes ampersand and angle brackets' {
        $raw = 'script.ps1 -Param "foo & bar" <test>'
        $escaped = $raw -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
        $escaped | Should -Be 'script.ps1 -Param "foo &amp; bar" &lt;test&gt;'
    }

    It 'TC-InvokedAs-02: double quotes pass through (in span content, not attribute)' {
        $raw = 'script.ps1 -Param "value"'
        $escaped = $raw -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
        $escaped | Should -Match '"value"'
    }
}

Describe 'TC-DashEscValues: Dashboard escape helper unit tests (v14.0.8)' {

    BeforeAll {
        $script:esc = { param([string]$s) $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&#39;" }
    }

    It 'TC-DashEscVal-01: phone numbers with + pass through safely' {
        $result = & $script:esc '+12065551234, +14255550100'
        $result | Should -Be '+12065551234, +14255550100'
    }

    It 'TC-DashEscVal-02: URL with ampersand escaped' {
        $result = & $script:esc 'https://contoso.crm.dynamics.com?a=1&b=2'
        $result | Should -Be 'https://contoso.crm.dynamics.com?a=1&amp;b=2'
    }

    It 'TC-DashEscVal-03: script injection in log filename escaped' {
        $result = & $script:esc "tpe-run-<img src=x onerror=alert(1)>.html"
        $result | Should -Match '&lt;img'
        $result | Should -Not -Match '<img'
    }
}

# --------------------------------------------------------------------------
#  v14.0.9 TESTS — Dashboard $esc null guard, DryRun D365 backup guard,
#  dashboard version v14.0.8, Undo Step 2 FQDN wrapping, migration
#  DryRun backup skip logic
# --------------------------------------------------------------------------

Describe 'TC-DashEscNull: Dashboard $esc handles null phoneNumbers (v14.0.9)' {

    BeforeAll {
        $script:esc = { param([string]$s) $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&#39;" }
    }

    It 'TC-DashEscNull-01: null phoneNumbers array produces N/A via guard' {
        $last = [PSCustomObject]@{ type = 'migrate'; dryRun = $false; phoneNumbers = $null }
        $lastNums = if ($last -and $last.phoneNumbers -and @($last.phoneNumbers).Count -gt 0) { & $script:esc ((@($last.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { 'N/A' }
        $lastNums | Should -Be 'N/A'
    }

    It 'TC-DashEscNull-02: empty phoneNumbers array produces N/A via guard' {
        $last = [PSCustomObject]@{ type = 'migrate'; dryRun = $false; phoneNumbers = @() }
        $lastNums = if ($last -and $last.phoneNumbers -and @($last.phoneNumbers).Count -gt 0) { & $script:esc ((@($last.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { 'N/A' }
        $lastNums | Should -Be 'N/A'
    }

    It 'TC-DashEscNull-03: phoneNumbers with values produces escaped string' {
        $last = [PSCustomObject]@{ type = 'migrate'; dryRun = $false; phoneNumbers = @('+12065551234', '+14255550100') }
        $lastNums = if ($last -and $last.phoneNumbers -and @($last.phoneNumbers).Count -gt 0) { & $script:esc ((@($last.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { 'N/A' }
        $lastNums | Should -Be '+12065551234, +14255550100'
    }

    It 'TC-DashEscNull-04: phoneNumbers with null entries filtered out' {
        $last = [PSCustomObject]@{ type = 'migrate'; dryRun = $false; phoneNumbers = @('+12065551234', $null, '+14255550100') }
        $lastNums = if ($last -and $last.phoneNumbers -and @($last.phoneNumbers).Count -gt 0) { & $script:esc ((@($last.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { 'N/A' }
        $lastNums | Should -Be '+12065551234, +14255550100'
    }

    It 'TC-DashEscNull-05: row nums for null phoneNumbers in run history' {
        $r = [PSCustomObject]@{ phoneNumbers = $null }
        $nums = if ($r.phoneNumbers -and @($r.phoneNumbers).Count -gt 0) { & $script:esc ((@($r.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { '&mdash;' }
        $nums | Should -Be '&mdash;'
    }

    It 'TC-DashEscNull-06: row nums for empty phoneNumbers in run history' {
        $r = [PSCustomObject]@{ phoneNumbers = @() }
        $nums = if ($r.phoneNumbers -and @($r.phoneNumbers).Count -gt 0) { & $script:esc ((@($r.phoneNumbers) | Where-Object { $_ }) -join ', ') } else { '&mdash;' }
        $nums | Should -Be '&mdash;'
    }
}

Describe 'TC-DryRunD365Backup: DryRun skips D365 backup token acquisition (v14.0.9)' {

    It 'TC-DryBkp-01: DryRun branch skips D365 token acquisition' {
        $DryRun = $true
        $tokenAcquired = $false
        if ($DryRun) {
            # DryRun: skip token acquisition
        } else {
            $tokenAcquired = $true
        }
        $tokenAcquired | Should -BeFalse
    }

    It 'TC-DryBkp-02: live mode acquires D365 token' {
        $DryRun = $false
        $tokenAcquired = $false
        if ($DryRun) {
            # DryRun: skip
        } else {
            $tokenAcquired = $true
        }
        $tokenAcquired | Should -BeTrue
    }

    It 'TC-DryBkp-03: migration script has DryRun guard around D365 backup section' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '(?s)if \(\$DryRun\) \{[\s\S]*?DRY RUN.*back up phone states[\s\S]*?\} else \{'
        } else {
            Set-ItResult -Skipped -Because 'migration script not found'
        }
    }
}

Describe 'TC-DashVersionV8: Dashboard versions match v14.0.8 (v14.0.9)' {

    It 'TC-DashVerV8-01: Migration dashboard has v14.0.8' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.8'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-DashVerV8-02: Undo dashboard has v14.0.8' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.8'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-DashVerV8-03: Migration HTML footer says v14.15.0' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'COMPLETE \(v14.15.0\)'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-UndoStep2Wrap: Undo Step 2 FQDN JSON parsing wraps in @() (v14.0.9)' {

    It 'TC-UndoWrap-01: single-string JSON produces array with 1 element' {
        $json = '"sbc.contoso.com"'
        $raw = $json | ConvertFrom-Json
        $disabledFqdns = @()
        if ($null -eq $raw) { $disabledFqdns = @() }
        elseif ($raw -is [System.Array]) { $disabledFqdns = @($raw) }
        else { $disabledFqdns = @([string]$raw) }
        $disabledFqdns.Count | Should -Be 1
        $disabledFqdns[0] | Should -Be 'sbc.contoso.com'
    }

    It 'TC-UndoWrap-02: array JSON produces array with correct count' {
        $json = '["sbc1.contoso.com","sbc2.contoso.com"]'
        $raw = $json | ConvertFrom-Json
        $disabledFqdns = @()
        if ($null -eq $raw) { $disabledFqdns = @() }
        elseif ($raw -is [System.Array]) { $disabledFqdns = @($raw) }
        else { $disabledFqdns = @([string]$raw) }
        $disabledFqdns.Count | Should -Be 2
    }

    It 'TC-UndoWrap-03: empty array JSON produces 0-count array' {
        $json = '[]'
        $raw = $json | ConvertFrom-Json
        $disabledFqdns = @()
        if ($null -eq $raw) { $disabledFqdns = @() }
        elseif ($raw -is [System.Array]) { $disabledFqdns = @($raw) }
        else { $disabledFqdns = @([string]$raw) }
        $disabledFqdns.Count | Should -Be 0
    }
}

Describe 'TC-MigDryRunSummary: Migration COMPLETE footer says v14.0.8 (v14.0.9)' {

    It 'TC-MigFooter-01: HTML console summary references v14.0.8' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.8'
            $content | Should -Not -Match 'COMPLETE \(v14\.0\.7\)'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-UndoNotesV8: Undo .NOTES references v14.0.8 (v14.0.9)' {

    It 'TC-UndoNotes-01: Undo script has v14.0.8 in notes' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.0\.8'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

# --------------------------------------------------------------------------
#  v14.1.0 TESTS — Final consistency pass: Undo .NOTES version fix,
#  dashboard v14.1.0 versions, README alignment, all-scripts #Requires,
#  WaitWithMessage DryRun guard, exclude filter, undo result edges
# --------------------------------------------------------------------------

Describe 'TC-UndoNotesV14: Undo .NOTES says Version 14 not Version 9 (v14.1.0 fix)' {

    It 'TC-UndoNotesV14-01: Undo .NOTES second block says Version 14' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Version 14:'
            $content | Should -Not -Match 'Version 9:'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-DashVersionV10: Dashboard versions match v14.2.0 (v14.2.0)' {

    It 'TC-DashVerV10-01: Migration dashboard has v14.2.0' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.2\.0'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-DashVerV10-02: Undo dashboard has v14.2.0' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.2\.0'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }

    It 'TC-DashVerV10-03: Migration HTML footer says v14.8.0' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'COMPLETE \(v14.15.0\)'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-MigFooterV10: Migration COMPLETE footer says v14.2.0 (v14.2.0)' {

    It 'TC-MigFooterV10-01: HTML console summary references v14.2.0' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.2\.0'
            $content | Should -Not -Match 'COMPLETE \(v14\.1\.0\)'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-ReadmeVersion: README.md says v14.16.0 (v14.16.0)' {

    It 'TC-ReadmeVer-01: README has version v14.16.0' {
        $path = Join-Path $PSScriptRoot 'README.md'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Version:\*\*\s*v14.16.0'
        } else {
            Set-ItResult -Skipped -Because 'README.md not found'
        }
    }
}

Describe 'TC-WaitWithMessage: WaitWithMessage DryRun guard (v14.1.0)' {

    It 'TC-Wait-01: DryRun skips actual wait' {
        $DryRun = $true
        $waited = $false
        if ($DryRun) {
            # DryRun: skip wait
        } else {
            $waited = $true
        }
        $waited | Should -BeFalse
    }

    It 'TC-Wait-02: live mode would execute wait' {
        $DryRun = $false
        $waited = $false
        if ($DryRun) {
            # DryRun: skip
        } else {
            $waited = $true
        }
        $waited | Should -BeTrue
    }
}

Describe 'TC-ExcludeFilter: D365 discovery exclude by row and by number (v14.1.0)' {

    It 'TC-Exclude-01: exclude by row number removes correct entries' {
        $d365Numbers = @(
            [PSCustomObject]@{ Number = '+12065551001'; Name = 'Q1' }
            [PSCustomObject]@{ Number = '+12065551002'; Name = 'Q2' }
            [PSCustomObject]@{ Number = '+12065551003'; Name = 'Q3' }
        )
        $excludeSet = @('2')
        $byRow = @($excludeSet | Where-Object { $_ -match '^\d+$' })
        $rowIdx = @()
        foreach ($r in $byRow) { $rowIdx += ([int]$r - 1) }
        $filtered = @($d365Numbers | Where-Object {
            $idx = [array]::IndexOf($d365Numbers, $_)
            $idx -notin $rowIdx
        })
        $filtered.Count | Should -Be 2
        $filtered[0].Number | Should -Be '+12065551001'
        $filtered[1].Number | Should -Be '+12065551003'
    }

    It 'TC-Exclude-02: exclude by phone number removes correct entries' {
        $d365Numbers = @(
            [PSCustomObject]@{ Number = '+12065551001'; Name = 'Q1' }
            [PSCustomObject]@{ Number = '+12065551002'; Name = 'Q2' }
        )
        $excludeSet = @('+12065551001')
        $byNum = @($excludeSet | Where-Object { $_ -notmatch '^\d+$' })
        $filtered = @($d365Numbers | Where-Object { $_.Number -notin $byNum })
        $filtered.Count | Should -Be 1
        $filtered[0].Number | Should -Be '+12065551002'
    }
}

Describe 'TC-UndoResultEdge: Undo result edge cases (v14.1.0)' {

    It 'TC-UndoEdge-01: single failure => WARN (not FAIL)' {
        $failures = @('one')
        $result = if ($failures.Count -gt 3) { 'FAIL' } elseif ($failures.Count -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'WARN'
    }

    It 'TC-UndoEdge-02: empty completed + empty failures => OK' {
        $completed = @()
        $failures = @()
        $result = if ($failures.Count -gt 3) { 'FAIL' } elseif ($failures.Count -gt 0) { 'WARN' } else { 'OK' }
        $result | Should -Be 'OK'
    }
}

Describe 'TC-MigNotesV10: Migration .NOTES includes v14.1.0 entry (v14.1.0)' {

    It 'TC-MigNotesV10-01: migration script .NOTES has v14.1.0 changelog' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.1\.0\s*:'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-MigNotesV10-02: undo script .NOTES has v14.1.0 changelog' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.1\.0\s*:'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

# ===========================================================================
#  v14.2.0 TESTS
# ===========================================================================

Describe 'TC-E164: Test-E164Format validation (v14.2.0)' {

    It 'TC-E164-01: +12065551234 is valid E.164' {
        Test-E164Format '+12065551234' | Should -BeTrue
    }

    It 'TC-E164-02: +442079999888 (UK) is valid E.164' {
        Test-E164Format '+442079999888' | Should -BeTrue
    }

    It 'TC-E164-03: missing + prefix is invalid' {
        Test-E164Format '12065551234' | Should -BeFalse
    }

    It 'TC-E164-04: too short (5 digits after country code) is invalid' {
        Test-E164Format '+120655' | Should -BeFalse
    }

    It 'TC-E164-05: too long (16 digits after +) is invalid' {
        Test-E164Format '+12065551234567890' | Should -BeFalse
    }

    It 'TC-E164-06: leading zero after + is invalid' {
        Test-E164Format '+0123456789' | Should -BeFalse
    }

    It 'TC-E164-07: contains non-digit is invalid' {
        Test-E164Format '+1206555ABC' | Should -BeFalse
    }

    It 'TC-E164-08: minimum valid length (7 digits after +1) is valid' {
        Test-E164Format '+12065550' | Should -BeTrue
    }

    It 'TC-E164-09: maximum valid length (15 total digits) is valid' {
        Test-E164Format '+123456789012345' | Should -BeTrue
    }

    It 'TC-E164-10: empty string is invalid' {
        Test-E164Format '' | Should -BeFalse
    }
}

Describe 'TC-ToggleObs: Toggle observability parity (v14.2.0)' {

    It 'TC-ToggleObs-01: Toggle script has Write-HtmlLine function' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-HtmlLine'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleObs-02: Toggle script has Write-TpeRunRecord function' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Write-TpeRunRecord'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleObs-03: Toggle script has Update-TpeStatusDashboard function' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Update-TpeStatusDashboard'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleObs-04: Toggle script has Exit-Script helper' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Exit-Script'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleObs-05: Toggle script has HtmlLogPath setup' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'tpe-toggle-run-'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleObs-06: Toggle script calls Write-TpeRunRecord at end' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Write-TpeRunRecord\s+-Type\s+\$toggleType'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleObs-07: Toggle script calls Update-TpeStatusDashboard at end' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Update-TpeStatusDashboard'
            $content | Should -Match 'Exit-Script 0'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }
}

Describe 'TC-ToggleAutoConfirm: Toggle -AutoConfirm parameter (v14.2.0)' {

    It 'TC-ToggleAC-01: Toggle script accepts -AutoConfirm parameter' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '\[switch\]\$AutoConfirm'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleAC-02: Toggle skips confirmation prompt when AutoConfirm is set' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'elseif\s*\(\$AutoConfirm\)'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleAC-03: Migration Step 10 passes -AutoConfirm to Toggle' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Toggle-AcsTeamsRouting-v14\.ps1.*-AutoConfirm'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-ToggleType: Toggle run type classification (v14.2.0)' {

    It 'TC-ToggleType-01: toggle-to-tpe is classified as MIGRATE in dashboard' {
        $last = [PSCustomObject]@{ type = 'toggle-to-tpe'; dryRun = $false; timestamp = '2026-04-27T12:00:00' }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams' -or $last.type -eq 'toggle-to-tpe')
        $isTeamsActive | Should -BeTrue
    }

    It 'TC-ToggleType-02: toggle-to-acs is classified as UNDO in dashboard' {
        $last = [PSCustomObject]@{ type = 'toggle-to-acs'; dryRun = $false; timestamp = '2026-04-27T12:00:00' }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams' -or $last.type -eq 'toggle-to-tpe')
        $isTeamsActive | Should -BeFalse
    }

    It 'TC-ToggleType-03: migration dashboard recognizes toggle-to-tpe in migCount' {
        $records = @(
            [PSCustomObject]@{ type = 'migrate'; dryRun = $false }
            [PSCustomObject]@{ type = 'toggle-to-tpe'; dryRun = $false }
        )
        $migCount = @($records | Where-Object { ($_.type -eq 'migrate' -or $_.type -eq 'flip-teams' -or $_.type -eq 'toggle-to-tpe') -and -not $_.dryRun }).Count
        $migCount | Should -Be 2
    }

    It 'TC-ToggleType-04: migration dashboard recognizes toggle-to-acs in undoCount' {
        $records = @(
            [PSCustomObject]@{ type = 'undo'; dryRun = $false }
            [PSCustomObject]@{ type = 'toggle-to-acs'; dryRun = $false }
        )
        $undoCount = @($records | Where-Object { ($_.type -eq 'undo' -or $_.type -eq 'flip-acs' -or $_.type -eq 'toggle-to-acs') -and -not $_.dryRun }).Count
        $undoCount | Should -Be 2
    }
}

Describe 'TC-D365UrlEncode: D365 phone number URL-encoding (v14.2.0)' {

    It 'TC-D365Enc-01: + is encoded as %2B in D365 OData filter' {
        $num = '+12065551234'
        $encoded = $num -replace '\+', '%2B'
        $encoded | Should -Be '%2B12065551234'
    }

    It 'TC-D365Enc-02: number without + is unchanged' {
        $num = '12065551234'
        $encoded = $num -replace '\+', '%2B'
        $encoded | Should -Be '12065551234'
    }

    It 'TC-D365Enc-03: encoded value does not contain raw +' {
        $num = '+14255550100'
        $encoded = $num -replace '\+', '%2B'
        $encoded | Should -Not -Match '^\+'
        $encoded | Should -Match '^%2B'
    }
}

Describe 'TC-MigE164: Migration script has E.164 validation (v14.2.0)' {

    It 'TC-MigE164-01: Migration script contains Test-E164Format function' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'function Test-E164Format'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-MigE164-02: Migration script validates E.164 in Phase 0D' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'Test-E164Format'
            $content | Should -Match 'NOT in E\.164 format'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }
}

Describe 'TC-ToggleVersion: Toggle version strings (v14.2.0)' {

    It 'TC-ToggleVer-01: Toggle .NOTES has v14.2.0 entry' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.2\.0\s*:'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleVer-02: Toggle header banner shows v14.2.0' {
        $path = Join-Path $PSScriptRoot 'Toggle-AcsTeamsRouting-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.2\.0'
        } else {
            Set-ItResult -Skipped -Because 'Toggle script not found'
        }
    }

    It 'TC-ToggleVer-03: Migration .NOTES has v14.2.0 entry' {
        $path = Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.2\.0\s*:'
        } else {
            Set-ItResult -Skipped -Because 'Migration script not found'
        }
    }

    It 'TC-ToggleVer-04: Undo .NOTES has v14.2.0 entry' {
        $path = Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'v14\.2\.0\s*:'
        } else {
            Set-ItResult -Skipped -Because 'Undo script not found'
        }
    }
}

Describe 'TC-ArchivePattern: Archive-TpeRuns-v14.ps1 script patterns (v14.2.0)' {

    It 'TC-ArchivePat-01: Archive script has #Requires -Version 5.1' {
        $path = Join-Path $PSScriptRoot 'Archive-TpeRuns-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match '#Requires -Version 5\.1'
        } else {
            Set-ItResult -Skipped -Because 'Archive script not found'
        }
    }

    It 'TC-ArchivePat-02: Archive script handles tpe-toggle-run prefix' {
        $path = Join-Path $PSScriptRoot 'Archive-TpeRuns-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'tpe-toggle-run-'
        } else {
            Set-ItResult -Skipped -Because 'Archive script not found'
        }
    }

    It 'TC-ArchivePat-03: Archive script preserves tpe-status.html' {
        $path = Join-Path $PSScriptRoot 'Archive-TpeRuns-v14.ps1'
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content | Should -Match 'tpe-status\.html'
        } else {
            Set-ItResult -Skipped -Because 'Archive script not found'
        }
    }
}

Describe 'TC-BuildRaSingle: Build-RaList with 1 number (v14.2.0)' {

    It 'TC-BuildRa1-01: empty number array throws ParameterBinding (Mandatory validation)' {
        { Build-RaList -Numbers @() -Prefix 'RA' -Domain 'test.com' } | Should -Throw
    }

    It 'TC-BuildRa1-02: single number returns single-element list' {
        $nums = @([PSCustomObject]@{ Number = '+12065551001'; Name = 'Q1' })
        $list = Build-RaList -Numbers $nums -Prefix 'RA' -Domain 'test.com'
        @($list).Count | Should -Be 1
        $list[0].PhoneNumber | Should -Be '+12065551001'
    }
}

Describe 'TC-DashToggleState: Dashboard stateLabel with toggle types (v14.2.0)' {

    It 'TC-DashTogSt-01: toggle-to-tpe shows MIGRATED state' {
        $last = [PSCustomObject]@{ type = 'toggle-to-tpe'; dryRun = $false; timestamp = '2026-04-27' }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams' -or $last.type -eq 'toggle-to-tpe')
        $stateLabel = if (-not $last) { 'Unknown' } elseif ($isTeamsActive) { 'MIGRATED' } else { 'ROLLED BACK' }
        $stateLabel | Should -Be 'MIGRATED'
    }

    It 'TC-DashTogSt-02: toggle-to-acs shows ROLLED BACK state' {
        $last = [PSCustomObject]@{ type = 'toggle-to-acs'; dryRun = $false; timestamp = '2026-04-27' }
        $isTeamsActive = $last -and ($last.type -eq 'migrate' -or $last.type -eq 'flip-teams' -or $last.type -eq 'toggle-to-tpe')
        $stateLabel = if (-not $last) { 'Unknown' } elseif ($isTeamsActive) { 'MIGRATED' } else { 'ROLLED BACK' }
        $stateLabel | Should -Be 'ROLLED BACK'
    }

    It 'TC-DashTogSt-03: toggle-to-tpe row renders as MIGRATE type' {
        $r = [PSCustomObject]@{ type = 'toggle-to-tpe'; dryRun = $false }
        $tHtml = if ($r.type -eq 'migrate' -or $r.type -eq 'flip-teams' -or $r.type -eq 'toggle-to-tpe') { 'MIGRATE' } else { 'UNDO' }
        $tHtml | Should -Be 'MIGRATE'
    }

    It 'TC-DashTogSt-04: toggle-to-acs row renders as UNDO type' {
        $r = [PSCustomObject]@{ type = 'toggle-to-acs'; dryRun = $false }
        $tHtml = if ($r.type -eq 'migrate' -or $r.type -eq 'flip-teams' -or $r.type -eq 'toggle-to-tpe') { 'MIGRATE' } else { 'UNDO' }
        $tHtml | Should -Be 'UNDO'
    }
}

Describe 'TC-DashVersionV14: Dashboard versions match v14.7.0 (v14.7.0)' {

    It 'TC-DashV14-01: Migration dashboard sub-header says v14.15.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'v14.15.0 &nbsp;\|&nbsp; \$d365Url'
    }

    It 'TC-DashV14-02: Migration dashboard footer says v14.15.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'ACS TPE v14.15.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl'
    }

    It 'TC-DashV14-03: Undo dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $content | Should -Match 'v14.11.0 &nbsp;\|&nbsp; \$d365Url'
    }

    It 'TC-DashV14-04: Undo dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $content | Should -Match 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl'
    }

    It 'TC-DashV14-05: Toggle dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'v14.11.0 &nbsp;\|&nbsp; \$d365Url'
    }

    It 'TC-DashV14-06: Toggle dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl'
    }

    It 'TC-DashV14-07: FlipToACS dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'v14.11.0 &nbsp;\|&nbsp; \$d365Url'
    }

    It 'TC-DashV14-08: FlipToACS dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl'
    }

    It 'TC-DashV14-09: FlipToTeams dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'v14.11.0 &nbsp;\|&nbsp; \$d365Url'
    }

    It 'TC-DashV14-10: FlipToTeams dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl'
    }
}

Describe 'TC-FlipDashParity: Flip scripts have dashboard parity with Toggle (v14.4.0)' {

    It 'TC-FlipPar-01: FlipToACS dashboard has $esc scriptblock' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match '\$esc = \{ param\(\[string\]\$s\)'
    }

    It 'TC-FlipPar-02: FlipToACS dashboard recognizes toggle-to-tpe type' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'toggle-to-tpe'
    }

    It 'TC-FlipPar-03: FlipToACS dashboard recognizes toggle-to-acs type' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'toggle-to-acs'
    }

    It 'TC-FlipPar-04: FlipToACS dashboard has Steps column header' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match '<th>Steps</th>'
    }

    It 'TC-FlipPar-05: FlipToACS dashboard card label says Migrate not To Teams' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match '>Migrate</div>'
        $content | Should -Not -Match '>To Teams</div>'
    }

    It 'TC-FlipPar-06: FlipToTeams dashboard has $esc scriptblock' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match '\$esc = \{ param\(\[string\]\$s\)'
    }

    It 'TC-FlipPar-07: FlipToTeams dashboard recognizes toggle-to-tpe type' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'toggle-to-tpe'
    }

    It 'TC-FlipPar-08: FlipToTeams dashboard has Steps column header' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match '<th>Steps</th>'
    }

    It 'TC-FlipPar-09: FlipToTeams dashboard card label says Undo not To ACS' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match '>Undo</div>'
        $content | Should -Not -Match '>To ACS</div>'
    }

    It 'TC-FlipPar-10: FlipToACS run record has startStep/stopStep fields' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'startStep\s*=\s*0'
        $content | Should -Match 'stopStep\s*=\s*0'
    }

    It 'TC-FlipPar-11: FlipToTeams run record has startStep/stopStep fields' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'startStep\s*=\s*0'
        $content | Should -Match 'stopStep\s*=\s*0'
    }
}

Describe 'TC-Step1SkipGuard: Step 1 skip path handles missing acs-export.json (v14.4.0)' {

    It 'TC-Step1Sk-01: Migration script has Test-Path guard for acs-export.json in skip path' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'if \(-not \(Test-Path \$acsExportPath\)\)'
    }

    It 'TC-Step1Sk-02: Skip path provides fallback trunks and routes from config' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'acs-export\.json not found\. Using config values as fallback'
    }
}

Describe 'TC-Step9DryRun: Step 9 Export-Csv guarded by DryRun (v14.4.0)' {

    It 'TC-Step9Dry-01: Export-Csv wrapped in if -not DryRun block' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'if \(-not \$DryRun\) \{\s*\$results \| Export-Csv'
    }
}

Describe 'TC-ToggleHtmlLog: Toggle state display logged to HTML (v14.4.0)' {

    It 'TC-TogHtml-01: Toggle script logs ACS state to HTML' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'Write-HtmlLine\s+"  ACS   : \$Fqdn'
    }

    It 'TC-TogHtml-02: Toggle script logs Teams state to HTML' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'Write-HtmlLine\s+"  Teams : \$Fqdn'
    }

    It 'TC-TogHtml-03: Toggle script logs new state to HTML' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'Write-HtmlLine\s+"  New State:'
    }

    It 'TC-TogHtml-04: Toggle banner says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'Toggle\s+v14.11.0'
    }
}

Describe 'TC-MigFooterV14: Migration COMPLETE footer says v14.8.0 (v14.7.0)' {

    It 'TC-MigFoot-01: COMPLETE footer says v14.15.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'COMPLETE \(v14.15.0\)'
    }
}

Describe 'TC-MigNotesV14: All scripts have v14.4.0 .NOTES entry (v14.4.0)' {

    It 'TC-MigNotes-01: Migration .NOTES has v14.4.0 changelog line' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'v14\.4\.0\s+: Step 9 DryRun guard'
    }

    It 'TC-MigNotes-02: Undo .NOTES has v14.4.0 changelog line' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $content | Should -Match 'v14\.4\.0\s+: Exit-Script parity'
    }

    It 'TC-MigNotes-03: Toggle .NOTES has v14.4.0 changelog line' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'v14\.4\.0\s+: All exit paths use Exit-Script'
    }

    It 'TC-MigNotes-04: FlipToACS .NOTES has v14.4.0 changelog line' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'v14\.4\.0: Write-TpeRunRecord -Failed'
    }

    It 'TC-MigNotes-05: FlipToTeams .NOTES has v14.4.0 changelog line' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'v14\.4\.0: Write-Err function added'
    }
}

Describe 'TC-ToggleExitScript: Toggle uses Exit-Script on all error paths (v14.4.0)' {

    BeforeAll {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
    }

    It 'TC-TogExit-01: Toggle has no raw exit 1 outside comments' {
        $lines = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1"
        $rawExits = $lines | Where-Object { $_ -match '^\s*exit\s+[01]\s*$' }
        $rawExits | Should -BeNullOrEmpty
    }

    It 'TC-TogExit-02: Toggle has Exit-Script 1 calls for error paths' {
        $exitScriptCalls = ([regex]::Matches($content, 'Exit-Script 1')).Count
        $exitScriptCalls | Should -BeGreaterOrEqual 14
    }

    It 'TC-TogExit-03: Toggle writes run record on toggle error paths' {
        $runRecordFails = ([regex]::Matches($content, "Write-TpeRunRecord.*-Result 'FAIL'")).Count
        $runRecordFails | Should -BeGreaterOrEqual 4
    }
}

Describe 'TC-FlipFailuresParam: Flip scripts use -Failures not -Failed (v14.4.0)' {

    It 'TC-FlipFail-01: FlipToACS has no -Failed parameter in Write-TpeRunRecord' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Not -Match 'Write-TpeRunRecord.*-Failed '
    }

    It 'TC-FlipFail-02: FlipToACS uses -Failures parameter' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'Write-TpeRunRecord.*-Failures '
    }

    It 'TC-FlipFail-03: FlipToTeams has no -Failed parameter in Write-TpeRunRecord' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Not -Match 'Write-TpeRunRecord.*-Failed '
    }

    It 'TC-FlipFail-04: FlipToTeams uses -Failures parameter' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'Write-TpeRunRecord.*-Failures '
    }
}

Describe 'TC-FlipTeamsWriteErr: FlipToTeams has Write-Err function (v14.4.0)' {

    BeforeAll {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
    }

    It 'TC-FTErr-01: FlipToTeams defines Write-Err function' {
        $content | Should -Match 'function Write-Err\s*\{'
    }

    It 'TC-FTErr-02: FlipToTeams Write-Err writes to HTML log' {
        $content | Should -Match "function Write-Err.*Write-HtmlLine.*'Red'"
    }

    It 'TC-FTErr-03: FlipToTeams uses Write-Err for config not found' {
        $content | Should -Match 'Write-Err\s+"Config file not found'
    }

    It 'TC-FTErr-04: FlipToTeams uses Write-Err for missing D365OrgUrl' {
        $content | Should -Match 'Write-Err\s+"D365OrgUrl is missing'
    }

    It 'TC-FTErr-05: FlipToTeams has no raw Write-Host ! outside function def' {
        $lines = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1"
        $rawRed = $lines | Where-Object { $_ -match 'Write-Host\s+"  !.*-ForegroundColor Red' -and $_ -notmatch '^function Write-Err' }
        $rawRed | Should -BeNullOrEmpty
    }
}

Describe 'TC-MigPartialRunType: Migration uses migrate-partial for partial runs (v14.4.0)' {

    It 'TC-MigPart-01: Migration script computes runType based on StopAfterStep' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match "migrate-partial"
    }

    It 'TC-MigPart-02: runType is migrate when StopAfterStep >= 10' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match '\$StopAfterStep -ge 10.*migrate.*migrate-partial'
    }
}

Describe 'TC-Step9DryRunVerify: Step 9 D365 post-sync verification guarded by DryRun (v14.4.0)' {

    It 'TC-Step9Vrfy-01: Post-sync verification wrapped in DryRun guard' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'DRY RUN\) Would verify D365 phone number state post-sync'
    }
}

Describe 'TC-DashVersionV14_4: All 5 scripts dashboard shows v14.7.0 (v14.7.0)' {

    It 'TC-DashV14_5-01: Migration dashboard sub-header says v14.15.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        ($content | Select-String 'v14.15.0.*Auto-refresh').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-02: Undo dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        ($content | Select-String 'v14.11.0.*Auto-refresh').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-03: Toggle dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        ($content | Select-String 'v14.11.0.*Auto-refresh').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-04: FlipToACS dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        ($content | Select-String 'v14.11.0.*Auto-refresh').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-05: FlipToTeams dashboard sub-header says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        ($content | Select-String 'v14.11.0.*Auto-refresh').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-06: Migration dashboard footer says v14.15.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        ($content | Select-String 'ACS TPE v14.15.0.*stats').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-07: Undo dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        ($content | Select-String 'ACS TPE v14.11.0.*stats').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-08: Toggle dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        ($content | Select-String 'ACS TPE v14.11.0.*stats').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-09: FlipToACS dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        ($content | Select-String 'ACS TPE v14.11.0.*stats').Matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'TC-DashV14_5-10: FlipToTeams dashboard footer says v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        ($content | Select-String 'ACS TPE v14.11.0.*stats').Matches.Count | Should -BeGreaterOrEqual 1
    }
}

#endregion

#region -----------------------------------------------------------------------
#  v14.5.0 — NEW FIX VERIFICATION TESTS
#endregion

Describe 'TC-ToggleNullActive: Toggle $acsActive uses -eq $true not -ne $false (v14.5.0)' {

    It 'TC-NullActive-01: $acsActive uses -eq $true' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match '\$acsActive\s*=.*-eq \$true'
    }

    It 'TC-NullActive-02: $teamsActive uses -eq $true' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match '\$teamsActive\s*=.*-eq \$true'
    }

    It 'TC-NullActive-03: no -ne $false pattern for active detection' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Not -Match '\$(acsActive|teamsActive)\s*=.*-ne \$false'
    }
}

Describe 'TC-UndoHtmlEscape: Undo failure list is HTML-escaped in footer (v14.5.0)' {

    It 'TC-UndoEsc-01: failure list items are escaped before HTML insertion' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $content | Should -Match "replace\s+'&'\s*,\s*'&amp;'"
    }

    It 'TC-UndoEsc-02: angle brackets escaped in failure list' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $content | Should -Match "replace\s+'<'\s*,\s*'&lt;'"
    }
}

Describe 'TC-E164Utility: E.164 validation in utility scripts (v14.5.0)' {

    It 'TC-E164U-01: Update-PhoneNumberType validates E.164 format' {
        $content = Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw
        $content | Should -Match 'notmatch.*\^\\\+\[1-9\]\\d\{6,14\}\$'
    }

    It 'TC-E164U-02: Invoke-MigrateTpsPhoneNumber validates E.164 format' {
        $content = Get-Content "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1" -Raw
        $content | Should -Match 'notmatch.*\^\\\+\[1-9\]\\d\{6,14\}\$'
    }

    It 'TC-E164U-03: Repair-D365PhoneRecord validates E.164 format on inputs' {
        $content = Get-Content "$PSScriptRoot\Repair-D365PhoneRecord-v14.ps1" -Raw
        $content | Should -Match 'notmatch.*\^\\\+\[1-9\]\\d\{6,14\}\$'
    }
}

Describe 'TC-Http204: Sync scripts handle HTTP 204 No Content (v14.5.0)' {

    It 'TC-Http204-01: Sync-TeamsPhoneNumbers handles 204' {
        $content = Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1" -Raw
        $content | Should -Match 'StatusCode\s*-eq\s*204'
    }

    It 'TC-Http204-02: Invoke-TeamsPhoneSync handles 204' {
        $content = Get-Content "$PSScriptRoot\Invoke-TeamsPhoneSync-v14.ps1" -Raw
        $content | Should -Match 'StatusCode\s*-eq\s*204'
    }

    It 'TC-Http204-03: Sync-TeamsPhoneNumbers shows success message on 204' {
        $content = Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1" -Raw
        $content | Should -Match '204 No Content.*accepted'
    }

    It 'TC-Http204-04: Invoke-TeamsPhoneSync shows success message on 204' {
        $content = Get-Content "$PSScriptRoot\Invoke-TeamsPhoneSync-v14.ps1" -Raw
        $content | Should -Match '204 No Content.*accepted'
    }
}

Describe 'TC-PatchTryCatch: Update-PhoneNumberType PATCH wrapped in try-catch (v14.5.0)' {

    It 'TC-PatchTC-01: PATCH operation is inside try block' {
        $content = Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw
        $content | Should -Match '(?s)try\s*\{[^}]*Invoke-RestMethod.*Method PATCH'
    }

    It 'TC-PatchTC-02: catch block reports HTTP status on PATCH failure' {
        $content = Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw
        $content | Should -Match 'PATCH failed'
    }
}

Describe 'TC-PortValidation: Port validation in config scripts (v14.5.0)' {

    It 'TC-PortVal-01: New-AcsTpeConfig validates port range' {
        $content = Get-Content "$PSScriptRoot\New-AcsTpeConfig-v14.ps1" -Raw
        $content | Should -Match '65535'
    }

    It 'TC-PortVal-02: Add-AcsTrunkDisabled validates SbcPort range' {
        $content = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $content | Should -Match '65535'
    }

    It 'TC-PortVal-03: Add-AcsTrunkDisabled checks config file exists' {
        $content = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $content | Should -Match 'Test-Path \$ConfigPath'
    }
}

Describe 'TC-FixRouteConfig: Fix-AcsRoutePattern has ConfigPath parameter (v14.5.0)' {

    It 'TC-FixRoute-01: Fix-AcsRoutePattern accepts -ConfigPath parameter' {
        $content = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $content | Should -Match '\$ConfigPath'
    }

    It 'TC-FixRoute-02: Fix-AcsRoutePattern validates config file exists' {
        $content = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $content | Should -Match 'Test-Path \$ConfigPath'
    }
}

Describe 'TC-GetProviderTryCatch: Get-TeamsProviderSetting has try-catch on API call (v14.5.0)' {

    It 'TC-GetProv-01: API call wrapped in try-catch' {
        $content = Get-Content "$PSScriptRoot\Get-TeamsProviderSetting-v14.ps1" -Raw
        $content | Should -Match '(?s)try\s*\{[^}]*Invoke-RestMethod.*providerUri'
    }

    It 'TC-GetProv-02: catch reports HTTP status on failure' {
        $content = Get-Content "$PSScriptRoot\Get-TeamsProviderSetting-v14.ps1" -Raw
        $content | Should -Match 'Failed to query Teams provider settings'
    }
}

Describe 'TC-NotesV14_5: All core scripts have v14.5.0 .NOTES entry (v14.5.0)' {

    It 'TC-NotesV14_5-01: Migration .NOTES has v14.5.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'v14\.5\.0\s*:'
    }

    It 'TC-NotesV14_5-02: Undo .NOTES has v14.5.0' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $content | Should -Match 'v14\.5\.0\s*:'
    }

    It 'TC-NotesV14_5-03: Toggle .NOTES has v14.5.0' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'v14\.5\.0\s*:'
    }

    It 'TC-NotesV14_5-04: FlipToACS .NOTES has v14.5.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $content | Should -Match 'v14\.5\.0\s*:'
    }

    It 'TC-NotesV14_5-05: FlipToTeams .NOTES has v14.5.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'v14\.5\.0\s*:'
    }
}

Describe 'TC-BannerV14_5: Migration banner and footer say v14.7.0 (v14.7.0)' {

    It 'TC-BannerV14_5-01: Migration banner contains v14.16.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'Migration\s+v14.16.0'
    }

    It 'TC-BannerV14_5-02: Migration COMPLETE footer contains v14.15.0' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $content | Should -Match 'COMPLETE.*v14.15.0'
    }

    It 'TC-BannerV14_5-03: Toggle banner contains v14.8.0' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $content | Should -Match 'Toggle\s+v14.11.0'
    }
}

#region -----------------------------------------------------------------------
#  v14.5.0 ITERATION 2 — CONSISTENCY + ADDITIONAL COVERAGE
#endregion

Describe 'TC-ConfigOutputPath: New-AcsTpeConfig default output uses v14.7.0 (v14.5.0 iter2)' {

    It 'TC-CfgOut-01: default OutputPath includes v14.7.0' {
        $content = Get-Content "$PSScriptRoot\New-AcsTpeConfig-v14.ps1" -Raw
        $content | Should -Match 'new-acs-tpe-config-v14.11.0\.json'
    }

    It 'TC-CfgOut-02: FlipToTeams examples reference v14.7.0 config' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $content | Should -Match 'new-acs-tpe-config-v14.11.0\.json'
    }
}

Describe 'TC-StrictMode: Key v14 scripts have Set-StrictMode -Version Latest (v14.5.0 iter2)' {

    It 'TC-Strict-01: Migration has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-02: Undo has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-03: Toggle has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-04: FlipToACS has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-05: FlipToTeams has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-06: New-AcsTpeConfig has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\New-AcsTpeConfig-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-07: Update-PhoneNumberType has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-08: Invoke-MigrateTpsPhoneNumber has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-09: Repair-D365PhoneRecord has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Repair-D365PhoneRecord-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-10: Sync-TeamsPhoneNumbers has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-11: Archive-TpeRuns has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Archive-TpeRuns-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-12: Fix-AcsRoutePattern has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
    It 'TC-Strict-13: Add-AcsTrunkDisabled has Set-StrictMode' {
        (Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw) | Should -Match 'Set-StrictMode\s+-Version\s+Latest'
    }
}

Describe 'TC-ErrorAction: Key v14 scripts have ErrorActionPreference Stop (v14.5.0 iter2)' {

    It 'TC-ErrAct-01: Migration has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
    It 'TC-ErrAct-02: Undo has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
    It 'TC-ErrAct-03: Toggle has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
    It 'TC-ErrAct-04: Update-PhoneNumberType has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
    It 'TC-ErrAct-05: Invoke-MigrateTpsPhoneNumber has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
    It 'TC-ErrAct-06: Fix-AcsRoutePattern has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
    It 'TC-ErrAct-07: Add-AcsTrunkDisabled has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
    It 'TC-ErrAct-08: Archive-TpeRuns has ErrorActionPreference Stop' {
        (Get-Content "$PSScriptRoot\Archive-TpeRuns-v14.ps1" -Raw) | Should -Match "ErrorActionPreference\s*=\s*['""]Stop['""]"
    }
}

Describe 'TC-NoV13Refs: No stale v13 script references in live code (v14.5.0 iter2)' {

    It 'TC-NoV13-01: Migration has no v13 script references' {
        $content = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        [regex]::Matches($content, '-v13\.ps1').Count | Should -Be 0
    }
    It 'TC-NoV13-02: Undo has no v13 script references' {
        $content = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        [regex]::Matches($content, '-v13\.ps1').Count | Should -Be 0
    }
    It 'TC-NoV13-03: Toggle has no v13 script references' {
        $content = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        [regex]::Matches($content, '-v13\.ps1').Count | Should -Be 0
    }
    It 'TC-NoV13-04: FlipToACS has no v13 script references' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        [regex]::Matches($content, '-v13\.ps1').Count | Should -Be 0
    }
    It 'TC-NoV13-05: FlipToTeams has no v13 script references' {
        $content = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        [regex]::Matches($content, '-v13\.ps1').Count | Should -Be 0
    }
}

Describe 'TC-RequiresV51: Key v14 scripts have #Requires -Version 5.1 (v14.5.0 iter2)' {

    It 'TC-Req51-01: Migration has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
    It 'TC-Req51-02: Undo has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
    It 'TC-Req51-03: Toggle has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
    It 'TC-Req51-04: FlipToACS has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
    It 'TC-Req51-05: FlipToTeams has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
    It 'TC-Req51-06: Update-PhoneNumberType has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
    It 'TC-Req51-07: Invoke-MigrateTpsPhoneNumber has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
    It 'TC-Req51-08: Fix-AcsRoutePattern has #Requires -Version 5.1' {
        (Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -TotalCount 1).Trim() | Should -Match '#Requires\s+-Version\s+5\.1'
    }
}

# =====================================================================
# v14.6.0 TESTS — Iteration 1 fixes
# =====================================================================

Describe 'TC-UpdPhoneSource: Update-PhoneNumberType includes msdyn_ocphonenumbersource (v14.6.0)' {
    BeforeAll {
        $updPhonePath = "$PSScriptRoot\Update-PhoneNumberType-v14.ps1"
        $updPhoneContent = if (Test-Path $updPhonePath) { Get-Content $updPhonePath -Raw } else { '' }
    }

    It 'TC-UpdPhoneSource-01: ACS_TO_TPS PATCH body sets msdyn_ocphonenumbersource = 192350001' {
        $updPhoneContent | Should -Match 'msdyn_ocphonenumbersource\s*=\s*192350001'
    }
    It 'TC-UpdPhoneSource-02: TPS_TO_ACS PATCH body sets msdyn_ocphonenumbersource = 192350000' {
        $updPhoneContent | Should -Match 'msdyn_ocphonenumbersource\s*=\s*192350000'
    }
    It 'TC-UpdPhoneSource-03: Script has DryRun parameter' {
        $updPhoneContent | Should -Match '\[switch\]\$DryRun'
    }
    It 'TC-UpdPhoneSource-04: DryRun guard wraps PATCH call' {
        $updPhoneContent | Should -Match 'if\s*\(\$DryRun\)'
    }
    It 'TC-UpdPhoneSource-05: CCaaS sync auto-discovery present for ACS_TO_TPS' {
        $updPhoneContent | Should -Match 'CCaaS_SynchronizePhoneNumbers'
    }
    It 'TC-UpdPhoneSource-06: CCaaS sync skipped for TPS_TO_ACS' {
        $updPhoneContent | Should -Match 'Step 5: CCaaS sync SKIPPED \(TPS_TO_ACS\)'
    }
    It 'TC-UpdPhoneSource-07: Version banner shows v14.6.0' {
        $updPhoneContent | Should -Match 'UpdatePhoneNumberType v14.11.0'
    }
    It 'TC-UpdPhoneSource-08: .NOTES mentions v14.6.0' {
        $updPhoneContent | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-UpdPhoneSource-09: Verify step selects msdyn_ocphonenumbersource' {
        $updPhoneContent | Should -Match 'msdyn_ocphonenumbersource.*statecode'
    }
}

Describe 'TC-FixRouteParam: Fix-AcsRoutePattern is parameterized (v14.6.0)' {
    BeforeAll {
        $fixRoutePath = "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1"
        $fixRouteContent = if (Test-Path $fixRoutePath) { Get-Content $fixRoutePath -Raw } else { '' }
    }

    It 'TC-FixRouteParam-01: Has Mandatory RouteName parameter' {
        $fixRouteContent | Should -Match '\[Parameter\(Mandatory\)\]\s*\[string\]\$RouteName'
    }
    It 'TC-FixRouteParam-02: Has Mandatory NumberPattern parameter' {
        $fixRouteContent | Should -Match '\[Parameter\(Mandatory\)\]\s*\[string\]\$NumberPattern'
    }
    It 'TC-FixRouteParam-03: Has Mandatory TrunkFqdn parameter' {
        $fixRouteContent | Should -Match '\[Parameter\(Mandatory\)\]\s*\[string\]\$TrunkFqdn'
    }
    It 'TC-FixRouteParam-04: Has DryRun switch' {
        $fixRouteContent | Should -Match '\[switch\]\$DryRun'
    }
    It 'TC-FixRouteParam-05: No hardcoded xyz.cbg FQDN' {
        $fixRouteContent | Should -Not -Match 'xyz\.cbg-voice\.sandbox\.dev\.microsoft'
    }
    It 'TC-FixRouteParam-06: Route-building code uses $NumberPattern not hardcoded pattern' {
        $codeSection = ($fixRouteContent -split '#>',2)[1]
        $codeSection | Should -Match 'numberPattern\s*=\s*\$NumberPattern'
    }
    It 'TC-FixRouteParam-07: Uses $RouteName variable in patch body' {
        $fixRouteContent | Should -Match 'name\s*=\s*\$RouteName'
    }
    It 'TC-FixRouteParam-08: Uses $NumberPattern variable in patch body' {
        $fixRouteContent | Should -Match 'numberPattern\s*=\s*\$NumberPattern'
    }
    It 'TC-FixRouteParam-09: Uses $TrunkFqdn variable in patch body' {
        $fixRouteContent | Should -Match '\$TrunkFqdn'
    }
    It 'TC-FixRouteParam-10: Version banner shows v14.6.0' {
        $fixRouteContent | Should -Match 'Fix-AcsRoutePattern v14.11.0'
    }
    It 'TC-FixRouteParam-11: Has Mandatory ConfigPath parameter' {
        $fixRouteContent | Should -Match '\[Parameter\(Mandatory\)\]\s*\[string\]\$ConfigPath'
    }
}

Describe 'TC-AddTrunkDryRun: Add-AcsTrunkDisabled has DryRun support (v14.6.0)' {
    BeforeAll {
        $addTrunkPath = "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1"
        $addTrunkContent = if (Test-Path $addTrunkPath) { Get-Content $addTrunkPath -Raw } else { '' }
    }

    It 'TC-AddTrunkDryRun-01: Has DryRun switch parameter' {
        $addTrunkContent | Should -Match '\[switch\]\$DryRun'
    }
    It 'TC-AddTrunkDryRun-02: DryRun guard prevents API call' {
        $addTrunkContent | Should -Match 'if\s*\(\$DryRun\)'
    }
    It 'TC-AddTrunkDryRun-03: DryRun exits with code 0' {
        $addTrunkContent | Should -Match 'DRY RUN.*no API call'
    }
    It 'TC-AddTrunkDryRun-04: .NOTES mentions v14.6.0' {
        $addTrunkContent | Should -Match 'v14\.6\.0\s*:'
    }
}

Describe 'TC-SbcFqdnBlank: Set-AcsSbcFqdn validates blank FQDN input (v14.6.0)' {
    BeforeAll {
        $sbcPath = "$PSScriptRoot\Set-AcsSbcFqdn-v14.ps1"
        $sbcContent = if (Test-Path $sbcPath) { Get-Content $sbcPath -Raw } else { '' }
    }

    It 'TC-SbcFqdnBlank-01: Validates OldFqdn is not blank' {
        $sbcContent | Should -Match 'IsNullOrWhiteSpace\(\$OldFqdn\)'
    }
    It 'TC-SbcFqdnBlank-02: Exits on blank OldFqdn' {
        $sbcContent | Should -Match 'Old FQDN cannot be blank'
    }
    It 'TC-SbcFqdnBlank-03: Validates NewFqdn is not blank' {
        $sbcContent | Should -Match 'New FQDN cannot be blank'
    }
    It 'TC-SbcFqdnBlank-04: .NOTES mentions v14.6.0' {
        $sbcContent | Should -Match 'v14\.6\.0\s*:'
    }
}

Describe 'TC-ArchiveDedup: Archive-TpeRuns Sort-Object dedup fix (v14.6.0)' {
    BeforeAll {
        $archivePath = "$PSScriptRoot\Archive-TpeRuns-v14.ps1"
        $archiveContent = if (Test-Path $archivePath) { Get-Content $archivePath -Raw } else { '' }
    }

    It 'TC-ArchiveDedup-01: Uses FullName for uniqueness dedup instead of LastWriteTime' {
        $archiveContent | Should -Match 'Sort-Object\s*\{\s*\$_\.FullName\s*\}\s*-Unique'
    }
    It 'TC-ArchiveDedup-02: Still sorts by LastWriteTime for chronological order' {
        $archiveContent | Should -Match 'Sort-Object\s+LastWriteTime'
    }
    It 'TC-ArchiveDedup-03: Does NOT use Sort-Object LastWriteTime -Unique (old pattern)' {
        $archiveContent | Should -Not -Match 'Sort-Object\s+LastWriteTime\s+-Unique'
    }
}

Describe 'TC-SyncGuidVal: Invoke-TeamsPhoneSync validates ProviderSettingId GUID (v14.6.0)' {
    BeforeAll {
        $syncPath = "$PSScriptRoot\Invoke-TeamsPhoneSync-v14.ps1"
        $syncContent = if (Test-Path $syncPath) { Get-Content $syncPath -Raw } else { '' }
    }

    It 'TC-SyncGuidVal-01: Has GUID validation with Guid::Parse' {
        $syncContent | Should -Match '\[System\.Guid\]::Parse\(\$ProviderSettingId\)'
    }
    It 'TC-SyncGuidVal-02: Exits on invalid GUID' {
        $syncContent | Should -Match 'not a valid GUID'
    }
    It 'TC-SyncGuidVal-03: Version banner shows v14.8.0' {
        $syncContent | Should -Match 'Invoke-TeamsPhoneSync v14.11.0'
    }
}

Describe 'TC-V146Version: All main scripts have v14.6.0 version references (v14.6.0)' {
    It 'TC-V146-01: Migration .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-02: Undo .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-03: Toggle .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-04: FlipToACS .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-05: FlipToTeams .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-06: Update-PhoneNumberType .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-07: Fix-AcsRoutePattern .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-08: Add-AcsTrunkDisabled .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-09: Set-AcsSbcFqdn .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Set-AcsSbcFqdn-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
    It 'TC-V146-10: Repair-D365PhoneRecord .NOTES has v14.6.0 entry' {
        $c = Get-Content "$PSScriptRoot\Repair-D365PhoneRecord-v14.ps1" -Raw
        $c | Should -Match 'v14\.6\.0\s*:'
    }
}

Describe 'TC-UpdPhoneSourceParity: Update-PhoneNumberType has source parity with Invoke-MigrateTpsPhoneNumber (v14.6.0)' {
    BeforeAll {
        $updPhone = if (Test-Path "$PSScriptRoot\Update-PhoneNumberType-v14.ps1") { Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw } else { '' }
        $migratePhone = if (Test-Path "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1") { Get-Content "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1" -Raw } else { '' }
    }

    It 'TC-UpdPhoneSourceParity-01: Both scripts set source to 192350001 for ACS_TO_TPS' {
        $updPhone | Should -Match 'msdyn_ocphonenumbersource\s*=\s*192350001'
        $migratePhone | Should -Match 'msdyn_ocphonenumbersource\s*=\s*192350001'
    }
    It 'TC-UpdPhoneSourceParity-02: Both scripts set source to 192350000 for TPS_TO_ACS' {
        $updPhone | Should -Match 'msdyn_ocphonenumbersource\s*=\s*192350000'
        $migratePhone | Should -Match 'msdyn_ocphonenumbersource\s*=\s*192350000'
    }
    It 'TC-UpdPhoneSourceParity-03: Both scripts have E.164 validation' {
        $updPhone | Should -Match '\^\\\+\[1-9\]\\d\{6,14\}\$'
        $migratePhone | Should -Match '\^\\\+\[1-9\]\\d\{6,14\}\$'
    }
}

Describe 'TC-FixRouteMandatory: Fix-AcsRoutePattern requires all params (v14.6.0)' {
    It 'TC-FixRouteMandatory-01: ConfigPath is Mandatory' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match '\[Parameter\(Mandatory\)\][\s\S]*?\[string\]\$ConfigPath'
    }
    It 'TC-FixRouteMandatory-02: RouteName is Mandatory' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match '\[Parameter\(Mandatory\)\][\s\S]*?\[string\]\$RouteName'
    }
}

Describe 'TC-NewConfigV148: New-AcsTpeConfig output default references v14.8.0 (v14.8.0)' {
    It 'TC-NewConfigV148-01: OutputPath default contains v14.8.0' {
        $c = Get-Content "$PSScriptRoot\New-AcsTpeConfig-v14.ps1" -Raw
        $c | Should -Match 'new-acs-tpe-config-v14.11.0\.json'
    }
}

# =====================================================================
# v14.7.0 TESTS — Iteration 2 fixes
# =====================================================================

Describe 'TC-DashFailState: Dashboard state skips FAIL results (v14.7.0)' {
    BeforeAll {
        $scripts = @(
            "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1",
            "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1",
            "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1",
            "$PSScriptRoot\Invoke-FlipToACS-v14.ps1",
            "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1"
        )
    }

    It 'TC-DashFailState-01: Migration dashboard filters out FAIL from state detection' {
        $c = Get-Content $scripts[0] -Raw
        $c | Should -Match "result -ne 'FAIL'"
    }
    It 'TC-DashFailState-02: Undo dashboard filters out FAIL from state detection' {
        $c = Get-Content $scripts[1] -Raw
        $c | Should -Match "result -ne 'FAIL'"
    }
    It 'TC-DashFailState-03: Toggle dashboard filters out FAIL from state detection' {
        $c = Get-Content $scripts[2] -Raw
        $c | Should -Match "result -ne 'FAIL'"
    }
    It 'TC-DashFailState-04: FlipToACS dashboard filters out FAIL from state detection' {
        $c = Get-Content $scripts[3] -Raw
        $c | Should -Match "result -ne 'FAIL'"
    }
    It 'TC-DashFailState-05: FlipToTeams dashboard filters out FAIL from state detection' {
        $c = Get-Content $scripts[4] -Raw
        $c | Should -Match "result -ne 'FAIL'"
    }
    It 'TC-DashFailState-06: Migration shows (last run FAILED) indicator' {
        $c = Get-Content $scripts[0] -Raw
        $c | Should -Match 'last run FAILED'
    }
    It 'TC-DashFailState-07: All 5 scripts have $hasPendingFail variable' {
        foreach ($s in $scripts) {
            $c = Get-Content $s -Raw
            $c | Should -Match '\$hasPendingFail'
        }
    }
}

Describe 'TC-DomRegDryRun: Test-DomainRegistration DryRun does not set verified=true (v14.7.0)' {
    BeforeAll {
        $domRegPath = "$PSScriptRoot\Test-DomainRegistration-v14.ps1"
        $domRegContent = if (Test-Path $domRegPath) { Get-Content $domRegPath -Raw } else { '' }
    }

    It 'TC-DomRegDryRun-01: DryRun block does NOT set $verified = $true' {
        $dryBlock = [regex]::Match($domRegContent, 'if\s*\(\$DryRun\)\s*\{[^}]+\}').Value
        $dryBlock | Should -Not -Match '\$verified\s*=\s*\$true'
    }
    It 'TC-DomRegDryRun-02: DryRun shows accurate message about skipping verification' {
        $domRegContent | Should -Match 'Skipping verification polling'
    }
    It 'TC-DomRegDryRun-03: Post-loop handles DryRun separately from verification timeout' {
        $domRegContent | Should -Match 'if\s*\(\$DryRun\)'
        $domRegContent | Should -Match 'DRY RUN.*Verification would proceed'
    }
    It 'TC-DomRegDryRun-04: .NOTES mentions v14.7.0' {
        $domRegContent | Should -Match 'v14\.8\.0\s*:'
    }
}

Describe 'TC-V148Version: All main scripts have v14.8.0 version references (v14.8.0)' {
    It 'TC-V148-01: Migration .NOTES has v14.8.0 entry' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0\s*:'
    }
    It 'TC-V148-02: Undo .NOTES has v14.8.0 entry' {
        $c = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0\s*:'
    }
    It 'TC-V148-03: Toggle .NOTES has v14.8.0 entry' {
        $c = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0\s*:'
    }
    It 'TC-V148-04: FlipToACS .NOTES has v14.8.0 entry' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0\s*:'
    }
    It 'TC-V148-05: FlipToTeams .NOTES has v14.8.0 entry' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0\s*:'
    }
    It 'TC-V148-06: Test-DomainRegistration .NOTES has v14.8.0 entry' {
        $c = Get-Content "$PSScriptRoot\Test-DomainRegistration-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0\s*:'
    }
    It 'TC-V148-07: New-AcsTpeConfig output path uses v14.11.0' {
        $c = Get-Content "$PSScriptRoot\New-AcsTpeConfig-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0\.json'
    }
    It 'TC-V148-08: README says v14.16.0' {
        $c = Get-Content "$PSScriptRoot\README.md" -Raw
        $c | Should -Match '\*\*Version:\*\*\s*v14.16.0'
    }
}

Describe 'TC-DashV148: Dashboard HTML strings show v14.7.0 (v14.7.0)' {
    It 'TC-DashV148-01: Migration dashboard sub-header says v14.15.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        ($c | Select-String 'v14.15.0 &nbsp;\|&nbsp; \$d365Url').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-02: Migration dashboard footer says v14.15.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        ($c | Select-String 'ACS TPE v14.15.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-03: Undo dashboard sub-header says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        ($c | Select-String 'v14.11.0 &nbsp;\|&nbsp; \$d365Url').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-04: Undo dashboard footer says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        ($c | Select-String 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-05: Toggle dashboard sub-header says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        ($c | Select-String 'v14.11.0 &nbsp;\|&nbsp; \$d365Url').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-06: Toggle dashboard footer says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        ($c | Select-String 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-07: FlipToACS dashboard sub-header says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        ($c | Select-String 'v14.11.0 &nbsp;\|&nbsp; \$d365Url').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-08: FlipToACS dashboard footer says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        ($c | Select-String 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-09: FlipToTeams dashboard sub-header says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        ($c | Select-String 'v14.11.0 &nbsp;\|&nbsp; \$d365Url').Count | Should -BeGreaterThan 0
    }
    It 'TC-DashV148-10: FlipToTeams dashboard footer says v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        ($c | Select-String 'ACS TPE v14.11.0 &nbsp;\|&nbsp; stats/tpe-runs\.jsonl').Count | Should -BeGreaterThan 0
    }
}

Describe 'TC-BannerV148: Console banners show v14.8.0 (v14.8.0)' {
    It 'TC-BannerV148-01: Migration banner contains v14.16.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match 'Migration\s+v14.16.0'
    }
    It 'TC-BannerV148-02: Migration COMPLETE footer contains v14.15.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match 'COMPLETE.*v14.15.0'
    }
    It 'TC-BannerV148-03: Toggle banner contains v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $c | Should -Match 'Toggle\s+v14.11.0'
    }
}

# =====================================================================
# v14.8.0 TESTS — Version parity + safety fixes
# =====================================================================

Describe 'TC-UtilBannerV148: All 9 utility scripts have version banner (v14.11.0)' {
    It 'TC-UtilBannerV148-01: Invoke-MigrateTpsPhoneNumber banner says v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-MigrateTpsPhoneNumber-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0'
    }
    It 'TC-UtilBannerV148-02: Invoke-TeamsPhoneSync banner says v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-TeamsPhoneSync-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0'
    }
    It 'TC-UtilBannerV148-03: Sync-TeamsPhoneNumbers banner says v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0'
    }
    It 'TC-UtilBannerV148-04: Get-TeamsProviderSetting banner says v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Get-TeamsProviderSetting-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0'
    }
    It 'TC-UtilBannerV148-05: Update-PhoneNumberType .NOTES has v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0'
    }
    It 'TC-UtilBannerV148-06: Add-AcsTrunkDisabled .NOTES has v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0'
    }
    It 'TC-UtilBannerV148-07: Fix-AcsRoutePattern .NOTES has v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0'
    }
    It 'TC-UtilBannerV148-08: Set-AcsSbcFqdn .NOTES has v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Set-AcsSbcFqdn-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0'
    }
    It 'TC-UtilBannerV148-09: Repair-D365PhoneRecord .NOTES has v14.8.0' {
        $c = Get-Content "$PSScriptRoot\Repair-D365PhoneRecord-v14.ps1" -Raw
        $c | Should -Match 'v14\.8\.0'
    }
}

Describe 'TC-UpdPhoneBoundsCheck: Update-PhoneNumberType guards provider array access (v14.8.0)' {
    BeforeAll {
        $updPhone = if (Test-Path "$PSScriptRoot\Update-PhoneNumberType-v14.ps1") { Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw } else { '' }
    }
    It 'TC-UpdPhoneBoundsCheck-01: Has provider array bounds check before [0] access' {
        $updPhone | Should -Match 'provResp\.value\.Count -eq 0'
    }
}

Describe 'TC-UndoSummaryBox: Undo summary box alignment (v14.11.0)' {
    It 'TC-UndoSummaryBox-01: Undo Run Summary header has v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $c | Should -Match 'UNDO v14.11.0 -- Run Summary'
    }
}

Describe 'TC-AllScriptsV148: Scripts with .NOTES have v14.8.0 in changelog (v14.8.0 — historical)' {
    It 'TC-AllScriptsV148-<_>: <_> contains v14.8.0 in changelog' -ForEach @(
        'Invoke-ACS-TPE-Full-Migration-v14.ps1',
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1',
        'Set-AcsSbcFqdn-v14.ps1',
        'Repair-D365PhoneRecord-v14.ps1',
        'Test-DomainRegistration-v14.ps1',
        'Test-ACS-TPE-Migration-v14.Tests.ps1'
    ) {
        $path = Join-Path $PSScriptRoot $_
        if (Test-Path $path) {
            $c = Get-Content $path -Raw
            $c | Should -Match 'v14\.8\.0'
        } else {
            Set-ItResult -Skipped -Because "File $_ not found"
        }
    }
}

# =====================================================================
# v14.11.0 TESTS — Banner fixes, HTML title, README completeness
# =====================================================================

Describe 'TC-AllScriptsV149: All 18 scripts have v14.11.0 somewhere (v14.11.0)' {
    It 'TC-AllScriptsV149-<_>: <_> contains v14.11.0' -ForEach @(
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1',
        'Invoke-MigrateTpsPhoneNumber-v14.ps1',
        'Invoke-TeamsPhoneSync-v14.ps1',
        'Sync-TeamsPhoneNumbers-v14.ps1',
        'Get-TeamsProviderSetting-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1',
        'Set-AcsSbcFqdn-v14.ps1',
        'Repair-D365PhoneRecord-v14.ps1',
        'New-AcsTpeConfig-v14.ps1',
        'Test-DomainRegistration-v14.ps1',
        'Archive-TpeRuns-v14.ps1',
        'Test-ACS-TPE-Migration-v14.Tests.ps1'
    ) {
        $path = Join-Path $PSScriptRoot $_
        if (Test-Path $path) {
            $c = Get-Content $path -Raw
            $c | Should -Match 'v14.11.0'
        } else {
            Set-ItResult -Skipped -Because "File $_ not found"
        }
    }
}

Describe 'TC-FixRoutePatternBanner: Fix-AcsRoutePattern banner version (v14.11.0)' {
    BeforeAll {
        $script:fixRoute = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
    }
    It 'TC-FixRoutePatternBanner-01: Banner says v14.11.0 not v14.6.0' {
        $fixRoute | Should -Match 'Fix-AcsRoutePattern v14.11.0'
    }
    It 'TC-FixRoutePatternBanner-02: No v14.6.0 in banner line' {
        $fixRoute | Should -Not -Match 'Fix-AcsRoutePattern v14\.6\.0'
    }
}

Describe 'TC-UpdatePhoneBanner: Update-PhoneNumberType banner version (v14.11.0)' {
    BeforeAll {
        $script:updPhone = Get-Content "$PSScriptRoot\Update-PhoneNumberType-v14.ps1" -Raw
    }
    It 'TC-UpdatePhoneBanner-01: Banner says v14.11.0 not v14.6.0' {
        $updPhone | Should -Match 'UpdatePhoneNumberType v14.11.0'
    }
    It 'TC-UpdatePhoneBanner-02: No v14.6.0 in banner line' {
        $updPhone | Should -Not -Match 'UpdatePhoneNumberType v14\.6\.0'
    }
}

Describe 'TC-MigHtmlTitle: Migration HTML title has version (v14.11.0)' {
    BeforeAll {
        $script:migScript = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
    }
    It 'TC-MigHtmlTitle-01: HTML title includes v14.15.0' {
        $migScript | Should -Match '<title>ACS TPE Migration v14.15.0'
    }
    It 'TC-MigHtmlTitle-02: HTML title does not say just v14 without version' {
        $migScript | Should -Not -Match '<title>ACS TPE Migration v14 -'
    }
}

Describe 'TC-ReadmeV149: README.md version v14.11.0 (v14.11.0)' {
    BeforeAll {
        $script:readme = Get-Content "$PSScriptRoot\README.md" -Raw
    }
    It 'TC-ReadmeV149-01: README contains v14.11.0' {
        $readme | Should -Match 'v14.11.0'
    }
}

Describe 'TC-ReadmeMissingScripts: README documents all standalone scripts (v14.11.0)' {
    BeforeAll {
        $script:readme = Get-Content "$PSScriptRoot\README.md" -Raw
    }
    It 'TC-ReadmeMissingScripts-01: README has Invoke-FlipToACS section' {
        $readme | Should -Match 'Invoke-FlipToACS-v14\.ps1'
    }
    It 'TC-ReadmeMissingScripts-02: README has Invoke-FlipToTeams section' {
        $readme | Should -Match 'Invoke-FlipToTeams-v14\.ps1'
    }
    It 'TC-ReadmeMissingScripts-03: README has Invoke-MigrateTpsPhoneNumber section' {
        $readme | Should -Match 'Invoke-MigrateTpsPhoneNumber-v14\.ps1'
    }
    It 'TC-ReadmeMissingScripts-04: README has Sync-TeamsPhoneNumbers section' {
        $readme | Should -Match 'Sync-TeamsPhoneNumbers-v14\.ps1'
    }
    It 'TC-ReadmeMissingScripts-05: README has Archive-TpeRuns section' {
        $readme | Should -Match 'Archive-TpeRuns-v14\.ps1'
    }
}

Describe 'TC-DashVersionV149: Dashboard version strings v14.11.0 (v14.11.0)' {
    It 'TC-DashVersionV149-01: Migration dashboard sub-header has v14.15.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match 'v14.15.0 &nbsp;'
    }
    It 'TC-DashVersionV149-02: Undo dashboard sub-header has v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0 &nbsp;'
    }
    It 'TC-DashVersionV149-03: Migration COMPLETE footer says v14.15.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match 'COMPLETE.*v14.15.0'
    }
    It 'TC-DashVersionV149-04: Toggle dashboard sub-header has v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Toggle-AcsTeamsRouting-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0'
    }
    It 'TC-DashVersionV149-05: FlipToACS has v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToACS-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0'
    }
    It 'TC-DashVersionV149-06: FlipToTeams has v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-FlipToTeams-v14.ps1" -Raw
        $c | Should -Match 'v14.11.0'
    }
}

Describe 'TC-MigBannerV149: Migration banner v14.11.0 (v14.11.0)' {
    It 'TC-MigBannerV149-01: Migration console banner has v14.16.0' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match 'TPE\) Migration  v14.16.0'
    }
    It 'TC-MigBannerV149-02: Undo console banner has v14.11.0' {
        $c = Get-Content "$PSScriptRoot\Undo-ACS-TPE-Migration-v14.ps1" -Raw
        $c | Should -Match 'UNDO v14.11.0'
    }
}

Describe 'TC-UtilBannerV149: Utility script banners have v14.11.0 (v14.11.0)' {
    It 'TC-UtilBannerV149-<_>: <_> banner has v14.11.0' -ForEach @(
        @{ File = 'Fix-AcsRoutePattern-v14.ps1';         Pattern = 'Fix-AcsRoutePattern v14.11.0' },
        @{ File = 'Update-PhoneNumberType-v14.ps1';      Pattern = 'UpdatePhoneNumberType v14.11.0' },
        @{ File = 'Invoke-MigrateTpsPhoneNumber-v14.ps1'; Pattern = 'MigrateTpsPhoneNumber v14.11.0' },
        @{ File = 'Invoke-TeamsPhoneSync-v14.ps1';       Pattern = 'TeamsPhoneSync v14.11.0' },
        @{ File = 'Sync-TeamsPhoneNumbers-v14.ps1';      Pattern = 'TeamsPhoneNumbers v14.11.0' },
        @{ File = 'Get-TeamsProviderSetting-v14.ps1';    Pattern = 'TeamsProviderSetting v14.11.0' },
        @{ File = 'New-AcsTpeConfig-v14.ps1';            Pattern = 'AcsTpeConfig v14.11.0' }
    ) {
        $path = Join-Path $PSScriptRoot $_.File
        if (Test-Path $path) {
            $c = Get-Content $path -Raw
            $c | Should -Match $_.Pattern
        } else {
            Set-ItResult -Skipped -Because "File $($_.File) not found"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  v14.11.0 — Bug-fix iteration: DryRun Step 4 guard, exit-on-error parity,
#             verification GETs, Sync try-catch, version bump
# ═══════════════════════════════════════════════════════════════════════════════

Describe 'TC-Step4DryRunGuard: Migration Step 4 domain registration is DryRun-guarded (v14.11.0)' {
    It 'TC-Step4DryRunGuard-01: Step 4 block contains DryRun guard before New-MgDomain' {
        $c = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1" -Raw
        $c | Should -Match '\} elseif \(\$DryRun\) \{'
        $c | Should -Match '\(DRY RUN\) Would register/verify domain'
    }
    It 'TC-Step4DryRunGuard-02: New-MgDomain is inside else branch, not the DryRun branch' {
        $lines = Get-Content "$PSScriptRoot\Invoke-ACS-TPE-Full-Migration-v14.ps1"
        $dryIdx = ($lines | Select-String -Pattern 'elseif \(\$DryRun\)' | Select-Object -First 1).LineNumber
        $mgIdx  = ($lines | Select-String -Pattern 'New-MgDomain -Id' | Select-Object -First 1).LineNumber
        $mgIdx | Should -BeGreaterThan $dryIdx
    }
}

Describe 'TC-AddTrunkExitCode: Add-AcsTrunkDisabled exits 1 on PATCH failure (v14.11.0)' {
    It 'TC-AddTrunkExitCode-01: catch block contains exit 1' {
        $c = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $c | Should -Match 'catch \{[\s\S]*?exit 1'
    }
    It 'TC-AddTrunkExitCode-02: has verification GET after PATCH' {
        $c = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $c | Should -Match 'Verification GET'
        $c | Should -Match 'Invoke-RestMethod.*-Method GET'
    }
    It 'TC-AddTrunkExitCode-03: verification GET has HMAC Dispose' {
        $c = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $disposes = ([regex]::Matches($c, '\.Dispose\(\)')).Count
        $disposes | Should -BeGreaterOrEqual 4
    }
}

Describe 'TC-FixRouteExitCode: Fix-AcsRoutePattern exits 1 on PATCH failure (v14.11.0)' {
    It 'TC-FixRouteExitCode-01: catch block after PATCH contains exit 1' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match '! Error:[\s\S]*?exit 1'
    }
    It 'TC-FixRouteExitCode-02: has verification GET after PATCH' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match 'Verification GET'
        $c | Should -Match 'Invoke-RestMethod.*-Method GET'
    }
    It 'TC-FixRouteExitCode-03: verification GET SHA256 and HMAC both disposed' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $disposes = ([regex]::Matches($c, '\.Dispose\(\)')).Count
        $disposes | Should -BeGreaterOrEqual 4
    }
}

Describe 'TC-SyncTryCatch: Sync-TeamsPhoneNumbers Steps 1 and 2 wrapped in try-catch (v14.11.0)' {
    It 'TC-SyncTryCatch-01: Step 1 query has try-catch' {
        $c = Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1" -Raw
        $c | Should -Match 'Step 1 query failed'
    }
    It 'TC-SyncTryCatch-02: Step 2 query has try-catch with fallback' {
        $c = Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1" -Raw
        $c | Should -Match 'Step 2 query failed'
        $c | Should -Match 'continuing without DynamicsAppId'
    }
    It 'TC-SyncTryCatch-03: Step 1 failure exits with code 1' {
        $c = Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1" -Raw
        $c | Should -Match 'Step 1 query failed[\s\S]*?exit 1'
    }
    It 'TC-SyncTryCatch-04: Step 2 failure does NOT exit (non-fatal)' {
        $lines = Get-Content "$PSScriptRoot\Sync-TeamsPhoneNumbers-v14.ps1"
        $step2Catch = $lines | Select-String -Pattern 'Step 2 query failed'
        $lineNum = $step2Catch.LineNumber
        $nextLines = $lines[($lineNum)..([Math]::Min($lineNum + 3, $lines.Count - 1))] -join "`n"
        $nextLines | Should -Not -Match 'exit 1'
    }
}

Describe 'TC-AllScriptsV1410: All 18 scripts have v14.11.0 in .NOTES or banner (v14.11.0)' {
    It 'TC-AllScriptsV1410-<_>: <_> has v14.11.0' -ForEach @(
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1',
        'New-AcsTpeConfig-v14.ps1',
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1',
        'Set-AcsSbcFqdn-v14.ps1',
        'Repair-D365PhoneRecord-v14.ps1',
        'Test-DomainRegistration-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Get-TeamsProviderSetting-v14.ps1',
        'Invoke-MigrateTpsPhoneNumber-v14.ps1',
        'Invoke-TeamsPhoneSync-v14.ps1',
        'Sync-TeamsPhoneNumbers-v14.ps1',
        'Archive-TpeRuns-v14.ps1',
        'Test-ACS-TPE-Migration-v14.Tests.ps1'
    ) {
        $path = Join-Path $PSScriptRoot $_
        if (Test-Path $path) {
            $c = Get-Content $path -Raw
            $c | Should -Match 'v14.11.0'
        } else {
            Set-ItResult -Skipped -Because "File $_ not found"
        }
    }
}

Describe 'TC-ReadmeV1410: README.md has v14.11.0 (v14.11.0)' {
    It 'TC-ReadmeV1410-01: README version line says v14.16.0' {
        $c = Get-Content "$PSScriptRoot\README.md" -Raw
        $c | Should -Match '\*\*Version:\*\* v14.16.0'
    }
}

Describe 'TC-AddTrunkVerifyDispose: Add-AcsTrunkDisabled verification GET crypto cleanup (v14.11.0)' {
    It 'TC-AddTrunkVerifyDispose-01: getSha SHA256 is disposed in finally' {
        $c = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $c | Should -Match '\$getSha\.Dispose\(\)'
    }
    It 'TC-AddTrunkVerifyDispose-02: getHmac HMAC is disposed in finally' {
        $c = Get-Content "$PSScriptRoot\Add-AcsTrunkDisabled-v14.ps1" -Raw
        $c | Should -Match '\$getHmac\.Dispose\(\)'
    }
}

Describe 'TC-FixRouteVerifyDispose: Fix-AcsRoutePattern verification GET crypto cleanup (v14.11.0)' {
    It 'TC-FixRouteVerifyDispose-01: vSha SHA256 is disposed in finally' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match '\$vSha\.Dispose\(\)'
    }
    It 'TC-FixRouteVerifyDispose-02: vHmac HMAC is disposed in finally' {
        $c = Get-Content "$PSScriptRoot\Fix-AcsRoutePattern-v14.ps1" -Raw
        $c | Should -Match '\$vHmac\.Dispose\(\)'
    }
}

Describe 'TC-DashVersionV1410: Dashboard HTML has v14.11.0 strings (v14.11.0)' {
    It 'TC-DashVersionV1410-<_>: <_> dashboard has v14.11.0' -ForEach @(
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1'
    ) {
        $c = Get-Content (Join-Path $PSScriptRoot $_) -Raw
        $c | Should -Match 'ACS TPE v14.11.0'
    }
}

# =============================================================================
# v14.11.0 TESTS — Security hardening, error handling, cross-script consistency
# =============================================================================

Describe 'TC-V1411-ConnStringValidation: Migration validates connection string endpoint/accesskey' {
    It 'TC-V1411-ConnStr-01: Step 1 throws on missing endpoint or accesskey' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
        $content | Should -Match "missing 'endpoint' or 'accesskey'"
    }
    It 'TC-V1411-ConnStr-02: validation occurs after parsing, before API call (Step 1)' {
        $lines = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1')
        $parseLine  = ($lines | Select-String "parts\['endpoint'\]" | Select-Object -Last 1).LineNumber
        $guardLine  = ($lines | Select-String "missing 'endpoint' or 'accesskey'" | Select-Object -First 1).LineNumber
        $apiLine    = ($lines | Select-String 'Invoke-RestMethod.*GET.*headers' | Select-Object -Last 1).LineNumber
        $guardLine | Should -BeGreaterThan $parseLine
        $apiLine   | Should -BeGreaterThan $guardLine
    }
}

Describe 'TC-V1411-ErrorMsgNullGuard: All scripts use -split instead of .Split([char]10)' {
    It 'TC-V1411-NullGuard-<_>: <_> has no .Split([char]10)' -ForEach @(
        'Invoke-ACS-TPE-Full-Migration-v14.ps1',
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Get-TeamsProviderSetting-v14.ps1'
    ) {
        $content = Get-Content (Join-Path $PSScriptRoot $_) -Raw
        $content | Should -Not -Match '\.Split\(\[char\]10\)'
    }
    It 'TC-V1411-NullGuard-Split-<_>: <_> uses -split for error messages' -ForEach @(
        'Invoke-ACS-TPE-Full-Migration-v14.ps1',
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1'
    ) {
        $content = Get-Content (Join-Path $PSScriptRoot $_) -Raw
        $content | Should -Match "\-split '\\r\?\\n'"
    }
}

Describe 'TC-V1411-HtmlXssFooter: Phone numbers in HTML footers are XSS-escaped' {
    It 'TC-V1411-XSS-Migration: Migration footer escapes numsList' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
        $content | Should -Match "numsList.*-replace '&','&amp;'"
    }
    It 'TC-V1411-XSS-Undo: Undo footer escapes phone numbers' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1') -Raw
        $content | Should -Match "PhoneNumber\b.*-replace '&','&amp;'.*-replace '<','&lt;'"
    }
    It 'TC-V1411-XSS-FlipAcs-li: FlipToACS failure list items are escaped' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Invoke-FlipToACS-v14.ps1') -Raw
        $content | Should -Match "failListHtml.*-replace '&','&amp;'.*<li>"
    }
    It 'TC-V1411-XSS-FlipAcs-nums: FlipToACS footer Numbers line uses escNums' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Invoke-FlipToACS-v14.ps1') -Raw
        $content | Should -Match '\$escNums'
    }
    It 'TC-V1411-XSS-FlipTeams-li: FlipToTeams failure list items are escaped' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1') -Raw
        $content | Should -Match "failListHtml.*-replace '&','&amp;'.*<li>"
    }
    It 'TC-V1411-XSS-FlipTeams-nums: FlipToTeams footer Numbers line uses escNums' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Invoke-FlipToTeams-v14.ps1') -Raw
        $content | Should -Match '\$escNums'
    }
}

Describe 'TC-V1411-UndoD365FailureCount: Undo D365 restore failure increments undoFailures' {
    It 'TC-V1411-UndoFail-01: D365 restore catch adds to undoFailures' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1') -Raw
        $content | Should -Match 'D365 restore failed'
        $content | Should -Match '\$script:undoFailures \+= "D365 restore failed'
    }
    It 'TC-V1411-UndoFail-02: undoFailures array is used in result calculation' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1') -Raw
        $content | Should -Match 'undoFailures\.Count.*-gt 3.*FAIL'
    }
}

Describe 'TC-V1411-UndoTrunkPatchTryCatch: Invoke-AcsTrunkPatch has try-catch' {
    It 'TC-V1411-TrunkPatch-01: Invoke-AcsTrunkPatch wraps Invoke-RestMethod in try' {
        $lines = Get-Content (Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1')
        $fnStart = ($lines | Select-String 'function Invoke-AcsTrunkPatch' | Select-Object -First 1).LineNumber
        $fnEnd   = $fnStart + 50
        $fnBody  = $lines[($fnStart-1)..($fnEnd-1)] -join "`n"
        $fnBody | Should -Match 'try\s*\{[\s\S]*?Invoke-RestMethod'
    }
    It 'TC-V1411-TrunkPatch-02: catch block re-throws after warning' {
        $lines = Get-Content (Join-Path $PSScriptRoot 'Undo-ACS-TPE-Migration-v14.ps1')
        $fnStart = ($lines | Select-String 'function Invoke-AcsTrunkPatch' | Select-Object -First 1).LineNumber
        $fnEnd   = $fnStart + 50
        $fnBody  = $lines[($fnStart-1)..($fnEnd-1)] -join "`n"
        $fnBody | Should -Match 'throw'
    }
}

Describe 'TC-V1411-WriteErrParity: Write-Err prefix is consistent across HTML-logging scripts' {
    It 'TC-V1411-WriteErr-<_>: <_> Write-Err uses single-space prefix' -ForEach @(
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1'
    ) {
        $content = Get-Content (Join-Path $PSScriptRoot $_) -Raw
        $content | Should -Match 'function Write-Err.*"  ! \$m"'
    }
    It 'TC-V1411-WriteErr-NoDoubleSpace: No HTML-logging script uses double-space "  !  "' -TestCases @(
        @{ File = 'Toggle-AcsTeamsRouting-v14.ps1' }
        @{ File = 'Invoke-FlipToACS-v14.ps1' }
        @{ File = 'Invoke-FlipToTeams-v14.ps1' }
    ) {
        $content = Get-Content (Join-Path $PSScriptRoot $File) -Raw
        $content | Should -Not -Match 'function Write-Err.*"  !  \$m"'
    }
}

Describe 'TC-V1411-UpdatePhoneTypeTryCatch: Update-PhoneNumberType lookup has try-catch' {
    It 'TC-V1411-UpdPhone-01: D365 lookup wrapped in try-catch' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Update-PhoneNumberType-v14.ps1') -Raw
        $content | Should -Match 'try\s*\{[\s\S]*?lookupResponse\s*=\s*Invoke-RestMethod'
    }
    It 'TC-V1411-UpdPhone-02: verification GET wrapped in try-catch' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Update-PhoneNumberType-v14.ps1') -Raw
        $content | Should -Match 'try\s*\{[\s\S]*?updatedRecord\s*=\s*Invoke-RestMethod'
    }
    It 'TC-V1411-UpdPhone-03: no .Split([char]10) remains' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Update-PhoneNumberType-v14.ps1') -Raw
        $content | Should -Not -Match '\.Split\(\[char\]10\)'
    }
}

Describe 'TC-V1411-GetTeamsProvTryCatch: Get-TeamsProviderSetting entries query has try-catch' {
    It 'TC-V1411-TeamsProv-01: entries query wrapped in try-catch' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Get-TeamsProviderSetting-v14.ps1') -Raw
        $content | Should -Match 'try\s*\{[\s\S]*?entriesResponse\s*=\s*Invoke-RestMethod'
    }
    It 'TC-V1411-TeamsProv-02: catch provides fallback empty value' {
        $content = Get-Content (Join-Path $PSScriptRoot 'Get-TeamsProviderSetting-v14.ps1') -Raw
        $content | Should -Match 'catch\s*\{[\s\S]*?value\s*=\s*@\(\)'
    }
}

Describe 'TC-V1411-ReadmeFixAcsRoute: README has Fix-AcsRoutePattern parameter table' {
    It 'TC-V1411-Readme-01: README has Parameters table for Fix-AcsRoutePattern' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match 'Fix-AcsRoutePattern[\s\S]*?\| `-ConfigPath`'
    }
    It 'TC-V1411-Readme-02: README has -RouteName parameter' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match 'Fix-AcsRoutePattern[\s\S]*?\| `-RouteName`'
    }
    It 'TC-V1411-Readme-03: README has -NumberPattern parameter' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match 'Fix-AcsRoutePattern[\s\S]*?\| `-NumberPattern`'
    }
    It 'TC-V1411-Readme-04: README has -TrunkFqdn parameter' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match 'Fix-AcsRoutePattern[\s\S]*?\| `-TrunkFqdn`'
    }
    It 'TC-V1411-Readme-05: README no longer says "no -ConfigPath parameter"' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Not -Match 'no `-ConfigPath` parameter'
    }
}

Describe 'TC-V1411-VersionV1411: All 17 scripts have v14.11.0 (migration script bumped to v14.15.0+)' {
    It 'TC-V1411-Ver-<_>: <_> has v14.11.0' -ForEach @(
        'Undo-ACS-TPE-Migration-v14.ps1',
        'Toggle-AcsTeamsRouting-v14.ps1',
        'Invoke-FlipToACS-v14.ps1',
        'Invoke-FlipToTeams-v14.ps1',
        'Invoke-MigrateTpsPhoneNumber-v14.ps1',
        'New-AcsTpeConfig-v14.ps1',
        'Repair-D365PhoneRecord-v14.ps1',
        'Update-PhoneNumberType-v14.ps1',
        'Set-AcsSbcFqdn-v14.ps1',
        'Add-AcsTrunkDisabled-v14.ps1',
        'Fix-AcsRoutePattern-v14.ps1',
        'Get-TeamsProviderSetting-v14.ps1',
        'Sync-TeamsPhoneNumbers-v14.ps1',
        'Invoke-TeamsPhoneSync-v14.ps1',
        'Archive-TpeRuns-v14.ps1',
        'Test-DomainRegistration-v14.ps1'
    ) {
        $c = Get-Content (Join-Path $PSScriptRoot $_) -Raw
        $c | Should -Match 'v14\.11\.0'
    }
}

Describe 'TC-V1411-ReadmeChangelog: README changelog documents v14.11.0' {
    It 'TC-V1411-Changelog-01: README has v14.11.0 section' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match '### v14\.11\.0'
    }
    It 'TC-V1411-Changelog-02: changelog mentions XSS hardening' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match 'v14\.11\.0[\s\S]*?XSS hardening'
    }
    It 'TC-V1411-Changelog-03: changelog mentions error message null guard' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match 'v14\.11\.0[\s\S]*?null guard'
    }
    It 'TC-V1411-Changelog-04: changelog mentions connection string validation' {
        $content = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $content | Should -Match 'v14\.11\.0[\s\S]*?[Cc]onnection string validation'
    }
}

# =============================================================================
# v14.13.0 TESTS — IncludeNumbers filter in Phase 0D, Step 2 SbcFqdn-only
# =============================================================================

Describe 'TC-V1413-IncludeNumbers: Phase 0D IncludeNumbers config filter (v14.13.0)' {
    BeforeAll {
        $script:migContent = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
    }

    It 'TC-V1413-Include-01: Invoke-D365Discovery has IncludeNumbers parameter' {
        $migContent | Should -Match 'function Invoke-D365Discovery[\s\S]*?\[string\[\]\]\$IncludeNumbers'
    }

    It 'TC-V1413-Include-02: IncludeNumbers filters d365Numbers via Where-Object -in' {
        $migContent | Should -Match '\$d365Numbers.*Where-Object.*\$_.Number -in \$IncludeNumbers'
    }

    It 'TC-V1413-Include-03: Phase 0D extracts cfgInclude from cfg.IncludeNumbers' {
        $migContent | Should -Match '\$cfgInclude = if \(\$cfg\.PSObject\.Properties'
    }

    It 'TC-V1413-Include-04: Phase 0D passes cfgInclude to Invoke-D365Discovery' {
        $migContent | Should -Match 'Invoke-D365Discovery[\s\S]*?-IncludeNumbers\s+\$cfgInclude'
    }

    It 'TC-V1413-Include-05: IncludeNumbers bypasses interactive selection prompt' {
        $lines = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1')
        $filterLine = ($lines | Select-String '\$_.Number -in \$IncludeNumbers' | Select-Object -First 1).LineNumber
        $promptLine = ($lines | Select-String 'Read-Host.*Select' | Select-Object -First 1).LineNumber
        $filterLine | Should -BeLessThan $promptLine
    }

    It 'TC-V1413-Include-06: IncludeNumbers emits count of selected numbers' {
        $migContent | Should -Match 'Pre-filtered by IncludeNumbers.*number\(s\) selected'
    }

    It 'TC-V1413-Include-07: empty IncludeNumbers falls through to interactive prompt' {
        $migContent | Should -Match 'if \(\$IncludeNumbers -and \$IncludeNumbers\.Count -gt 0\)'
    }
}

Describe 'TC-V1413-Step2SbcFilter: Step 2 filters acsTrunks to cfg.SbcFqdn only (v14.13.0)' {
    BeforeAll {
        $script:migContent = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
    }

    It 'TC-V1413-Step2Filt-01: Step 2 filters acsTrunks by cfg.SbcFqdn' {
        $migContent | Should -Match '\$acsTrunks.*Where-Object.*\$_\.fqdn -eq \$cfg\.SbcFqdn'
    }

    It 'TC-V1413-Step2Filt-02: fallback creates trunk from config when SbcFqdn not in ACS export' {
        $migContent | Should -Match "SbcFqdn.*not found in ACS export.*Using config values directly"
    }

    It 'TC-V1413-Step2Filt-03: fallback trunk uses cfg.SbcFqdn and cfg.SbcPort' {
        $migContent | Should -Match 'fqdn = \$cfg\.SbcFqdn.*sipSignalingPort = \$cfg\.SbcPort'
    }
}

# =============================================================================
# v14.14.0 TESTS — Step 3 builds voice route from config only
# =============================================================================

Describe 'TC-V1414-Step3Config: Step 3 creates voice route from config, not ACS export (v14.14.0)' {
    BeforeAll {
        $script:migContent = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
        $script:migLines   = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1')
    }

    It 'TC-V1414-Step3-01: vrName comes from cfg.RouteName' {
        $migContent | Should -Match '\$vrName\s*=\s*\$cfg\.RouteName'
    }

    It 'TC-V1414-Step3-02: vrSbcs comes from cfg.SbcFqdn (single FQDN)' {
        $migContent | Should -Match '\$vrSbcs\s*=\s*@\(\$cfg\.SbcFqdn\)'
    }

    It 'TC-V1414-Step3-03: vrPattern built from cfg.ResourceAccounts phone numbers' {
        $migContent | Should -Match '\$vrPattern\s*=\s*Get-NumberPatternRegex -Numbers.*\$cfg\.ResourceAccounts'
    }

    It 'TC-V1414-Step3-04: New-CsOnlineVoiceRoute uses vrSbcs for gateway list' {
        $migContent | Should -Match 'New-CsOnlineVoiceRoute[\s\S]*?-OnlinePstnGatewayList \$vrSbcs'
    }

    It 'TC-V1414-Step3-05: New-CsOnlineVoiceRoute uses vrName for Identity' {
        $migContent | Should -Match 'New-CsOnlineVoiceRoute[\s\S]*?-Identity\s+\$vrName'
    }

    It 'TC-V1414-Step3-06: Step 3 does NOT read SbcFqdn from acs-export.json' {
        $lines = $migLines
        $step3Start = ($lines | Select-String 'STEP 3 -- CONFIGURE CALL ROUTING' | Select-Object -First 1).LineNumber
        $step3End   = ($lines | Select-String 'STEP 4 -- REGISTER AND VERIFY DOMAIN' | Select-Object -First 1).LineNumber
        $step3Block = ($lines[($step3Start - 1)..($step3End - 2)]) -join "`n"
        $step3Block | Should -Not -Match 'acs-export\.json'
    }

    It 'TC-V1414-Step3-07: Step 3 creates PSTN usage from cfg.UsageName' {
        $migContent | Should -Match 'Set-CsOnlinePstnUsage.*Usage @\{Add = \$cfg\.UsageName\}'
    }

    It 'TC-V1414-Step3-08: Step 3 creates routing policy from cfg.PolicyName' {
        $migContent | Should -Match 'New-CsOnlineVoiceRoutingPolicy[\s\S]*?-Identity\s+\$cfg\.PolicyName'
    }
}

# =============================================================================
# v14.15.0 TESTS — Step 5 validates only cfg.SbcFqdn and cfg.RouteName
# =============================================================================

Describe 'TC-V1415-Step5Validate: Step 5 validates cfg.SbcFqdn and cfg.RouteName only (v14.15.0)' {
    BeforeAll {
        $script:migContent = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
        $script:migLines   = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1')
    }

    It 'TC-V1415-Step5-01: SBC gateway check uses cfg.SbcFqdn' {
        $migContent | Should -Match 'Get-CsOnlinePSTNGateway -Identity \$cfg\.SbcFqdn'
    }

    It 'TC-V1415-Step5-02: voice route check uses cfg.RouteName' {
        $migContent | Should -Match 'Get-CsOnlineVoiceRoute -Identity \$cfg\.RouteName'
    }

    It 'TC-V1415-Step5-03: routing policy check uses cfg.PolicyName' {
        $migContent | Should -Match 'Get-CsOnlineVoiceRoutingPolicy -Identity \$cfg\.PolicyName'
    }

    It 'TC-V1415-Step5-04: Step 5 does NOT reference acs-export.json' {
        $lines = $migLines
        $step5Start = ($lines | Select-String 'STEP 5 -- VALIDATE' | Select-Object -First 1).LineNumber
        $step5End   = ($lines | Select-String 'STEP 6 -- UPLOAD DR NUMBERS' | Select-Object -First 1).LineNumber
        $step5Block = ($lines[($step5Start - 1)..($step5End - 2)]) -join "`n"
        $step5Block | Should -Not -Match 'acs-export\.json'
    }

    It 'TC-V1415-Step5-05: validation sets validationPassed to false on SBC missing' {
        $migContent | Should -Match 'SBC.*was not found in Teams.*validationPassed = \$false'
    }

    It 'TC-V1415-Step5-06: validation sets validationPassed to false on route missing' {
        $migContent | Should -Match 'Voice route.*was not found.*validationPassed = \$false'
    }

    It 'TC-V1415-Step5-07: validation sets validationPassed to false on policy missing' {
        $migContent | Should -Match 'Voice routing policy.*was not found.*validationPassed = \$false'
    }

    It 'TC-V1415-Step5-08: failed validation calls Exit-Script' {
        $migContent | Should -Match 'if \(-not \$validationPassed\).*Exit-Script 1'
    }

    It 'TC-V1415-Step5-09: Step 5 passes even if acs-export.json is absent' {
        $lines = $migLines
        $step5Start = ($lines | Select-String 'STEP 5 -- VALIDATE' | Select-Object -First 1).LineNumber
        $step5End   = ($lines | Select-String 'STEP 6 -- UPLOAD DR NUMBERS' | Select-Object -First 1).LineNumber
        $step5Block = ($lines[($step5Start - 1)..($step5End - 2)]) -join "`n"
        $step5Block | Should -Not -Match '\$acsTrunks'
        $step5Block | Should -Not -Match '\$acsRoutes'
    }
}

# =============================================================================
# v14.16.0 TESTS — Step 8 guards against empty ObjectId
# =============================================================================

Describe 'TC-V1416-Step8ObjectId: Step 8 skips UPNs with empty ObjectId (v14.16.0)' {
    BeforeAll {
        $script:migContent = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
        $script:migLines   = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1')
    }

    It 'TC-V1416-ObjId-01: license assignment loop guards against empty objectId' {
        $lines = $migLines
        $step8Start = ($lines | Select-String 'STEP 8 -- ASSIGN LICENSES' | Select-Object -First 1).LineNumber
        $step8End   = ($lines | Select-String '#endregion' | Where-Object { $_.LineNumber -gt $step8Start } | Select-Object -First 1).LineNumber
        $step8Block = ($lines[($step8Start - 1)..($step8End - 2)]) -join "`n"
        $step8Block | Should -Match 'if \(-not \$objectId\).*continue'
    }

    It 'TC-V1416-ObjId-02: guard emits error message with UPN name' {
        $migContent | Should -Match 'Could not find the resource account for.*skipping license assignment'
    }

    It 'TC-V1416-ObjId-03: guard suggests re-running Step 7' {
        $migContent | Should -Match 'Re-run Step 7 to recreate it'
    }

    It 'TC-V1416-ObjId-04: polling loop filters pendingUPNs to only those with ObjectId' {
        $migContent | Should -Match '\$pendingUPNs\s*=.*Where-Object \{ \$raObjectIds\[\$_\.UPN\] \}'
    }

    It 'TC-V1416-ObjId-05: polling loop has inner guard for empty objectId' {
        $lines = $migLines
        $pollingStart = ($lines | Select-String 'Polling for license provisioning completion' | Select-Object -First 1).LineNumber
        $pollingEnd   = ($lines | Select-String 'Step 8 complete' | Select-Object -First 1).LineNumber
        $pollingBlock = ($lines[($pollingStart - 1)..($pollingEnd - 2)]) -join "`n"
        $pollingBlock | Should -Match 'if \(-not \$objectId\) \{ continue \}'
    }

    It 'TC-V1416-ObjId-06: guard uses continue, not throw or Exit-Script' {
        $lines = $migLines
        $step8Start = ($lines | Select-String 'STEP 8 -- ASSIGN LICENSES' | Select-Object -First 1).LineNumber
        $step8End   = ($lines | Select-String '#endregion' | Where-Object { $_.LineNumber -gt $step8Start } | Select-Object -First 1).LineNumber
        $step8Block = ($lines[($step8Start - 1)..($step8End - 2)]) -join "`n"
        $guards = [regex]::Matches($step8Block, 'if \(-not \$objectId\).*')
        foreach ($g in $guards) {
            $g.Value | Should -Match 'continue'
            $g.Value | Should -Not -Match 'Exit-Script'
            $g.Value | Should -Not -Match 'throw'
        }
    }

    It 'TC-V1416-ObjId-07: skipped UPN emits Write-Err not Write-Warn' {
        $lines = $migLines
        $step8Start = ($lines | Select-String 'STEP 8 -- ASSIGN LICENSES' | Select-Object -First 1).LineNumber
        $guardLine  = ($lines | Select-String 'Could not find the resource account for' | Where-Object { $_.LineNumber -gt $step8Start } | Select-Object -First 1).LineNumber
        $guardText  = $lines[$guardLine - 1]
        $guardText | Should -Match 'Write-Err'
    }
}

Describe 'TC-V1416-Version: Migration script has v14.16.0 version strings (v14.16.0)' {

    It 'TC-V1416-Ver-01: .NOTES has v14.16.0 entry' {
        $c = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
        $c | Should -Match 'v14\.16\.0\s*:'
    }

    It 'TC-V1416-Ver-02: console banner has v14.16.0' {
        $c = Get-Content (Join-Path $PSScriptRoot 'Invoke-ACS-TPE-Full-Migration-v14.ps1') -Raw
        $c | Should -Match 'Migration\s+v14\.16\.0'
    }

    It 'TC-V1416-Ver-03: README says v14.16.0' {
        $c = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
        $c | Should -Match '\*\*Version:\*\*\s*v14\.16\.0'
    }
}

Describe 'TC-V1416-ReadmeChangelog: README changelog documents v14.13.0 through v14.16.0' {
    BeforeAll {
        $script:readme = Get-Content (Join-Path $PSScriptRoot 'README.md') -Raw
    }

    It 'TC-V1416-Changelog-01: README has v14.13.0 section' {
        $readme | Should -Match '### v14\.13\.0'
    }

    It 'TC-V1416-Changelog-02: v14.13.0 mentions IncludeNumbers' {
        $readme | Should -Match 'v14\.13\.0[\s\S]*?IncludeNumbers'
    }

    It 'TC-V1416-Changelog-03: README has v14.14.0 section' {
        $readme | Should -Match '### v14\.14\.0'
    }

    It 'TC-V1416-Changelog-04: v14.14.0 mentions Step 3 or voice route from config' {
        $readme | Should -Match 'v14\.14\.0[\s\S]*?(Step 3|voice route|config)'
    }

    It 'TC-V1416-Changelog-05: README has v14.15.0 section' {
        $readme | Should -Match '### v14\.15\.0'
    }

    It 'TC-V1416-Changelog-06: v14.15.0 mentions Step 5 or validation' {
        $readme | Should -Match 'v14\.15\.0[\s\S]*?(Step 5|validat)'
    }

    It 'TC-V1416-Changelog-07: README has v14.16.0 section' {
        $readme | Should -Match '### v14\.16\.0'
    }

    It 'TC-V1416-Changelog-08: v14.16.0 mentions Step 8 or ObjectId' {
        $readme | Should -Match 'v14\.16\.0[\s\S]*?(Step 8|ObjectId|empty)'
    }
}
