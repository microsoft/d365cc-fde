#!/usr/bin/env node
/**
 * D365 Contact Center - DCA Companion Checker
 * Native Messaging Host
 * 
 * This script handles communication between the browser extension and the system.
 * It can detect if DCA is running, launch it, and provide version information.
 * 
 * Process names and paths can be customized via extension settings.
 */

const { spawn, exec } = require('child_process');
const path = require('path');
const fs = require('fs');

// Default DCA process names to look for (can be overridden by extension)
const DEFAULT_PROCESS_NAMES = [
  'Microsoft.Dynamics.DCA.exe',
  'DesktopCompanionApp.exe',
  'DCA.exe',
  'Microsoft.Dynamics.ContactCenter.DCA.exe',
  'DesktopCompanion.exe'
];

// Default DCA installation paths to check (can be overridden by extension)
const DEFAULT_INSTALL_PATHS = [
  process.env['ProgramFiles'] + '\\Microsoft\\Dynamics 365 Contact Center\\DCA',
  process.env['ProgramFiles'] + '\\Microsoft\\Desktop Companion Application',
  process.env['ProgramFiles(x86)'] + '\\Microsoft\\Desktop Companion Application',
  process.env['LOCALAPPDATA'] + '\\Microsoft\\Desktop Companion Application',
  process.env['LOCALAPPDATA'] + '\\Programs\\Desktop Companion Application'
];

/**
 * Read message from stdin
 */
function readMessage() {
  return new Promise((resolve, reject) => {
    let chunks = [];
    let bytesRead = 0;
    let messageLength = null;

    process.stdin.on('readable', () => {
      let chunk;
      while ((chunk = process.stdin.read()) !== null) {
        chunks.push(chunk);
        bytesRead += chunk.length;

        // First 4 bytes are message length
        if (messageLength === null && bytesRead >= 4) {
          const buffer = Buffer.concat(chunks);
          messageLength = buffer.readUInt32LE(0);
          chunks = [buffer.slice(4)];
          bytesRead -= 4;
        }

        // Read complete message
        if (messageLength !== null && bytesRead >= messageLength) {
          const buffer = Buffer.concat(chunks);
          const message = buffer.slice(0, messageLength).toString('utf8');
          try {
            resolve(JSON.parse(message));
          } catch (e) {
            reject(new Error('Invalid JSON message'));
          }
          return;
        }
      }
    });

    process.stdin.on('end', () => {
      reject(new Error('stdin closed'));
    });
  });
}

/**
 * Send message to stdout
 */
function sendMessage(message) {
  const json = JSON.stringify(message);
  const buffer = Buffer.alloc(4 + json.length);
  buffer.writeUInt32LE(json.length, 0);
  buffer.write(json, 4);
  process.stdout.write(buffer);
}

/**
 * Check if DCA process is running
 * @param {string[]} customProcessNames - Optional custom process names to check
 */
async function isDCARunning(customProcessNames = null) {
  const processNames = customProcessNames || DEFAULT_PROCESS_NAMES;
  
  return new Promise((resolve) => {
    exec('tasklist /FO CSV /NH', (error, stdout) => {
      if (error) {
        resolve({ isRunning: false, error: error.message });
        return;
      }

      const processes = stdout.toLowerCase();
      
      for (const processName of processNames) {
        const nameToCheck = processName.toLowerCase().replace('.exe', '');
        if (processes.includes(nameToCheck)) {
          resolve({ isRunning: true, processName });
          return;
        }
      }

      resolve({ isRunning: false });
    });
  });
}

/**
 * Find DCA installation
 * @param {string} customPath - Optional custom path to DCA executable
 */
function findDCAInstallation(customPath = null) {
  // If custom path provided and exists, use it
  if (customPath && fs.existsSync(customPath)) {
    return customPath;
  }
  
  // Search default paths
  for (const basePath of DEFAULT_INSTALL_PATHS) {
    if (!basePath) continue;
    
    for (const processName of DEFAULT_PROCESS_NAMES) {
      const fullPath = path.join(basePath, processName);
      if (fs.existsSync(fullPath)) {
        return fullPath;
      }
    }
  }
  return null;
}

/**
 * Get DCA version
 */
async function getDCAVersion() {
  const dcaPath = findDCAInstallation();
  
  if (!dcaPath) {
    return null;
  }

  // Try to read version from file properties
  return new Promise((resolve) => {
    exec(`powershell "(Get-Item '${dcaPath}').VersionInfo.FileVersion"`, (error, stdout) => {
      if (error) {
        resolve(null);
      } else {
        resolve(stdout.trim());
      }
    });
  });
}

/**
 * Launch DCA
 * @param {string} customPath - Optional custom path to DCA executable
 * @param {string[]} customProcessNames - Optional custom process names to verify launch
 */
async function launchDCA(customPath = null, customProcessNames = null) {
  const dcaPath = findDCAInstallation(customPath);
  
  if (!dcaPath) {
    return { success: false, error: 'DCA installation not found. Check the DCA path in extension settings.' };
  }

  return new Promise((resolve) => {
    try {
      const child = spawn(dcaPath, [], {
        detached: true,
        stdio: 'ignore'
      });
      
      child.unref();
      
      // Give it a moment to start
      setTimeout(async () => {
        const status = await isDCARunning(customProcessNames);
        resolve({ 
          success: status.isRunning, 
          path: dcaPath,
          error: status.isRunning ? null : 'DCA did not start'
        });
      }, 2000);
    } catch (error) {
      resolve({ success: false, error: error.message });
    }
  });
}

/**
 * Handle incoming commands
 * Commands can include custom settings from the extension
 */
async function handleCommand(message) {
  const { command, settings = {} } = message;
  
  // Extract custom configuration from settings
  const customProcessNames = settings.dcaProcessName 
    ? [settings.dcaProcessName + '.exe', settings.dcaProcessName]
    : null;
  const customPath = settings.dcaPath || null;

  switch (command) {
    case 'ping':
      return {
        status: 'ok',
        version: '1.0.0',
        timestamp: new Date().toISOString()
      };

    case 'checkStatus':
    case 'status':
      const runningStatus = await isDCARunning(customProcessNames);
      const version = await getDCAVersion();
      return {
        ...runningStatus,
        status: runningStatus.isRunning ? 'running' : 'stopped',
        version,
        installPath: findDCAInstallation(customPath)
      };

    case 'launch':
      return await launchDCA(customPath, customProcessNames);

    case 'getVersion':
      const ver = await getDCAVersion();
      return { version: ver };

    case 'getInstallPath':
      return { path: findDCAInstallation(customPath) };

    default:
      return { error: `Unknown command: ${command}` };
  }
}

/**
 * Main entry point
 */
async function main() {
  try {
    while (true) {
      const message = await readMessage();
      const response = await handleCommand(message);
      sendMessage(response);
    }
  } catch (error) {
    // Exit gracefully
    process.exit(0);
  }
}

main();
