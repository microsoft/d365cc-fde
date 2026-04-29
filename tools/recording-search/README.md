# Recording Search

A Dynamics 365 Contact Center web resource that gives supervisors, quality assurance
staff, and administrators a dedicated search interface for voice conversations and
recordings — without leaving Customer Service Workspace (CSW).

**Version:** 1.4.1 &nbsp;·&nbsp; **Type:** Dataverse HTML web resource (CSW application tab)

---

## Overview

Recording Search adds a standalone conversation and recording history tab to Customer
Service Workspace. It is intended for supervisors, quality assurance staff, and
administrators who need to search across voice conversations — independent of any active
case or conversation session. Users can find any voice conversation by date, agent, caller
number, contact, queue, sentiment, and more — without navigating standard Dynamics views
or requesting a separate reporting tool.

**Features:**

- Search by date range using quick-select presets (Today, Yesterday, Last 7 / 30 / 90
  days, This month, Last month) or a custom date and time range
- Search by agent name — finds conversations where the agent participated at any point,
  including after transfers
- Search by caller phone number (partial match)
- Search by linked contact record name
- Filter by queue, workstream, call direction (inbound / outbound), sentiment, and
  duration range
- Toggle to show only conversations that have a recording, or only transferred calls
- Sortable results table — click any column header to sort
- Inline audio player — expand any row to play the recording directly in the tab
- Open in Dynamics — jump to the full conversation record in a single click
- Results persist across CSW tab switches for up to 10 minutes; automatic reload prompt
  when a newer version is deployed

`[screenshot]`

---

## Prerequisites

| Requirement | Details |
|---|---|
| Dynamics 365 Contact Center | Omnichannel for Customer Service must be enabled in your environment |
| Customer Service Workspace | The CSW app must be deployed and accessible to your agents |
| Administrator role | **System Customizer** or **System Administrator** to upload and publish web resources |
| Supervisor / QA / admin role | Read access to the entities listed below |

**Entities users must be able to read:**

| Entity display name | Schema name |
|---|---|
| Conversation (Live Work Item) | `msdyn_ocliveworkitem` |
| Session | `msdyn_ocsession` |
| Recording | `msdyn_ocrecording` |
| Phone Call Engagement Context | `msdyn_ocphonecallengagementctx` |
| Queue | `queue` |
| Workstream | `msdyn_liveworkstream` |
| System User | `systemuser` |
| Contact | `contact` |

---

## Installation

### Step 1 — Upload the web resource

1. Go to [make.powerapps.com](https://make.powerapps.com) and select your environment.
2. In the left navigation, select **Solutions**.
3. Open an existing solution or create a new one (**New solution**).
4. Select **New** → **More** → **Web resource**.
5. Fill in the following fields:

   | Field | Value |
   |---|---|
   | **Display name** | `Recording Search` |
   | **Name** | `csac_recordingSearch` (your publisher prefix will be added automatically, e.g. `prefix_csac_recordingSearch`) |
   | **Type** | `HTML (htm, html)` |
   | **File** | Upload `csac_recordingSearch.html` from this repository |

6. Select **Save**, then select **Publish**.

`[screenshot — web resource form]`

---

### Step 2 — Create the application tab template

1. Open Customer Service admin center — in CSW, select the app switcher and choose **Customer Service admin center**.
2. In the left navigation, select **Workspaces** → **Application tab templates**.
3. Select **New**.
4. Fill in the following fields:

   | Field | Value |
   |---|---|
   | **Name** | `Recording Search` |
   | **Unique name** | `csac_recordingSearch_tab` |
   | **Page type** | `Web resource` |

5. In the **Parameters** section, set **Web resource** to the resource you uploaded in Step 1.
6. Select **Save**.

`[screenshot — application tab template form]`

---

### Step 3 — Create a session template

1. In Customer Service admin center, select **Workspaces** → **Session templates** (same app as Step 2).
2. Select **New**.
3. Fill in the following fields:

   | Field | Value |
   |---|---|
   | **Name** | `Recording Search Home` |
   | **Unique name** | `csac_recordingSearch_home_session` |
   | **Type** | `Generic` |
   | **Anchor tab** | Select the tab template created in Step 2 (`Recording Search`) |

4. Select **Save**.

---

### Step 4 — Add the session template to experience profiles

Recording Search should be added only to the experience profiles assigned to the users
who need it — typically supervisors, quality assurance staff, or administrators. Do not
add it to front-line agent profiles unless those agents are explicitly intended to have
search access.

1. In Customer Service admin center, select **Workspaces** → **Experience profiles**.
2. Open the experience profile for the target group (for example, a *Supervisor* or
   *Quality Assurance* profile).
3. Select the **Session templates** tab.
4. Select **Add existing**, then select **Recording Search Home**.
5. Select **Save**.
6. Repeat for each profile that should have access.

`[screenshot — experience profile session templates tab]`

---

### Step 5 — Verify

1. Open **Customer Service Workspace**.
2. Hard-refresh: **Ctrl + Shift + R** (or **Cmd + Shift + R** on Mac).
3. The **Recording Search** tab should appear in the application tab bar or navigation.
4. Run a test search — set a date range and select **Search**. Confirm results load.

If the tab does not appear, see [Troubleshooting](#troubleshooting).

---

## Configuration

Recording Search works out of the box against standard Dynamics 365 Contact Center field
names. In most environments no configuration is needed after installation.

If your environment uses non-standard field names, open `csac_recordingSearch.html` in a
text editor and locate the `CONFIG.entities` block near the top of the `<script>` section.
Fields marked with a `// VERIFY` comment may need to be adjusted:

| Config path | Default value | Controls |
|---|---|---|
| `phonecallctx.set` | `msdyn_ocphonecallengagementctxes` | OData entity set for phone call context records |
| `phonecallctx.fromPhone` | `msdyn_fromphone` | Field that holds the caller's phone number (ANI) |
| `conversation.durationSec` | `msdyn_conversationhandletimeinseconds` | Field used for duration filter and sort |
| `recording.set` | `msdyn_ocrecordings` | OData entity set for recording records |
| `recording.uri` | `msdyn_mediauri` | Field that holds the recording file URL |

After editing the file, re-upload it to the web resource and republish (see
[Upgrading](#upgrading)).

> **Note on caller phone numbers:** The caller's phone number (ANI) is not stored directly
> on the conversation record. Recording Search fetches it from the
> `msdyn_ocphonecallengagementctx` entity using the `msdyn_fromphone` field. If caller
> numbers are not appearing, verify that agents have read access to this entity and that
> the field name matches your environment.

### Version self-check

The tool checks for updates automatically — 8 seconds after load and every 5 minutes
thereafter. If a newer version of the web resource has been published, a blue banner
prompts agents to reload their browser tab. No administrator action is needed.

---

## Upgrading

1. Download the latest `csac_recordingSearch.html` from this repository.
2. Go to [make.powerapps.com](https://make.powerapps.com) → **Solutions** → open your
   solution → find the **Recording Search** web resource.
3. Select **Edit** (or open the record).
4. Under **File**, select **Upload file** and choose the new `csac_recordingSearch.html`.
5. Select **Save**, then select **Publish**.
6. Agents currently using the tab will see a reload banner automatically. Ask them to
   reload, or they can wait for the next automatic check.

---

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| Recording Search tab does not appear | Experience profile not updated, or app not refreshed | Confirm the session template is assigned to the correct experience profile (Step 4). Hard-refresh CSW: **Ctrl + Shift + R** |
| No results returned | User lacks read permission on required entities | Check that the agent's security role grants read access to all entities listed in [Prerequisites](#prerequisites) |
| Caller Number column is blank | `msdyn_fromphone` field name differs in your environment | Open the `CONFIG.entities.phonecallctx` block and verify `fromPhone` and `set` match your entity metadata |
| Phone search returns no results | `msdyn_ocphonecallengagementctxes` entity not accessible | Confirm read access to the Phone Call Engagement Context entity; verify the OData set name in `CONFIG.entities.phonecallctx.set` |
| Queue dropdown is empty | No public queues returned, or missing read permission | Confirm the agent role has read access to `queue` records; the tool filters to public queues only (`queuetypecode = 1`) |
| Recording does not play | Recording URI field name differs in your environment | Verify `CONFIG.entities.recording.uri`; confirm the recording file is accessible from the agent's browser |
| Duration shows `—` | `actualdurationminutes` is not populated for voice calls in this environment | Expected behavior — duration filtering and sorting work correctly; display is a known cosmetic issue |
| "Open in Dynamics" does nothing | Tool is not running inside Customer Service Workspace | The Open in Dynamics action requires the CSW JavaScript API (`Xrm`). The tool must be accessed via a CSW application tab, not a standalone browser window |
| Agents see a reload banner immediately after opening | A newer version was published after the tab was loaded | Ask agents to select the banner or hard-refresh: **Ctrl + Shift + R** |

---

## Project structure

```
recording-search/
├── README.md
├── CHANGELOG.md
└── csac_recordingSearch.html   ← web resource file to upload
```

---

## License

See [LICENSE](../../LICENSE) in the repository root.
