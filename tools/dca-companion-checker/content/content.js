/**
 * D365 Contact Center - DCA Companion Checker
 * Content Script
 * 
 * Injects visual indicators and monitoring into D365 Contact Center pages
 * MOST IMPORTANT: Blocks page load until DCA is verified running (in strict mode)
 */

(function() {
  'use strict';

  // ============================================================
  // IMMEDIATE BLOCKING - runs BEFORE anything else loads
  // This must happen synchronously at document_start
  // ============================================================
  
  const isDynamicsUrl = window.location.hostname.includes('dynamics.com');
  let immediateBlocker = null;
  let hideStylesheet = null;
  
  if (isDynamicsUrl) {
    console.log('[DCA Checker] Dynamics URL detected - blocking page immediately');
    
    // STEP 1: Inject CSS to hide ALL page content immediately
    // This runs synchronously before any content renders
    hideStylesheet = document.createElement('style');
    hideStylesheet.id = 'dca-hide-all';
    hideStylesheet.textContent = `
      html > body, html > body * {
        visibility: hidden !important;
        opacity: 0 !important;
      }
      #dca-blocker-overlay, #dca-blocker-overlay * {
        visibility: visible !important;
        opacity: 1 !important;
      }
    `;
    
    // Insert style as early as possible
    (document.head || document.documentElement).appendChild(hideStylesheet);
    
    // STEP 2: Create blocker overlay immediately
    immediateBlocker = document.createElement('div');
    immediateBlocker.id = 'dca-blocker-overlay';
    immediateBlocker.innerHTML = `
      <style>
        #dca-blocker-overlay {
          position: fixed !important;
          top: 0 !important;
          left: 0 !important;
          width: 100vw !important;
          height: 100vh !important;
          background: #1a1a2e !important;
          z-index: 2147483647 !important;
          display: flex !important;
          align-items: center !important;
          justify-content: center !important;
          font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif !important;
        }
        #dca-blocker-overlay .dca-container {
          text-align: center;
          padding: 40px;
          max-width: 500px;
        }
        #dca-blocker-overlay .dca-icon { font-size: 64px; margin-bottom: 24px; }
        #dca-blocker-overlay h1 { font-size: 24px; margin-bottom: 10px; color: #ffd93d; }
        #dca-blocker-overlay p { font-size: 16px; color: #ccc; margin-bottom: 20px; line-height: 1.5; }
        #dca-blocker-overlay .dca-status {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 10px;
          padding: 12px 20px;
          background: #2d2d44;
          border-radius: 8px;
          margin-bottom: 24px;
          color: white;
        }
        #dca-blocker-overlay .dca-dot {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          background: #f59e0b;
          animation: dca-pulse 2s infinite;
        }
        @keyframes dca-pulse {
          0%, 100% { box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.4); }
          50% { box-shadow: 0 0 0 8px rgba(245, 158, 11, 0); }
        }
        #dca-blocker-overlay .dca-actions { display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }
        #dca-blocker-overlay button {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 14px 24px;
          border: none;
          border-radius: 8px;
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s ease;
        }
        #dca-blocker-overlay .dca-launch {
          background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%);
          color: white;
        }
        #dca-blocker-overlay .dca-launch:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(79, 70, 229, 0.4); }
        #dca-blocker-overlay .dca-check {
          background: #374151;
          color: white;
        }
        #dca-blocker-overlay .dca-check:hover { background: #4b5563; }
        #dca-blocker-overlay .dca-help { font-size: 13px; color: #9ca3af; margin-top: 20px; }
        #dca-blocker-overlay .dca-help a { color: #60a5fa; text-decoration: none; }
      </style>
      <div class="dca-container">
        <div class="dca-icon">🔒</div>
        <h1>Desktop Companion App Required</h1>
        <p>Checking if DCA is running before allowing access to D365 Contact Center...</p>
        <div class="dca-status">
          <div class="dca-dot" id="dcaBlockerDot"></div>
          <span id="dcaBlockerStatus">Checking DCA status...</span>
        </div>
        <div class="dca-actions">
          <button class="dca-launch" id="dcaBlockerLaunch">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polygon points="5 3 19 12 5 21 5 3"></polygon>
            </svg>
            Launch DCA
          </button>
          <button class="dca-check" id="dcaBlockerCheck">
            Check Again
          </button>
        </div>
        <p class="dca-help">
          Need help? <a href="https://learn.microsoft.com/en-us/dynamics365/contact-center/use/voice-dca-application" target="_blank">View DCA Documentation</a>
        </p>
      </div>
    `;
    
    // Insert blocker into document as soon as possible
    const insertBlocker = () => {
      if (document.body) {
        document.body.appendChild(immediateBlocker);
        setupBlockerButtons();
      } else if (document.documentElement) {
        document.documentElement.appendChild(immediateBlocker);
        setupBlockerButtons();
      } else {
        // Wait for document to be ready
        setTimeout(insertBlocker, 10);
      }
    };
    insertBlocker();
    
    console.log('[DCA Checker] Blocker overlay injected');
  }
  
  // Setup blocker button handlers
  function setupBlockerButtons() {
    const launchBtn = document.getElementById('dcaBlockerLaunch');
    const checkBtn = document.getElementById('dcaBlockerCheck');
    
    if (launchBtn) {
      launchBtn.addEventListener('click', async () => {
        try {
          await chrome.runtime.sendMessage({ type: 'LAUNCH_DCA' });
          updateBlockerStatus('Launching DCA...', '#f59e0b');
          setTimeout(checkDCAStatus, 2000);
        } catch (e) {
          updateBlockerStatus('Launch failed - start DCA manually', '#ef4444');
        }
      });
    }
    
    if (checkBtn) {
      checkBtn.addEventListener('click', checkDCAStatus);
    }
    
    // Auto-check immediately and poll
    setTimeout(checkDCAStatus, 100);
    setInterval(checkDCAStatus, 3000);
  }
  
  // Check DCA status and update blocker
  async function checkDCAStatus() {
    try {
      const response = await chrome.runtime.sendMessage({ type: 'CHECK_NOW', options: { deep: true } });
      if (response && response.isRunning) {
        updateBlockerStatus('DCA is running! Loading page...', '#10b981');
        // Remove blocker and show page
        setTimeout(removeBlocker, 500);
      } else {
        updateBlockerStatus('DCA not detected - please start DCA', '#ef4444');
      }
    } catch (e) {
      updateBlockerStatus('Checking...', '#f59e0b');
    }
  }
  
  // Update blocker status display
  function updateBlockerStatus(text, dotColor) {
    const statusEl = document.getElementById('dcaBlockerStatus');
    const dotEl = document.getElementById('dcaBlockerDot');
    if (statusEl) statusEl.textContent = text;
    if (dotEl) dotEl.style.background = dotColor;
  }
  
  // Remove blocker and show page
  function removeBlocker() {
    const blocker = document.getElementById('dca-blocker-overlay');
    const hideStyle = document.getElementById('dca-hide-all');
    if (blocker) blocker.remove();
    if (hideStyle) hideStyle.remove();
    console.log('[DCA Checker] Blocker removed - page now visible');
  }

  const DCA_CHECKER = {
    status: null,
    indicator: null,
    panel: null,
    settings: null,
    isVoicePage: false,
    isTargetUrl: false,
    pollInterval: null,
    pageBlocked: isDynamicsUrl, // Start blocked if on dynamics URL

    /**
     * Initialize the content script
     */
    async init() {
      console.log('[DCA Checker] Initializing content script');
      
      // Load settings FIRST
      this.settings = await this.getSettings();
      
      // Check if this is the target D365 URL
      this.isTargetUrl = this.checkTargetUrl();
      
      // Check if this is a voice-related page
      this.isVoicePage = this.detectVoicePage();

      // If NOT target URL or NOT strict mode, remove the blocker
      if (!this.isTargetUrl || this.settings.enforcementLevel !== 'strict') {
        console.log('[DCA Checker] Not target URL or not strict mode - removing blocker');
        removeBlocker();
        this.pageBlocked = false;
      }
      // If strict mode on target URL, the blocker stays (handled by top-level code)
      
      // Create UI elements (only if blocker is not showing)
      if (!this.pageBlocked) {
        this.createIndicator();
        this.createPanel();
      }
      
      // Request initial status - this will update the blocking modal if DCA is running
      await this.requestStatus();
      
      // Listen for messages from background
      chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.type === 'DCA_STATUS_UPDATE') {
          this.updateStatus(message.status);
        }
        return true;
      });

      // Observe DOM changes for voice elements (only if not blocked)
      if (!this.pageBlocked) {
        this.observeDOMChanges();
        
        // Check for voice elements periodically
        this.startPolling();
      }
      
      console.log('[DCA Checker] Content script initialized');
    },

    /**
     * Check if current URL matches the target D365 URL pattern
     * Supports wildcards: *.crm.dynamics.com, adatum.crm.dynamics.com/*, *adatum*
     */
    checkTargetUrl() {
      const currentUrl = window.location.href.toLowerCase();
      const pattern = (this.settings.d365Url || '').toLowerCase().trim();
      
      if (!pattern) return true; // If no target set, apply to all D365 pages
      
      // Convert glob pattern to regex
      // * matches any characters, ? matches single character
      const globToRegex = (glob) => {
        let regex = glob
          .replace(/[.+^${}()|[\]\\]/g, '\\$&') // Escape special regex chars except * and ?
          .replace(/\*/g, '.*')                  // * -> .*
          .replace(/\?/g, '.');                  // ? -> .
        return new RegExp('^' + regex + '$', 'i');
      };
      
      // Try different matching strategies
      try {
        // If pattern contains ://, treat as full URL pattern
        if (pattern.includes('://')) {
          const regex = globToRegex(pattern);
          if (regex.test(currentUrl)) return true;
          
          // Also try without trailing slash differences
          const normalizedCurrent = currentUrl.replace(/\/$/, '');
          const normalizedPattern = pattern.replace(/\/$/, '');
          if (globToRegex(normalizedPattern).test(normalizedCurrent)) return true;
        }
        
        // If pattern looks like just a hostname (with or without wildcards)
        // e.g., "*.crm.dynamics.com" or "adatum.crm.dynamics.com"
        const hostname = window.location.hostname.toLowerCase();
        const hostPattern = pattern.replace(/^https?:\/\//, '').split('/')[0];
        if (globToRegex(hostPattern).test(hostname)) return true;
        
        // Simple contains check as fallback
        const cleanPattern = pattern.replace(/^https?:\/\//, '').replace(/\*/g, '');
        if (cleanPattern && currentUrl.includes(cleanPattern)) return true;
        
      } catch (e) {
        console.warn('[DCA Checker] URL pattern matching error:', e);
        // Fallback: simple contains check
        const cleanPattern = pattern.replace(/^https?:\/\//, '').replace(/\*/g, '');
        return cleanPattern && currentUrl.includes(cleanPattern);
      }
      
      return false;
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
        showWarningBanner: true,
        indicatorPosition: 'bottom-right',
        // Enforcement defaults - STRICT BY DEFAULT
        d365Url: '*.crm.dynamics.com',
        enforcementLevel: 'strict',
        blockPresenceChange: true,
        showBlockingModal: true,
        requireAcknowledgment: true,
        logNonCompliance: true,
        autoLaunchDCA: false
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
      
      // Check URL
      for (const indicator of voiceIndicators) {
        if (url.includes(indicator)) {
          return true;
        }
      }

      // Check page content for voice elements
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
      
      // Remove existing indicator if present
      const existing = document.querySelector('.dca-status-indicator');
      if (existing) existing.remove();

      // Create indicator element
      this.indicator = document.createElement('div');
      this.indicator.className = 'dca-status-indicator';
      this.indicator.innerHTML = `
        <div class="dca-indicator-dot"></div>
        <div class="dca-indicator-label">DCA</div>
        <div class="dca-indicator-status">Checking...</div>
      `;
      
      // Position based on settings
      this.indicator.classList.add(`position-${this.settings.indicatorPosition || 'bottom-right'}`);
      
      // Add click handler
      this.indicator.addEventListener('click', () => this.togglePanel());
      
      // Append to body
      document.body.appendChild(this.indicator);
    },

    /**
     * Create the status panel
     */
    createPanel() {
      // Remove existing panel if present
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

      // Add event listeners
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
        const dot = this.indicator.querySelector('.dca-indicator-dot');
        const statusEl = this.indicator.querySelector('.dca-indicator-status');
        
        this.indicator.classList.remove('running', 'not-running', 'checking');
        this.indicator.classList.add(isRunning ? 'running' : 'not-running');
        
        statusEl.textContent = isRunning ? 'Active' : 'Inactive';
      }

      // Update panel
      if (this.panel) {
        const panelDot = this.panel.querySelector('.dca-panel-dot');
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

        // Show/hide warning
        if (isRunning) {
          panelWarning.classList.add('hidden');
        } else {
          panelWarning.classList.remove('hidden');
        }
      }

      // Show warning banner if not running and on voice page
      if (!isRunning && this.isVoicePage && this.settings.showWarningBanner) {
        this.showWarningBanner();
      } else {
        this.hideWarningBanner();
      }

      // Handle enforcement modes
      if (!isRunning) {
        this.handleEnforcement();
      } else {
        this.clearEnforcement();
      }
    },

    /**
     * Handle enforcement when DCA is not running
     */
    handleEnforcement() {
      const { enforcementLevel, showBlockingModal, blockPresenceChange, autoLaunchDCA, logNonCompliance } = this.settings;

      // Auto-launch DCA if enabled
      if (autoLaunchDCA && !this._autoLaunchAttempted) {
        this._autoLaunchAttempted = true;
        this.launchDCA();
      }

      // Show blocking modal in strict mode or if setting enabled
      if (enforcementLevel === 'strict' || showBlockingModal) {
        this.showBlockingModal();
      }

      // Block presence changes if enabled
      if (blockPresenceChange) {
        this.interceptPresenceChanges();
      }

      // Log non-compliance
      if (logNonCompliance) {
        this.logNonComplianceEvent();
      }
    },

    /**
     * Clear enforcement measures when DCA is running
     */
    clearEnforcement() {
      this._autoLaunchAttempted = false;
      this.hideBlockingModal();
      this.restorePresenceChanges();
      
      // Unblock the page
      if (this.pageBlocked) {
        console.log('[DCA Checker] DCA is now running - unblocking page');
        this.pageBlocked = false;
      }
    },

    /**
     * Show full-screen blocking modal
     */
    showBlockingModal() {
      // Use the top-level blocker - it's already shown if we're on dynamics.com
      // This method is now mainly for non-strict modes
      const existingBlocker = document.getElementById('dca-blocker-overlay');
      if (existingBlocker) return; // Already showing

      if (document.querySelector('.dca-blocking-modal')) return;

      const modal = document.createElement('div');
      modal.className = 'dca-blocking-modal';
      modal.innerHTML = `
        <div class="dca-modal-overlay"></div>
        <div class="dca-modal-content">
          <div class="dca-modal-icon">🚫</div>
          <h2 class="dca-modal-title">Desktop Companion Application Required</h2>
          <p class="dca-modal-message">
            You must start the Desktop Companion Application (DCA) before handling voice calls.
            This is required to ensure call continuity and prevent dropped calls.
          </p>
          <div class="dca-modal-status">
            <div class="dca-modal-status-dot"></div>
            <span>DCA Status: Not Running</span>
          </div>
          <div class="dca-modal-actions">
            <button class="dca-modal-btn dca-modal-launch">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <polygon points="5 3 19 12 5 21 5 3"></polygon>
              </svg>
              Launch DCA Now
            </button>
            <button class="dca-modal-btn dca-modal-check">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <polyline points="23 4 23 10 17 10"></polyline>
                <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"></path>
              </svg>
              Check Again
            </button>
          </div>
          <p class="dca-modal-help">
            Need help? <a href="https://learn.microsoft.com/en-us/dynamics365/contact-center/use/voice-dca-application" target="_blank">View DCA Documentation</a>
          </p>
        </div>
      `;

      // Add event listeners
      modal.querySelector('.dca-modal-launch').addEventListener('click', () => {
        this.launchDCA();
      });

      modal.querySelector('.dca-modal-check').addEventListener('click', () => {
        this.checkNow();
      });

      // Wait for body if not available (safety check for document_start)
      const appendModal = () => {
        if (document.body) {
          document.body.appendChild(modal);
          this.injectBlockingModalStyles();
        } else {
          // Wait and try again
          setTimeout(appendModal, 10);
        }
      };
      appendModal();
    },

    /**
     * Hide blocking modal
     */
    hideBlockingModal() {
      // Remove full blocking modal
      const modal = document.querySelector('.dca-blocking-modal');
      if (modal) {
        modal.remove();
      }
      // Also remove the top-level blocker
      removeBlocker();
      this.pageBlocked = false;
    },

    /**
     * Inject blocking modal styles
     */
    injectBlockingModalStyles() {
      if (document.getElementById('dca-blocking-modal-styles')) return;

      const styles = document.createElement('style');
      styles.id = 'dca-blocking-modal-styles';
      styles.textContent = `
        .dca-blocking-modal {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          z-index: 9999999;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .dca-modal-overlay {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(0, 0, 0, 0.85);
          backdrop-filter: blur(4px);
        }
        .dca-modal-content {
          position: relative;
          background: white;
          border-radius: 16px;
          padding: 48px;
          max-width: 500px;
          text-align: center;
          box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
          animation: dca-modal-appear 0.3s ease;
        }
        @keyframes dca-modal-appear {
          from { opacity: 0; transform: scale(0.9); }
          to { opacity: 1; transform: scale(1); }
        }
        .dca-modal-icon {
          font-size: 64px;
          margin-bottom: 24px;
        }
        .dca-modal-title {
          font-size: 24px;
          font-weight: 600;
          color: #1a1a1a;
          margin-bottom: 16px;
        }
        .dca-modal-message {
          font-size: 15px;
          color: #666;
          line-height: 1.6;
          margin-bottom: 24px;
        }
        .dca-modal-status {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 10px;
          padding: 12px 20px;
          background: #fef2f2;
          border: 1px solid #fca5a5;
          border-radius: 8px;
          margin-bottom: 24px;
          color: #dc2626;
          font-weight: 500;
        }
        .dca-modal-status-dot {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          background: #ef4444;
          animation: dca-pulse 2s infinite;
        }
        @keyframes dca-pulse {
          0%, 100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.4); }
          50% { box-shadow: 0 0 0 8px rgba(239, 68, 68, 0); }
        }
        .dca-modal-actions {
          display: flex;
          gap: 12px;
          justify-content: center;
          margin-bottom: 20px;
        }
        .dca-modal-btn {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 14px 24px;
          border: none;
          border-radius: 8px;
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s ease;
        }
        .dca-modal-launch {
          background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
          color: white;
        }
        .dca-modal-launch:hover {
          transform: translateY(-2px);
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
        }
        .dca-modal-check {
          background: #f3f4f6;
          color: #1a1a1a;
        }
        .dca-modal-check:hover {
          background: #e5e7eb;
        }
        .dca-modal-help {
          font-size: 13px;
          color: #666;
        }
        .dca-modal-help a {
          color: #0078d4;
          text-decoration: none;
        }
        .dca-modal-help a:hover {
          text-decoration: underline;
        }
      `;
      document.head.appendChild(styles);
    },

    /**
     * Intercept presence/status changes in D365
     */
    interceptPresenceChanges() {
      if (this._presenceIntercepted) return;
      this._presenceIntercepted = true;

      // Observe for presence status dropdown/button clicks
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
      // Remove existing message
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

      // Auto-remove after 5 seconds
      setTimeout(() => message.remove(), 5000);

      document.body.appendChild(message);

      // Inject styles if needed
      this.injectPresenceBlockedStyles();
    },

    /**
     * Inject presence blocked message styles
     */
    injectPresenceBlockedStyles() {
      if (document.getElementById('dca-presence-blocked-styles')) return;

      const styles = document.createElement('style');
      styles.id = 'dca-presence-blocked-styles';
      styles.textContent = `
        .dca-presence-blocked {
          position: fixed;
          top: 20px;
          left: 50%;
          transform: translateX(-50%);
          z-index: 9999998;
          animation: dca-slide-down 0.3s ease;
        }
        @keyframes dca-slide-down {
          from { opacity: 0; transform: translateX(-50%) translateY(-20px); }
          to { opacity: 1; transform: translateX(-50%) translateY(0); }
        }
        .dca-presence-blocked-content {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 14px 20px;
          background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%);
          border: 1px solid #f59e0b;
          border-radius: 10px;
          box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
        }
        .dca-presence-blocked-icon {
          font-size: 20px;
        }
        .dca-presence-blocked-text {
          font-size: 14px;
          color: #92400e;
        }
        .dca-presence-blocked-link {
          color: #0078d4;
          font-weight: 600;
          text-decoration: none;
        }
        .dca-presence-blocked-link:hover {
          text-decoration: underline;
        }
        .dca-presence-blocked-close {
          background: transparent;
          border: none;
          font-size: 20px;
          color: #92400e;
          cursor: pointer;
          padding: 0 4px;
          opacity: 0.7;
        }
        .dca-presence-blocked-close:hover {
          opacity: 1;
        }
      `;
      document.head.appendChild(styles);
    },

    /**
     * Log non-compliance event
     */
    logNonComplianceEvent() {
      // Don't log too frequently
      const now = Date.now();
      if (this._lastNonComplianceLog && (now - this._lastNonComplianceLog) < 60000) {
        return; // Only log once per minute
      }
      this._lastNonComplianceLog = now;

      const event = {
        timestamp: new Date().toISOString(),
        url: window.location.href,
        isVoicePage: this.isVoicePage,
        enforcementLevel: this.settings.enforcementLevel,
        userAgent: navigator.userAgent
      };

      // Send to background for storage
      chrome.runtime.sendMessage({
        type: 'LOG_NON_COMPLIANCE',
        event
      }).catch(() => {
        // Fallback to console if messaging fails
        console.warn('[DCA Checker] Non-compliance logged:', event);
      });
    },

    /**
     * Show warning banner at top of page
     */
    showWarningBanner() {
      let banner = document.querySelector('.dca-warning-banner');
      const requireAck = this.settings.requireAcknowledgment;
      
      if (!banner) {
        banner = document.createElement('div');
        banner.className = 'dca-warning-banner';
        
        if (requireAck) {
          // Banner with acknowledgment requirement
          banner.innerHTML = `
            <div class="dca-banner-content dca-banner-expanded">
              <span class="dca-banner-icon">⚠️</span>
              <div class="dca-banner-main">
                <span class="dca-banner-text">
                  <strong>Desktop Companion Application is not running.</strong>
                  Voice calls may experience issues if the browser crashes or freezes.
                </span>
                <div class="dca-banner-actions">
                  <button class="dca-banner-btn dca-banner-launch">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <polygon points="5 3 19 12 5 21 5 3"></polygon>
                    </svg>
                    Launch DCA
                  </button>
                  <button class="dca-banner-btn dca-banner-acknowledge">
                    I Understand the Risk - Continue Anyway
                  </button>
                </div>
              </div>
            </div>
          `;
          
          banner.querySelector('.dca-banner-launch').addEventListener('click', () => {
            this.launchDCA();
          });
          
          banner.querySelector('.dca-banner-acknowledge').addEventListener('click', () => {
            banner.classList.add('dismissed');
            // Log that user acknowledged the risk
            if (this.settings.logNonCompliance) {
              chrome.runtime.sendMessage({
                type: 'LOG_NON_COMPLIANCE',
                event: {
                  timestamp: new Date().toISOString(),
                  action: 'acknowledged_risk',
                  url: window.location.href
                }
              }).catch(() => {});
            }
          });
        } else {
          // Simple dismissible banner
          banner.innerHTML = `
            <div class="dca-banner-content">
              <span class="dca-banner-icon">⚠️</span>
              <span class="dca-banner-text">
                <strong>Desktop Companion Application is not running.</strong>
                Voice calls may experience issues. 
                <a href="#" class="dca-banner-link">Launch DCA</a>
              </span>
              <button class="dca-banner-close">&times;</button>
            </div>
          `;
          
          banner.querySelector('.dca-banner-link').addEventListener('click', (e) => {
            e.preventDefault();
            this.launchDCA();
          });
          
          banner.querySelector('.dca-banner-close').addEventListener('click', () => {
            banner.classList.add('dismissed');
          });
        }
        
        document.body.insertBefore(banner, document.body.firstChild);
        
        // Inject expanded banner styles
        this.injectExpandedBannerStyles();
      }
      
      banner.classList.remove('hidden', 'dismissed');
    },

    /**
     * Inject expanded banner styles
     */
    injectExpandedBannerStyles() {
      if (document.getElementById('dca-expanded-banner-styles')) return;

      const styles = document.createElement('style');
      styles.id = 'dca-expanded-banner-styles';
      styles.textContent = `
        .dca-banner-expanded {
          flex-direction: column;
          gap: 16px !important;
          padding: 20px !important;
        }
        .dca-banner-main {
          display: flex;
          flex-direction: column;
          gap: 16px;
          text-align: center;
        }
        .dca-banner-actions {
          display: flex;
          gap: 12px;
          justify-content: center;
          flex-wrap: wrap;
        }
        .dca-banner-btn {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 10px 20px;
          border: none;
          border-radius: 6px;
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s ease;
        }
        .dca-banner-launch {
          background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
          color: white;
        }
        .dca-banner-launch:hover {
          transform: translateY(-1px);
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
        }
        .dca-banner-acknowledge {
          background: transparent;
          color: #92400e;
          border: 1px solid #d97706 !important;
        }
        .dca-banner-acknowledge:hover {
          background: rgba(217, 119, 6, 0.1);
        }
      `;
      document.head.appendChild(styles);
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

    /**
     * Show panel
     */
    showPanel() {
      this.panel.classList.remove('hidden');
      // Position panel near indicator
      this.positionPanel();
    },

    /**
     * Hide panel
     */
    hidePanel() {
      this.panel.classList.add('hidden');
    },

    /**
     * Position panel near indicator
     */
    positionPanel() {
      if (!this.indicator || !this.panel) return;
      
      const indicatorRect = this.indicator.getBoundingClientRect();
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
        // Check status after a delay
        setTimeout(() => this.checkNow(), 2000);
      } catch (error) {
        console.error('[DCA Checker] Launch failed:', error);
      }
    },

    /**
     * Format timestamp
     */
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

    /**
     * Format detection method
     */
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
      // Safety check - document.body may not exist at document_start
      if (!document.body) {
        // Wait for body to be available
        const waitForBody = () => {
          if (document.body) {
            this.observeDOMChanges();
          } else {
            setTimeout(waitForBody, 50);
          }
        };
        waitForBody();
        return;
      }

      const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
            // Check for voice-related elements being added
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
      
      // Use getAttribute('class') instead of className to handle SVG elements
      // SVG elements have className as SVGAnimatedString, not a regular string
      const className = (element.getAttribute?.('class') || '').toLowerCase();
      const id = (element.id || '').toLowerCase();
      
      for (const vc of voiceClasses) {
        if (className.includes(vc) || id.includes(vc)) {
          return true;
        }
      }
      
      // Check for data attributes
      const dataAttrs = Object.keys(element.dataset || {});
      for (const attr of dataAttrs) {
        if (attr.toLowerCase().includes('voice') || attr.toLowerCase().includes('call')) {
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
