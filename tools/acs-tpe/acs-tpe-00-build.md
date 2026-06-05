0a. Study specs/* to learn about the ACS-TPE migration tool specifications.

0b. The 18 PowerShell scripts are in the current directory (samples/acs-tpe/).

0c. Study fix_plan.md for known issues and in-progress work.

0d. The test suite is Test-ACS-TPE-Migration-v14.Tests.ps1 (501+ Pester tests).

1. Your task is to improve the ACS-TPE migration scripts (see @specs/*) using parallel subagents where possible. **IMPORTANT: If fix_plan.md has any open items (unchecked `- [ ]` lines), you MUST work on those first and complete them before doing anything else. Only after all fix_plan.md items are resolved may you choose other improvements.** Before making changes, search the scripts (don't assume something is missing or broken without reading the code first). Use up to 3 parallel subagents for investigation but only 1 subagent for running tests.

2. After implementing a fix or feature, run the Pester tests for the affected scripts:
   ```powershell
   Invoke-Pester ./Test-ACS-TPE-Migration-v14.Tests.ps1 -Output Detailed
   ```
   If a test is missing for new functionality, add it. Tests must use mocked dependencies — no live ACS/Teams/D365 calls.

3. When you discover a bug, validate logic error, or edge-case gap, immediately update @fix_plan.md using a subagent. When resolved, remove from fix_plan.md using a subagent.

4. When tests pass:
   - Update @fix_plan.md to mark the item resolved (subagent)
   - `git add` the changed scripts and test file
   - `git commit` with message describing what changed and why
   - Push unless no remote is configured
   - Do NOT bump the version or create a tag on every commit — see rule 5

5. Version bumping and tagging — only when a bug is fixed or the test count increases:
   - Increment the patch version (e.g. 14.16.0 → 14.16.1) across all 18 scripts:
     - Update `$scriptVersion` constant in every script
     - Update the console banner in every script
     - Add a .NOTES changelog entry in Invoke-ACS-TPE-Full-Migration-v14.ps1
   - Create a git tag: `git tag acs-tpe-vX.Y.Z`
   - Do NOT bump the version for refactors, comment changes, or spec/doc-only commits

6. DryRun requirement: every code path that calls a mutating API or writes a file must be guarded by `if (-not $DryRun)`. Dry run must produce identical console output without side effects.

7. HTML safety: any user-supplied string (phone numbers, FQDNs, URLs, names) embedded into HTML must be escaped with `-replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'`.

8. Keep @fix_plan.md up to date after every turn using a subagent — especially when wrapping up.

9. Keep @specs/* accurate. If you discover that a spec document does not match the actual script behavior, update the spec using a subagent.

10. IMPORTANT: Do not implement placeholder or stub implementations. Every feature must be fully implemented and tested.

11. IMPORTANT: Single source of truth — do not duplicate logic across scripts. Shared helper functions (Write-Ok, Write-Err, Write-Warn, Exit-Script, Test-E164Format, Write-TpeRunRecord) must remain centralized within each script that uses them.

12. When you discover a new test gap, add tests before fixing the bug (TDD). Tests must cover both the happy path and the failure/edge case.

13. ALWAYS keep @fix_plan.md up to date with your learnings using a subagent, especially after wrapping up.
