<div align="center">

<img src="../../assets/d365cc-logo.png" width="80" alt="D365 Contact Center" />

# Dynamics 365 Contact Center
### Forward Deployed Engineering Toolkit

<br />

*Crafted with care for contact center excellence*

<br />

**AI-powered solutions for the next generation of customer service**

<br />

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)
[![GitHub issues](https://img.shields.io/github/issues/microsoft/d365cc-fde)](https://github.com/microsoft/d365cc-fde/issues)
[![GitHub stars](https://img.shields.io/github/stars/microsoft/d365cc-fde)](https://github.com/microsoft/d365cc-fde/stargazers)
[![Manifest V3](https://img.shields.io/badge/Chrome-Manifest%20V3-4285F4?logo=googlechrome&logoColor=white)](https://developer.chrome.com/docs/extensions/mv3/intro/)
[![Edge Compatible](https://img.shields.io/badge/Edge-Compatible-0078D7?logo=microsoftedge&logoColor=white)](https://microsoftedge.microsoft.com)

<br />

[**Get Started**](#quick-start) · [**Tools**](#available-tools) · [**Agent Templates**](#agent-templates) · [**Contributing**](#contributing)

<br />

---

</div>

## Forward Deployed Engineering

**Accelerating the future of AI-powered customer service at enterprise scale.**

The Forward Deployed Engineering team partners directly with the world's largest organizations to reimagine contact center operations through the power of Dynamics 365 Contact Center and Microsoft AI. We don't just implement technology—we engineer transformational outcomes.

Our mission is to close the gap between cutting-edge AI capabilities and real-world customer service operations, delivering production-ready solutions that drive measurable business impact from day one.

<div align="center">

| What We Do | How We Deliver |
|------------|----------------|
| **AI-First Engineering** | Leverage Copilot, GPT models, and Azure AI to automate agent workflows, predict customer intent, and deliver intelligent self-service |
| **Enterprise Architecture** | Design and deploy multi-region, high-availability contact center solutions for the world's most demanding organizations—Fortune 500, federal agencies, healthcare systems, and global enterprises |
| **Rapid Prototyping** | Transform customer challenges into working solutions in days, not quarters |
| **Open Source First** | Every solution we build is generalized and shared—elevating the entire ecosystem |

</div>

**Our Engineering Philosophy:**

- **Embedded with customers** — We operate on-site alongside contact center teams, not from conference rooms
- **Ship code, not slide decks** — We measure success in deployed solutions, not consulting hours
- **AI augments humans** — We build tools that make agents superhuman, not replace them
- **Scale by default** — Every solution handles millions of interactions from the start

---
## Streaming Mode Agent Templates

Production-tested templates for real-time voice agents (Speech-to-Speech). Each template is a parameterized configuration you can customize for your organization.

<div align="center">

| Industry | Template | Use Case |
|----------|----------|----------|
| Retail | [Store Routing](https://github.com/microsoft/d365cc-fde/tree/main/tools/streaming-Mode-agent-templates/retail/store-routing%20) | A rules-driven, deterministic retail store IVR that identifies caller intent, retrieves approved store information using validated tools, and routes callers to the correct department or representative without inventing answers. Used to handle high-volume store calls by answering store hours and service questions, sending approved links via SMS using internal API tools, and routing callers to departments such as Pharmacy, Vision, OPD, HR, quickly and consistently. |
| Professional Services | [Appointment Management](./professional-services/appointment-management/) | A deterministic, low-latency voice IVR that strictly identifies callers and manages appointments via validated tools with ISO-formatted data to prevent errors and assumptions. Used to reliably book, view, update, cancel, or route appointment-related requests in one voice experience while reducing scheduling mistakes, misroutes, and unnecessary live-agent handoffs. |
| Pharmaceuticals | [Healthcare Professional](./pharmaceuticals/hcp-patient-voice-agent/) | A pharmaceutical-grade, low-latency voice IVR that validates HCP eligibility, normalizes drug names from natural speech, checks live inventory, and creates confirmed sample requests via ERP/back-end APIs. Used to handle HCP + patient inbound calls by enforcing policy, collecting structured details conversationally, validating drug names for lookup, verifying inventory, creating confirmed sample requests, delivering request numbers via SMS, supporting copay/financial assistance intents, and escalating to CSRs with full context to reduce forms, callbacks, and handle time. |
| healthcare | [Pharmacy](./healthcare/pharmacy/) | A secure, deterministic IVR for high-volume pharmacy member services that performs single identity verification (speech or DTMF) once, then silently orchestrates specialized child intents without re-authentication. Used to provide prescription order status with sensitive medication masking, plan-specific drug pricing (brand vs. generic resolution), and DTMF-secured refill payment collection—allowing callers to switch intents freely while reducing live-agent escalation across retail, mail-order, and PBM lines. |
| Generic | [Skeleton Template](./Generic%20template/Realtime-agent-config/) | A reusable, rules-first voice agent blueprint designed for safe, deterministic IVR behavior. It enforces strict conversation structure (state machine), short turn-taking, one-question-at-a-time prompts, tool-only truth (no fabrication), hard safety boundaries (no restricted data), and standardized escalation/closing behavior. Use this template as the base framework to build any enterprise IVR by plugging in company details, scope, tools, states, and handoff rules while ensuring consistent compliance, tool discipline, and predictable customer experience across all deployments. |
</div>

**What's included:**

- Parameterized JSON templates with `{{VARIABLE}}` placeholders
- Example variable files for quick customization  
- JSON Schema for validation
- Comprehensive documentation

[**Browse Templates →**](./tools/streaming-Mode-agent-templates/)

---

## Quick Start

---

## How These Templates Help You

Instead of designing a voice agent from scratch, you:

1. Pick a template that matches your scenario  
2. Enter your company‑specific details (like company name or business rules)  
3. Upload it into D365 Contact Center  

That’s it.

No deep technical design required.

---

## What’s Inside a Template?

template-name/
README.md              # Documentation and customization guide
template.json          # Parameterized template ({{VARIABLES}})
____________________________________________________________________
You usually only need to edit the **template.json** file.

---

## How to Use a Template

### Step 1: Pick a Template

Choose the template that best matches your business use case.

---

### Step 2: Fill in Your Details

Open the **template.json** file and replace the placeholder values shown like `{{...}}`.

For example:
- `{{COMPANY_NAME}}`
- `{{Department names}}`
- `{{Business hours}}`
- `{{Tool names}}`

You don’t need to understand the underlying code — just replace the example text with your own details.

---

### Step 3: Apply Your Details

The template automatically uses your values wherever they are needed.

This helps ensure:
- The agent speaks consistently
- Business rules remain aligned
- Nothing important is missed

---

### Step 4: Deploy

Copy and paste the completed **JSON** content into your **Copilot Studio agent instructions**, then publish your agent.

Your voice agent is now ready.

---

## What the Agent Is Made Of (Conceptually)

You don’t need to edit these sections directly, but understanding them can be helpful.

### Agent Personality & Goal

Defines:
- How the agent sounds (friendly, professional, calm)
- What the agent’s main responsibility is (for example, routing calls correctly)

---

### Guardrails (What the Agent Can and Can’t Do)

Clearly defines:
- Which topics the agent is allowed to handle
- What the agent should do when something is out of scope (such as escalating to a human agent)

---

### How the Agent Handles Confidence

The agent behaves differently based on how confident it is about the caller’s intent:
- **High confidence** → acts immediately
- **Medium confidence** → confirms with the caller
- **Low confidence** → asks follow-up questions or routes to an agent

---

### Tool Usage

Templates define **when and how** the agent interacts with business systems, such as:
- Looking up customer information
- Checking availability
- Booking appointments

This ensures consistent and predictable behavior.

---

## Quality Checks

All templates follow a standard structure to ensure:
- Reliability
- Predictable behavior
- Easy maintenance

Optional validation tools are available for teams that want extra assurance before deploying.

---

## Best Practices

### Recommended

- JSON‑formatted instructions are especially effective for complex scenarios where an agent uses multiple tools, steps, and conditional logic.
- While not mandatory, following a structured JSON template has proven to be faster and consistently yields better results.
- Start with the example values and change only what you need  
- Test common scenarios before going live  
- Monitor call outcomes after deployment  

### Avoid

- Guessing IDs or system values  
- Skipping confirmation or fallback scenarios  
- Deploying without testing escalation paths  

---

## Want to Contribute?

If you have a template that works well in production, we welcome contributions.

Please:
1. Replace customer-specific data with placeholders  
2. Remove any sensitive information  
3. Add clear documentation  
4. Include example values  

See `CONTRIBUTING.md` for details.

---

## Need Help?

- Ask questions in Discussions  
- Report issues on GitHub  

We’re here to help you succeed.
