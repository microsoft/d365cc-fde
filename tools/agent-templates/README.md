<div align="center">

<img src="../../assets/d365cc-logo.png" width="60" alt="D365 Contact Center" />

*Designed to make modern contact centers simple and reliable*

</div>

# Agent Templates

Ready‑to‑use templates that help you quickly set up **voice agents** in **D365 Contact Center**.

These templates are already tested in real customer deployments, so you don’t have to start from scratch.

---

## What Is This?

Think of these templates as **pre-built blueprints** for how your phone agent behaves.

Each template defines:
- How the agent talks to callers
- What questions it asks
- How it understands customer requests
- What actions it can take (like routing calls or booking appointments)

**You just fill in your business details.**  
**The structure and best practices are already taken care of.**

---

## Available Templates

| Industry | Template | What It Helps With |
|--------|---------|--------------------|
| Retail | Store Routing | Routes calls to the right store department |
| Professional Services | Appointment Management | Identifies customers and schedules appointments |

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
**variables.example.json # Example values to fill in** Remove this file?   

____________________________________________________________________
You usually only need to edit the **template.json** file.

---

## How to Use a Template (Simple Version)

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

### Step 4: Validate (Optional but Recommended)

A validation step is available to check that nothing is missing before deployment.  
This helps catch typos or incomplete settings early.

---

### Step 5: Deploy

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
