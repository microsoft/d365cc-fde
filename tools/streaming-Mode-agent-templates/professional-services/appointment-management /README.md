<div align="center">

<img src="../../../../assets/d365cc-logo.png" width="60" alt="D365 Contact Center" />

*Crafted with care for contact center excellence*

</div>

# Professional Services Appointment Management Template

Real-time voice agent template for customer identification and appointment scheduling in professional services environments.

---

## Use Cases

- Tax preparation and financial services
- Legal consultations
- Healthcare appointments
- Any service requiring scheduled consultations

---

## What's Included

This template provides a production-tested pattern for:

| Component | Description |
|-----------|-------------|
| **Customer Identification** | Phone-based lookup at call start |
| **New Customer Registration** | Seamless onboarding when not found |
| **Appointment Lookup** | Automatic check for existing appointments |
| **Slot Availability** | Office-based availability checking |
| **Booking Flow** | End-to-end appointment creation |
| **Update/Cancel Flow** | Modify existing appointments |
| **DateTime Validation** | Strict ISO-8601 enforcement |
| **Office ID Integrity** | Prevents common ID confusion errors |
| **Low Latency Behavior** | Sub-3-second initial response |

---

## Required Variables

### Company Information

| Variable | Type | Description |
|----------|------|-------------|
| `COMPANY_NAME` | string | Your company/brand name |
| `VOICE_STYLE` | string | Voice personality description |
| `SERVICE_DESCRIPTION` | string | Brief description of your services |

### Appointment Configuration

| Variable | Type | Description |
|----------|------|-------------|
| `APPOINTMENT_DURATION_MINUTES` | number | Standard appointment length |
| `CUSTOMER_ID_FIELD` | string | Name of your customer ID field (e.g., "UCID", "CustomerId") |

### Tool Names

| Variable | Description |
|----------|-------------|
| `IDENTIFY_CUSTOMER_TOOL` | Tool to identify customer by phone |
| `LOOKUP_APPOINTMENT_TOOL` | Tool to check existing appointments |
| `CREATE_CUSTOMER_TOOL` | Tool to register new customers |
| `CLIENT_INTERACTIONS_TOOL` | Tool to get recent office interactions |
| `GET_OFFICE_TOOL` | Tool to find office by postal code |
| `AVAILABLE_SLOTS_TOOL` | Tool to check appointment availability |
| `CREATE_APPOINTMENT_TOOL` | Tool to book appointments |
| `UPDATE_APPOINTMENT_TOOL` | Tool to modify appointments |

See [variables.example.json](./variables.example.json) for a complete example.

---

## How to Use

### 1. Copy the Template

```bash
cp template.json my-appointment-agent.json
```

### 2. Create Your Variables File

```bash
cp variables.example.json my-variables.json
# Edit my-variables.json with your values
```

### 3. Apply Variables and Configure Tools

Replace `{{VARIABLE}}` placeholders with your actual values. Ensure your D365 environment has the corresponding tools/flows configured.

### 4. Validate Against Schema

```bash
npx ajv validate -s ../../_schema/realtime-agent.schema.json -d my-configured-agent.json
```

---

## Critical Rules

### DateTime Handling

This template enforces strict ISO-8601 datetime formatting:

```json
// CORRECT
"appointment_start_datetime": "2026-03-18T13:00:00"

// WRONG - will cause failures
"appointment_start_datetime": "next Tuesday"
"appointment_start_datetime": "tomorrow at 2pm"
```

The agent MUST convert natural language dates to ISO-8601 before calling any tool.

### Office ID Integrity

The `officeId` field is a common source of errors. This template includes strict rules:

- `officeId` must come from tool outputs only
- Never derive from user input
- Never confuse with datetime values
- If unavailable, do not proceed to booking

---

## Conversation Flow

```
┌─────────────────────────────────────────┐
│  Call Start                             │
│  └─> Identify Customer (by phone)       │
└─────────────┬───────────────────────────┘
              │
    ┌─────────┴─────────┐
    │                   │
┌───▼───┐           ┌───▼───┐
│ Found │           │ Not   │
│       │           │ Found │
└───┬───┘           └───┬───┘
    │                   │
    │               ┌───▼───────────┐
    │               │ Collect Name  │
    │               │ Create Record │
    │               └───────┬───────┘
    │                       │
┌───▼───────────────────────▼───┐
│  Check Existing Appointments  │
└───────────┬───────────────────┘
            │
    ┌───────┴───────┐
    │               │
┌───▼───┐       ┌───▼───┐
│ Has   │       │ No    │
│ Appt  │       │ Appt  │
└───┬───┘       └───┬───┘
    │               │
┌───▼───────┐   ┌───▼───────────┐
│ Confirm/  │   │ Ask Intent    │
│ Update    │   │ └─> Schedule? │
└───────────┘   └───────────────┘
```

---

## Best Practices

1. **Test customer identification** - Verify phone lookup works consistently
2. **Validate tool integration** - Test each tool independently before full flow
3. **Monitor datetime conversion** - Log and review any natural language date handling
4. **Handle edge cases** - Multiple offices, no availability, customer corrections
5. **Track confirmation rates** - Measure successful bookings vs. escalations

---

## Related Templates

- [Retail Store Routing](../../retail/store-routing/) - For department call routing
