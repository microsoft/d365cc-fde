/**
 * Notification Manager Module
 * 
 * Handles browser notifications for DCA status changes
 */

export class NotificationManager {
  constructor(storageManager) {
    this.storageManager = storageManager;
    this.notificationQueue = [];
    this.isProcessing = false;
  }

  /**
   * Show a notification
   */
  async show(options) {
    const settings = await this.storageManager.get('settings') || {};
    
    // Check if notifications are enabled
    if (settings.notificationsEnabled === false) {
      console.log('[Notification Manager] Notifications disabled');
      return;
    }

    const notificationOptions = {
      type: 'basic',
      iconUrl: this.getIconForType(options.type),
      title: options.title,
      message: options.message,
      priority: options.priority || 1,
      requireInteraction: options.requireInteraction || false,
      silent: options.silent || false
    };

    try {
      const notificationId = `dca-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      
      await chrome.notifications.create(notificationId, notificationOptions);
      
      // Auto-dismiss after timeout (unless requireInteraction)
      if (!options.requireInteraction) {
        setTimeout(() => {
          chrome.notifications.clear(notificationId);
        }, options.timeout || 5000);
      }

      // Log notification
      await this.logNotification({
        id: notificationId,
        ...options,
        timestamp: new Date().toISOString()
      });

      return notificationId;
    } catch (error) {
      console.error('[Notification Manager] Failed to show notification:', error);
      throw error;
    }
  }

  /**
   * Get icon URL for notification type
   */
  getIconForType(type) {
    const iconMap = {
      success: chrome.runtime.getURL('icons/icon-success-128.png'),
      warning: chrome.runtime.getURL('icons/icon-warning-128.png'),
      error: chrome.runtime.getURL('icons/icon-error-128.png'),
      info: chrome.runtime.getURL('icons/icon128.png')
    };

    return iconMap[type] || iconMap.info;
  }

  /**
   * Log notification to history
   */
  async logNotification(notification) {
    try {
      const history = await this.storageManager.get('notificationHistory') || [];
      history.unshift(notification);
      
      // Keep only last 100 notifications
      if (history.length > 100) {
        history.pop();
      }

      await this.storageManager.set('notificationHistory', history);
    } catch (error) {
      console.error('[Notification Manager] Failed to log notification:', error);
    }
  }

  /**
   * Clear notification history
   */
  async clearHistory() {
    await this.storageManager.set('notificationHistory', []);
  }

  /**
   * Get notification history
   */
  async getHistory() {
    return await this.storageManager.get('notificationHistory') || [];
  }
}
