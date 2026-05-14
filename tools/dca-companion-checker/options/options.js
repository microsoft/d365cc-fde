/**
 * D365 Contact Center - DCA Companion Checker
 * Options Page Script
 */

class OptionsController {
  constructor() {
    this.settings = {};
    this.initialize();
  }

  async initialize() {
    await this.loadSettings();
    this.cacheElements();
    this.populateForm();
    this.attachEventListeners();
    this.checkNativeStatus();
  }

  cacheElements() {
    this.elements = {
      // General
      checkInterval: document.getElementById('checkInterval'),
      // Notifications
      notifyOnStop: document.getElementById('notifyOnStop'),
      notifyOnStart: document.getElementById('notifyOnStart'),
      // Display
      showBadge: document.getElementById('showBadge'),
      showPageIndicator: document.getElementById('showPageIndicator'),
      indicatorPosition: document.getElementById('indicatorPosition'),
      // Enforcement Mode
      d365Url: document.getElementById('d365Url'),
      enforcementLevel: document.getElementById('enforcementLevel'),
      enforcementInfo: document.getElementById('enforcementInfo'),
      blockPresenceChange: document.getElementById('blockPresenceChange'),
      logNonCompliance: document.getElementById('logNonCompliance'),
      autoLaunchDCA: document.getElementById('autoLaunchDCA'),
      // Detection
      dcaProcessName: document.getElementById('dcaProcessName'),
      dcaDisplayName: document.getElementById('dcaDisplayName'),
      dcaPath: document.getElementById('dcaPath'),
      ports: document.getElementById('ports'),
      protocols: document.getElementById('protocols'),
      detectionTimeout: document.getElementById('detectionTimeout'),
      // Native Messaging
      nativeStatus: document.getElementById('nativeStatus'),
      setupNativeBtn: document.getElementById('setupNativeBtn'),
      // Actions
      resetBtn: document.getElementById('resetBtn'),
      saveBtn: document.getElementById('saveBtn'),
      statusMessage: document.getElementById('statusMessage')
    };
  }

  async loadSettings() {
    try {
      const response = await chrome.runtime.sendMessage({ type: 'GET_SETTINGS' });
      this.settings = response || this.getDefaultSettings();
    } catch (error) {
      console.error('Failed to load settings:', error);
      this.settings = this.getDefaultSettings();
    }
  }

  getDefaultSettings() {
    return {
      // General
      checkInterval: 30,
      // Notifications
      notifyOnStop: true,
      notifyOnStart: true,
      // Display
      showBadge: true,
      showPageIndicator: true,
      indicatorPosition: 'bottom-right',
      // Enforcement Mode - STRICT BY DEFAULT
      d365Url: '*.crm.dynamics.com',
      enforcementLevel: 'strict',
      blockPresenceChange: true,
      // These are derived from enforcementLevel but included for backwards compatibility
      showBlockingModal: true,
      requireAcknowledgment: true,
      logNonCompliance: true,
      autoLaunchDCA: false,
      // Detection - DCA Configuration
      dcaProcessName: 'Microsoft.Dynamics.DCA',
      dcaDisplayName: 'Desktop Companion Application',
      dcaPath: 'C:\\Program Files\\Microsoft\\Dynamics 365 Contact Center\\DCA\\Microsoft.Dynamics.DCA.exe',
      ports: [9222, 9223, 9224, 9876, 12345],
      protocolHandlers: ['ms-ccaas', 'msdyn-ccaas', 'd365-dca'],
      detectionTimeout: 2000,
      nativeMessagingHost: 'com.microsoft.dynamics.dca.checker'
    };
  }

  populateForm() {
    const { 
      checkInterval, notifyOnStop, notifyOnStart, 
      showBadge, showPageIndicator, indicatorPosition,
      d365Url, enforcementLevel, blockPresenceChange,
      logNonCompliance, autoLaunchDCA,
      dcaProcessName, dcaDisplayName, dcaPath,
      ports, protocolHandlers, detectionTimeout
    } = this.settings;

    // General
    this.elements.checkInterval.value = checkInterval || 30;
    // Notifications
    this.elements.notifyOnStop.checked = notifyOnStop !== false;
    this.elements.notifyOnStart.checked = notifyOnStart !== false;
    // Display
    this.elements.showBadge.checked = showBadge !== false;
    this.elements.showPageIndicator.checked = showPageIndicator !== false;
    this.elements.indicatorPosition.value = indicatorPosition || 'bottom-right';
    // Enforcement Mode
    this.elements.d365Url.value = d365Url || '*.crm.dynamics.com';
    this.elements.enforcementLevel.value = enforcementLevel || 'strict';
    this.elements.blockPresenceChange.checked = blockPresenceChange !== false;
    this.elements.logNonCompliance.checked = logNonCompliance !== false;
    this.elements.autoLaunchDCA.checked = autoLaunchDCA === true;
    // Detection
    this.elements.dcaProcessName.value = dcaProcessName || 'Microsoft.Dynamics.DCA';
    this.elements.dcaDisplayName.value = dcaDisplayName || 'Desktop Companion Application';
    this.elements.dcaPath.value = dcaPath || '';
    this.elements.ports.value = (ports || []).join(', ');
    this.elements.protocols.value = (protocolHandlers || []).join(', ');
    this.elements.detectionTimeout.value = detectionTimeout || 2000;
    
    // Show enforcement level description
    this.updateEnforcementInfo();
  }

  updateEnforcementInfo() {
    const level = this.elements.enforcementLevel.value;
    const infoBox = this.elements.enforcementInfo;
    if (infoBox) {
      // Hide all
      infoBox.querySelectorAll('.enforcement-level').forEach(el => el.classList.remove('active'));
      // Show selected
      const activeEl = infoBox.querySelector(`.enforcement-level.${level}`);
      if (activeEl) activeEl.classList.add('active');
    }
  }

  attachEventListeners() {
    this.elements.saveBtn.addEventListener('click', () => this.saveSettings());
    this.elements.resetBtn.addEventListener('click', () => this.resetSettings());
    this.elements.setupNativeBtn.addEventListener('click', () => this.setupNativeHost());
    this.elements.enforcementLevel.addEventListener('change', () => this.updateEnforcementInfo());
  }

  // Derive showBlockingModal and requireAcknowledgment from enforcement level
  getEnforcementFlags(level) {
    switch (level) {
      case 'strict':
        return { showBlockingModal: true, requireAcknowledgment: true };
      case 'soft':
        return { showBlockingModal: false, requireAcknowledgment: true };
      case 'none':
      default:
        return { showBlockingModal: false, requireAcknowledgment: false };
    }
  }

  collectFormData() {
    const enforcementLevel = this.elements.enforcementLevel.value;
    const enforcementFlags = this.getEnforcementFlags(enforcementLevel);
    
    return {
      // General
      checkInterval: parseInt(this.elements.checkInterval.value, 10),
      // Notifications
      notifyOnStop: this.elements.notifyOnStop.checked,
      notifyOnStart: this.elements.notifyOnStart.checked,
      // Display
      showBadge: this.elements.showBadge.checked,
      showPageIndicator: this.elements.showPageIndicator.checked,
      indicatorPosition: this.elements.indicatorPosition.value,
      // Enforcement Mode
      d365Url: this.elements.d365Url.value.trim() || '*.crm.dynamics.com',
      enforcementLevel: enforcementLevel,
      blockPresenceChange: this.elements.blockPresenceChange.checked,
      // Derived from enforcement level (no separate toggles)
      showBlockingModal: enforcementFlags.showBlockingModal,
      requireAcknowledgment: enforcementFlags.requireAcknowledgment,
      logNonCompliance: this.elements.logNonCompliance.checked,
      autoLaunchDCA: this.elements.autoLaunchDCA.checked,
      // Detection - DCA Configuration
      dcaProcessName: this.elements.dcaProcessName.value.trim() || 'Microsoft.Dynamics.DCA',
      dcaDisplayName: this.elements.dcaDisplayName.value.trim() || 'Desktop Companion Application',
      dcaPath: this.elements.dcaPath.value.trim(),
      ports: this.elements.ports.value.split(',').map(p => parseInt(p.trim(), 10)).filter(p => !isNaN(p)),
      protocolHandlers: this.elements.protocols.value.split(',').map(p => p.trim()).filter(p => p),
      detectionTimeout: parseInt(this.elements.detectionTimeout.value, 10) || 2000,
      nativeMessagingHost: this.settings.nativeMessagingHost || 'com.microsoft.dynamics.dca.checker'
    };
  }

  async saveSettings() {
    try {
      const settings = this.collectFormData();
      
      await chrome.runtime.sendMessage({
        type: 'SAVE_SETTINGS',
        settings
      });

      this.settings = settings;
      this.showMessage('Settings saved successfully!', 'success');
    } catch (error) {
      console.error('Failed to save settings:', error);
      this.showMessage('Failed to save settings', 'error');
    }
  }

  async resetSettings() {
    if (!confirm('Are you sure you want to reset all settings to defaults?')) {
      return;
    }

    this.settings = this.getDefaultSettings();
    this.populateForm();
    await this.saveSettings();
  }

  async checkNativeStatus() {
    try {
      // Try to connect to native host
      const port = chrome.runtime.connectNative(this.settings.nativeMessagingHost);
      
      port.onMessage.addListener((message) => {
        this.updateNativeStatus(true, message.version);
        port.disconnect();
      });

      port.onDisconnect.addListener(() => {
        const error = chrome.runtime.lastError;
        if (error) {
          this.updateNativeStatus(false);
        }
      });

      port.postMessage({ command: 'ping' });
    } catch (error) {
      this.updateNativeStatus(false);
    }
  }

  updateNativeStatus(connected, version = null) {
    const statusEl = this.elements.nativeStatus;
    
    if (connected) {
      statusEl.innerHTML = `
        <span class="status-icon">✅</span>
        <span class="status-text">Native host connected${version ? ` (v${version})` : ''}</span>
      `;
      statusEl.classList.add('connected');
      statusEl.classList.remove('disconnected');
    } else {
      statusEl.innerHTML = `
        <span class="status-icon">❌</span>
        <span class="status-text">Native host not installed</span>
      `;
      statusEl.classList.add('disconnected');
      statusEl.classList.remove('connected');
    }
  }

  setupNativeHost() {
    // Open instructions for installing native host
    const instructions = `
To install the native messaging host:

1. Download the native host installer from the extension folder
2. Run the install script with administrator privileges
3. Restart the browser

The native host enables:
- Direct communication with DCA
- Process detection
- Auto-launch capabilities

Click OK to open the native host folder.
    `;

    if (confirm(instructions)) {
      // Open extension folder
      chrome.tabs.create({
        url: chrome.runtime.getURL('native-host/README.md')
      });
    }
  }

  showMessage(message, type) {
    const el = this.elements.statusMessage;
    el.textContent = message;
    el.className = `status-message ${type}`;
    
    setTimeout(() => {
      el.classList.add('hidden');
    }, 3000);
  }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  new OptionsController();
});
