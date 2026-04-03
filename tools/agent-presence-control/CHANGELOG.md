# Changelog

All notable changes to the Agent Presence Control will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-04

### Added
- **Real-time agent presence grid** — View all agents with their current presence status
- **Teams-style presence icons** — Available (green), Busy (red), DND (red with bar), Away (yellow), Offline (grey)
- **Summary bar** — Clickable status counts for quick filtering
- **Search** — Filter agents by name with 200ms debounced input
- **Grouping** — Group agents by Presence or Logged In status
- **Queue filtering** — Filter agents by Omnichannel queue membership with multi-select
- **Expandable rows** — View detailed presence info + 24-hour history timeline
- **History modal** — Full 7-day presence history with day-by-day breakdown and timeline visualization
- **Presence modification** — Change agent presence (requires System Administrator or Omnichannel Supervisor role)
- **Auto-refresh** — Optional 10-second polling with manual refresh button
- **Virtual scrolling** — Binary-search based viewport calculation for 30,000+ agent performance

### Technical
- Built with React 16.14 + Fluent UI React Components v9
- PCF Virtual Control architecture
- Griffel (zero-runtime CSS-in-JS) for styling
- Efficient O(n) data diffing to minimize re-renders
- Concurrent queue membership fetching with configurable limit

---

## Unreleased

### Planned
- Export to Excel functionality
- Presence duration alerts
- Custom column configuration
- Dark mode support
