/**
 * DCA Detector Module
 * 
 * Implements multiple detection strategies to determine if the
 * Desktop Companion Application is running:
 * 
 * 1. Native Messaging - Direct communication with DCA native host
 * 2. Local Server Detection - Check for DCA's local HTTP/WebSocket server
 * 3. Protocol Handler - Verify custom protocol registration
 * 4. Process Detection (via native messaging host)
 */

export class DCADetector {
  constructor(storageManager) {
    this.storageManager = storageManager;
    this.nativePort = null;
    this.lastSuccessfulMethod = null;
  }

  /**
   * Main detection method - tries multiple strategies
   */
  async detect(options = {}) {
    const settings = await this.storageManager.get('settings') || this.getDefaultSettings();
    const methods = options.deep 
      ? ['native', 'localServer', 'protocol']
      : [this.lastSuccessfulMethod || 'localServer', 'native'];

    for (const method of methods) {
      try {
        const result = await this.detectWithMethod(method, settings);
        if (result.isRunning) {
          this.lastSuccessfulMethod = method;
          return {
            isRunning: true,
            method: method,
            ...result
          };
        }
      } catch (error) {
        console.log(`[DCA Detector] ${method} detection failed:`, error.message);
      }
    }

    return {
      isRunning: false,
      method: 'none',
      error: 'DCA not detected with any method'
    };
  }

  /**
   * Detect using specific method
   */
  async detectWithMethod(method, settings) {
    switch (method) {
      case 'native':
        return await this.detectViaNativeMessaging(settings);
      case 'localServer':
        return await this.detectViaLocalServer(settings);
      case 'protocol':
        return await this.detectViaProtocol(settings);
      default:
        throw new Error(`Unknown detection method: ${method}`);
    }
  }

  /**
   * Detection via Native Messaging
   * Requires native messaging host to be installed
   */
  async detectViaNativeMessaging(settings) {
    const hostName = settings.nativeMessagingHost || 'com.microsoft.dynamics.dca.checker';
    const timeout_ms = settings.detectionTimeout || 5000;
    
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Native messaging timeout'));
      }, timeout_ms);

      try {
        const port = chrome.runtime.connectNative(hostName);
        
        port.onMessage.addListener((message) => {
          clearTimeout(timeout);
          port.disconnect();
          
          if (message.status === 'running' || message.isRunning) {
            resolve({
              isRunning: true,
              version: message.version,
              details: message
            });
          } else {
            resolve({ isRunning: false });
          }
        });

        port.onDisconnect.addListener(() => {
          clearTimeout(timeout);
          const error = chrome.runtime.lastError;
          if (error) {
            reject(new Error(error.message));
          }
        });

        // Send status check command with settings for custom process name/path
        port.postMessage({ 
          command: 'checkStatus',
          settings: {
            dcaProcessName: settings.dcaProcessName,
            dcaPath: settings.dcaPath
          }
        });
      } catch (error) {
        clearTimeout(timeout);
        reject(error);
      }
    });
  }

  /**
   * Detection via Local Server
   * DCA may expose a local HTTP/WebSocket endpoint
   */
  async detectViaLocalServer(settings) {
    const ports = settings.ports || [9222, 9223, 9224, 9876, 12345, 8765, 5000];
    const endpoints = [
      '/status',
      '/health',
      '/api/status',
      '/api/v1/status',
      '/dca/status',
      '/'
    ];

    for (const port of ports) {
      for (const endpoint of endpoints) {
        try {
          const result = await this.checkLocalEndpoint(port, endpoint);
          if (result.isRunning) {
            return {
              isRunning: true,
              port: port,
              endpoint: endpoint,
              details: result.data
            };
          }
        } catch (e) {
          // Continue to next port/endpoint
        }
      }
    }

    // Try WebSocket detection
    for (const port of ports) {
      try {
        const wsResult = await this.checkWebSocket(port);
        if (wsResult.isRunning) {
          return {
            isRunning: true,
            port: port,
            connectionType: 'websocket',
            details: wsResult
          };
        }
      } catch (e) {
        // Continue
      }
    }

    return { isRunning: false };
  }

  /**
   * Check a specific local HTTP endpoint
   */
  async checkLocalEndpoint(port, endpoint) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 2000);

    try {
      const response = await fetch(`http://localhost:${port}${endpoint}`, {
        method: 'GET',
        signal: controller.signal,
        headers: {
          'Accept': 'application/json, text/plain, */*'
        }
      });

      clearTimeout(timeoutId);

      if (response.ok) {
        const contentType = response.headers.get('content-type');
        let data = null;

        if (contentType && contentType.includes('application/json')) {
          data = await response.json();
        } else {
          data = await response.text();
        }

        // Check if response indicates DCA
        if (this.isDCAResponse(data, response)) {
          return { isRunning: true, data };
        }
      }

      return { isRunning: false };
    } catch (error) {
      clearTimeout(timeoutId);
      throw error;
    }
  }

  /**
   * Check WebSocket connection
   */
  async checkWebSocket(port) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        ws.close();
        reject(new Error('WebSocket timeout'));
      }, 3000);

      const ws = new WebSocket(`ws://localhost:${port}`);

      ws.onopen = () => {
        clearTimeout(timeout);
        ws.send(JSON.stringify({ type: 'ping', command: 'status' }));
      };

      ws.onmessage = (event) => {
        clearTimeout(timeout);
        try {
          const data = JSON.parse(event.data);
          ws.close();
          resolve({ isRunning: true, data });
        } catch (e) {
          ws.close();
          resolve({ isRunning: true, raw: event.data });
        }
      };

      ws.onerror = () => {
        clearTimeout(timeout);
        reject(new Error('WebSocket error'));
      };

      ws.onclose = (event) => {
        if (!event.wasClean) {
          reject(new Error('WebSocket closed unexpectedly'));
        }
      };
    });
  }

  /**
   * Check if response indicates DCA is running
   */
  isDCAResponse(data, response) {
    // Check headers
    const serverHeader = response.headers.get('server');
    if (serverHeader && (
      serverHeader.toLowerCase().includes('dca') ||
      serverHeader.toLowerCase().includes('dynamics') ||
      serverHeader.toLowerCase().includes('microsoft')
    )) {
      return true;
    }

    // Check response body
    if (typeof data === 'object' && data !== null) {
      // Look for DCA indicators
      const indicators = [
        'dca', 'desktop-companion', 'dynamics', 'ccaas',
        'contact-center', 'voice-channel', 'microsoft'
      ];
      
      const jsonStr = JSON.stringify(data).toLowerCase();
      for (const indicator of indicators) {
        if (jsonStr.includes(indicator)) {
          return true;
        }
      }

      // Check for status fields
      if (data.status === 'running' || data.isRunning || data.active) {
        return true;
      }
    }

    if (typeof data === 'string') {
      const lowerData = data.toLowerCase();
      if (
        lowerData.includes('dca') ||
        lowerData.includes('desktop companion') ||
        lowerData.includes('dynamics')
      ) {
        return true;
      }
    }

    return false;
  }

  /**
   * Detection via Protocol Handler
   */
  async detectViaProtocol(settings) {
    const protocols = settings.protocolHandlers || ['ms-ccaas', 'msdyn-ccaas', 'd365-dca'];
    
    for (const protocol of protocols) {
      try {
        const isRegistered = await this.checkProtocolHandler(protocol);
        if (isRegistered) {
          return {
            isRunning: true, // Protocol registered suggests app is installed
            protocol: protocol
          };
        }
      } catch (e) {
        // Continue to next protocol
      }
    }

    return { isRunning: false };
  }

  /**
   * Check if a protocol handler is registered
   */
  async checkProtocolHandler(protocol) {
    // Use the navigator.registerProtocolHandler API to check
    // Note: This is limited and may not work in all browsers
    return new Promise((resolve) => {
      try {
        // Create a hidden iframe to test protocol
        const iframe = document.createElement('iframe');
        iframe.style.display = 'none';
        document.body.appendChild(iframe);

        const timeout = setTimeout(() => {
          iframe.remove();
          resolve(false);
        }, 1000);

        iframe.onload = () => {
          clearTimeout(timeout);
          iframe.remove();
          resolve(true);
        };

        iframe.onerror = () => {
          clearTimeout(timeout);
          iframe.remove();
          resolve(false);
        };

        iframe.src = `${protocol}://check`;
      } catch (e) {
        resolve(false);
      }
    });
  }

  /**
   * Launch DCA via Native Messaging
   */
  async launchViaNativeMessaging() {
    const settings = await this.storageManager.get('settings') || this.getDefaultSettings();
    const hostName = settings.nativeMessagingHost || 'com.microsoft.dynamics.dca.checker';

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Launch timeout'));
      }, 10000);

      try {
        const port = chrome.runtime.connectNative(hostName);

        port.onMessage.addListener((message) => {
          clearTimeout(timeout);
          port.disconnect();
          resolve({ success: true, message });
        });

        port.onDisconnect.addListener(() => {
          clearTimeout(timeout);
          const error = chrome.runtime.lastError;
          reject(new Error(error?.message || 'Native messaging failed'));
        });

        port.postMessage({ command: 'launch' });
      } catch (error) {
        clearTimeout(timeout);
        reject(error);
      }
    });
  }

  /**
   * Launch DCA via Protocol Handler
   */
  async launchViaProtocol() {
    const settings = await this.storageManager.get('settings') || this.getDefaultSettings();
    const protocols = settings.protocolHandlers || ['ms-ccaas', 'msdyn-ccaas', 'd365-dca'];

    for (const protocol of protocols) {
      try {
        // Create a link and click it to trigger protocol handler
        const link = document.createElement('a');
        link.href = `${protocol}://launch`;
        link.click();
        
        return { success: true, protocol };
      } catch (e) {
        // Try next protocol
      }
    }

    return { success: false, error: 'No protocol handler available' };
  }

  /**
   * Get default settings
   */
  getDefaultSettings() {
    return {
      // D365 Contact Center URL
      d365Url: 'https://adatum.crm.dynamics.com/',
      // Enforcement - STRICT BY DEFAULT
      enforcementLevel: 'strict',
      blockPresenceChange: true,
      showBlockingModal: true,
      // DCA Configuration (can be customized per organization)
      dcaProcessName: 'Microsoft.Dynamics.DCA',
      dcaDisplayName: 'Desktop Companion Application',
      dcaPath: 'C:\\Program Files\\Microsoft\\Dynamics 365 Contact Center\\DCA\\Microsoft.Dynamics.DCA.exe',
      // Detection settings
      ports: [9222, 9223, 9224, 9876, 12345, 8765, 5000],
      protocolHandlers: ['ms-ccaas', 'msdyn-ccaas', 'd365-dca'],
      detectionTimeout: 2000,
      nativeMessagingHost: 'com.microsoft.dynamics.dca.checker'
    };
  }
}
