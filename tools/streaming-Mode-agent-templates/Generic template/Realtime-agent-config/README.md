# Realtime Agent Configs

This repo stores structured prompt/config files for realtime voice agents.

## Purpose

These files help teams:
- define agent behaviour in a structured format
- keep configs in source control
- review changes through pull requests
- validate configs before deployment
- maintain both editable and trimmed versions

**These templates are provided as starting guidelines to help you kick‑start development. They must be reviewed, updated, and tailored to align with your organization’s specific use cases, policies, and requirements.**


## Suggested Repo Structure

```text
realtime-agent-config/
├── README.md
├── agents/
│   ├── customer-service-agent.full.json
│   ├── customer-service-agent.trimmed.json
│   └── templates/
│       ├── realtime-template.full.json
│       └── realtime-template.trimmed.json
├── schemas/
│   └── agent-config.schema.json
├── examples/
│   ├── generic-customer-service-example.json
│   └── minimal-example.json
├── scripts/
│   └── validate-agent-config.js
└── .github/
    └── workflows/
        └── validate-agent-config.yml
