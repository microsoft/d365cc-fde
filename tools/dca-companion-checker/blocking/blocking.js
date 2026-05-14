/**
 * Blocking Page Script
 * 
 * Checks DCA status and redirects to the original URL when DCA is running.
 * The original URL is passed via query parameter.
 */

(function() {
  'use strict';

  // Get the original URL from query parameters
  const urlParams = new URLSearchParams(window.location.search);
  const originalUrl = urlParams.get('url');
  const decodedUrl = originalUrl ? decodeURIComponent(originalUrl) : null;

  // UI Elements
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const originalUrlEl = document.getElementById('originalUrl');
  const launchBtn = document.getElementById('launchBtn');
  const checkBtn = document.getElementById('checkBtn');
  const checkBtnContent = document.getElementById('checkBtnContent');
  const infoBox = document.getElementById('infoBox');

  // Show original URL
  if (decodedUrl) {
    // Extract just the domain for cleaner display
    try {
      const url = new URL(decodedUrl);
      originalUrlEl.innerHTML = `<span class="destination-label">Destination</span>${url.hostname}`;
    } catch {
      originalUrlEl.innerHTML = `<span class="destination-label">Destination</span>${decodedUrl}`;
    }
  } else {
    originalUrlEl.innerHTML = '<span class="destination-label">Destination</span>No URL specified';
  }

  // Update status display
  function updateStatus(status, message, isRunning = false) {
    statusText.textContent = message;
    statusDot.className = 'status-dot';
    if (isRunning) {
      statusDot.classList.add('running');
    } else if (status === 'error') {
      statusDot.classList.add('error');
    }
  }

  // Check DCA status
  async function checkDCA() {
    checkBtn.classList.add('checking');
    checkBtnContent.innerHTML = '<span class="spinner"></span>';
    
    try {
      const response = await chrome.runtime.sendMessage({ 
        type: 'CHECK_NOW', 
        options: { deep: true } 
      });
      
      console.log('[Blocking Page] DCA check response:', response);
      
      if (response && response.isRunning) {
        updateStatus('running', 'DCA verified! Redirecting...', true);
        infoBox.className = 'info-box success';
        infoBox.innerHTML = '<strong>✓ DCA Verified</strong>Connecting to D365 Contact Center...';
        
        // Tell background to allow this tab before redirecting
        if (decodedUrl) {
          try {
            const allowResult = await chrome.runtime.sendMessage({
              type: 'ALLOW_AND_REDIRECT',
              url: decodedUrl
            });
            console.log('[Blocking Page] Allow result:', allowResult);
            
            // Redirect after confirming the tab is allowed
            window.location.href = decodedUrl;
          } catch (e) {
            console.error('[Blocking Page] Allow failed:', e);
            // Still try to redirect
            window.location.href = decodedUrl;
          }
        }
      } else {
        updateStatus('not-running', 'DCA not detected');
        restoreCheckButton();
      }
    } catch (error) {
      console.error('[Blocking Page] Check failed:', error);
      updateStatus('error', 'Unable to check status');
      restoreCheckButton();
    }
  }

  // Restore check button to original state
  function restoreCheckButton() {
    checkBtn.classList.remove('checking');
    checkBtnContent.innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="23 4 23 10 17 10"></polyline>
        <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"></path>
      </svg>
      Check
    `;
  }

  // Launch DCA
  async function launchDCA() {
    updateStatus('checking', 'Launching DCA...');
    launchBtn.classList.add('checking');
    
    try {
      await chrome.runtime.sendMessage({ type: 'LAUNCH_DCA' });
      // Check after a delay to give DCA time to start
      setTimeout(() => {
        launchBtn.classList.remove('checking');
        checkDCA();
      }, 2000);
    } catch (error) {
      console.error('[Blocking Page] Launch failed:', error);
      updateStatus('error', 'Launch failed - start DCA manually');
      launchBtn.classList.remove('checking');
    }
  }

  // Event listeners
  launchBtn.addEventListener('click', launchDCA);
  checkBtn.addEventListener('click', checkDCA);

  // Initial check on page load
  setTimeout(checkDCA, 500);

  // Auto-check periodically
  setInterval(() => {
    if (!checkBtn.classList.contains('checking')) {
      checkDCA();
    }
  }, 5000);
})();
