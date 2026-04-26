<div align="center">
<img src="../../../../assets/d365cc-logo.png" width="60" alt="D365 Contact Center" />
  </BR>
*Crafted with care for contact center excellence*

</div>

# Pharmacy Voice Agent — Multi-Agent S2S Template

Real-time speech-to-speech voice agent template for pharmacy member services. Covers identity verification, order status, drug pricing, and prescription refill in a single natural conversation using a parent orchestrator with dedicated child agents.

---

## Use Cases

- Retail pharmacy chains
- Mail-order and specialty pharmacy
- Health plan pharmacy benefit lines
- Any pharmacy requiring member-authenticated voice self-service

**These templates are provided as starting guidelines to help you kick‑start development. They must be reviewed, updated, and tailored to align with your organization’s specific use cases, policies, and requirements.**


---

## What's Included

| Component | Description |
|-----------|-------------|
| **Parent Orchestrator** | Intent detection, member identity verification, and child agent routing |
| **Member Authentication** | Variable-length member ID + DOB capture via speech and DTMF |
| **Order Status Child** | Retrieves all prescription orders with sensitive medication masking |
| **Drug Pricing Child** | Resolves drug version and returns plan-specific pricing |
| **Refill Child** | Presents refill offer and collects DTMF-only card payment |
| **Seamless Intent Switching** | Caller moves between intents without re-authenticating |
| **DTMF + Speech Input** | Supports keypad and voice simultaneously for member ID capture |
| **Payment Security** | Card number, expiry, and security code are DTMF-only |
| **Low Latency Behavior** | One acknowledgment per turn, silence preferred while tools run |

## Runtime & Technology

This template is built for **speech-to-speech (S2S)** mode in **Dynamics 365 Contact Center**, powered by:

- **Copilot Studio** — hosts the agent configuration, tools, child agent routing, and session lifecycle
- **GPT-4o Realtime** — the underlying voice runtime that processes audio end-to-end in a single low-latency pass, with no intermediate text step

### How It Works

Unlike a text chatbot, in S2S mode the GPT-4o Realtime runtime:

1. Receives live audio directly from the caller
2. Speaks responses back in real time — no text-to-speech conversion step
3. Interprets the agent JSON loaded in Copilot Studio as live behavioral constraints on every turn
4. Calls Power Automate flows (tools) mid-conversation and speaks results back immediately

The template JSON you configure in Copilot Studio is loaded directly into the GPT-4o Realtime session as the system prompt. Every field — `grounding_principles`, `conversation_states`, `context_rules` — is an active instruction that shapes model behavior on each turn of the live voice call.

### What `context_rules` Does

`context_rules` in each child agent template tells the GPT-4o Realtime runtime **how to behave** during that agent's portion of the call. It is not metadata — it is interpreted at runtime on every turn.

| Rule Group | What It Controls at Runtime |
|---|---|
| `voice_first: true` | Optimizes output for speech — short sentences, no markdown, no bullet lists |
| `keep_session_alive: true` | Prevents the GPT-4o session from closing after a tool response or caller silence |
| `session_timeout_seconds: 0` | Disables automatic session timeout — agent stays active until the call ends |
| `conversation_rules` | Turn-by-turn flags: one acknowledgment per turn, no wake-up prompts, seamless intent switching |
| `payment_input_policy` | Restricts payment field input to DTMF only — spoken card numbers are rejected |

These flags directly constrain GPT-4o's generation. For example, `never_use_call_closing_language: true` prevents the model from producing phrases like *"Have a great day!"* that would prematurely signal end of call on a live voice line.

---

## Agent Architecture

```
Caller
  │
  ▼
┌──────────────────────────────────────────────────┐
│  Parent Orchestrator  ({{PARENT_AGENT_NAME}})    │
│                                                  │
│  1. Intent Detection                             │
│  2. Identity Verification  ──► {{MEMBER_AUTH_TOOL}} │
│  3. Route to Child Agent                         │
└──────────┬──────────────┬──────────────┬─────────┘
           │              │              │
    ┌──────▼──────┐ ┌─────▼──────┐ ┌────▼──────┐
    │ Order Status│ │Drug Pricing│ │  Refill   │
    │   Child     │ │   Child    │ │   Child   │
    │             │ │            │ │           │
    │{{ORDER_     │ │{{DRUG_     │ │{{REFILL_  │
    │STATUS_TOOL}}│ │VERSION_    │ │TOOL}}     │
    │             │ │TOOL}}      │ │           │
    │             │ │{{DRUG_     │ │ DTMF-only │
    │             │ │PRICE_TOOL}}│ │ payment   │
    └─────────────┘ └────────────┘ └───────────┘
```

---

## Conversation Flow

```
┌─────────────────────────────────┐
│  Incoming Call                  │
│  └─> Detect Intent              │
└────────────┬────────────────────┘
             │
     ┌───────┴────────┐
     │                │
 ┌───▼────┐      ┌────▼────────────────────┐
 │Already │      │    Identity Verification │
 │Verified│      │                          │
 └───┬────┘      │  Ask Member ID + DOB     │
     │           │  ├─ Accept DTMF or speech│
     │           │  ├─ Read back, confirm   │
     │           │  └─ Max 3 attempts       │
     │           └────────────┬────────────┘
     │                        │
     │           ┌────────────▼────────────┐
     │           │  Authenticate Member    │
     │           │  {{MEMBER_AUTH_TOOL}}   │
     │           │  ├─ Success → continue  │
     │           │  └─ Fail → re-verify    │
     │           └────────────┬────────────┘
     │                        │
     └───────────┬────────────┘
                 │
     ┌───────────▼─────────────┐
     │  Route Request          │
     │  (set focus_intent)     │
     └──────┬────────┬────┬────┘
            │        │    │
   ┌────────▼──┐  ┌──▼──┐ └──────────────┐
   │  Order    │  │Drug │                │
   │  Status   │  │Price│             ┌──▼─────┐
   │           │  │     │             │ Refill │
   │ Retrieve  │  │Resolve            │        │
   │ orders    │  │drug  │            │ Offer  │
   │ Filter by │  │version            │ refill │
   │ intent    │  │Get   │            │ DTMF   │
   │ Present   │  │pricing            │ payment│
   │ results   │  │Present            │ Confirm│
   └────────┬──┘  └──┬──┘             └──┬─────┘
            │        │                   │
            └────────┴─────────┬─────────┘
                                │
              ┌─────────────────▼──────────────┐
              │  Continue or Switch Intent      │
              │  (no re-auth while same member) │
              └────────────────────────────────┘
```

---

## Required Variables

Fill in all values in `variables.example.json` before deploying.

### Branding

| Variable | Type | Description |
|----------|------|-------------|
| `COMPANY_NAME` | string | Your pharmacy or brand name |
| `VOICE_STYLE` | string | Voice personality (e.g. "warm, professional pharmacy voice") |

### Agent Config Names
Must match the agent configuration names set up in your D365 environment exactly.

| Variable | Description |
|----------|-------------|
| `PARENT_AGENT_NAME` | Config name for the parent orchestrator agent |
| `CHILD_ORDER_STATUS_CONFIG` | Config name for the order status child agent |
| `CHILD_DRUG_PRICING_CONFIG` | Config name for the drug pricing child agent |
| `CHILD_REFILL_CONFIG` | Config name for the refill child agent |

### Tool / Flow Names
Replace with the actual tool or Power Automate flow names registered in your D365 environment.

| Variable | Description |
|----------|-------------|
| `MEMBER_AUTH_TOOL` | Member authentication — accepts member ID and DOB |
| `ORDER_STATUS_TOOL` | Retrieves all prescription orders for a member |
| `DRUG_VERSION_TOOL` | Resolves drug name to form, strength, and version |
| `DRUG_PRICE_TOOL` | Returns plan-specific pricing for a resolved drug |
| `REFILL_TOOL` | Retrieves refill-eligible prescriptions |

### Mock / Demo Data *(remove in production)*

| Variable | Description |
|----------|-------------|
| `MOCK_MED_1_NAME` … `MOCK_MED_3_NAME` | Medication names for demo mode |
| `MOCK_MED_1_STRENGTH` … `MOCK_MED_3_STRENGTH` | Strengths for demo mode |
| `MOCK_30DAY_PRICE_MIN/MAX` | Price range for 30-day supply demo |
| `MOCK_90DAY_PRICE_MIN/MAX` | Price range for 90-day supply demo |

See [variables.example.json](./variables.example.json) for a complete example.

---

## How to Use

### 1. Copy the Variables File

```bash
cp variables.example.json my-variables.json
# Edit my-variables.json with your actual values
```

### 2. Replace Placeholders

Replace every `{{VARIABLE}}` in all template files with the values from your variables file.

### 3. Configure Agents in D365

Create one agent per template file in your D365 environment:

| Template File | D365 Agent Config |
|---|---|
| `parent_template.json` | Set name = your `PARENT_AGENT_NAME` value |
| `child_order_status_template.json` | Set name = your `CHILD_ORDER_STATUS_CONFIG` value |
| `child_drug_pricing_template.json` | Set name = your `CHILD_DRUG_PRICING_CONFIG` value |
| `child_refill_template.json` | Set name = your `CHILD_REFILL_CONFIG` value |

### 4. Register Tools and Flows

Register each tool or Power Automate flow in D365 using the names from your variables file.

### 5. Validate Against Schema

```bash
# Validate parent orchestrator
npx ajv validate -s _schema/multiagent-orchestrator.schema.json -d parent_template.json

# Validate each child agent
npx ajv validate -s _schema/child-agent.schema.json -d child_order_status_template.json
npx ajv validate -s _schema/child-agent.schema.json -d child_drug_pricing_template.json
npx ajv validate -s _schema/child-agent.schema.json -d child_refill_template.json
```

### 6. Deploy

Copy and paste each completed JSON into the corresponding Copilot Studio agent instructions, then publish.

---

## Critical Rules

### Member ID Capture

Member IDs are variable-length and may be numeric or alphanumeric:

```
Numeric:       77670110802
Alphanumeric:  RS12123123
```

- Accept both DTMF and speech simultaneously
- For alphanumeric IDs: collect letter prefix via speech (or NATO phonetics), then switch to DTMF for digits
- Always read back the full ID one character at a time before proceeding
- Never truncate based on assumed length

### DTMF-Only Payment Fields

Card number, expiration date, and security code in the refill agent must be entered by keypad only:

```json
"payment_fields_dtmf_only": true,
"reject_speech_for_payment_fields": true
```

If the caller speaks payment digits, re-prompt for keypad input.

### Intent Switching

Callers may switch between order status, pricing, and refill at any point. The parent re-routes silently — never mention transfer, handoff, or agent routing to the caller.

---

## Best Practices

1. **Test authentication end-to-end** — Verify `MEMBER_AUTH_TOOL` handles both numeric and alphanumeric member IDs
2. **Validate child agent names** — Config names in D365 must exactly match the values in your variables file
3. **Remove mock data before production** — Delete or disable `mock_data_rules` in `child_refill_template.json`
4. **Test intent switching** — Walk through all transitions: pricing → refill, order status → pricing, etc.
5. **Monitor DTMF collection** — Log cases where callers exceed silence nudge limits in the refill payment flow
6. **Handle sensitive medications** — Ensure `isSensitiveMedication` flag is respected in order status responses

---

## Schema

This template introduces a multi-agent pattern not covered by the base `realtime-agent.schema.json`. Two dedicated schemas are provided:

| Schema File | Validates |
|---|---|
| `_schema/multiagent-orchestrator.schema.json` | `parent_template.json` |
| `_schema/child-agent.schema.json` | All `child_*_template.json` files |

---
