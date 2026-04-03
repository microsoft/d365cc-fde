<div align="center">

<img src="./assets/d365cc-logo.png" width="80" alt="D365 Contact Center" />

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
- **Production-ready from day one** — Solutions are architected to scale with customer growth

---

## Available Tools

<table>
<tr>
<td width="120" align="center">
<br />
<img src="./tools/dialer-helper/icons/d365logo.png" width="60" alt="Dialer Helper" />
<br /><br />
</td>
<td>

### [Dialer Helper](./tools/dialer-helper/)

**Auto-fill country codes in the D365 Contact Center dialer**

Stop scrolling through 200+ countries for every external transfer. Set your preferred country once, and it's automatically selected every time.

[![Version](https://img.shields.io/badge/version-4.0.0-blue)](#)
[![Chrome](https://img.shields.io/badge/Chrome-88+-success?logo=googlechrome&logoColor=white)](#)
[![Edge](https://img.shields.io/badge/Edge-88+-success?logo=microsoftedge&logoColor=white)](#)

**Features:** Auto-fill · Shadow DOM support · ServiceNow embed support · Custom URL config · Debug mode

[**Install Now →**](./tools/dialer-helper/#installation)

</td>
</tr>
<tr>
<td width="120" align="center">
<br />
<img src="./assets/d365cc-logo.png" width="60" alt="AI Disposition Codes" />
<br /><br />
</td>
<td>

### [AI Disposition Codes](./tools/ai-disposition-codes/)

**AI-powered disposition code recommendations at conversation end**

Streamline wrap-up decisions. AI analyzes the Copilot conversation summary, surfaces the most relevant disposition codes with confidence scores, and agents confirm or adjust with one click.

[![Version](https://img.shields.io/badge/version-1.0.0.2-blue)](#)
[![Platform](https://img.shields.io/badge/Power%20Platform-Solution-742774)](#)
[![AI](https://img.shields.io/badge/AI%20Builder-GPT--4.1--mini-00A67E)](#)

**Features:** AI recommendations · Confidence scoring · One-click confirm · 75-90% time reduction · Dataverse native

[**Deploy Now →**](./tools/ai-disposition-codes/#11-deployment-guide)

</td>
</tr>
<tr>
<td width="120" align="center">
<br />
<img src="./assets/d365cc-logo.png" width="60" alt="Agent Presence Control" />
<br /><br />
</td>
<td>

### [Agent Presence Control](./tools/agent-presence-control/)

**Real-time agent presence monitoring for contact center supervisors**

See all agents at a glance with Teams-style presence icons. Filter by queue, view presence history, and modify agent status—all from a single PCF control.

[![Version](https://img.shields.io/badge/version-1.0-blue)](#)
[![Platform](https://img.shields.io/badge/Power%20Platform-PCF%20Control-742774)](#)
[![React](https://img.shields.io/badge/React-16.14-61DAFB?logo=react&logoColor=white)](#)

**Features:** Real-time grid · Queue filtering · Presence history · Supervisor edit · Virtual scroll (30K+ agents)

[**Deploy Now →**](./tools/agent-presence-control/#10-deployment-guide)

</td>
</tr>
</table>

<details>
<summary><b>Want more tools?</b></summary>

<br />

We build tools based on real problems we encounter in the field. If you have an idea for a tool that would help contact center agents, we'd love to hear it.

[Open a feature request →](https://github.com/microsoft/d365cc-fde/issues/new?template=feature_request.md)

</details>

---

## Quick Start

### Option 1: Install a Tool (Recommended)

Each tool has its own installation guide. Start with:

```
tools/
└── dialer-helper/        ← Start here
    └── README.md         ← Installation instructions
```

**[→ Install Dialer Helper](./tools/dialer-helper/#installation)**

### Option 2: Clone the Repository

```bash
# Clone the repo
git clone https://github.com/microsoft/d365cc-fde.git

# Navigate to a tool
cd d365cc-fde/tools/dialer-helper

# Follow the tool's README for installation
```

---

## Contributing

We welcome contributions from the community! Whether you're fixing bugs, adding features, or improving documentation, your help makes these tools better for everyone.

<div align="center">

| I want to... | Start here |
|--------------|------------|
| Report a bug | [Open an issue](https://github.com/microsoft/d365cc-fde/issues/new?template=bug_report.md) |
| Request a feature | [Feature request](https://github.com/microsoft/d365cc-fde/issues/new?template=feature_request.md) |
| Contribute code | [Contributing guide](./CONTRIBUTING.md) |
| Ask a question | [GitHub Discussions](https://github.com/microsoft/d365cc-fde/discussions) |
| Report security issue | [Security policy](./SECURITY.md) |

</div>

### Development Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/d365cc-fde.git
cd d365cc-fde

# Create a branch
git checkout -b feature/my-awesome-feature

# Make changes, then submit a PR
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for detailed guidelines.

---

## What's Next

We don't publish a fixed roadmap. Instead, we build tools based on:

- **Real problems** we encounter working with enterprise customers
- **Community requests** from feature requests and discussions
- **Opportunities** to improve agent efficiency

<div align="center">

| Want to influence what we build? |
|----------------------------------|
| [Start a discussion](https://github.com/microsoft/d365cc-fde/discussions) |
| [Request a feature](https://github.com/microsoft/d365cc-fde/issues/new?template=feature_request.md) |

</div>

---

## Resources

<div align="center">

| Resource | Description |
|----------|-------------|
| [**D365 Contact Center Docs**](https://learn.microsoft.com/dynamics365/contact-center/) | Official Microsoft documentation |
| [**Chrome Extension Development**](https://developer.chrome.com/docs/extensions/) | Build browser extensions |
| [**Manifest V3 Migration**](https://developer.chrome.com/docs/extensions/mv3/intro/) | Extension architecture guide |

</div>

---

## About Us

This repository is maintained by the **Dynamics 365 Contact Center Forward Deployment Engineering** team at Microsoft. We work directly with enterprise customers to deliver successful contact center implementations.

The tools here are born from real-world challenges we've encountered and solved. We open-source them so everyone can benefit.

---

## License

This project is licensed under the [MIT License](./LICENSE) - use it, modify it, share it.

---

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third-party's policies.

---

<div align="center">

<br />

<img src="./assets/d365cc-logo.png" width="40" alt="D365 Contact Center" />

*Crafted with care by the D365 Contact Center FDE Team*

<br />

[Back to top](#dynamics-365-contact-center)

</div>
