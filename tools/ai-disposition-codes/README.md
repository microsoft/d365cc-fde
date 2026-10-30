<div align="center">

<img src="../../assets/d365cc-logo.png" width="60" alt="D365 Contact Center" />

*Crafted with care for contact center excellence*

</div>

# AI Recommended Disposition Codes

> **Dynamics 365 Contact Center — AI-Assisted Conversation Classification**

---

| Field | Value |
|-------|-------|
| **Solution Unique Name** | `AIDispositionCode` |
| **Version** | 1.0.0.3 |
| **Publisher** | CCaaSFDE (prefix: `ccaasfde_`, option value prefix: `35716`) |
| **Target Application** | Customer Service workspace (`msdyn_CustomerServiceWorkspace`) |
| **Platform** | Dynamics 365 Customer Service / Omnichannel / Power Platform |
| **AI Model** | GPT-4.1-mini via AI Builder |
| **Solution Type** | Unmanaged |
| **Language** | English (LCID 1033) |
| **Last Updated** | 2026-10-29 |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Business Problem](#2-business-problem)
3. [Solution Overview](#3-solution-overview)
4. [Business Impact & ROI](#4-business-impact--roi)
5. [Solution Components](#5-solution-components)
6. [Architecture](#6-architecture)
7. [Data Flow & Sequence](#7-data-flow--sequence)
8. [AI Model Specification](#8-ai-model-specification)
9. [Dataverse Tables](#9-dataverse-tables)
10. [Prerequisites](#10-prerequisites)
11. [Deployment Guide](#11-deployment-guide)
12. [Post-Deployment Validation](#12-post-deployment-validation)
13. [Configuration](#13-configuration)
14. [Security & Compliance](#14-security--compliance)
15. [Performance](#15-performance)
16. [Monitoring & Observability](#16-monitoring--observability)
17. [Known Limitations](#17-known-limitations)
18. [Troubleshooting](#18-troubleshooting)
19. [Rollback Procedure](#19-rollback-procedure)
20. [Version History](#20-version-history)
21. [Building & Testing](#21-building--testing)
22. [Roadmap & Not Yet Implemented](#22-roadmap--not-yet-implemented)

---

## 1. Executive Summary

This solution introduces **AI-powered disposition code recommendations** into the Dynamics 365 Contact Center agent experience. When a conversation ends, the system automatically analyzes the Copilot-generated conversation summary and recommends the most relevant disposition codes — reducing agent wrap-up time, improving classification accuracy, and enabling reliable downstream analytics.

Agents see a focused modal with ranked recommendations they can accept, modify, or override. The entire process adds **2–6 seconds** to conversation wrap-up and eliminates the manual search-and-scroll process that currently averages **15–45 seconds** per interaction.

---

## 2. Business Problem

### Current State

In most contact center operations, agents are required to assign one or more **disposition codes** (also called wrap-up codes, call outcome codes, or ACW codes) after every customer interaction. These codes drive:

- **Reporting and analytics** — understanding contact reasons, trending topics, first-contact resolution rates
- **Workforce management** — forecasting volumes by contact type
- **Quality management** — identifying training needs, process gaps
- **Automation triggers** — routing follow-ups, triggering workflows based on disposition

#### Pain Points

| # | Pain Point | Impact |
|---|-----------|--------|
| 1 | **Manual code selection is slow** | Agents scroll through 50–200+ disposition codes, often organized in multi-level hierarchies. Average selection time: 15–45 seconds per conversation |
| 2 | **Inconsistent classification** | Different agents classify identical conversations differently. Studies show 20–35% variance in disposition coding across agent populations |
| 3 | **Forgotten or default codes** | Under time pressure, agents select generic/catch-all codes ("Other", "General Inquiry") — corrupting analytics. Industry estimates: 10–25% of dispositions are inaccurate |
| 4 | **Training burden** | New agents require extensive training on code taxonomies. Code changes require re-training |
| 5 | **Analytics degradation** | Inaccurate dispositions cascade into unreliable reports, incorrect forecasts, and misallocated resources |

### Desired State

- AI recommends the correct disposition code(s) immediately at conversation end
- Agent confirms or adjusts with a single click — no searching, no scrolling
- Classification accuracy improves from ~70–80% to 90%+
- Wrap-up time (After-Contact Work) is reduced significantly
- Analytics teams receive consistent, high-quality disposition data

---

## 3. Solution Overview

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    AGENT CONVERSATION ENDS                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  JS Form Handler (v2.2) detects EndConversation via CIF         │
│  SessionGuard checks: already handled? → skip (prevents dupes)  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Custom Page "Disposition Recommendation" opens as modal        │
│  Sends conversationId + workstreamId + disposition codes        │
│  to Cloud Flow                                                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Cloud Flow "Disposition Recommender"                           │
│  ┌──────────────────────────────────────────────────┐           │
│  │ Poll msdyn_conversationinsights for Copilot      │           │
│  │ summary (up to 15 attempts, 2s interval)         │           │
│  └──────────────────────┬───────────────────────────┘           │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────┐           │
│  │ AI Builder: GPT-4.1-mini classifies summary      │           │
│  │ against available disposition codes              │           │
│  │ Returns 1–3 ranked matches (confidence ≥ 0.40)   │           │
│  └──────────────────────┬───────────────────────────┘           │
└──────────────────────────┤──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Agent sees ranked recommendations in PowerCAT Picker           │
│  ┌─────────────────────────────────────────────────────┐        │
│  │   Account Closure Request      (confidence: 0.92)   │        │
│  │   Service Cancellation         (confidence: 0.78)   │        │
│  │   Billing Dispute              (confidence: 0.45)   │        │
│  └─────────────────────────────────────────────────────┘        │
│  Agent accepts, adjusts, or searches for additional codes       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Save → Patch msdyn_conversationdispositioncodemap              │
│  Agent returns to next conversation                             │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Non-blocking** | Workstream and disposition data pre-cached on form load — modal opens instantly |
| **Agent-in-the-loop** | AI recommends, agent decides. Agent can override, add, or remove codes |
| **Graceful degradation** | If Copilot summary unavailable, agent can manually search codes — no dead end |
| **Low-variance AI** | Temperature=0 minimizes run-to-run variation. Identical summaries usually, but not always, produce identical recommendations |
| **Minimal footprint** | No custom entities, no new security roles, no plugins — uses existing D365 tables |

---

## 4. Business Impact & ROI

### Time Savings

| Metric | Before (Manual) | After (AI-Assisted) | Improvement |
|--------|-----------------|---------------------|-------------|
| **Disposition selection time** | 15–45 seconds | 2–6 seconds | **75–90% reduction** |
| **Agent wrap-up (ACW) time** | Includes scrolling, searching, second-guessing | One-click confirm or quick adjustment | **10–30 seconds saved per interaction** |

### Projected Annual Impact

> *Assumptions: 500 agents, 30 conversations/agent/day, 250 working days/year*

| Scenario | Calculation | Annual Savings |
|----------|-------------|----------------|
| **Conservative** (10s saved/conversation) | 500 × 30 × 250 × 10s = 10,416 hours | **~10,400 agent-hours/year** |
| **Moderate** (20s saved/conversation) | 500 × 30 × 250 × 20s = 20,833 hours | **~20,800 agent-hours/year** |
| **Optimistic** (30s saved/conversation) | 500 × 30 × 250 × 30s = 31,250 hours | **~31,250 agent-hours/year** |

At an average loaded agent cost of $25–40/hour, the **moderate scenario** represents **$520K–$830K in annual labor savings**.

### Quality Improvements

| Metric | Before | After (Expected) | Measurement Method |
|--------|--------|-------------------|--------------------|
| **Disposition accuracy** | 65–80% (industry avg.) | 90%+ | QA audit sampling + AI confidence correlation |
| **"Other/Generic" code usage** | 10–25% of dispositions | <5% | Report: % of conversations with catch-all codes |
| **Agent-to-agent consistency** | 20–35% variance | <10% variance | Same conversation, different agent — classification agreement rate |

### Downstream Benefits

- **More accurate reporting**: Contact reason analysis, trending topic detection, root cause identification all depend on correct disposition data
- **Better workforce planning**: Forecasters can predict volumes by contact type with higher confidence
- **Faster agent onboarding**: New agents no longer need to memorize 100+ disposition codes — AI recommends, they learn organically
- **Audit readiness**: AI-recommended codes with confidence scores provide an auditable trail of why a code was selected
- **Continuous improvement**: Confidence scoring data enables ongoing prompt refinement and identification of disposition taxonomy gaps

---

## 5. Solution Components

### Component Inventory

| # | Component | Type | Unique Name | Purpose |
|---|-----------|------|-------------|---------|
| 1 | **Disposition Recommender** | Cloud Flow (Power Automate) | Disposition Recommender | Orchestrates the polling-for-summary + AI classification pipeline |
| 2 | **Disposition Recommendation** | Custom Page (Canvas App) | `ccaasfde_dispositionrecommendation_d051d` | Agent-facing modal UI — displays recommendations, handles code selection and save |
| 3 | **Disposition code classifier** | AI Builder Prompt (AI Model) | Disposition code classifier | GPT-4.1-mini prompt that classifies conversation summaries against disposition codes |
| 4 | **Form Handler** | JavaScript Web Resource (v2.2) | `ccaasfde_dispositioncodeformhandler` | Detects conversation end via CIF, opens modal, manages lifecycle |
| 5 | **Active Conversation form** | Form Customization | Active Conversation (`msdyn_ocliveworkitem`) | Registers JS handler on `onLoad` event (ordinal position 7) |
| 6 | **Connection Reference** | Dataverse Connection | `shared_commondataserviceforapps` | Shared Dataverse connection used by the Cloud Flow |

### Component Dependency Map

```
Active Conversation Form (onLoad)
    └── ccaasfde_dispositioncodeformhandler (JS v2.2)
            └── Opens: Disposition Recommendation (Custom Page)
                    ├── Calls: Disposition Recommender (Cloud Flow)
                    │       ├── Reads: msdyn_conversationinsights (Copilot summary)
                    │       └── Calls: Disposition code classifier (AI Model)
                    ├── Reads: msdyn_ocdispositioncode (available codes)
                    ├── Reads: msdyn_ocliveworkitem (conversation context)
                    ├── Writes: msdyn_conversationdispositioncodemap (selected codes)
                    └── Uses: cat_PowerCAT.Picker (Creator Kit control)
```

---

## 6. Architecture

### Solution Architecture

```
┌────────────────────────────────── Power Platform ──────────────────────────────────┐
│                                                                                    │
│  ┌─── Customer Service Workspace ───────────────────────────────────────────────┐  │
│  │                                                                              │  │
│  │  ┌── Active Conversation Form ──────────────────────────────────────────┐    │  │
│  │  │                                                                      │    │  │
│  │  │  onLoad handlers:                                                    │    │  │
│  │  │   [0] msdyn_customersummaryscripts.js (OOB)                          │    │  │
│  │  │   [6] msdyn_Loadkbsearch.js (OOB)                                    │    │  │
│  │  │   [7] ccaasfde_dispositioncodeformhandler (THIS SOLUTION)            │    │  │
│  │  │        ↓                                                             │    │  │
│  │  │   Subscribes to CIF EndConversationEvent                             │    │  │
│  │  │   Pre-caches workstream + disposition data (parallel)                │    │  │
│  │  │   On conversation end → opens modal                                  │    │  │
│  │  │                                                                      │    │  │
│  │  └───────────────────────────┬──────────────────────────────────────────┘    │  │
│  │                              │                                               │  │
│  │                              ▼                                               │  │
│  │  ┌── Custom Page (Canvas App) ──────────────────────────────────────────┐    │  │
│  │  │  Disposition Recommendation                                          │    │  │
│  │  │  ┌──────────────┐  ┌───────────────────┐  ┌──────────────────────┐   │    │  │
│  │  │  │ Loading      │  │ PowerCAT Picker   │  │ Save / Cancel        │   │    │  │
│  │  │  │ Spinner      │  │ (recommendations) │  │ Buttons              │   │    │  │
│  │  │  └──────────────┘  └───────────────────┘  └──────────────────────┘   │    │  │
│  │  └───────────────────────────┬──────────────────────────────────────────┘    │  │
│  │                              │                                               │  │
│  └──────────────────────────────┤───────────────────────────────────────────────┘  │
│                                 │                                                  │
│  ┌── Power Automate ────────────┤────────────────────────────────────────────────┐ │
│  │                              ▼                                                │ │
│  │  Cloud Flow: Disposition Recommender                                          │ │
│  │  ┌────────────────┐  ┌───────────────────┐  ┌────────────────────────────┐    │ │
│  │  │ Poll for       │  │ AI Builder        │  │ Return JSON response       │    │ │
│  │  │ Copilot Summary│→ │ Prompt Execution  │→ │ to Canvas App              │    │ │
│  │  │ (Do Until loop)│  │ (GPT-4.1-mini)    │  │                            │    │ │
│  │  └────────────────┘  └───────────────────┘  └────────────────────────────┘    │ │
│  │                                                                               │ │
│  └───────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                    │
│  ┌── Dataverse ─────────────────────────────────────────────────────────────────   │
│  │                                                                              │  │
│  │  msdyn_conversationinsights ← Copilot summary (read)                         │  │
│  │  msdyn_ocdispositioncode    ← Available codes (read)                         │  │
│  │  msdyn_ocliveworkitem       ← Conversation context (read)                    │  │
│  │  msdyn_conversationdispositioncodemap ← Selected codes (write)               │  │
│  │                                                                              │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                    │
└────────────────────────────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology | Version / Notes |
|-------|-----------|-----------------|
| Agent UI | Customer Service workspace (Model-driven app) | Multi-session, CIF-enabled |
| Modal UI | Power Apps Custom Page (Canvas) | Embedded in model-driven app |
| Picker Control | PowerCAT Picker (PCF) | Creator Kit Core, published by Microsoft |
| Event Detection | Channel Integration Framework (CIF) | `EndConversationEvent` |
| Form Handler | JavaScript Web Resource | v2.2 (SessionGuard, kill switch, scoped globals) |
| Orchestration | Power Automate Cloud Flow | Instant flow, PowerApp V2 trigger |
| AI Classification | AI Builder Custom Prompt | GPT-4.1-mini, temperature=0 |
| Data Layer | Microsoft Dataverse | Standard OOB Omnichannel tables |
| AI Summary Source | Copilot for Customer Service | `msdyn_copilotsummary` field |

---

## 7. Data Flow & Sequence

### Sequence Diagram

```
Agent        Form Handler (JS)     Custom Page        Cloud Flow        Dataverse         AI Builder
  │               │                     │                  │                │                  │
  │──ends call──→ │                     │                  │                │                  │
  │               │                     │                  │                │                  │
  │            CIF fires                │                  │                │                  │
  │         EndConversationEvent        │                  │                │                  │
  │               │                     │                  │                │                  │
  │            SessionGuard             │                  │                │                  │
  │            check (v2.2)             │                  │                │                  │
  │               │                     │                  │                │                  │
  │               │──opens modal──────→ │                  │                │                  │
  │               │  (payload:          │                  │                │                  │
  │               │   convId,           │                  │                │                  │
  │               │   workstreamId,     │                  │                │                  │
  │               │   codes[])          │                  │                │                  │
  │               │                     │                  │                │                  │
  │               │                     │──Run flow──────→ │                │                  │
  │               │                     │                  │                │                  │
  │               │                     │                  │──poll──────→   │                  │
  │               │                     │                  │  (insights)    │                  │
  │               │                     │                  │ ←─summary───   │                  │
  │               │                     │                  │                │                  │
  │               │                     │                  │──classify────────────────────→    │
  │               │                     │                  │  (summary +    │                  │
  │               │                     │                  │   codes)       │                  │
  │               │                     │                  │ ←─recommendations──────────────   │
  │               │                     │                  │                │                  │
  │               │                     │ ←─JSON response─ │                │                  │
  │               │                     │                  │                │                  │
  │ ←───shows recommendations────────   │                  │                │                  │
  │                                     │                  │                │                  │
  │──reviews, adjusts, clicks Save────→ │                  │                │                  │
  │                                     │──Patch records─────────────────→  │                  │
  │                                     │  (disposition    │                │                  │
  │                                     │   code map)      │                │                  │
  │                                     │ ←─success───────────────────────  │                  │
  │ ←───modal closes, back to queue──   │                  │                │                  │
```

### Data Payload Specification

**JS Handler → Custom Page (modal parameters):**
```json
{
  "conversationId": "GUID — msdyn_ocliveworkitem ID",
  "workstreamId": "GUID — msdyn_liveworkstreamid",
  "dispositionCodes": "[{\"dispositionId\":\"GUID\",\"code\":\"CODE\",\"label\":\"Display Name\"}, ...]"
}
```

**Cloud Flow → Custom Page (response):**
```json
{
  "success": true,
  "summary": "Customer called to request account closure due to relocation...",
  "recommendations": [
    {
      "id": "GUID",
      "code": "ACCT_CLOSE",
      "label": "Account Closure Request",
      "confidence": 0.92,
      "reason": "Customer explicitly requested account closure"
    }
  ]
}
```

**Error response (no Copilot summary):**
```json
{
  "success": false,
  "summary": "",
  "recommendations": [],
  "error": "No Copilot summary found after polling"
}
```

---

## 8. AI Model Specification

### Model Details

| Property | Value |
|----------|-------|
| **AI Model Name** | Disposition code classifier |
| **Template** | AI Builder Custom Prompt (Dynamic Prompt v2) |
| **Underlying Model** | GPT-4.1-mini |
| **Temperature** | 0 (lowest variability; not a determinism guarantee) |
| **Major Iteration** | 2 |

### Prompt Design

The prompt follows a structured classification pattern:

1. **Role assignment**: "You are a disposition code classifier"
2. **Input specification**: Summary text + available codes (JSON)
3. **Strict rules**: Max 3 matches, one code per distinct intent, prefer specific over generic codes, exact ID matching, semantic understanding
4. **Output format**: Rigid JSON `{"recommendations":[{"id","confidence","reason"}]}` — no markdown, no explanation, no code blocks. The model no longer echoes the summary; the flow adds `success` and `summary`
5. **Reason constraint**: Max 12 words per recommendation reason
6. **Prompt-injection guard**: The summary is wrapped in `<summary>` tags and declared untrusted data; instructions inside it must be ignored
7. **Few-shot examples**: One multi-intent example and one "nothing fits" example

The prompt source lives in `src/prompt/disposition-classifier.prompt.txt`; `npm run build` writes it into `solution/customizations.xml`. Edit the source file, not the XML.

### Classification Rules

| Rule | Description |
|------|-------------|
| Match limit | 1–3 codes maximum, ranked by confidence (highest first) |
| Confidence threshold | The prompt asks for ≥ 0.40; the flow enforces it again (`Config.minConfidence`) because model-reported confidence is not calibrated |
| Matching approach | Semantic understanding — matches intent and context, not just keywords |
| ID integrity | `id` must EXACTLY match a `dispositionId` from the input codes. The flow drops unknown ids, and the Custom Page takes `code`/`label` from its own list, never from the model |
| Empty result handling | If no codes match well, return empty recommendations array |
| Variability | Temperature=0 minimizes variation; identical outputs are not guaranteed across runs or model updates |

### AI Responsible Use

- AI generates **recommendations**, not decisions — the agent always has final authority
- The Custom Page footer includes Microsoft's standard AI disclaimer: *"AI-generated content may be incorrect. Make sure AI-generated content is accurate and appropriate before using."* with link to [Microsoft AI Terms](https://go.microsoft.com/fwlink/?linkid=2189520)
- The Copilot-generated summary is sent to the AI Builder prompt. Summaries can contain personal data mentioned in the conversation (names, account numbers, contact details), so treat them as personal data in your privacy review. No other customer record fields are sent
- Confidence scores provide transparency into AI certainty

---

## 9. Dataverse Tables

### Tables Read (No Schema Changes)

| Table Logical Name | Display Name | Usage | Source Solution |
|--------------------|-------------|-------|-----------------|
| `msdyn_ocliveworkitem` | Conversation | Read conversation context (workstream, status, customer) | OmnichannelBase |
| `msdyn_ocdispositioncode` | OC Disposition Code | Read available disposition codes for the workstream | ChannelExperienceApps |
| `msdyn_conversationinsights` | Conversation Insight | Read Copilot conversation summary (`msdyn_copilotsummary`) | ConversationInsight |

### Tables Written

| Table Logical Name | Display Name | Usage | Source Solution |
|--------------------|-------------|-------|-----------------|
| `msdyn_conversationdispositioncodemap` | Conversation Disposition Code Map | Write agent's selected disposition codes (one record per code selected) | ChannelExperienceApps |

### Record Created on Save

For each selected disposition code, one record is patched into `msdyn_conversationdispositioncodemap`:

| Field | Value |
|-------|-------|
| `Name` | Disposition code label |
| `Disposition code value` | Disposition code label |
| `OC Disposition Code` | Lookup to `msdyn_ocdispositioncode` |
| `Live work item ID` | Lookup to `msdyn_ocliveworkitem` (the conversation) |

> **Note:** This solution does NOT create any custom entities, custom fields, or schema changes. It uses existing OOB Omnichannel tables exclusively.

---

## 10. Prerequisites

### Required Components

Install all prerequisites **before** importing this solution.

| # | Prerequisite | Required Version | Source | Validation |
|---|-------------|------------------|--------|------------|
| 1 | **Dynamics 365 Customer Service Enterprise** | Latest GA | D365 license | CS workspace app is available |
| 2 | **Omnichannel for Customer Service** | 1.10+ | D365 CS admin center | `msdyn_ocliveworkitem` entity exists |
| 3 | **Copilot for Customer Service** | Enabled | CS admin center → Copilot | `msdyn_conversationinsights` table is being populated. Verify: after a test conversation, query `msdyn_conversationinsights` and confirm `msdyn_copilotsummary` is non-null |
| 4 | **Disposition codes configured** | N/A | CS admin center → Workstreams → select workstream → Disposition codes | At least one workstream has disposition codes enabled with codes created |
| 5 | **Creator Kit Core** | 1.0+ | [AppSource](https://appsource.microsoft.com/product/dynamics-365/microsoftpowercatarch.creatorkit1) or [GitHub](https://github.com/microsoft/powercat-creator-kit) | Provides `cat_PowerCAT.Picker` PCF control. Published by Microsoft, free, no additional licensing |
| 6 | **Customer Service workspace app** | 9.0+ | Included with D365 CS | App `msdyn_CustomerServiceWorkspace` exists in Solutions |

### Environment Requirements

| Requirement | Detail |
|-------------|--------|
| **Environment type** | Production or Sandbox (not Developer — AI Builder must be available) |
| **AI Builder credits** | Required for GPT-4.1-mini prompt execution. Included with D365 CS Enterprise license or available as add-on |
| **Dataverse database** | Required (non-Dataverse environments are not supported) |
| **Browser** | Microsoft Edge or Google Chrome (latest). CIF requires modern browser |
| **Region** | AI Builder prompts must be available in the environment's region. Check [AI Builder availability](https://learn.microsoft.com/ai-builder/availability-region) |

---

## 11. Deployment Guide

### Pre-Deployment Checklist

- [ ] All prerequisites from Section 10 are installed and validated
- [ ] Target environment has been identified (Production / Sandbox / UAT)
- [ ] Solution `.zip` file is available: `AIDispositionCode_1_0_0_3.zip`
- [ ] Deployer has System Administrator or Solution Customizer role
- [ ] Backup of target environment has been taken (recommended for Production)
- [ ] Change request / deployment ticket has been approved (if required by ITSM policy)

### Import Steps

| Step | Action | Detail |
|------|--------|--------|
| 1 | Navigate to Power Apps | Go to [make.powerapps.com](https://make.powerapps.com), select the target environment |
| 2 | Open Solutions | Left nav → Solutions |
| 3 | Import | Click **Import solution** → Browse → select `AIDispositionCode_1_0_0_3.zip` |
| 4 | Connection reference | When prompted, create a new Dataverse connection or select an existing one. Use a **service account** for production deployments |
| 5 | Import | Click **Import** and wait for completion (typically 1–3 minutes) |
| 6 | Activate Cloud Flow | Open the solution → Cloud flows → **Disposition Recommender** → Turn on |
| 7 | Publish customizations | Solutions → select AIDispositionCode → **Publish all customizations** |

### Post-Import Steps

| Step | Action | Validation |
|------|--------|------------|
| 1 | Verify Cloud Flow status | Cloud flows → Disposition Recommender → Status = "On" |
| 2 | Verify connection reference | Connection references tab → Dataverse connection is green/connected |
| 3 | Verify form registration | Open msdyn_ocliveworkitem entity → Forms → Active Conversation → Events → `onLoad` → confirm `ccaasfde_dispositioncodeformhandler` is listed at ordinal 7 |
| 4 | Verify Custom Page | Apps → Disposition Recommendation → should open without errors |
| 5 | Test end-to-end | See Section 12 |

### Upgrading from 1.0.0.2

Import `AIDispositionCode_1_0_0_3.zip` over the existing unmanaged solution (**Upgrade is not required**).

- The form handler function is still `onLoad`, so the existing form registration is reused and not duplicated. Still verify post-import step 3.
- The new version no longer carries the Customer Service workspace app settings, role maps or event handlers. An import does not remove them from the environment, so nothing changes there.
- Turn the Cloud Flow back on if the import left it off, and re-check the connection reference.
- **Back up the Active Conversation form first.** This solution contains the whole form. Importing with *overwrite unmanaged customizations* replaced the form's unmanaged layer on a sandbox test and silently **removed another solution's custom `onLoad` handler**. Import with overwrite disabled (API `OverwriteUnmanagedCustomizations=false`) and check the form's Events afterwards, or re-add any other custom handlers.
- Run the smoke tests in Section 12. They were not executed against a live environment as part of this release (see Section 21).

---

## 12. Post-Deployment Validation

### Smoke Test Procedure

| # | Step | Expected Result | Pass/Fail |
|---|------|-----------------|-----------|
| 1 | Open Customer Service workspace | App loads without errors | ☐ |
| 2 | Start a test conversation (any channel) | Conversation form opens with Active Conversation form | ☐ |
| 3 | Have a brief conversation with recognizable topic (e.g., "I want to close my account") | Conversation proceeds normally | ☐ |
| 4 | End the conversation (agent-side) | **Disposition Recommendation modal appears** within 2–10 seconds | ☐ |
| 5 | Observe loading state | Spinner with "Loading recommendations..." is shown while Cloud Flow runs | ☐ |
| 6 | Observe recommendations | 1–3 disposition codes appear with confidence indicators | ☐ |
| 7 | Modify selection | Add or remove a code using the Picker — search works, tags appear/disappear | ☐ |
| 8 | Click Save | "Saving disposition codes to conversation" notification appears, then "Saved successfully", modal closes | ☐ |
| 9 | Verify Dataverse records | Query `msdyn_conversationdispositioncodemap` filtered by conversation ID — records exist for each selected code | ☐ |
| 10 | Close the conversation form/tab | **Modal does NOT appear again** (SessionGuard prevents duplicate) | ☐ |

### Negative Test Cases

| # | Scenario | Expected Result |
|---|----------|-----------------|
| 1 | Copilot disabled / summary not generated | Modal shows: "No AI recommendations available. Pick a disposition code from the list below, or search to narrow it down." The agent clicks a code in the list (it narrows as they type in the search box) |
| 2 | No disposition codes configured for workstream | The modal is not opened (nothing to recommend or pick). The agent uses the standard disposition control |
| 3 | Cloud Flow fails / times out | The flow's Catch scope (or the app's `IfError`) returns `success: false`; the modal shows "No AI recommendations available" and the agent can still search and select |
| 4 | Agent clicks Cancel | Modal closes, no records written. Agent can still assign codes via standard D365 disposition control |
| 5 | Agent closes browser tab mid-modal | No crash, no orphaned records. SessionGuard prevents re-trigger on next form load |

---

## 13. Configuration

### Configurable Parameters

The following values are defined in the JS web resource `CONFIG` object and the Cloud Flow:

| Parameter | Location | Default | Description |
|-----------|----------|---------|-------------|
| `DISPOSITION_CACHE_TTL_MS` | JS CONFIG | 300,000 (5 min) | How long to cache disposition codes client-side before re-fetching |
| `WORKSTREAM_CACHE_TTL_MS` | JS CONFIG | 1,800,000 (30 min) | How long to cache workstream ID client-side |
| `SESSION_STORAGE_TTL_MS` | JS CONFIG | 1,800,000 (30 min) | How long the SessionGuard remembers a handled conversation |
| Poll interval | Cloud Flow | 2 seconds | Delay between Copilot summary polls |
| Poll max attempts | Cloud Flow (`Config` action) | 15 | Maximum number of poll attempts before giving up |
| Poll timeout | Cloud Flow | 2 minutes | Overall Do Until loop timeout (keeps the flow inside the 2-minute Power Apps response limit) |
| AI confidence threshold | Cloud Flow (`Config` action) | 0.40 | Minimum confidence score to include a recommendation |
| AI max recommendations | Cloud Flow (`Config` action) | 3 | Maximum number of codes returned to the Custom Page |
| AI temperature | AI Prompt | 0 | Lowest run-to-run variation (not a determinism guarantee) |
| `ENABLED` | JS CONFIG | `true` | Kill switch. Set to `false` and publish to stop the modal without touching the form registration |
| `ENABLED_WORKSTREAM_IDS` | JS CONFIG | `[]` (all) | Optional allowlist of workstream IDs (lowercase GUIDs) for a phased rollout |
| `DISPOSITION_FETCH_LIMIT` | JS CONFIG | 500 | Maximum disposition codes loaded; a console warning is logged when the limit is reached |

### Changing Configuration

- **JS parameters**: Edit the web resource `ccaasfde_dispositioncodeformhandler` in the solution → modify `CONFIG` object → save and publish
- **Cloud Flow parameters**: Edit the Cloud Flow → modify the `Config` action (poll attempts, confidence threshold, max recommendations) or the Wait duration
- **AI prompt parameters**: Go to AI Builder → AI Models → Disposition code classifier → edit prompt text

---

## 14. Security & Compliance

### Security Model

| Aspect | Detail |
|--------|--------|
| **Authentication** | Calls made by the JS handler and the Custom Page (reading codes, saving the disposition map) use the agent's security context. The Cloud Flow is different — see the next row |
| **Authorization** | Agents must have read access to `msdyn_ocliveworkitem`, `msdyn_ocdispositioncode`, `msdyn_conversationinsights` and create access to `msdyn_conversationdispositioncodemap`. These are granted by the standard **Omnichannel Agent** security role |
| **Cloud Flow execution** | Runs as the connection reference owner, **not** the calling agent, so it cannot enforce the agent's own access to a conversation. The flow only validates that `conversationId` is a GUID before using it in a query. Use a dedicated service account with read-only access to `msdyn_conversationinsights` and limit who can run the flow. Switching the flow to run as the invoking user is listed in the roadmap |
| **AI Builder** | Prompt executes through AI Builder (Azure OpenAI) inside the Power Platform service boundary. Data residency depends on your environment region and the AI Builder / Copilot cross-geography data movement settings — verify these against your compliance requirements |
| **No custom security roles** | This solution does not create or require custom security roles |
| **No plugins / custom APIs** | No server-side code execution — all logic is client-side JS + Cloud Flow + AI Builder |

### Data Classification

| Data Element | Classification | Handling |
|-------------|---------------|----------|
| Conversation summary (Copilot) | Internal / Confidential | Read from Dataverse, passed to AI Builder within tenant boundary. Not stored separately |
| Disposition codes | Internal | Configuration data, read-only from Dataverse |
| Selected disposition (agent choice) | Internal | Written to standard Dataverse table (`msdyn_conversationdispositioncodemap`) |
| AI confidence scores | Internal | Transient — displayed in UI, not persisted |

### Compliance Considerations

- **GDPR / privacy**: The Copilot summary is an abstraction of the conversation but can still contain personal data, and it is processed by AI Builder. Include this flow in your DPIA / records of processing. Disposition codes are operational metadata
- **AI Transparency**: Footer includes Microsoft AI disclaimer and Terms link. Confidence scores visible to agents
- **Audit Trail**: Dataverse audit logging (if enabled on `msdyn_conversationdispositioncodemap`) captures who created each disposition record and when

---

## 15. Performance

### Expected Latency

| Phase | Duration | Notes |
|-------|----------|-------|
| Form load → data pre-cached | < 1 second | Parallel fetch of workstream + disposition codes, non-blocking |
| Conversation end → modal appears | < 500ms | Instant — uses pre-cached data, no network call |
| Modal open → recommendations displayed | 2–8 seconds | Depends on Copilot summary availability (polling) + AI Builder response time |
| Agent saves → records written | < 2 seconds | 1–3 Dataverse Patch operations |
| **Total agent-visible time** | **3–10 seconds** | From conversation end to modal close |

### Scalability Considerations

| Factor | Limit | Mitigation |
|--------|-------|------------|
| Cloud Flow concurrency | Power Automate fair-use limits (depends on license) | Each flow run is short-lived (< 30s). At 500 concurrent agents, peak = ~500 concurrent runs — within limits |
| AI Builder throughput | API rate limits per environment | GPT-4.1-mini prompts are fast (~1–2s). Rate limit unlikely to be hit unless >1000 simultaneous classification requests |
| Dataverse API limits | 6,000 requests/5 min per user | Each conversation generates ~5–10 API calls total (reads + writes). Well within limits |
| Client-side caching | sessionStorage (per browser tab) | Prevents redundant API calls for workstream/disposition data |

---

## 16. Monitoring & Observability

### Monitoring Checklist

| What to Monitor | Where | Alert Threshold |
|----------------|-------|-----------------|
| Cloud Flow run failures | Power Automate → Flow runs → filter by "Failed" | Any failure in production |
| Cloud Flow "no summary" rate | Flow runs → filter by response containing `"success": false` | > 20% of runs indicate Copilot may not be configured correctly |
| AI Builder errors | AI Builder → Models → Disposition code classifier → Run history | Any error |
| AI confidence distribution | (Custom report) Average confidence across recommendations | Median confidence < 0.50 may indicate poor prompt-taxonomy fit |
| Agent skip rate | (Custom report) Conversations closed without disposition records | Increase from baseline may indicate UX friction |

### Cloud Flow Run History

Navigate to: **make.powerapps.com** → Solutions → AIDispositionCode → Cloud flows → Disposition Recommender → Run history

Each run shows:
- Trigger inputs (conversationId, workstreamId, codes)
- Number of poll iterations
- Whether summary was found
- AI Builder response
- Final output returned to Custom Page

---

## 17. Known Limitations

| # | Limitation | Impact | Workaround |
|---|-----------|--------|------------|
| 1 | **Copilot summary required** | If Copilot for Customer Service is not enabled or hasn't generated a summary for the conversation, the flow gives up after about 45 seconds (15 polls) and shows "No AI recommendations available" | Agent can pick a code from the list shown in the modal, or search in the picker. No dead end |
| 2 | **Polling delay** | The Cloud Flow polls every 2 seconds for the Copilot summary. Typical wait: 2–6 seconds. Long or complex conversations may take longer for Copilot to summarize | Loading spinner with status message keeps the agent informed. Can reduce poll interval to 1s if needed (increases API calls) |
| 3 | **Creator Kit dependency** | The PowerCAT Picker control requires Creator Kit Core. If not installed, the Custom Page shows a "control not found" error | Install Creator Kit Core from AppSource before importing. See Prerequisites (Section 10) |
| 4 | **SessionGuard cancel → no retry** | If the agent cancels or closes the modal, the `sessionStorage` guard marks the conversation as handled. The modal won't reappear for that conversation in the same browser session (a modal that *fails to open* is released and retried) | Agent can still assign disposition codes via the standard D365 disposition control on the conversation record |
| 5 | **Single-language prompt** | The AI prompt is English-only. Summaries in other languages may produce lower-quality matches | For multilingual deployments, the prompt can be adapted. AI Builder supports multilingual prompts |
| 6 | **Canvas App is a binary artifact** | The `.msapp` cannot be meaningfully diffed in Git | `src/canvas/*.pa.yaml` holds the readable source and the tests verify it matches the `.msapp`. See Section 21 |
| 7 | **500-code limit** | The JS handler loads at most 500 active codes. Beyond that, extra codes are missing from AI recommendations and search | A console warning is logged. Reduce the taxonomy per workstream or raise `DISPOSITION_FETCH_LIMIT` and test the payload size |
| 8 | **Save has no error handling** | The Save button shows "Saved successfully" even if a `Patch` fails, does not de-duplicate codes and does not check that the conversation record exists (unchanged from 1.0.0.2) | Verify in the standard disposition control. A hardened Save was attempted but could not be verified, see Section 22 |

---

## 18. Troubleshooting

### Common Issues

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| Modal never appears after conversation end | JS handler not registered on form, or CIF not loaded | Verify `ccaasfde_dispositioncodeformhandler` is in the Active Conversation form `onLoad` events (ordinal 7). Check browser console for `[ccaasfde dispo v2.2]` log messages. Also check that `CONFIG.ENABLED` is `true`, the workstream is in `ENABLED_WORKSTREAM_IDS` (if set) and the workstream has active disposition codes — the modal is skipped otherwise |
| Modal appears twice | Running v2.0 JS (without SessionGuard) | Confirm the web resource is v2.1 or later by checking for `SessionGuard` in the code. Re-import solution if needed |
| Modal shows "No AI recommendations" but Copilot is enabled | Copilot summary not generated in time (flow timed out) | Check Cloud Flow run history — verify poll count reached 15. May need to increase poll count or interval. Also verify `msdyn_conversationinsights` has records for the conversation |
| "Control not found" error in Custom Page | Creator Kit Core not installed | Install Creator Kit Core from AppSource |
| Cloud Flow fails with "connection" error | Dataverse connection reference not configured or expired | Open the solution → Connection references → create/update the Dataverse connection |
| Save fails / no records created | Agent lacks create permission on `msdyn_conversationdispositioncodemap` | Assign the Omnichannel Agent security role to the user |
| AI recommendations are poor quality | Disposition code taxonomy doesn't match conversation topics, or prompt needs tuning | Review the prompt in AI Builder. Test with sample summaries. Consider adjusting confidence threshold or prompt instructions |

### Debug Mode

The JS handler logs to the browser console with the prefix `[ccaasfde dispo v2.2]`. To enable verbose logging:

1. Open browser DevTools (F12)
2. Console tab → filter by `ccaasfde`
3. All lifecycle events, cache operations, and error states are logged

---

## 19. Rollback Procedure

If the solution needs to be reverted:

| Step | Action | Detail |
|------|--------|--------|
| 1 | Turn off Cloud Flow | Solutions → AIDispositionCode → Cloud flows → Disposition Recommender → Turn off |
| 2 | Remove JS handler from form | Open Active Conversation form → Events → `onLoad` → remove `ccaasfde_dispositioncodeformhandler` → Save and publish |
| 3 | Delete solution (optional) | Solutions → AIDispositionCode → Delete. This removes all solution components but does **not** delete disposition records already created in `msdyn_conversationdispositioncodemap` |
| 4 | Verify | End a test conversation → confirm no modal appears and standard disposition control still works |

> **Data impact**: Deleting the solution does NOT delete disposition records already written. The `msdyn_conversationdispositioncodemap` records are data, not metadata — they persist after solution removal.

---

## 20. Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| **1.0.0.3** | 2026-10-29 | FDE contributor | **Hardening release, tested on a sandbox (see Section 21).** JS handler v2.2 (retry after failed open, `formContext.data.refresh`, kill switch + workstream allowlist, skip when no codes, scoped globals, dead code removed). Flow: Try/Catch with a guaranteed response, input validation, non-empty summary polling, model output validation (ids, confidence, max 3), 2-minute poll bound. Prompt: no summary echo, prompt-injection guard, few-shot examples. Canvas: test mode removed, flow/parse errors degrade to the manual picker, recommendation ids validated and labels taken from our own list (the Save formula is unchanged), the picker search now filters as you type, and when the AI has no recommendation a clickable list of all codes is shown (the PowerCAT Picker cannot open its own dropdown on focus). The canvas app was rebuilt with `pac canvas pack`. Solution: removed forced CS workspace app settings, copied OOB event handlers/role maps and 37 stale dependencies. Added `src/`, build script, tests, CI. Review follow-ups: empty-array fallback uses `json('[]')`, confidence must be a number in [0, 1], the code list is validated before polling or the AI call, error paths stop the loading spinner, and re-evaluating the handler script no longer registers a second end-of-conversation callback |
| **1.0.0.2** | 2025-12-23 | CCaaSFDE | JS handler upgraded to v2.1 — added `SessionGuard` using `sessionStorage` to prevent duplicate modal on tab/form close. Cleaned `AppModuleComponents` in `customizations.xml` to prevent unintended removal of CS Workspace components on import |
| **1.0.0.1** | 2025-12-20 | CCaaSFDE | AI Builder prompt tuning — tightened classification rules, added confidence threshold, improved output format specification. Canvas App UI refinements |
| **1.0.0.0** | 2025-12-20 | CCaaSFDE | Initial release — Cloud Flow (Disposition Recommender), Custom Page (Disposition Recommendation), AI Model (Disposition code classifier), JS handler v2.0. Full end-to-end pipeline for AI-assisted disposition code selection |

---

## 21. Building & Testing

The importable zip is generated from sources. Requires Node.js 22+; there are no npm dependencies and the Power Platform CLI (`pac`) is **not** needed.

| Path | Purpose |
|------|---------|
| `src/webresource/dispositioncodeformhandler.js` | Source of the form handler. `npm run build` copies it to `solution/WebResources/` |
| `src/prompt/disposition-classifier.prompt.txt` | Source of the AI prompt (`{{Summary}}` and `{{Codes}}` are the inputs). `npm run build` writes it into `solution/customizations.xml` |
| `src/canvas/*.pa.yaml` | Readable copy of the canvas app source (reference). The tests verify it matches the `.msapp` |
| `solution/` | Unpacked solution (what gets zipped) |
| `scripts/` | `build.mjs` (sync + zip, `--check` to verify) and a small zip reader/writer |
| `tests/` | Automated tests (`node --test`) |

```bash
npm test          # run all tests
npm run build     # sync src -> solution and rebuild AIDispositionCode_<version>.zip
npm run check     # fail if solution/ or the zip is out of sync with src/
```

**What the tests cover:** the form handler running in an isolated VM with mocked `Xrm` and CIF (guards, retry, cancel, refresh, kill switch, allowlist), the flow definition (every `runAfter`, expression reference and the Try/Catch response guarantee), the prompt/AI configuration, solution XML well-formedness, zip contents, and consistency between the canvas YAML and the formulas stored in the `.msapp`.

**What they cannot cover:** import into Dataverse, Power Automate expression evaluation, Power Fx evaluation, AI Builder output quality and real CIF behavior. Run the smoke tests in Section 12 in a sandbox before promoting a build.

**Changing the canvas app:** edit it in Power Apps Studio, export the solution, then replace the `.msapp` in `solution/CanvasApps/` and refresh `src/canvas/*.pa.yaml` (`pac canvas unpack` produces them). Run `npm test` to confirm they match.

**Canvas gotcha (verified on a real environment):** never write `Set(x, IfError(Flow.Run(...), ...))`. The page then never calls the flow and stays on the loading spinner. Use `IfError(Set(x, Flow.Run(...)), Set(x, fallback))` instead. A test enforces this.

**What was verified on a sandbox (Dynamics 365 CS workspace, solution imported unmanaged):**

| Area | Result |
|------|--------|
| Solution import | Succeeds, 26 components. Re-import over an existing install succeeds |
| Flow end to end (real Copilot summaries, real codes, real AI Builder call) | Correct ranked recommendations: *Return* 0.9 / *Refund* 0.6, *Refund* 0.9, *Contract Cancelation* 0.9, *Windshield Repair* 0.9, and an empty result for an unrelated lease-payment call. 3–5 s per call |
| Flow failure paths | Malformed input and an OData-injection attempt are rejected. A forced model-side failure returns `success:false` with the summary. No summary or no insight record returns the "No Copilot summary" result after about 45 s |
| Canvas page | Loads, calls the flow, shows ranked chips with labels from the environment's own code list, Save button enabled |
| Form handler v2.2 | Registered on the Active Conversation form. Behavior covered by the automated tests; not exercised against a live end-of-conversation event |
| **Not verified** | Saving codes from the canvas page against a live conversation (the page could not be driven reliably in the available automation browser); a rewritten Save formula did not save and was **not shipped**; live CIF end-conversation event |

---

## 22. Roadmap & Not Yet Implemented

| Item | Why it is not in 1.0.0.3 |
|------|--------------------------|
| **Stop shipping the Active Conversation form** | Importing the solution overwrites the form's unmanaged layer (see Section 11). A safer design registers the handler with a small post-import script (or a form patch) instead of carrying the whole form |
| **Hardened Save formula** (error reporting, de-duplication, conversation existence check) | A rewrite using `With` + `IfError(ForAll(Patch(...)))` did not save on the test environment and could not be debugged in time, so the original Save is shipped |
| **Suggestion-vs-selection logging** (needed to verify the accuracy and ROI claims in Section 4) | Needs a new Dataverse table (for example `ccaasfde_dispositionsuggestion`: conversation lookup, suggested ids + confidences, selected ids, prompt version, latency) written by the Custom Page on Save. Hand-authoring table metadata without an environment to validate it was too risky. Until then, accuracy has to be measured by QA sampling |
| Run the flow as the invoking user | Requires changing the connection model and re-testing run-only permissions in a real tenant |
| Environment-variable kill switch | `CONFIG.ENABLED` in the web resource is the interim control |
| Managed solution build | Requires a deliberate decision about layering the Active Conversation form customization |
| Multilingual prompt variants | Needs sample summaries per language to tune and test |
| Active Conversation form is still part of the solution | A solution can only register a form handler by including the form. Keep this in mind when other solutions customize the same form |

---

*Last updated: 2026-10-29 — Version 1.0.0.3*
