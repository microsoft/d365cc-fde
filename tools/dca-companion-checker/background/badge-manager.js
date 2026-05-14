/**
 * Badge Manager Module
 * 
 * Manages the extension's toolbar badge state and appearance
 */

export class BadgeManager {
  constructor() {
    this.colors = {
      running: '#22C55E',      // Green
      notRunning: '#EF4444',   // Red
      checking: '#F59E0B',     // Yellow/Orange
      unknown: '#6B7280'       // Gray
    };
  }

  /**
   * Update badge based on DCA status
   */
  async updateBadge(isRunning, isChecking = false) {
    try {
      if (isChecking) {
        await this.setChecking();
        return;
      }

      if (isRunning) {
        await this.setRunning();
      } else {
        await this.setNotRunning();
      }
    } catch (error) {
      console.error('[Badge Manager] Update failed:', error);
    }
  }

  /**
   * Set badge to running state
   */
  async setRunning() {
    await chrome.action.setBadgeText({ text: '✓' });
    await chrome.action.setBadgeBackgroundColor({ color: this.colors.running });
    await chrome.action.setTitle({ title: 'DCA Checker - Running ✓' });
  }

  /**
   * Set badge to not running state
   */
  async setNotRunning() {
    await chrome.action.setBadgeText({ text: '!' });
    await chrome.action.setBadgeBackgroundColor({ color: this.colors.notRunning });
    await chrome.action.setTitle({ title: 'DCA Checker - Not Running ⚠' });
  }

  /**
   * Set badge to checking state
   */
  async setChecking() {
    await chrome.action.setBadgeText({ text: '...' });
    await chrome.action.setBadgeBackgroundColor({ color: this.colors.checking });
    await chrome.action.setTitle({ title: 'DCA Checker - Checking...' });
  }

  /**
   * Set badge to unknown state
   */
  async setUnknown() {
    await chrome.action.setBadgeText({ text: '?' });
    await chrome.action.setBadgeBackgroundColor({ color: this.colors.unknown });
    await chrome.action.setTitle({ title: 'DCA Checker - Unknown Status' });
  }

  /**
   * Clear badge
   */
  async clearBadge() {
    await chrome.action.setBadgeText({ text: '' });
    await chrome.action.setTitle({ title: 'DCA Companion Checker' });
  }
}
