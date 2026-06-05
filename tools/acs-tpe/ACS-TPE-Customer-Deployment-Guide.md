# ACS to Teams Phone Extensibility (TPE) — Customer Deployment Guide

**Version:** v14.18.0  
**Audience:** IT Administrators deploying ACS-TPE migration in a production Dynamics 365 environment  
**Support:** Contact your Microsoft representative for assistance

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Package Contents](#3-package-contents)
4. [Prerequisites](#4-prerequisites)
5. [Configuration Setup](#5-configuration-setup)
6. [Migration Walkthrough — Step by Step](#6-migration-walkthrough--step-by-step)
7. [Post-Migration: Flip Between ACS and Teams](#7-post-migration-flip-between-acs-and-teams)
8. [Undo / Full Rollback](#8-undo--full-rollback)
9. [Generated Files Reference](#9-generated-files-reference)
10. [Troubleshooting](#10-troubleshooting)
11. [Quick Reference Card](#11-quick-reference-card)

---

## 1. Overview

This package automates the migration of phone numbers from **Azure Communication Services (ACS) Direct Routing** to **Microsoft Teams Phone Extensibility (TPE)** — also known as Teams Direct Routing — for organizations running Dynamics 365 Customer Service contact centers.

### What it does

- Migrates your ACS Direct Routing phone numbers to Teams Phone System (Teams Direct Routing)
- Creates Teams Resource Accounts and links them to Dynamics 365 CCaaS phone number records
- Performs the cutover with **zero call disruption** — ACS remains active while Teams is being prepared
- Provides full rollback capability at every stage

### What stays the same

- Your SBC (Session Border Controller) FQDN — the same SBC serves both ACS and Teams
- Your Dynamics 365 environment and contact center configuration
- Your phone numbers — only the routing path changes

### Key principle: Zero-downtime cutover

The migration is designed so ACS stays active throughout all preparation steps (Steps 1–9). The actual cutover — when calls switch from ACS to Teams — happens only at **Step 10**, which you control. You can also flip back to ACS at any time using the provided scripts.

---

## 2. Architecture

### System Overview

```
Before Migration                        After Migration
─────────────────────────────           ─────────────────────────────
Phone Number → ACS Direct Routing  →   Phone Number → Teams Direct Routing
              ↓                                        ↓
              SBC                                      SBC (same FQDN)
              ↓                                        ↓
              Dynamics 365 CCaaS                       Dynamics 365 CCaaS
              (type = ACS)                             (type = Teams Phone System)
```

### Script Dependency Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR SCRIPTS                             │
│                                                                     │
│  Invoke-ACS-TPE-Full-Migration-v14.ps1   ←  Full 11-step migration │
│  Invoke-FlipToTeams-v14.ps1              ←  Re-migrate ACS → Teams │
│  Invoke-FlipToACS-v14.ps1               ←  Rollback Teams → ACS   │
│  Undo-ACS-TPE-Migration-v14.ps1         ←  Full undo (all steps)  │
└────────────────────┬────────────────────────────────────┬───────────┘
                     │ calls                              │ calls
                     ▼                                    ▼
       Toggle-AcsTeamsRouting-v14.ps1      Invoke-MigrateTpsPhoneNumber-v14.ps1
       (switches SIP routing direction)    (updates D365 phone type per number)
```

### Migration Timeline

```
Phase 0 ──► Step 1 ──► Step 2 ──► Step 3 ──► Step 4 ──► Step 5
 Config     Export     Create     Configure   Register   Validate
 & Auth     ACS        SBC in     Call        Domain     Config
            Config     Teams      Routing     in Entra

  ◄── ACS ACTIVE throughout Steps 1–9, taking production calls ──►

Step 6 ──► Step 7 ──► Step 8 ──► Step 9 ──► Step 10 ──► Step 11
Upload     Create     Assign     Assign      CUTOVER     Update
DR Phone   Resource   Licenses   Numbers     ACS→Teams   D365
Numbers    Accounts   to RAs     to RAs      (5-10s)     Phone Types

                                             ▲
                                    You control this moment
```

### Files Produced During Migration

| File | Created at | Purpose |
|------|-----------|---------|
| `acs-export.json` | Step 1 | Snapshot of ACS SIP trunks and routes |
| `acs-trunk-disabled.json` | Step 2 | Tracks which SBC FQDNs were temporarily disabled |
| `ra-objectids.json` | Step 7 | Maps Resource Account UPNs to Entra ObjectIds |
| `d365-phone-backup.json` | Step 9 | Backup of D365 phone records before migration |
| `tpe-migration-results.csv` | Step 9 | Summary of assignment results per number |
| `tpe-migration-run-*.html` | Every run | Full color-coded HTML log |
| `tpe-status.html` | Every run | Live migration status dashboard |
| `stats/tpe-runs.jsonl` | Every run | Machine-readable run history |

> **Important:** Keep all generated JSON files. They are required for rollback.

---

## 3. Package Contents

```
acs-tpe-package/
├── Invoke-ACS-TPE-Full-Migration-v14.ps1   ← Main migration (run this first)
├── Invoke-FlipToACS-v14.ps1                ← Roll back routing: Teams → ACS
├── Invoke-FlipToTeams-v14.ps1              ← Re-migrate routing: ACS → Teams
├── Undo-ACS-TPE-Migration-v14.ps1          ← Full undo: removes all Teams objects
├── Toggle-AcsTeamsRouting-v14.ps1          ← Shared: switches SIP routing direction
├── Invoke-MigrateTpsPhoneNumber-v14.ps1    ← Shared: updates D365 phone type
└── acs-tpe-config-template.json            ← Configuration template (fill in your values)
```

All 6 scripts must be in the **same directory**. The two shared scripts (Toggle, MigrateTpsPhoneNumber) are called automatically — you do not run them directly.

---

## 4. Prerequisites

### 4.1 Software Requirements

| Requirement | Version | Install |
|-------------|---------|---------|
| Windows PowerShell | 5.1+ | Built into Windows |
| MicrosoftTeams module | Latest | `Install-Module MicrosoftTeams -Scope CurrentUser -Force` |
| Microsoft.Graph module | Latest | `Install-Module Microsoft.Graph -Scope CurrentUser -Force` |
| ExchangeOnlineManagement | Latest | `Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force` |
| Azure CLI (`az`) | Latest | https://aka.ms/installazurecliwindows |

### 4.2 Azure CLI Login

Before running any script, log in to Azure CLI with your admin account:

```powershell
az login
az account set --subscription "<Your-Azure-Subscription-ID>"
```

Verify you are logged in to the correct tenant:

```powershell
az account show
```

### 4.3 Required Permissions

Your admin account must have **all** of the following roles:

| Role | System | Required For |
|------|--------|-------------|
| Teams Administrator | Microsoft Teams | All Teams Direct Routing operations (Steps 2, 3, 5, 6, 9, 10) |
| **User Administrator** | Microsoft Entra ID | Creating Resource Accounts (Step 7) — Teams Admin alone is NOT sufficient |
| Global Admin or Domain Administrator | Microsoft Entra ID | Registering the custom domain (Step 4) |
| License Administrator | Microsoft 365 | Assigning PHONESYSTEM_VIRTUALUSER licenses (Step 8) |
| System Administrator | Dynamics 365 | Querying and updating D365 phone records (Phase 0D, Steps 9, 11) |
| Owner or Contributor | Azure Communication Services resource | Reading and patching ACS SIP trunks (Steps 1, 2, 10) |

> **Critical:** If Step 7 fails with `"user not authorized"`, your admin account is missing the **User Administrator** role in Entra ID. Add it in the Microsoft Entra ID portal → Roles and administrators → User Administrator, then resume from Step 7.

### 4.4 License Availability

The migration creates one **PHONESYSTEM_VIRTUALUSER** (Teams Phone Resource Account) license per phone number. Verify your tenant has sufficient available licenses before starting:

```powershell
Connect-MicrosoftTeams -TenantId "<Your-Tenant-ID>"
Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER' } |
    Select-Object SkuPartNumber, @{N='Available';E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}
```

### 4.5 DNS Requirement (Step 4)

The migration registers a **custom domain** in Microsoft Entra ID for Resource Account UPNs. You need:

- A domain name you control (e.g., `tpe.contoso.com`)
- The ability to add a DNS TXT record at your DNS registrar during Step 4
- DNS propagation typically takes 5–30 minutes

---

## 5. Configuration Setup

### 5.1 Copy and Edit the Config Template

Copy `acs-tpe-config-template.json` to a local file and fill in your organization's values:

```powershell
Copy-Item .\acs-tpe-config-template.json .\my-org-config.json
notepad .\my-org-config.json
```

### 5.2 Config Field Reference

```jsonc
{
  "TenantId":           "<Your Microsoft Entra ID Tenant ID (GUID)>",
  "AdminUpn":           "<Your Teams/Graph Admin UPN, e.g. admin@contoso.onmicrosoft.com>",
  "Domain":             "<Domain for Resource Account UPNs, e.g. tpe.contoso.com>",
  "DynamicsAppId":      "<D365 App Registration Client ID (GUID)>",
  "D365OrgUrl":         "<Your D365 Org URL, e.g. https://contoso.crm.dynamics.com/>",
  "RaPrefix":           "acs-tpe-ra-<phonenumber>",
  "AcsSubscriptionId":  "<Azure Subscription ID (GUID) hosting your ACS resource>",
  "AcsResourceId":      "<ACS Resource ID (GUID) from D365 CSAC provider setting>",
  "AcsEndpoint":        "<ACS Endpoint URL, e.g. https://contoso.unitedstates.communication.azure.com/>",
  "AcsConnectionString":"endpoint=https://...;accesskey=<your-base64-access-key>",
  "SbcFqdn":            "<Your SBC FQDN, e.g. sbc.contoso.com>",
  "SbcPort":            5061,
  "PolicyName":         "acs-tpe-migration",
  "UsageName":          "acs-tpe-pstn-usage",
  "RouteName":          "acs-tpe-voice-route",
  "CommsProviderId":    "<D365 Communications Provider Setting ID (GUID)>",
  "IncludeNumbers":     [],
  "ResourceAccounts":   []
}
```

### 5.3 Where to Find Each Value

| Field | Where to Find |
|-------|--------------|
| `TenantId` | Azure Portal → Microsoft Entra ID → Overview → Tenant ID |
| `AdminUpn` | Your admin account sign-in name |
| `Domain` | A domain you own and can add DNS records to |
| `DynamicsAppId` | D365 CSAC → Settings → Channels → Phone numbers → Advanced → App ID |
| `D365OrgUrl` | Your D365 browser URL root (e.g., `https://org.crm.dynamics.com/`) |
| `AcsSubscriptionId` | Azure Portal → Subscriptions |
| `AcsResourceId` | D365 CSAC → Settings → Channels → Manage telephony → Azure Communication Services resource ID |
| `AcsEndpoint` | Azure Portal → Your ACS resource → Keys → Endpoint |
| `AcsConnectionString` | Azure Portal → Your ACS resource → Keys → Connection string |
| `SbcFqdn` | Your SBC configuration / Azure Portal → ACS Direct Routing |
| `SbcPort` | Typically `5063` for ACS DR, `5061` for Teams DR |
| `CommsProviderId` | D365 CSAC → Manage telephony → inspect network calls during "Sync from Azure" |

### 5.4 Optional: Specify Phone Numbers in Advance

To skip the interactive phone number selection prompt during migration, pre-populate `IncludeNumbers`:

```json
"IncludeNumbers": ["+12065550100", "+12065550101", "+12065550102"]
```

Leave as `[]` to use the interactive selection during the run.

### 5.5 Security Note

`AcsConnectionString` contains an ACS access key. **Do not** commit this file to source control. If running in a shared environment, the migration script re-prompts for the connection string on every resumed run rather than saving it.

---

## 6. Migration Walkthrough — Step by Step

### 6.1 Always Do a Dry Run First

Before running any live changes, validate your config with a dry run:

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -DryRun
```

A dry run shows exactly what each step will do without making any changes. Review the output HTML log for your records.

### 6.2 Full Migration

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json
```

The script will prompt you to confirm before making live changes. Type **Y** and press Enter to proceed.

### 6.3 What Happens at Each Step

#### Phase 0 — Setup and Discovery
The script loads your config, installs PowerShell modules if needed, connects to Teams and Microsoft Graph, and verifies you have enough PHONESYSTEM_VIRTUALUSER licenses. It then queries Dynamics 365 to discover your active ACS phone numbers and presents them for selection.

**At this point, ACS is still fully active. No changes have been made.**

---

#### Step 1 — Export ACS Configuration
Exports your current ACS SIP trunks and voice routes to `acs-export.json`. This file is used by the rollback process to restore ACS exactly as it was.

**Output:** `acs-export.json`

---

#### Step 2 — Register SBC in Teams (Zero-Downtime)
Creates the Teams Direct Routing gateway for your SBC. To satisfy a Teams uniqueness constraint, the ACS trunk is briefly disabled (~5–10 seconds) while the gateway is created, then immediately re-enabled. ACS call interruption is minimal.

**Output:** `acs-trunk-disabled.json`  
**Teams change:** Adds an inactive (disabled) PSTN gateway

---

#### Step 3 — Configure Teams Call Routing
Creates the Teams voice routing infrastructure:
- PSTN Usage record
- Voice Route (maps your phone number patterns to the SBC gateway)
- Voice Routing Policy (assigns the usage and route)

**Teams changes:** Adds PSTN usage, voice route, and voice routing policy

---

#### Step 4 — Register Domain in Entra ID
Registers your chosen domain (e.g., `tpe.contoso.com`) in Microsoft Entra ID so that Resource Account UPNs can use it.

**You will be prompted to add a DNS TXT verification record.** The script polls for up to 5 minutes for propagation.

**Entra change:** Adds a verified domain

---

#### Step 5 — Validate Configuration
Reads back all Teams objects created in Steps 2–4 and confirms they exist. Hard-exits if anything is missing, allowing you to fix the issue before proceeding.

---

#### Step 6 — Upload Phone Numbers to Teams
Uploads each phone number to Teams as a Direct Routing number so it can be assigned to Resource Accounts in Step 9.

**Teams change:** Adds unassigned Direct Routing phone numbers

---

#### Step 7 — Create Resource Accounts
Creates one Teams Resource Account per phone number in the format:  
`acs-tpe-ra-<digits>@<your-domain>`

Each RA is stamped with your DynamicsAppId and AcsResourceId to link it to the Dynamics 365 contact center application.

**Output:** `ra-objectids.json` (stores the ObjectId of each RA — required for rollback)  
**Entra change:** Creates user objects for each RA  
**Teams change:** Stamps each RA with application identity

---

#### Step 8 — Assign Licenses
Assigns the **PHONESYSTEM_VIRTUALUSER** license to each Resource Account. The script waits up to 5 minutes for each license to provision before proceeding.

**M365 change:** License assigned to each RA

---

#### Step 9 — Assign Phone Numbers and Back Up D365
Assigns each phone number to its Resource Account in Teams, then backs up Dynamics 365 phone records and triggers the CCaaS sync.

**Output:** `d365-phone-backup.json`, `tpe-migration-results.csv`  
**Teams change:** Phone numbers assigned to RAs  
**D365 change:** `msdyn_teamsresourceaccount` linked; CCaaS sync triggered

**At this point, all Teams preparation is complete. ACS is still active.**

---

#### Step 10 — Cutover (ACS → Teams)
**This is the moment calls switch from ACS to Teams.** The script:
1. Disables the ACS SIP trunk
2. Enables the Teams Direct Routing gateway

The transition is near-instantaneous. In-progress calls are not interrupted; only new incoming calls route via Teams after this point.

**You will be prompted to confirm before proceeding.**

---

#### Step 11 — Update Dynamics 365 Phone Types
Updates each phone number record in D365 from ACS type to Teams Phone System type, and triggers an async CCaaS synchronization. This makes the change visible in D365 Customer Service Admin Center.

Allow **2–3 minutes** for the async sync to reflect in the D365 UI.

---

### 6.4 Resuming After a Failure

If the migration fails partway through, you can resume from where it stopped:

```powershell
# Resume from Step 7 onward (skip Steps 1–6 which already completed)
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 7

# Run only a specific step
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 4 -StopAfterStep 4
```

> **Note:** If resuming from Step 2 or later, `acs-export.json` must be present. If resuming from Step 8 or later, `ra-objectids.json` must be present.

### 6.5 Limiting to Specific Phone Numbers

To migrate only a subset of numbers:

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json `
    -StartAtStep 6 -StopAfterStep 11
```

Or set `IncludeNumbers` in the config file before running.

---

## 7. Post-Migration: Flip Between ACS and Teams

After migration completes, you can switch routing back and forth between ACS and Teams **without re-running the full migration**.

### 7.1 Flip Routing Back to ACS (Rollback Routing Only)

Use this when you want to revert call routing to ACS — for example, if you discover an issue after cutover. This does **not** remove any Teams objects; it simply switches routing back.

```powershell
# Dry run first
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-org-config.json -DryRun

# Execute
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-org-config.json
```

**What it does:**
- Step A: Switches routing back to ACS (re-enables ACS trunk, disables Teams gateway)
- Step B: Removes phone number assignments from Teams Resource Accounts
- Step C: Updates D365 phone type back to ACS

### 7.2 Flip Routing Back to Teams

Use this to re-cut over to Teams after a routing rollback.

```powershell
# Dry run first
.\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\my-org-config.json -DryRun

# Execute
.\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\my-org-config.json
```

**What it does:**
- Step A: Assigns phone numbers back to Teams Resource Accounts
- Step B: Switches routing to Teams (enables Teams gateway, disables ACS trunk)
- Step C: Updates D365 phone type to Teams Phone System

### 7.3 Toggle Routing Only (No D365 Update)

If you need to flip SIP routing only — without updating D365 phone types — use the Toggle script directly. It auto-detects the current direction and flips it:

```powershell
.\Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath .\my-org-config.json -DryRun
.\Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath .\my-org-config.json
```

---

## 8. Undo / Full Rollback

The Undo script **completely reverses the migration** — it removes all Teams objects created during the migration and restores ACS to its original state. Use this if you need to start over or fully decommission the Teams configuration.

> **Warning:** Undo deletes Teams Resource Accounts, removes phone number assignments, and removes the voice routing configuration. This is destructive and should be used only when a full teardown is required.

### 8.1 Prerequisites for Undo

The following files must be present (generated during the original migration):

| File | Generated at |
|------|-------------|
| `my-org-config.json` | Your config file |
| `acs-export.json` | Step 1 |
| `acs-trunk-disabled.json` | Step 2 |
| `ra-objectids.json` | Step 7 |
| `d365-phone-backup.json` | Step 9 |

### 8.2 Running Undo

```powershell
# Dry run first — shows exactly what will be removed
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\my-org-config.json -DryRun

# Full undo (prompts for YES confirmation before proceeding)
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\my-org-config.json
```

### 8.3 What Gets Undone (in reverse order)

| Undo Step | Reverses | What Happens |
|-----------|---------|--------------|
| 9 | Step 9 | Removes phone number assignments from Teams RAs; restores D365 phone records from `d365-phone-backup.json` |
| 8 | Step 8 | Removes PHONESYSTEM_VIRTUALUSER licenses from all RAs |
| 7 | Step 7 | Deletes all Resource Accounts from Entra ID |
| 6 | Step 6 | Removes Direct Routing phone numbers from Teams |
| 4 | Step 4 | Removes the custom domain from Entra ID (requires typing **DELETE** to confirm) |
| 3 | Step 3 | Removes voice routing policy, voice route, and PSTN usage |
| 2 | Step 2 | Removes Teams PSTN gateway; **re-enables ACS trunk** with original routes |
| 1 | Step 1 | Archives `acs-export.json` (file is kept for reference, not deleted) |

> Steps 5, 10, and 11 have no undo action. Step 10/11 are reversed by `Invoke-FlipToACS-v14.ps1`.

### 8.4 Partial Undo

You can undo a specific range of steps:

```powershell
# Undo only Steps 9 and 8 (phone assignment and license removal)
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 9 -StopAfterStep 8

# Undo only Step 9
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 9 -StopAfterStep 9
```

### 8.5 Per-Step Confirmation

By default, Undo prompts before each individual step with `[Y] Proceed  [S] Skip  [Q] Quit`. To bypass these prompts:

```powershell
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\my-org-config.json -AutoConfirm
```

---

## 9. Generated Files Reference

These files are created automatically during migration. **Do not delete them** until you are sure the migration is permanent and rollback is no longer needed.

| File | Created by | Required for | Safe to delete after |
|------|-----------|-------------|----------------------|
| `acs-export.json` | Step 1 | Toggle rollback, Undo Step 2 | Migration is permanent and fully verified |
| `acs-trunk-disabled.json` | Step 2 | Undo Step 2 (ACS re-enable) | Migration is permanent |
| `ra-objectids.json` | Step 7 | FlipToACS, FlipToTeams, Undo Steps 7–9 | Migration is permanent |
| `d365-phone-backup.json` | Step 9 | Undo Step 9 (D365 restore) | Migration is permanent |
| `tpe-migration-results.csv` | Step 9 | Reference only | Any time |
| `tpe-migration-run-*.html` | Every run | Reference / audit | Any time (use `Archive-TpeRuns-v14.ps1` to archive) |
| `tpe-status.html` | Every run | Live dashboard | Any time |
| `stats/tpe-runs.jsonl` | Every run | Dashboard history | Any time |

---

## 10. Troubleshooting

### Step 2 fails: "Gateway already exists"

The Teams PSTN gateway already exists from a previous run. Resume from Step 3:

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 3
```

### Step 4 fails: "Domain is already registered"

The domain was already verified in a previous run. Resume from Step 5:

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 5
```

### Step 7 fails: "user not authorized" creating Resource Account

Your admin account is missing the **User Administrator** role in Microsoft Entra ID. Add it in the Entra ID portal, wait 5 minutes for propagation, then resume:

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 7
```

### Step 8 fails: "PHONESYSTEM_VIRTUALUSER: insufficient licenses"

Your tenant does not have enough PHONESYSTEM_VIRTUALUSER licenses. Purchase additional licenses in Microsoft 365 Admin Center, then resume from Step 8.

### Step 9: Numbers in "InProgress" status

The license has not propagated yet. Wait 5–10 minutes and resume from Step 9:

```powershell
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep 9
```

### Step 10: Toggle fails — "Neither side is active"

Both the ACS trunk and Teams gateway are in an unknown state. Run Toggle with DryRun to inspect:

```powershell
.\Toggle-AcsTeamsRouting-v14.ps1 -ConfigPath .\my-org-config.json -DryRun
```

Then check the ACS portal and Teams Admin Center to determine current state and re-enable the correct side manually.

### D365 phone numbers not appearing in CSAC after Step 11

The async CCaaS sync takes 2–3 minutes. Refresh the D365 CSAC browser tab (Ctrl+Shift+R). If numbers still don't appear after 5 minutes, click **Sync from Azure** manually in the Manage Telephony panel.

### ACS connection string missing on resume

The ACS connection string is never saved to disk for security. On resume, the script will prompt you to enter it. Find it in Azure Portal → your ACS resource → Keys → Connection string.

---

## 11. Quick Reference Card

### First-time migration

```powershell
# 1. Install modules (once)
Install-Module MicrosoftTeams -Scope CurrentUser -Force
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# 2. Log in to Azure CLI
az login

# 3. Copy and fill in config
Copy-Item .\acs-tpe-config-template.json .\my-org-config.json
# Edit my-org-config.json with your values

# 4. Dry run (validate)
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -DryRun

# 5. Run migration
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json
```

### Routing rollback (keep Teams objects, just switch routing back to ACS)

```powershell
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-org-config.json -DryRun
.\Invoke-FlipToACS-v14.ps1 -ConfigPath .\my-org-config.json
```

### Re-cut over to Teams

```powershell
.\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\my-org-config.json -DryRun
.\Invoke-FlipToTeams-v14.ps1 -ConfigPath .\my-org-config.json
```

### Full undo (remove everything)

```powershell
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\my-org-config.json -DryRun
.\Undo-ACS-TPE-Migration-v14.ps1 -ConfigPath .\my-org-config.json
```

### Resume after failure

```powershell
# Replace N with the step number to resume from
.\Invoke-ACS-TPE-Full-Migration-v14.ps1 -ConfigPath .\my-org-config.json -StartAtStep N
```

### View migration status dashboard

```powershell
Start-Process .\tpe-status.html
```

### Archive old run logs

```powershell
.\Archive-TpeRuns-v14.ps1 -DryRun  # preview
.\Archive-TpeRuns-v14.ps1          # archive
```

---

*ACS-TPE Migration Suite v14.18.0 — Generated by Microsoft with AI assistance. Always run with -DryRun first and validate output before running live in production.*
