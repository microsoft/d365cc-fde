# Configuration

## Overview

All ACS-TPE scripts are driven by a single JSON configuration file. The file is built interactively by `New-AcsTpeConfig-v14.ps1` or produced by Phase 0D discovery and saved by the orchestrator. Scripts load the config with `-ConfigPath <path>`.

## Config JSON Schema

### Orchestrator Config (loaded by `-ConfigPath`)

```json
{
  "TenantId":            "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "AdminUpn":            "admin@tenant.onmicrosoft.com",
  "AcsConnectionString": "endpoint=https://xxx.communication.azure.com/;accesskey=BASE64==",
  "D365OrgUrl":          "https://tenant.crm.dynamics.com/",
  "SbcFqdn":             "sip-eastus-yt-00.staging.ivr.nuance.com",
  "RouteName":           "acs-tpe-voice-route",
  "PstnUsageName":       "acs-tpe-pstn-usage",
  "RoutingPolicyName":   "acs-tpe-migration",
  "CommsProviderId":     "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "IncludeNumbers":      ["+12202140029"],
  "ResourceAccounts": [
    {
      "UPN":         "ra_12202140029@tenant.onmicrosoft.com",
      "PhoneNumber": "+12202140029",
      "DisplayName": "TPE RA +12202140029",
      "ObjectId":    ""
    }
  ]
}
```

### New-AcsTpeConfig Output (auto-discovery config)

`New-AcsTpeConfig-v14.ps1` generates a superset of the orchestrator config with additional auto-discovered fields:

```json
{
  "_help": {
    "TenantId":            "Entra ID tenant GUID",
    "AdminUpn":            "Teams admin UPN for Connect-MicrosoftTeams",
    "Domain":              "Custom domain for RA UPNs",
    "DynamicsAppId":       "D365 App Registration Client ID (from provider setting entry)",
    "D365OrgUrl":          "Dynamics 365 org URL",
    "RaPrefix":            "Resource Account name prefix template",
    "AcsSubscriptionId":   "Azure subscription containing the ACS resource",
    "AcsResourceId":       "Azure resource ID of the ACS resource (immutable ID from D365)",
    "AcsEndpoint":         "ACS resource hostname",
    "AcsConnectionString": "endpoint=...;accesskey=...",
    "SbcFqdn":             "SBC FQDN discovered from ACS SIP trunks",
    "SbcPort":             "SBC SIP signaling port",
    "PolicyName":          "Teams Voice Routing Policy name",
    "UsageName":           "Teams PSTN Usage name",
    "RouteName":           "Teams Voice Route name",
    "CommsProviderId":     "Teams communication provider setting ID",
    "ResourceAccounts":    "Auto-populated by Phase 0D"
  },
  "TenantId":            "",
  "AdminUpn":            "",
  "Domain":              "",
  "DynamicsAppId":       "",
  "D365OrgUrl":          "",
  "RaPrefix":            "acs-tpe-ra-<phonenumber>",
  "AcsSubscriptionId":   "",
  "AcsResourceId":       "",
  "AcsEndpoint":         "",
  "AcsConnectionString": "",
  "SbcFqdn":             "",
  "SbcPort":             0,
  "PolicyName":          "acs-tpe-migration",
  "UsageName":           "acs-tpe-pstn-usage",
  "RouteName":           "acs-tpe-voice-route",
  "CommsProviderId":     "",
  "ResourceAccounts":    []
}
```

The `_help` object is embedded in the output for self-documentation. It is ignored by all scripts that load config.

## Field Reference

### Required Fields (Orchestrator)

| Field | Type | Description |
|-------|------|-------------|
| `TenantId` | string (GUID) | Entra ID tenant ID; used for Teams and Graph authentication |
| `AdminUpn` | string | Teams admin UPN; used for Teams module connection |
| `AcsConnectionString` | string | ACS connection string; format: `endpoint=https://...;accesskey=...` |
| `D365OrgUrl` | string | D365 organization URL; format: `https://<org>.crm.dynamics.com/` |
| `SbcFqdn` | string | Shared SBC FQDN; registered in both ACS and Teams |
| `RouteName` | string | Teams voice route name to create/validate |
| `CommsProviderId` | string (GUID) | Teams communications provider setting ID (from D365 or Get-TeamsProviderSetting) |
| `ResourceAccounts` | array | List of resource account objects (see below) |

### Optional Fields (with defaults)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `PstnUsageName` | string | `acs-tpe-pstn-usage` | PSTN usage name to create in Teams |
| `RoutingPolicyName` | string | `acs-tpe-migration` | Voice routing policy name to create |
| `IncludeNumbers` | string[] | `[]` | E.164 phone numbers to migrate; empty = interactive prompt |

### Auto-Discovered Fields (New-AcsTpeConfig output)

These fields are populated by `New-AcsTpeConfig-v14.ps1` during its discovery flow (see note on 8-phase implementation in [Architecture Overview](architecture-overview.md#config-builder-discovery-flow)) and are informational or used by specific scripts:

| Field | Type | Source Phase | Description |
|-------|------|-------------|-------------|
| `Domain` | string | Phase 6 (user input) | Custom domain for RA UPNs (e.g. `cbg-voice.contoso.com`) |
| `DynamicsAppId` | string (GUID) | Phase 3 (D365) | D365 App Registration Client ID from `msdyn_occommunicationprovidersettingentry` |
| `AcsSubscriptionId` | string (GUID) | Phase 1 (az CLI) | Azure subscription containing the ACS resource |
| `AcsResourceId` | string | Phase 3 (D365) | ACS resource immutable ID from D365 provider setting (`msdyn_occommunicationproviderimmutableid`) |
| `AcsEndpoint` | string | Phase 4 (Azure Mgmt) | ACS resource hostname (e.g. `resource.communication.azure.com`) |
| `SbcPort` | int | Phase 5 (ACS SIP) | SBC SIP signaling port discovered from ACS trunk |
| `RaPrefix` | string | Phase 6 (default) | Resource Account name prefix template (default: `acs-tpe-ra-<phonenumber>`) |
| `PolicyName` | string | Phase 6 (default) | Alias for `RoutingPolicyName` in New-AcsTpeConfig output |
| `UsageName` | string | Phase 6 (default) | Alias for `PstnUsageName` in New-AcsTpeConfig output |

### ResourceAccount Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `UPN` | string | Yes | Resource account UPN (must be in tenant) |
| `PhoneNumber` | string | Yes | E.164 phone number (e.g. `+12202140029`) |
| `DisplayName` | string | Yes | Display name shown in Teams |
| `ObjectId` | string | No | Entra ID ObjectId; empty string initially, populated by Step 7, used by Steps 8–11 |
| `D365Name` | string | No | Display name from D365 `msdyn_name` field; populated by Phase 0D discovery |
| `Type` | string | No | `DR` (Direct Routing) or `DO` (Direct Outward); populated by Phase 0D DR/DO classification |

### ResourceAccount Auto-Generation (Phase 0D)

When Phase 0D discovers phone numbers from D365, it auto-generates the `ResourceAccounts` array entries using `Build-RaList`. The output format depends on whether the `RaPrefix` contains a `<phonenumber>` token.

#### Template Mode (default: `RaPrefix = "acs-tpe-ra-<phonenumber>"`)

When `RaPrefix` contains the literal string `<phonenumber>`, the token is replaced with the raw phone digits (the `+` prefix is stripped):

| Field | Format | Example |
|-------|--------|---------|
| `UPN` | `<prefix-with-digits>@<tenant-domain>` | `acs-tpe-ra-12202140029@tenant.onmicrosoft.com` |
| `PhoneNumber` | E.164 (unchanged from D365) | `+12202140029` |
| `DisplayName` | `TPE RA +<number>` | `TPE RA +12202140029` |
| `ObjectId` | `""` (empty string) | `""` |

#### Sequential Mode (no `<phonenumber>` token in prefix)

When `RaPrefix` does not contain `<phonenumber>`, entries are numbered sequentially with zero-padded suffixes:

| Number Count | Padding Width | UPN Example |
|-------------|---------------|-------------|
| 1–99 | 2 digits | `my-ra-01@tenant.onmicrosoft.com` |
| 100–999 | 3 digits | `my-ra-001@tenant.onmicrosoft.com` |
| 1000+ | 4 digits | `my-ra-0001@tenant.onmicrosoft.com` |

#### UPN Sanitization

Before generating UPNs, the prefix is sanitized:
- Non-alphanumeric characters are replaced with hyphens (`-`)
- Consecutive hyphens are collapsed to a single hyphen
- The result is lowercased

Example: prefix `ACS+TPE_RA` → sanitized prefix `acs-tpe-ra`

#### Common Fields

- `<tenant-domain>` is extracted from `cfg.AdminUpn` (everything after `@`)
- `D365Name` is populated from the D365 `msdyn_name` field (if available)
- `Type` is populated from DR/DO classification (`DR` = Direct Routing, `DO` = Direct Outward)
- Phase 0D saves the enriched config to `-ConfigPath` so subsequent runs load the pre-built ResourceAccounts array

## ACS Connection String Parsing

The `AcsConnectionString` is parsed to extract the endpoint and access key:

```
endpoint=https://<resource>.communication.azure.com/;accesskey=<base64>
```

- `endpoint` → used as the base URL for ACS REST API calls
- `accesskey` → decoded from base64, used for HMAC-SHA256 request signing

When `AcsConnectionString` is manually entered but `AcsEndpoint` is empty, the script auto-extracts the endpoint hostname from the connection string via regex (matching the `endpoint=https://...` token).

Validation requirements:
- Must contain `endpoint=` token
- Must contain `accesskey=` token
- Endpoint must be a valid HTTPS URL
- Access key must decode as valid base64

## Config Lifecycle

1. **Creation**: `New-AcsTpeConfig-v14.ps1` — interactive prompts; writes JSON
2. **Population**: Phase 0D (D365 discovery) updates `ResourceAccounts` and `IncludeNumbers`
3. **Save**: Orchestrator saves enriched config to the path specified by `-ConfigPath`
4. **Auto-save**: When `-ConfigPath` is not provided, Phase 0A saves interactive config to `.\acs-tpe-config-<yyyyMMdd-HHmmss>.json`. **`AcsConnectionString` is excluded from auto-saved config files** for security — it contains the access key
5. **Resume**: `-ConfigPath` on subsequent runs loads saved config, skipping interactive prompts
6. **Update**: `Set-AcsSbcFqdn-v14.ps1` patches `SbcFqdn` in an existing file without rebuilding

**Phase 0A interactive flow**: When no `-ConfigPath` is provided and `StartAtStep=0`, the orchestrator enters a 16-prompt interactive flow collecting: TenantId, AdminUpn, Domain, DynamicsAppId, AcsSubscriptionId, AcsResourceId, AcsEndpoint, AcsAccessKey, SbcFqdn, SbcPort, D365OrgUrl, RaPrefix, PolicyName, UsageName, RouteName, and CommsProviderId.

## AcsConnectionString Re-Prompt

When config is loaded via `-ConfigPath` but `AcsConnectionString` is missing (it is excluded from auto-saved configs for security), the orchestrator prompts interactively for the ACS access key. The re-prompted key is combined with the saved `AcsEndpoint` to reconstruct the full connection string in the format `endpoint=https://<endpoint>/;accesskey=<key>`. This allows secure config files that do not persist credentials to still be usable on resume runs.

## IncludeNumbers Behavior

- `IncludeNumbers: []` (empty array) → interactive prompt during Phase 0D; user selects from D365 list
- `IncludeNumbers: ["+12202140029"]` → silently selects only the listed numbers, no prompt
- Non-E.164 entries → warned and skipped
- Numbers not found in D365 → warned and skipped

## Validation Rules

All scripts that load config must validate:
- `TenantId` is a valid GUID format
- `AdminUpn` is non-empty
- `AcsConnectionString` contains both `endpoint=` and `accesskey=`
- `SbcFqdn` is non-empty (validated by `Set-AcsSbcFqdn-v14.ps1` to be non-blank)
- `D365OrgUrl` ends with `/` and is a valid URL
- Each `ResourceAccounts[].PhoneNumber` matches E.164: `^\+[1-9]\d{6,14}$`
- `SbcFqdn` SIP port (if embedded) is numeric

### Resume Mode Guard

When `StartAtStep > 0` without `-ConfigPath`, the script exits with an error requiring a config file for resume runs. Config must contain all required fields since interactive prompts are skipped on resume.

## Default File Names

Scripts default to these config paths when `-ConfigPath` is not supplied:

| Context | Default Path |
|---------|-------------|
| New-AcsTpeConfig output | `.\new-acs-tpe-config-v14.11.0.json` |
| Add-AcsTrunkDisabled `-ConfigPath` | `.\acs-tpe-config-fromd365-local.json` |
| Orchestrator `-ConfigPath` | `''` (empty string — prompts interactively if not supplied) |
| FlipToACS / FlipToTeams `-ConfigPath` | required (Mandatory parameter) |
| Toggle `-ConfigPath` | `''` (empty string — individual params used instead) |
| Undo `-ConfigPath` | required (Mandatory parameter) |

## Cross-Subscription ACS Resource Discovery

`New-AcsTpeConfig-v14.ps1` supports discovering ACS resources across Azure subscriptions:

1. First queries the current az CLI subscription for ACS Communication Services resources via the Azure Management REST API
2. If no ACS resource is found or the user needs a different subscription, accepts a full Azure resource ID or portal URL
3. `Trim-ResourceId` extracts the canonical resource path from portal URLs using regex: `/subscriptions/[^/\s]+/resourceGroups/[^/\s]+/providers/Microsoft\.Communication/CommunicationServices/[^/?#\s]+`
4. `Get-MgmtHeaders` acquires management tokens scoped to a specific subscription ID for cross-tenant access

This allows config building when the ACS resource lives in a different subscription than the one currently selected in az CLI.

## SBC Port

The SBC FQDN may include a port number suffix (`fqdn:5061`). When present:
- Port is extracted and passed to `New-CsOnlinePSTNGateway -SipSignalingPort`
- Default port is `5061` if no port suffix is present
- Port must be a valid integer in range 1–65535 (validated at config load time and by `Add-AcsTrunkDisabled-v14.ps1`)
