<div align="center">
<img src="../../../../assets/d365cc-logo.png" width="60" alt="D365 Contact Center" />
  </BR>

*Crafted with care for contact center excellence*

</div>

# Healthcare Professional & Patient Voice Agent Template

Real-time voice agent template for pharmaceutical support, drug information, and healthcare professional sample requests with intelligent drug recognition and eligibility verification.

---

## Use Cases

- Drug information inquiries from patients and HCPs
- Healthcare professional sample requests
- Copay card support and enrollment
- Medication eligibility verification
- Drug lookup and confirmation
- Manufacturer information for non-Pfizer drugs
- Case creation and SMS confirmation

---

## What's Included

This template provides a production-tested pattern for:

| Component | Description |
|-----------|-------------|
| **Drug Recognition Engine** | Transcription normalization and spelling confirmation |
| **Intent Detection** | Keyword-based routing to samples, copay card, or general support |
| **HCP Eligibility Verification** | Licensed professional validation with NPI collection |
| **Intake & Routing Flow** | Structured drug and intent collection with validation |
| **FDA Drug Lookup** | Pfizer ownership detection and manufacturer information |
| **Sample Inventory Management** | Mock inventory table with availability checking |
| **Case Creation & SMS** | Random case number generation with SMS confirmation |
| **Natural Conversation** | No greetings, no filler, spelling confirmation, interruptions allowed |
| **Silence & Presence Cues** | 2-second silence limit with liveness indicators |
| **Error Handling** | Graceful drug lookup retry and escalation to human agents |

---

## Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `BRAND_NAME` | string | Pharmaceutical brand (e.g., Pfizer) |
| `CHANNEL` | string | Support channel (e.g., real-time voice) |
| `BRAND_DESCRIPTION` | string | Brand voice and positioning |
| `BRAND_OBJECTIVE` | string | Agent purpose and call objectives |
| `DRUG_LOOKUP_TOOL` | string | Name of FDA drug lookup tool |
| `SMS_TOOL` | string | Name of SMS outbound tool |
| `DEFAULT_PHONE_NUMBER` | string | Fallback phone number for SMS routing |
| `SAMPLE_PHONE_ROUTING` | object | Phone number routing rules |
| `COPAY_CARD_PHONE` | string | Copay card support phone |
| `TRANSFER_PHONE` | string | Default transfer number |

See [variables.example.json](./variables.example.json) for a complete example.

---

## Key Features

### Drug Recognition & Validation
- Normalizes speech transcription artifacts (duplicate letters, etc.)
- Spells drug names aloud for caller confirmation
- Converts confirmed names to ALL CAPS before lookup
- Handles pronunciation corrections gracefully
- Retries with phonetic variations if lookup fails

### Intelligent Intake Flow
- Collects drug name and caller intent simultaneously when possible
- Asks only missing information
- Handles multiple drugs one at a time
- Confirms understanding before proceeding to lookup

### HCP Sample Request Flow
- Verifies caller is a licensed healthcare professional
- Collects required fields: Full Name, Practice Name, NPI, Address, Drug, Quantity
- Checks mock inventory table
- Generates 5-digit case number
- Sends SMS confirmation with case number
- Handles back-to-back requests without re-greeting

### FDA Drug Lookup
- Checks if drug is manufactured by brand (Pfizer)
- Informs caller of manufacturer if not supported
- Offers human agent transfer for non-brand drugs
- Handles no-match scenarios with retry logic

### Copay Card Support
- Keyword detection for copay/savings card inquiries
- Routes appropriately based on caller type

### Conversation Behavior
- No initial greeting—caller speaks first
- No filler phrases ("I'm here to help")
- Short, natural sentences optimized for voice
- Allows interruptions and doesn't wait silently > 2 seconds
- Never ends call unless caller explicitly asks
- Professional but never scripted tone

---

## How to Use

### 1. Copy the Template

```bash
cp template.json my-hcp-agent.json
```

### 2. Create Your Variables File

```bash
cp variables.example.json my-variables.json
# Edit my-variables.json with your organization's values
```

### 3. Apply Variables to Template

You can use any templating tool to replace `{{VARIABLE}}` placeholders:

```bash
# Example using envsubst
envsubst < template.json > my-configured-agent.json
```

Or use a simple Python script:

```python
import json

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
        template = template.replace(f'"{placeholder}"', f'"{value}"')

with open('my-configured-agent.json', 'w') as f:
    f.write(template)
```

### 4. Deploy to Real-Time Agent

Use the configured agent JSON with your contact center platform's real-time agent deployment service.

---

## Mock Inventory Table

The template includes a sample inventory table for testing:

```json
{
  "BENEFIX": { "available": 25 },
  "PAXLOVID": { "available": 10 },
  "ELIQUIS": { "available": 0 }
}
```

Replace with your actual inventory data source or connect to a live inventory API.

---

## Testing Checklist

- [ ] Agent does not greet caller—caller speaks first
- [ ] Drug name is confirmed by spelling aloud
- [ ] Drug names converted to ALL CAPS before lookup
- [ ] No filler phrases used
- [ ] Intent is collected with drug name
- [ ] Multiple drugs handled one at a time
- [ ] HCP eligibility verified for sample requests
- [ ] All required HCP fields collected (Name, Practice, NPI, Address)
- [ ] Inventory check returns correct availability
- [ ] Case number is 5 digits and spoken aloud
- [ ] SMS sent with correct case number and phone
- [ ] FDA lookup identifies Pfizer vs. non-Pfizer drugs
- [ ] Non-Pfizer drugs show manufacturer information
- [ ] Transfer offered only with explicit caller consent
- [ ] No call ended unless caller explicitly requests end
- [ ] Silence never exceeds 2 seconds
- [ ] Liveness cues appear before delays
- [ ] All tool responses used without fabrication
