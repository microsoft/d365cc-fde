# Native Messaging Host for DCA Checker

This directory contains the native messaging host that enables direct communication between the browser extension and the Desktop Companion Application.

## What is Native Messaging?

Native messaging allows browser extensions to communicate with native applications installed on the user's computer. This provides:

- **Direct DCA Detection**: Check if DCA process is running
- **Launch Capability**: Start DCA from the browser
- **Version Information**: Get DCA version details
- **Health Checks**: Perform deeper health checks

## Installation

### Automatic Installation (Recommended)

1. Run `install.bat` as Administrator
2. The script will:
   - Copy the native host to the appropriate location
   - Register it with Chrome/Edge
   - Verify the installation

### Manual Installation

1. Copy `dca-checker-host.exe` to a permanent location
2. Update the path in `com.microsoft.dynamics.dca.checker.json`
3. Add the registry entry:
   - For Chrome: `HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\com.microsoft.dynamics.dca.checker`
   - For Edge: `HKEY_CURRENT_USER\Software\Microsoft\Edge\NativeMessagingHosts\com.microsoft.dynamics.dca.checker`
4. Set the registry value to the full path of the JSON manifest

## Files

- `com.microsoft.dynamics.dca.checker.json` - Native messaging manifest
- `dca-checker-host.js` - Node.js native host script
- `install.bat` - Windows installation script
- `uninstall.bat` - Windows uninstallation script

## Building the Native Host

If you want to build the native host executable yourself:

```bash
# Install dependencies
npm install

# Build with pkg
npm run build
```

## Troubleshooting

### Extension can't connect to native host

1. Verify the registry entry exists and points to the correct JSON file
2. Check that the JSON manifest has the correct extension ID
3. Ensure the native host executable exists at the specified path
4. Check Windows Event Viewer for errors

### Native host crashes immediately

1. Run the host manually from command line to see errors
2. Check that all required DLLs are present
3. Verify the host has necessary permissions

## Security

The native host only responds to the DCA Checker extension (verified by extension ID in the manifest). It cannot be accessed by other extensions or websites.
