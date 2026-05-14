/**
 * D365 Contact Center - DCA Companion Checker
 * Content Script
 * 
 * Shows status indicators on D365 Contact Center pages.
 * NOTE: Page blocking is now handled at the navigation level by the background script.
 * This content script only runs on pages that have been allowed (DCA verified running).
 */

(function() {
  'use strict';

  const DCA_CHECKER = {
    status: null,
    indicator: null,
    panel: null,
    settings: null,
    isVoicePage: false,
    pollInterval: null,

    /**
     * Initialize the content script
     */
    async init() {
      console.log('[DCA Checker] Initializing content script');
      
      // Load settings
      this.settings = await this.getSettings();
      
      // Check if this is a voice-related page
      this.isVoicePage = this.detectVoicePage();
      
      // Create UI elements
      this.createIndicator();
      this.createPanel();
      
      // Request initial status
      await this.requestStatus();
      
      // Listen for messages from background
      chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.type === 'DCA_STATUS_UPDATE') {
          this.updateStatus(message.status);
        }
        return true;
      });

      // Observe DOM changes for voice elements
      this.observeDOMChanges();
      
      // Check for voice elements periodically
      this.startPolling();
      
      console.log('[DCA Checker] Content script initialized');
    },

    /**
     * Get settings from background
     */
    async getSettings() {
      try {
        const response = await chrome.runtime.sendMessage({ type: 'GET_SETTINGS' });
        return response || this.getDefaultSettings();
      } catch (error) {
        return this.getDefaultSettings();
      }
    },

    /**
     * Get default settings
     */
    getDefaultSettings() {
      return {
        showPageIndicator: true,
        indicatorPosition: 'bottom-right',
        enforcementLevel: 'strict',
        blockPresenceChange: true,
        logNonCompliance: true
      };
    },

    /**
     * Detect if current page is voice-related
     */
    detectVoicePage() {
      const url = window.location.href.toLowerCase();
      const voiceIndicators = [
        'voice', 'omnichannel', 'csw', 'copilotservice',
        'customerservice', 'contactcenter', 'ccaas'
      ];
      
      for (const indicator of voiceIndicators) {
        if (url.includes(indicator)) {
          return true;
        }
      }

      const pageText = document.body?.innerText?.toLowerCase() || '';
      const voiceKeywords = ['voice channel', 'incoming call', 'outgoing call', 'phone', 'dial'];
      
      for (const keyword of voiceKeywords) {
        if (pageText.includes(keyword)) {
          return true;
        }
      }

      return false;
    },

    /**
     * Create the status indicator
     */
    createIndicator() {
      if (!this.settings.showPageIndicator) return;
      
      const existing = document.querySelector('.dca-status-indicator');
      if (existing) existing.remove();

      this.indicator = document.createElement('div');
      this.indicator.className = 'dca-status-indicator';
      this.indicator.innerHTML = `
        <div class="dca-indicator-dot"></div>
        <div class="dca-indicator-label">DCA</div>
        <div class="dca-indicator-status">Checking...</div>
      `;
      
      this.indicator.classList.add(`position-${this.settings.indicatorPosition || 'bottom-right'}`);
      this.indicator.addEventListener('click', () => this.togglePanel());
      
      document.body.appendChild(this.indicator);
    },

    /**
     * Create the status panel
     */
    createPanel() {
      const existing = document.querySelector('.dca-status-panel');
      if (existing) existing.remove();

      this.panel = document.createElement('div');
      this.panel.className = 'dca-status-panel hidden';
      this.panel.innerHTML = `
        <div class="dca-panel-header">
          <span class="dca-panel-title">DCA Status</span>
          <button class="dca-panel-close">&times;</button>
        </div>
        <div class="dca-panel-content">
          <div class="dca-panel-status">
            <div class="dca-panel-dot"></div>
            <span class="dca-panel-status-text">Unknown</span>
          </div>
          <div class="dca-panel-details">
            <div class="dca-detail-row">
              <span class="dca-detail-label">Last Check:</span>
              <span class="dca-detail-value" id="dcaPanelLastCheck">--</span>
            </div>
            <div class="dca-detail-row">
              <span class="dca-detail-label">Method:</span>
              <span class="dca-detail-value" id="dcaPanelMethod">--</span>
            </div>
          </div>
          <div class="dca-panel-actions">
            <button class="dca-action-btn dca-check-btn">Check Now</button>
            <button class="dca-action-btn dca-launch-btn">Launch DCA</button>
          </div>
        </div>
        <div class="dca-panel-warning hidden">
          <div class="dca-warning-icon">⚠️</div>
          <div class="dca-warning-text">
            <strong>DCA Not Running</strong><br>
            Voice calls may experience issues. Please start the Desktop Companion Application.
          </div>
        </div>
      `;

      this.panel.querySelector('.dca-panel-close').addEventListener('click', () => this.hidePanel());
      this.panel.querySelector('.dca-check-btn').addEventListener('click', () => this.checkNow());
      this.panel.querySelector('.dca-launch-btn').addEventListener('click', () => this.launchDCA());

      document.body.appendChild(this.panel);
    },

    /**
     * Request current status from background
     */
    async requestStatus() {
      try {
        const response = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
        this.updateStatus(response);
      } catch (error) {
        console.error('[DCA Checker] Failed to get status:', error);
        this.updateStatus({ isRunning: false, error: 'Failed to check status' });
      }
    },

    /**
     * Update status display
     */
    updateStatus(status) {
      if (!status) return;
      this.status = status;
      
      const { isRunning, lastCheck, detectionMethod } = status;

      // Update indicator
      if (this.indicator) {
        const statusEl = this.indicator.querySelector('.dca-indicator-status');
        
        this.indicator.classList.remove('running', 'not-running', 'checking');
        this.indicator.classList.add(isRunning ? 'running' : 'not-running');
        
        statusEl.textContent = isRunning ? 'Active' : 'Inactive';
      }

      // Update panel
      if (this.panel) {
        const panelStatus = this.panel.querySelector('.dca-panel-status-text');
        const panelWarning = this.panel.querySelector('.dca-panel-warning');
        const panelLastCheck = this.panel.querySelector('#dcaPanelLastCheck');
        const panelMethod = this.panel.querySelector('#dcaPanelMethod');

        this.panel.classList.remove('running', 'not-running');
        this.panel.classList.add(isRunning ? 'running' : 'not-running');
        
        panelStatus.textContent = isRunning ? 'Running' : 'Not Running';
        
        if (lastCheck) {
          panelLastCheck.textContent = this.formatTime(lastCheck);
        }
        
        if (detectionMethod) {
          panelMethod.textContent = this.formatMethod(detectionMethod);
        }

        if (isRunning) {
          panelWarning.classList.add('hidden');
        } else {
          panelWarning.classList.remove('hidden');
        }
      }

      // Show warning banner based on enforcement level
      // Note: 'strict' mode blocks at navigation level, so content script only runs in 'soft' or 'none' modes
      const enforcementLevel = this.settings.enforcementLevel || 'strict';
      
      if (!isRunning && (enforcementLevel === 'soft' || enforcementLevel === 'none')) {
        this.showWarningBanner(enforcementLevel);
      } else {
        this.hideWarningBanner();
      }

      // Handle enforcement (presence blocking)
      if (!isRunning && this.settings.blockPresenceChange) {
        this.interceptPresenceChanges();
      } else {
        this.restorePresenceChanges();
      }
    },

    /**
     * Intercept presence/status changes in D365
     */
    interceptPresenceChanges() {
      if (this._presenceIntercepted) return;
      this._presenceIntercepted = true;

      document.addEventListener('click', this._presenceClickHandler = (e) => {
        const target = e.target;
        const isPresenceElement = 
          target.closest('[data-id*="presence"]') ||
          target.closest('[data-id*="status"]') ||
          target.closest('[class*="presence"]') ||
          target.closest('[class*="available"]') ||
          target.closest('button[title*="Available"]') ||
          target.closest('[aria-label*="Available"]') ||
          target.closest('[aria-label*="presence"]');

        if (isPresenceElement && this.status && !this.status.isRunning) {
          e.preventDefault();
          e.stopPropagation();
          this.showPresenceBlockedMessage();
        }
      }, true);
    },

    /**
     * Restore presence change functionality
     */
    restorePresenceChanges() {
      if (this._presenceClickHandler) {
        document.removeEventListener('click', this._presenceClickHandler, true);
        this._presenceClickHandler = null;
        this._presenceIntercepted = false;
      }
    },

    /**
     * Show message when presence change is blocked
     */
    showPresenceBlockedMessage() {
      const existing = document.querySelector('.dca-presence-blocked');
      if (existing) existing.remove();

      const message = document.createElement('div');
      message.className = 'dca-presence-blocked';
      message.innerHTML = `
        <div class="dca-presence-blocked-content">
          <span class="dca-presence-blocked-icon">⚠️</span>
          <span class="dca-presence-blocked-text">
            Cannot change to Available - DCA is not running. 
            <a href="#" class="dca-presence-blocked-link">Launch DCA</a>
          </span>
          <button class="dca-presence-blocked-close">&times;</button>
        </div>
      `;

      message.querySelector('.dca-presence-blocked-link').addEventListener('click', (e) => {
        e.preventDefault();
        this.launchDCA();
      });

      message.querySelector('.dca-presence-blocked-close').addEventListener('click', () => {
        message.remove();
      });

      setTimeout(() => message.remove(), 5000);

      document.body.appendChild(message);
    },

    /**
     * Show warning banner at top of page
     * @param {string} enforcementLevel - 'none' or 'soft'
     */
    showWarningBanner(enforcementLevel = 'soft') {
      let banner = document.querySelector('.dca-warning-banner');
      
      // Remove existing banner if enforcement level changed
      if (banner && banner.dataset.enforcementLevel !== enforcementLevel) {
        banner.remove();
        banner = null;
      }
      
      if (!banner) {
        banner = document.createElement('div');
        banner.className = 'dca-warning-banner';
        banner.dataset.enforcementLevel = enforcementLevel;
        
        const requiresAcknowledgment = enforcementLevel === 'soft';
        
        banner.innerHTML = `
          <div class="dca-banner-content">
            <span class="dca-banner-icon">⚠️</span>
            <span class="dca-banner-text">
              <strong>Desktop Companion Application is not running.</strong>
              Voice calls may drop if your browser closes unexpectedly.
            </span>
            <div class="dca-banner-actions">
              <button class="dca-banner-btn dca-banner-launch">Launch DCA</button>
              ${requiresAcknowledgment 
                ? '<button class="dca-banner-btn dca-banner-acknowledge">I Understand the Risk</button>' 
                : '<button class="dca-banner-btn dca-banner-dismiss">Dismiss</button>'
              }
            </div>
          </div>
        `;
        
        banner.querySelector('.dca-banner-launch').addEventListener('click', (e) => {
          e.preventDefault();
          this.launchDCA();
        });
        
        if (requiresAcknowledgment) {
          banner.querySelector('.dca-banner-acknowledge').addEventListener('click', () => {
            this.logAcknowledgment();
            banner.classList.add('dismissed');
          });
        } else {
          banner.querySelector('.dca-banner-dismiss').addEventListener('click', () => {
            banner.classList.add('dismissed');
          });
        }
        
        document.body.insertBefore(banner, document.body.firstChild);
      }
      
      banner.classList.remove('hidden', 'dismissed');
    },

    /**
     * Log acknowledgment for compliance
     */
    async logAcknowledgment() {
      if (this.settings.logNonCompliance) {
        try {
          await chrome.runtime.sendMessage({
            type: 'LOG_NON_COMPLIANCE',
            event: {
              type: 'ACKNOWLEDGED_RISK',
              timestamp: new Date().toISOString(),
              url: window.location.href
            }
          });
          console.log('[DCA Checker] Risk acknowledgment logged');
        } catch (error) {
          console.error('[DCA Checker] Failed to log acknowledgment:', error);
        }
      }
    },

    /**
     * Hide warning banner
     */
    hideWarningBanner() {
      const banner = document.querySelector('.dca-warning-banner');
      if (banner) {
        banner.classList.add('hidden');
      }
    },

    /**
     * Toggle panel visibility
     */
    togglePanel() {
      if (this.panel.classList.contains('hidden')) {
        this.showPanel();
      } else {
        this.hidePanel();
      }
    },

    showPanel() {
      this.panel.classList.remove('hidden');
      this.positionPanel();
    },

    hidePanel() {
      this.panel.classList.add('hidden');
    },

    positionPanel() {
      if (!this.indicator || !this.panel) return;
      
      const position = this.settings.indicatorPosition || 'bottom-right';
      
      if (position.includes('right')) {
        this.panel.style.right = '20px';
        this.panel.style.left = 'auto';
      } else {
        this.panel.style.left = '20px';
        this.panel.style.right = 'auto';
      }
      
      if (position.includes('bottom')) {
        this.panel.style.bottom = '80px';
        this.panel.style.top = 'auto';
      } else {
        this.panel.style.top = '80px';
        this.panel.style.bottom = 'auto';
      }
    },

    /**
     * Check status now
     */
    async checkNow() {
      try {
        const response = await chrome.runtime.sendMessage({ 
          type: 'CHECK_NOW',
          options: { deep: true }
        });
        this.updateStatus(response);
      } catch (error) {
        console.error('[DCA Checker] Check failed:', error);
      }
    },

    /**
     * Launch DCA
     */
    async launchDCA() {
      try {
        await chrome.runtime.sendMessage({ type: 'LAUNCH_DCA' });
        setTimeout(() => this.checkNow(), 2000);
      } catch (error) {
        console.error('[DCA Checker] Launch failed:', error);
      }
    },

    formatTime(timestamp) {
      const date = new Date(timestamp);
      const now = new Date();
      const diff = now - date;
      
      if (diff < 60000) {
        return 'Just now';
      } else if (diff < 3600000) {
        const mins = Math.floor(diff / 60000);
        return `${mins}m ago`;
      } else {
        return date.toLocaleTimeString();
      }
    },

    formatMethod(method) {
      const methods = {
        'native': 'Native',
        'localServer': 'Server',
        'protocol': 'Protocol',
        'none': 'N/A'
      };
      return methods[method] || method;
    },

    /**
     * Observe DOM changes for voice elements
     */
    observeDOMChanges() {
      if (!document.body) {
        setTimeout(() => this.observeDOMChanges(), 50);
        return;
      }

      const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
            for (const node of mutation.addedNodes) {
              if (node.nodeType === Node.ELEMENT_NODE) {
                if (this.isVoiceElement(node)) {
                  this.isVoicePage = true;
                  this.checkNow();
                  break;
                }
              }
            }
          }
        }
      });

      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
    },

    /**
     * Check if element is voice-related
     */
    isVoiceElement(element) {
      const voiceClasses = [
        'voice', 'phone', 'call', 'dial', 'channel',
        'communication', 'telephony'
      ];
      
      const className = (element.getAttribute?.('class') || '').toLowerCase();
      const id = (element.id || '').toLowerCase();
      
      for (const vc of voiceClasses) {
        if (className.includes(vc) || id.includes(vc)) {
          return true;
        }
      }
      
      return false;
    },

    /**
     * Start polling for voice elements
     */
    startPolling() {
      this.pollInterval = setInterval(() => {
        if (!this.isVoicePage) {
          this.isVoicePage = this.detectVoicePage();
          if (this.isVoicePage && this.status && !this.status.isRunning) {
            this.showWarningBanner();
          }
        }
      }, 5000);
    },

    /**
     * Stop polling
     */
    stopPolling() {
      if (this.pollInterval) {
        clearInterval(this.pollInterval);
        this.pollInterval = null;
      }
    }
  };

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => DCA_CHECKER.init());
  } else {
    DCA_CHECKER.init();
  }

  // Cleanup on unload
  window.addEventListener('unload', () => {
    DCA_CHECKER.stopPolling();
  });
})();
