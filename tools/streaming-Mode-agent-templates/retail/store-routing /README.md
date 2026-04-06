<div align="center">

<img src="../../../../assets/d365cc-logo.png" width="60" alt="D365 Contact Center" />

*Crafted with care for contact center excellence*

</div>

# Retail Store Routing Template

Real-time voice agent template for routing callers to store departments in multi-department retail environments.

---

## Use Cases

- Large retail stores with multiple departments
- Pharmacy and specialty service routing
- Store hours inquiries
- General information and operator fallback

---

## What's Included

This template provides a production-tested pattern for:

| Component | Description |
|-----------|-------------|
| **Intent Confidence Model** | High/medium/low confidence classification |
| **Department Routing** | Configurable department codes and descriptions |
| **Immediate Transfer Rules** | Bypass clarification for clear intents (pharmacy, vision, HR) |
| **Speed Bump Logic** | Controlled escalation after clarification attempts |
| **Store Hours Integration** | Tool-based hours lookup with verbatim reading |
| **Knowledge Base Integration** | Article-driven answers with escalation rules |
| **Failure Tolerance** | Graceful degradation to operator |
| **Analytics Hooks** | Business, telemetry, and health metrics |

---

## Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `COMPANY_NAME` | string | Your company/brand name |
| `VOICE_STYLE` | string | Voice personality description |
| `SPECIALTY_SERVICES` | string | Comma-separated specialty services |
| `KNOWLEDGE_BASE_URL` | string | URL to your help/knowledge base |
| `SUPPORT_NUMBER` | string | Customer support phone number |
| `STORE_HOURS_TOOL` | string | Name of your store hours lookup tool |
| `DEPARTMENTS` | object | Department codes and descriptions |
| `IMMEDIATE_TRANSFER_INTENTS` | object | Intent phrases for immediate routing |
| `IMMEDIATE_TRANSFER_ACTIONS` | object | Actions for immediate transfer scenarios |

See [variables.example.json](./variables.example.json) for a complete example.

---

## How to Use

### 1. Copy the Template

```bash
cp template.json my-store-agent.json
```

### 2. Create Your Variables File

```bash
cp variables.example.json my-variables.json
# Edit my-variables.json with your values
```

### 3. Apply Variables to Template

You can use any templating tool (envsubst, jq, custom script) to replace `{{VARIABLE}}` placeholders:

```bash
# Example using envsubst
envsubst < template.json > my-configured-agent.json
```

Or use a simple Python script:

```python
import json
import re

with open('template.json') as f:
    template = f.read()

with open('my-variables.json') as f:
    variables = json.load(f)

for key, value in variables.items():
    if key.startswith('_'):
        continue
    placeholder = '{{' + key + '}}'
    if isinstance(value, (dict, list)):
        template = template.replace(f'"{placeholder}"', json.dumps(value))
    else:
        template = template.replace(placeholder, str(value))

with open('my-configured-agent.json', 'w') as f:
    f.write(template)
```

### 4. Validate Against Schema

```bash
# Using ajv-cli
npx ajv validate -s ../../_schema/realtime-agent.schema.json -d my-configured-agent.json
```

---

## Customization Guide

### Adding Departments

Add new entries to the `DEPARTMENTS` variable:

```json
{
  "DEPARTMENTS": {
    "garden_center": { "code": "150", "description": "Garden center" },
    "sporting_goods": { "code": "151", "description": "Sporting goods" }
  }
}
```

### Adding Immediate Transfer Intents

Extend the `IMMEDIATE_TRANSFER_INTENTS` with new categories:

```json
{
  "IMMEDIATE_TRANSFER_INTENTS": {
    "garden_intents": [
      "garden center hours",
      "plant availability",
      "landscaping question"
    ]
  }
}
```

### Modifying Intent Confidence Logic

The template uses a three-tier confidence model. Customize thresholds in the `intent_confidence_model` and `intent_handling` sections of the template.

### Adjusting Speed Bumps

Modify `speed_bump_rules.default_count` to change how many clarification attempts before escalation.

---

## Best Practices

1. **Test department codes** - Verify all routing codes work in your telephony system
2. **Validate hours tool** - Ensure your `STORE_HOURS_TOOL` returns data in expected format
3. **Review intents regularly** - Add new immediate transfer intents based on call analysis
4. **Monitor analytics** - Track escalation rates to identify improvement opportunities

---

## Related Templates

- [Appointment Management](../../professional-services/appointment-management/) - For service scheduling
