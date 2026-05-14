# Changelog

All notable changes to the DCA Companion Checker extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-14

### Added

- Initial release of DCA Companion Checker
- Multi-method DCA detection:
  - Native messaging support
  - Local server/WebSocket detection
  - Protocol handler detection
- Visual status indicators:
  - Toolbar badge with status colors
  - Popup panel with detailed information
  - Floating page indicator on D365 pages
  - Warning banner for voice-related pages
- Notification system:
  - Alerts when DCA stops running
  - Optional alerts when DCA starts
  - Configurable notification preferences
- Quick actions:
  - Manual status check
  - One-click DCA launch
- Settings page:
  - Configurable check intervals
  - Notification preferences
  - Display options
  - Detection configuration
- Native messaging host:
  - Windows installer/uninstaller
  - Process detection
  - DCA launch capability
- Welcome page for first-time users
- Keyboard shortcuts:
  - Ctrl+Shift+D: Open popup
  - Ctrl+Shift+C: Quick status check
- Dark mode support
- Comprehensive documentation

### Technical

- Manifest V3 compliant
- Service worker architecture
- Modular code structure
- Local storage with caching
- Mutation observer for dynamic D365 pages

## [Unreleased]

### Planned

- macOS support for native messaging
- Auto-launch DCA option
- Status history and analytics
- Integration with D365 voice channel events
- Multi-language support
