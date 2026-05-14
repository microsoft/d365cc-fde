/**
 * D365 Contact Center - DCA Companion Checker
 * Popup Script
 * 
 * Handles all popup UI interactions and communication with background service
 */

class PopupController {
  constructor() {
    this.elements = {};
    this.status = null;
    this.isChecking = false;
    
    this.initialize();
  }

  async initialize() {
    this.cacheElements();
    this.attachEventListeners();
    await this.loadStatus();
  }

  /**
   * Cache DOM elements
   */
  cacheElements() {
    this.elements = {
      statusCard: document.getElementById('statusCard'),
      statusDot: document.getElementById('statusDot'),
      statusIndicatorBar: document.getElementById('statusIndicatorBar'),
      statusTitle: document.getElementById('statusTitle'),
      statusDescription: document.getElementById('statusDescription'),
      statusBadge: document.getElementById('statusBadge'),
      statusBadgeText: document.getElementById('statusBadgeText'),
      detailsSection: document.getElementById('detailsSection'),
      lastCheck: document.getElementById('lastCheck'),
      detectionMethod: document.getElementById('detectionMethod'),
      versionRow: document.getElementById('versionRow'),
      dcaVersion: document.getElementById('dcaVersion'),
      checkNowBtn: document.getElementById('checkNowBtn'),
      launchDcaBtn: document.getElementById('launchDcaBtn'),
      settingsBtn: document.getElementById('settingsBtn'),
      warningBanner: document.getElementById('warningBanner')
    };
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    this.elements.checkNowBtn.addEventListener('click', () => this.handleCheckNow());
    this.elements.launchDcaBtn.addEventListener('click', () => this.handleLaunchDCA());
    this.elements.settingsBtn.addEventListener('click', () => this.openSettings());

    // Listen for status updates from background
    chrome.runtime.onMessage.addListener((message) => {
      if (message.type === 'DCA_STATUS_UPDATE') {
        this.updateUI(message.status);
      }
    });
  }

  /**
   * Load current status from background
   */
  async loadStatus() {
    this.setCheckingState(true);
    
    try {
      const response = await chrome.runtime.sendMessage({ type: 'GET_STATUS' });
      this.updateUI(response);
    } catch (error) {
      console.error('Failed to load status:', error);
      this.showError('Failed to load status');
    } finally {
      this.setCheckingState(false);
    }
  }

  /**
   * Handle Check Now button click
   */
  async handleCheckNow() {
    if (this.isChecking) return;
    
    this.setCheckingState(true);
    
    try {
      const response = await chrome.runtime.sendMessage({ 
        type: 'CHECK_NOW',
        options: { deep: true }
      });
      this.updateUI(response);
      
      // Visual feedback
      this.animateButton(this.elements.checkNowBtn);
    } catch (error) {
      console.error('Check failed:', error);
      this.showError('Check failed');
    } finally {
      this.setCheckingState(false);
    }
  }

  /**
   * Handle Launch DCA button click
   */
  async handleLaunchDCA() {
    this.elements.launchDcaBtn.disabled = true;
    
    try {
      const response = await chrome.runtime.sendMessage({ type: 'LAUNCH_DCA' });
      
      if (response.success) {
        this.showNotification('Launching DCA...', 'info');
        
        // Check status after a delay
        setTimeout(() => this.handleCheckNow(), 2000);
      } else {
        this.showNotification(response.error || 'Failed to launch DCA', 'error');
        this.showManualLaunchInstructions();
      }
    } catch (error) {
      console.error('Launch failed:', error);
      this.showNotification('Failed to launch DCA', 'error');
      this.showManualLaunchInstructions();
    } finally {
      this.elements.launchDcaBtn.disabled = false;
    }
  }

  /**
   * Show manual launch instructions
   */
  showManualLaunchInstructions() {
    this.elements.statusDescription.innerHTML = `
      <strong>Manual Launch Required:</strong><br>
      Search for "Desktop Companion Application" in Windows Start menu
    `;
  }

  /**
   * Open settings page
   */
  openSettings() {
    chrome.runtime.openOptionsPage();
  }

  /**
   * Update UI based on status
   */
  updateUI(status) {
    if (!status) return;
    
    this.status = status;
    const { isRunning, lastCheck, detectionMethod, version, error } = status;

    // Update status card class
    this.elements.statusCard.classList.remove('running', 'not-running', 'checking');
    this.elements.statusCard.classList.add(isRunning ? 'running' : 'not-running');

    // Update section indicator color based on status
    if (this.elements.statusIndicatorBar) {
      this.elements.statusIndicatorBar.className = 'section-indicator';
      if (!isRunning) {
        this.elements.statusIndicatorBar.classList.add('red');
      }
    }

    // Update status text
    if (isRunning) {
      this.elements.statusTitle.textContent = 'DCA Running';
      this.elements.statusDescription.textContent = 'Ready for voice calls';
      this.elements.statusBadgeText.textContent = 'Active';
      this.elements.warningBanner.style.display = 'none';
    } else {
      this.elements.statusTitle.textContent = 'DCA Not Running';
      this.elements.statusDescription.textContent = 'Voice calls may experience issues';
      this.elements.statusBadgeText.textContent = 'Inactive';
      this.elements.warningBanner.style.display = 'flex';
    }

    // Update details
    if (lastCheck) {
      const checkTime = new Date(lastCheck);
      this.elements.lastCheck.textContent = this.formatTime(checkTime);
    }

    if (detectionMethod) {
      this.elements.detectionMethod.textContent = this.formatMethod(detectionMethod);
    }

    if (version) {
      this.elements.versionRow.style.display = 'flex';
      this.elements.dcaVersion.textContent = version;
    } else {
      this.elements.versionRow.style.display = 'none';
    }

    // Show error if present
    if (error && !isRunning) {
      this.elements.statusDescription.textContent = error;
    }
  }

  /**
   * Set checking state
   */
  setCheckingState(checking) {
    this.isChecking = checking;
    
    if (checking) {
      this.elements.statusCard.classList.add('checking');
      this.elements.statusCard.classList.remove('running', 'not-running');
      this.elements.statusTitle.textContent = 'Checking...';
      this.elements.statusDescription.textContent = 'Detecting DCA status';
      this.elements.statusBadgeText.textContent = '...';
      this.elements.checkNowBtn.disabled = true;
      this.elements.checkNowBtn.innerHTML = `
        <svg class="spin" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M23 4v6h-6"/>
          <path d="M1 20v-6h6"/>
          <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
        </svg>
        Checking...
      `;
    } else {
      this.elements.checkNowBtn.disabled = false;
      this.elements.checkNowBtn.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M23 4v6h-6"/>
          <path d="M1 20v-6h6"/>
          <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
        </svg>
        Check Now
      `;
    }
  }

  /**
   * Format timestamp
   */
  formatTime(date) {
    const now = new Date();
    const diff = now - date;
    
    if (diff < 60000) {
      return 'Just now';
    } else if (diff < 3600000) {
      const mins = Math.floor(diff / 60000);
      return `${mins}m ago`;
    } else if (diff < 86400000) {
      const hours = Math.floor(diff / 3600000);
      return `${hours}h ago`;
    } else {
      return date.toLocaleTimeString();
    }
  }

  /**
   * Format detection method
   */
  formatMethod(method) {
    const methods = {
      'native': 'Native Messaging',
      'localServer': 'Local Server',
      'protocol': 'Protocol Handler',
      'none': 'Not Detected'
    };
    return methods[method] || method;
  }

  /**
   * Animate button
   */
  animateButton(button) {
    button.classList.add('success-flash');
    setTimeout(() => button.classList.remove('success-flash'), 500);
  }

  /**
   * Show notification
   */
  showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div');
    notification.className = `notification notification-${type}`;
    notification.textContent = message;
    
    // Add to page
    document.body.appendChild(notification);
    
    // Animate in
    requestAnimationFrame(() => {
      notification.classList.add('show');
    });
    
    // Remove after delay
    setTimeout(() => {
      notification.classList.remove('show');
      setTimeout(() => notification.remove(), 300);
    }, 3000);
  }

  /**
   * Show error state
   */
  showError(message) {
    this.elements.statusCard.classList.remove('running', 'checking');
    this.elements.statusCard.classList.add('not-running');
    this.elements.statusTitle.textContent = 'Error';
    this.elements.statusDescription.textContent = message;
  }
}

// Initialize popup when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  new PopupController();
});

// Add notification styles
const style = document.createElement('style');
style.textContent = `
  .notification {
    position: fixed;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%) translateY(100px);
    padding: 12px 20px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 500;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    transition: transform 0.3s ease;
    z-index: 1000;
  }
  
  .notification.show {
    transform: translateX(-50%) translateY(0);
  }
  
  .notification-info {
    background: #0078d4;
    color: white;
  }
  
  .notification-success {
    background: #22c55e;
    color: white;
  }
  
  .notification-error {
    background: #ef4444;
    color: white;
  }
  
  .notification-warning {
    background: #f59e0b;
    color: white;
  }
  
  .spin {
    animation: spin 1s linear infinite;
  }
  
  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
  
  .success-flash {
    animation: flash 0.5s ease;
  }
  
  @keyframes flash {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }
`;
document.head.appendChild(style);
