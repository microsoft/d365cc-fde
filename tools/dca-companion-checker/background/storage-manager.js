/**
 * Storage Manager Module
 * 
 * Handles all storage operations with caching and migration support
 */

export class StorageManager {
  constructor() {
    this.cache = new Map();
    this.initialized = false;
    this.version = 1;
  }

  /**
   * Initialize storage manager
   */
  async initialize() {
    if (this.initialized) return;

    try {
      // Load current version
      const storedVersion = await this.getRaw('storageVersion');
      
      // Run migrations if needed
      if (storedVersion && storedVersion < this.version) {
        await this.migrate(storedVersion, this.version);
      }

      // Store current version
      await this.setRaw('storageVersion', this.version);
      
      this.initialized = true;
      console.log('[Storage Manager] Initialized');
    } catch (error) {
      console.error('[Storage Manager] Initialization failed:', error);
      throw error;
    }
  }

  /**
   * Get value from storage
   */
  async get(key) {
    // Check cache first
    if (this.cache.has(key)) {
      return this.cache.get(key);
    }

    const value = await this.getRaw(key);
    
    if (value !== undefined) {
      this.cache.set(key, value);
    }

    return value;
  }

  /**
   * Set value in storage
   */
  async set(key, value) {
    // Update cache
    this.cache.set(key, value);

    // Persist to storage
    await this.setRaw(key, value);
  }

  /**
   * Remove value from storage
   */
  async remove(key) {
    this.cache.delete(key);
    await chrome.storage.local.remove(key);
  }

  /**
   * Clear all storage
   */
  async clear() {
    this.cache.clear();
    await chrome.storage.local.clear();
  }

  /**
   * Get raw value from storage (bypasses cache)
   */
  async getRaw(key) {
    const result = await chrome.storage.local.get(key);
    return result[key];
  }

  /**
   * Set raw value in storage (bypasses cache)
   */
  async setRaw(key, value) {
    await chrome.storage.local.set({ [key]: value });
  }

  /**
   * Run migrations
   */
  async migrate(fromVersion, toVersion) {
    console.log(`[Storage Manager] Migrating from v${fromVersion} to v${toVersion}`);

    for (let v = fromVersion; v < toVersion; v++) {
      const migration = this.migrations[v];
      if (migration) {
        await migration.call(this);
      }
    }
  }

  /**
   * Migration definitions
   */
  migrations = {
    // Example migration from v0 to v1
    0: async function() {
      // Migrate old settings format to new format
      const oldSettings = await this.getRaw('config');
      if (oldSettings) {
        await this.setRaw('settings', {
          ...oldSettings,
          version: 1
        });
        await this.remove('config');
      }
    }
  };

  /**
   * Export all data (for backup)
   */
  async exportData() {
    const data = await chrome.storage.local.get(null);
    return JSON.stringify(data, null, 2);
  }

  /**
   * Import data (from backup)
   */
  async importData(jsonData) {
    const data = JSON.parse(jsonData);
    await chrome.storage.local.clear();
    await chrome.storage.local.set(data);
    this.cache.clear();
  }

  /**
   * Get storage usage info
   */
  async getUsageInfo() {
    const bytesInUse = await chrome.storage.local.getBytesInUse();
    return {
      bytesInUse,
      bytesAvailable: chrome.storage.local.QUOTA_BYTES - bytesInUse,
      percentUsed: (bytesInUse / chrome.storage.local.QUOTA_BYTES * 100).toFixed(2)
    };
  }
}
