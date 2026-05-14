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

// Cached settings for synchronous access in navigation handler
// showBlockingModal is derived from enforcementLevel:
// - 'strict' = true (block page completely)
// - 'soft' = false (warning banner only)
// - 'none' = false (warning banner only)
let cachedSettings = {
  enforcementLevel: 'strict',
  showBlockingModal: true  // derived from enforcementLevel
};

// Set to track tabs that have been allowed (DCA was verified for them)
const allowedTabs = new Set();

// Check if URL matches dynamics.com pattern
function isDynamicsUrl(url) {
  try {
    const urlObj = new URL(url);
    return urlObj.hostname.includes('dynamics.com');
  } catch (e) {
    return false;
  }
}

// Check if URL is our blocking page
function isBlockingPage(url) {
  return url && url.includes(chrome.runtime.id) && url.includes('blocking/blocking.html');
}

// ============================================================
// URL BLOCKING - Intercept navigation to D365 when DCA not running
// ============================================================

// Listen for navigation commits to dynamics.com URLs
// Using onCommitted instead of onBeforeNavigate because the tab is guaranteed to exist
chrome.webNavigation.onCommitted.addListener((details) => {
  console.log('[DCA Checker] onCommitted fired:', {
    url: details.url,
    tabId: details.tabId,
    frameId: details.frameId,
    isAllowed: allowedTabs.has(details.tabId),
    dcaRunning: currentStatus.isRunning,
    showBlockingModal: cachedSettings.showBlockingModal
  });

  // Only handle main frame navigations (not iframes)
  if (details.frameId !== 0) {
    console.log('[DCA Checker] Skipping - not main frame');
    return;
  }
  
  // Skip if this is our blocking page
  if (isBlockingPage(details.url)) {
    console.log('[DCA Checker] Skipping - is blocking page');
    return;
  }
  
  // Skip if not a dynamics.com URL
  if (!isDynamicsUrl(details.url)) {
    console.log('[DCA Checker] Skipping - not dynamics URL');
    return;
  }
  
  // Skip if blocking modal is disabled in settings
  if (!cachedSettings.showBlockingModal) {
    console.log('[DCA Checker] Skipping - showBlockingModal is disabled');
    return;
  }
  
  // Skip if this tab has already been allowed
  if (allowedTabs.has(details.tabId)) {
    console.log('[DCA Checker] Tab', details.tabId, 'already allowed - letting through');
    return;
  }
  
  // If DCA is already known to be running, allow
  if (currentStatus.isRunning) {
    allowedTabs.add(details.tabId);
    console.log('[DCA Checker] DCA running, allowing navigation for tab', details.tabId);
    return;
  }
  
  // DCA not running (or status unknown) - redirect to blocking page immediately
  console.log('[DCA Checker] DCA not running, redirecting tab', details.tabId, 'to blocking page');
  
  const blockingUrl = chrome.runtime.getURL('blocking/blocking.html') + 
    '?url=' + encodeURIComponent(details.url);
  
  chrome.tabs.update(details.tabId, { url: blockingUrl }).then(() => {
    console.log('[DCA Checker] Successfully redirected tab', details.tabId);
  }).catch((error) => {
    console.error('[DCA Checker] Failed to redirect tab', details.tabId, ':', error);
  });
}, {
  url: [
    { hostContains: 'dynamics.com' }
  ]
});

// Clean up allowed tabs when they close
chrome.tabs.onRemoved.addListener((tabId) => {
  allowedTabs.delete(tabId);
});

// When DCA status changes to running, we don't automatically allow existing tabs
// They need to go through the blocking page flow

// Initialize on service worker start
async function initialize() {
  console.log('[DCA Checker] Initializing service worker...');
  
  storageManager = new StorageManager();
  await storageManager.initialize();
  
  badgeManager = new BadgeManager();
  notificationManager = new NotificationManager(storageManager);
  dcaDetector = new DCADetector(storageManager);
  
  // Load settings into cache for synchronous access
  const settings = await storageManager.get('settings');
  if (settings) {
    cachedSettings = { ...cachedSettings, ...settings };
    console.log('[DCA Checker] Loaded cached settings:', cachedSettings);
  }
  
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
      // Update cached settings for synchronous access
      cachedSettings = { ...cachedSettings, ...message.settings };
      console.log('[DCA Checker] Settings saved, cached:', cachedSettings);
      return { success: true };
    
    case 'GET_HISTORY':
      return await storageManager.get('statusHistory') || [];
    
    case 'CLEAR_HISTORY':
      await storageManager.set('statusHistory', []);
      return { success: true };
    
    case 'ALLOW_AND_REDIRECT':
      // Mark this tab as allowed and let the navigation proceed
      if (sender.tab) {
        allowedTabs.add(sender.tab.id);
        console.log('[DCA Checker] ALLOW_AND_REDIRECT: Tab', sender.tab.id, 'added to allowedTabs');
        console.log('[DCA Checker] Current allowedTabs:', Array.from(allowedTabs));
      } else {
        console.warn('[DCA Checker] ALLOW_AND_REDIRECT: No sender.tab available');
      }
      return { success: true, tabId: sender.tab?.id };
    
    case 'LOG_NON_COMPLIANCE':
      // Log non-compliance event
      const history = await storageManager.get('nonComplianceHistory') || [];
      history.push(message.event);
      // Keep last 100 entries
      if (history.length > 100) history.shift();
      await storageManager.set('nonComplianceHistory', history);
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
