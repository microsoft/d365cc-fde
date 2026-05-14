/**
 * D365 Contact Center - DCA Companion Checker
 * Background Service Worker
 * 
 * This service worker manages:
 * - DCA status detection using multiple methods
 * - Badge/icon state management
 * - Communication with content scripts and popup
 * - Native messaging with DCA (when available)
 * - Periodic health checks
 */

import { DCADetector } from './dca-detector.js';
import { BadgeManager } from './badge-manager.js';
import { NotificationManager } from './notification-manager.js';
import { StorageManager } from './storage-manager.js';

// Global state
let dcaDetector = null;
let badgeManager = null;
let notificationManager = null;
let storageManager = null;
let currentStatus = {
  isRunning: false,
  lastCheck: null,
  detectionMethod: null,
  error: null,
  version: null
};

// Initialize on service worker start
async function initialize() {
  console.log('[DCA Checker] Initializing service worker...');
  
  storageManager = new StorageManager();
  await storageManager.initialize();
  
  badgeManager = new BadgeManager();
  notificationManager = new NotificationManager(storageManager);
  dcaDetector = new DCADetector(storageManager);
  
  // Restore last known status
  const savedStatus = await storageManager.get('dcaStatus');
  if (savedStatus) {
    currentStatus = { ...currentStatus, ...savedStatus };
    await badgeManager.updateBadge(currentStatus.isRunning);
  }
  
  // Start periodic checks
  setupAlarms();
  
  // Perform initial check
  await performDCACheck();
  
  console.log('[DCA Checker] Service worker initialized');
}

// Setup periodic alarms for DCA checks
function setupAlarms() {
  // Clear existing alarms
  chrome.alarms.clearAll();
  
  // Create alarm for periodic checks (every 30 seconds)
  chrome.alarms.create('dcaCheck', {
    periodInMinutes: 0.5 // 30 seconds
  });
  
  // Create alarm for deeper health check (every 5 minutes)
  chrome.alarms.create('dcaHealthCheck', {
    periodInMinutes: 5
  });
}

// Handle alarms
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === 'dcaCheck') {
    await performDCACheck();
  } else if (alarm.name === 'dcaHealthCheck') {
    await performDeepHealthCheck();
  }
});

// Perform DCA status check
async function performDCACheck(options = {}) {
  try {
    const result = await dcaDetector.detect(options);
    
    const previousStatus = currentStatus.isRunning;
    currentStatus = {
      isRunning: result.isRunning,
      lastCheck: new Date().toISOString(),
      detectionMethod: result.method,
      error: result.error || null,
      version: result.version || null,
      details: result.details || {}
    };
    
    // Save status
    await storageManager.set('dcaStatus', currentStatus);
    
    // Update badge
    await badgeManager.updateBadge(currentStatus.isRunning);
    
    // Notify if status changed
    if (previousStatus !== currentStatus.isRunning) {
      await handleStatusChange(previousStatus, currentStatus.isRunning);
    }
    
    // Broadcast to all tabs
    broadcastStatus();
    
    return currentStatus;
  } catch (error) {
    console.error('[DCA Checker] Check failed:', error);
    currentStatus.error = error.message;
    return currentStatus;
  }
}

// Perform deep health check
async function performDeepHealthCheck() {
  return performDCACheck({ deep: true });
}

// Handle status change
async function handleStatusChange(wasRunning, isRunning) {
  const settings = await storageManager.get('settings') || {};
  
  if (!isRunning && wasRunning) {
    // DCA stopped
    console.log('[DCA Checker] DCA stopped running');
    
    if (settings.notifyOnStop !== false) {
      await notificationManager.show({
        title: '⚠️ DCA Not Running',
        message: 'The Desktop Companion Application is no longer running. Voice calls may be affected.',
        type: 'warning',
        requireInteraction: true
      });
    }
  } else if (isRunning && !wasRunning) {
    // DCA started
    console.log('[DCA Checker] DCA started running');
    
    if (settings.notifyOnStart !== false) {
      await notificationManager.show({
        title: '✅ DCA Running',
        message: 'Desktop Companion Application is now active and ready for voice calls.',
        type: 'success'
      });
    }
  }
}

// Broadcast status to all tabs
async function broadcastStatus() {
  try {
    const tabs = await chrome.tabs.query({ url: '*://*.dynamics.com/*' });
    for (const tab of tabs) {
      try {
        chrome.tabs.sendMessage(tab.id, {
          type: 'DCA_STATUS_UPDATE',
          status: currentStatus
        });
      } catch (e) {
        // Tab might not have content script loaded
      }
    }
  } catch (error) {
    console.error('[DCA Checker] Broadcast failed:', error);
  }
}

// Message handler
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender).then(sendResponse);
  return true; // Keep channel open for async response
});

async function handleMessage(message, sender) {
  switch (message.type) {
    case 'GET_STATUS':
      return currentStatus;
    
    case 'CHECK_NOW':
      return await performDCACheck(message.options || {});
    
    case 'LAUNCH_DCA':
      return await launchDCA();
    
    case 'GET_SETTINGS':
      return await storageManager.get('settings') || getDefaultSettings();
    
    case 'SAVE_SETTINGS':
      await storageManager.set('settings', message.settings);
      return { success: true };
    
    case 'GET_HISTORY':
      return await storageManager.get('statusHistory') || [];
    
    case 'CLEAR_HISTORY':
      await storageManager.set('statusHistory', []);
      return { success: true };
    
    default:
      console.warn('[DCA Checker] Unknown message type:', message.type);
      return { error: 'Unknown message type' };
  }
}

// Launch DCA application
async function launchDCA() {
  try {
    // Try native messaging first
    const nativeResult = await dcaDetector.launchViaNativeMessaging();
    if (nativeResult.success) {
      return nativeResult;
    }
    
    // Try protocol handler
    const protocolResult = await dcaDetector.launchViaProtocol();
    return protocolResult;
  } catch (error) {
    console.error('[DCA Checker] Launch failed:', error);
    return { success: false, error: error.message };
  }
}

// Get default settings
function getDefaultSettings() {
  return {
    checkInterval: 30,
    notifyOnStop: true,
    notifyOnStart: true,
    showBadge: true,
    showPageIndicator: true,
    autoLaunch: false,
    ports: [9222, 9223, 9224, 9876, 12345], // Possible DCA ports
    protocolHandlers: ['ms-ccaas', 'msdyn-ccaas', 'd365-dca'],
    nativeMessagingHost: 'com.microsoft.dynamics.dca.checker'
  };
}

// Handle extension install/update
chrome.runtime.onInstalled.addListener(async (details) => {
  console.log('[DCA Checker] Extension installed/updated:', details.reason);
  
  if (details.reason === 'install') {
    // First install - set defaults
    const settings = getDefaultSettings();
    await chrome.storage.local.set({ settings });
    
    // Open welcome page
    chrome.tabs.create({
      url: chrome.runtime.getURL('welcome/welcome.html')
    });
  } else if (details.reason === 'update') {
    // Migration logic if needed
    console.log('[DCA Checker] Updated from', details.previousVersion);
  }
  
  await initialize();
});

// Handle keyboard shortcuts
chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'check-dca-status') {
    const status = await performDCACheck();
    await notificationManager.show({
      title: status.isRunning ? '✅ DCA Running' : '⚠️ DCA Not Running',
      message: status.isRunning 
        ? 'Desktop Companion Application is active'
        : 'Desktop Companion Application is not detected',
      type: status.isRunning ? 'success' : 'warning'
    });
  }
});

// Handle notification clicks
chrome.notifications.onClicked.addListener(async (notificationId) => {
  if (notificationId.startsWith('dca-')) {
    // Open options or help page
    chrome.tabs.create({
      url: chrome.runtime.getURL('options/options.html')
    });
  }
});

// Initialize when service worker starts
initialize().catch(console.error);

// Export for testing
export { currentStatus, performDCACheck, launchDCA };
