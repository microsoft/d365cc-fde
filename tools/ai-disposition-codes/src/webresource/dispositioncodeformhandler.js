// ==========================================================
// Disposition Code Copilot - Form Handler v2.2
// OPTIMIZED FOR HIGH-VOLUME CONTACT CENTERS
// ==========================================================
// Web resources:
//  - JS:   ccaasfde_dispositioncodeformhandler
//  - Custom Page: ccaasfde_dispositionrecommendation_d051d
//
// Trigger:
//  - CIF "EndConversationEvent" (fires when conversation ends)
// Action:
//  - On form load: parallel fetch workstream + dispositions (non-blocking)
//  - On end: open modal with pre-cached data (instant)
//
// v2.2 CHANGE LOG:
//  - FIX: A failed modal open no longer leaves the conversation marked as
//    handled; the in-memory, global and sessionStorage guards are released
//    so the next end event can retry.
//  - FIX: Form refresh after the modal closes uses formContext.data.refresh();
//    DOM scraping for the Refresh button is only a fallback.
//  - NEW: CONFIG.ENABLED kill switch and CONFIG.ENABLED_WORKSTREAM_IDS
//    allowlist. The modal is skipped when the workstream has no disposition
//    codes.
//  - NEW: Warnings when the 500-code fetch limit or the payload size limit
//    is reached.
//  - FIX: Evaluating the script again (form reload) retires the previous copy
//    (unregisters its CIF callback and timer) so one end event cannot open
//    two modals.
//  - Everything is now scoped inside an IIFE. Only `onLoad` (the form event
//    handler, kept for backward compatibility with existing form
//    registrations) and `__ccaasfdeCopilot` (debug) are exposed on window.
//  - Removed unused code (saveDisposition, getDispositionCategories,
//    MessageHandler, withTimeout, formatGuidForOData). The Custom Page
//    performs all saves.
//
// v2.1: Added sessionStorage guard to prevent a duplicate modal when the
//    agent closes the conversation form/tab (EndConversationEvent fires on
//    both conversation end AND session close).
// ==========================================================

(function (global) {
"use strict";

// ===== CONFIGURATION =====
const CONFIG = Object.freeze({
  // Kill switch. Set to false and publish to disable the modal without
  // removing the form registration.
  ENABLED: true,

  // Optional allowlist of workstream IDs (lowercase GUIDs, no braces).
  // Empty = all workstreams.
  ENABLED_WORKSTREAM_IDS: [],

  // Entities
  DISPOSITION_ENTITY: "msdyn_ocdispositioncode",
  LIVEWORKITEM_ENTITY: "msdyn_ocliveworkitem",
  WORKSTREAM_LOOKUP: "_msdyn_liveworkstreamid_value",

  // UI
  MODAL_CUSTOM_PAGE: "ccaasfde_dispositionrecommendation_d051d",
  CIF_END_CONVERSATION_EVENT: "EndConversationEvent",

  // Limits
  DISPOSITION_FETCH_LIMIT: 500,
  MAX_PAYLOAD_CHARS: 200000,

  // Cache
  DISPOSITION_CACHE_TTL_MS: 5 * 60 * 1000,  // 5 minutes - dispositions rarely change
  WORKSTREAM_CACHE_TTL_MS: 30 * 60 * 1000,  // 30 minutes - workstream even more stable

  // Session storage key prefix for duplicate modal prevention (v2.1)
  SESSION_STORAGE_PREFIX: "ccaasfde_dispo_handled_",
  SESSION_STORAGE_TTL_MS: 30 * 60 * 1000,   // 30 minutes - generous TTL for session storage entries

  // In-memory guard lifetime
  HANDLED_GUARD_TTL_MS: 5 * 60 * 1000,

  // Debug
  DEBUG_PREFIX: "[ccaasfde dispo v2.2]",
  VERSION: "2.2.0"
});

// ===== GLOBAL CACHE (shared across all form instances) =====
// Agents handle multiple conversations; we don't want to re-fetch the same
// data for each session.
const GlobalCache = {
  // Structure: { [workstreamId]: { data: [...], timestamp: Date.now() } }
  dispositions: new Map(),

  // Structure: { [lwiId]: { workstreamId: "...", timestamp: Date.now() } }
  workstreams: new Map(),

  // In-flight promises for deduplication
  pendingRequests: new Map(),

  isValid(entry, ttlMs) {
    return !!entry && (Date.now() - entry.timestamp) < ttlMs;
  },

  cleanup() {
    const now = Date.now();
    for (const [key, entry] of this.dispositions) {
      if (now - entry.timestamp > CONFIG.DISPOSITION_CACHE_TTL_MS * 2) {
        this.dispositions.delete(key);
      }
    }
    for (const [key, entry] of this.workstreams) {
      if (now - entry.timestamp > CONFIG.WORKSTREAM_CACHE_TTL_MS * 2) {
        this.workstreams.delete(key);
      }
    }
  }
};

// If the script is evaluated again (form reload), retire the previous copy first. Otherwise its
// CIF callback stays registered next to the new one and a single end event opens two modals.
try { global.__ccaasfdeCopilot?.dispose?.(); } catch {}
let disposed = false;
const registeredCallbacks = [];

// Cleanup every 10 minutes.
const cleanupTimer = setInterval(() => GlobalCache.cleanup(), 10 * 60 * 1000);

function dispose() {
  disposed = true;
  try { clearInterval(cleanupTimer); } catch {}
  for (const callback of registeredCallbacks) {
    try { global.Microsoft?.CIFramework?.removeHandler?.(CONFIG.CIF_END_CONVERSATION_EVENT, callback); } catch {}
  }
  registeredCallbacks.length = 0;
}

// ===== LOGGING =====
const log = {
  debug: (msg, data) => {
    try { console.log(CONFIG.DEBUG_PREFIX, msg, data ?? ""); } catch {}
  },
  warn: (msg, data) => {
    try { console.warn(CONFIG.DEBUG_PREFIX, msg, data ?? ""); } catch {}
  },
  error: (msg, data) => {
    try { console.error(CONFIG.DEBUG_PREFIX, msg, data ?? ""); } catch {}
  },
  perf: (label, startTime) => {
    try { console.log(CONFIG.DEBUG_PREFIX, `⏱ ${label}: ${Date.now() - startTime}ms`); } catch {}
  }
};

// ===== UTILITY FUNCTIONS =====
const Utils = {
  cleanGuid: (id) => (id || "").replace(/[{}]/g, "").toLowerCase(),

  // Deduplicated async operation - prevents duplicate concurrent requests
  async dedupedAsync(cacheKey, asyncFn) {
    if (GlobalCache.pendingRequests.has(cacheKey)) {
      log.debug("dedupe hit", { cacheKey });
      return GlobalCache.pendingRequests.get(cacheKey);
    }

    const promise = asyncFn().finally(() => {
      GlobalCache.pendingRequests.delete(cacheKey);
    });

    GlobalCache.pendingRequests.set(cacheKey, promise);
    return promise;
  }
};

// ===== SESSION STORAGE GUARD (v2.1) =====
// Persists across form reloads within the same browser session.
// Prevents the duplicate modal when agent closes the conversation form/tab.
const SessionGuard = {
  isHandled(conversationId) {
    if (!conversationId) return false;
    try {
      const key = CONFIG.SESSION_STORAGE_PREFIX + conversationId;
      const val = sessionStorage.getItem(key);
      if (!val) return false;

      const storedTime = parseInt(val, 10);
      if (isNaN(storedTime)) return false;

      if ((Date.now() - storedTime) > CONFIG.SESSION_STORAGE_TTL_MS) {
        sessionStorage.removeItem(key);
        return false;
      }

      return true;
    } catch {
      // sessionStorage not available - fall through to in-memory guards
      return false;
    }
  },

  markHandled(conversationId) {
    if (!conversationId) return;
    try {
      sessionStorage.setItem(CONFIG.SESSION_STORAGE_PREFIX + conversationId, Date.now().toString());
    } catch {}
  },

  unmark(conversationId) {
    if (!conversationId) return;
    try {
      sessionStorage.removeItem(CONFIG.SESSION_STORAGE_PREFIX + conversationId);
    } catch {}
  }
};

// ===== DATA FETCHING =====
const DataService = {

  // Get workstream ID from live work item - with caching
  async getWorkstreamId(lwiId) {
    const cleanId = Utils.cleanGuid(lwiId);
    if (!cleanId) return null;

    const cached = GlobalCache.workstreams.get(cleanId);
    if (GlobalCache.isValid(cached, CONFIG.WORKSTREAM_CACHE_TTL_MS)) {
      log.debug("workstream cache hit", { lwiId: cleanId, workstreamId: cached.workstreamId });
      return cached.workstreamId;
    }

    return Utils.dedupedAsync(`ws_${cleanId}`, async () => {
      const startTime = Date.now();
      try {
        const res = await Xrm.WebApi.retrieveRecord(
          CONFIG.LIVEWORKITEM_ENTITY,
          cleanId,
          `?$select=${CONFIG.WORKSTREAM_LOOKUP}`
        );

        const workstreamId = Utils.cleanGuid(res?.[CONFIG.WORKSTREAM_LOOKUP]);

        if (workstreamId) {
          GlobalCache.workstreams.set(cleanId, { workstreamId, timestamp: Date.now() });
        }

        log.perf("getWorkstreamId", startTime);
        log.debug("workstream resolved", { lwiId: cleanId, workstreamId });
        return workstreamId;

      } catch (e) {
        log.error("getWorkstreamId failed", { lwiId: cleanId, error: e?.message });
        return null;
      }
    });
  },

  // Get disposition codes - with caching and workstream filtering
  // Priority: 1) Workstream-specific, 2) Global (appliestoallworkstreams), 3) All active
  async getDispositions(workstreamId = null) {
    const cacheKey = workstreamId ? Utils.cleanGuid(workstreamId) : "global";

    const cached = GlobalCache.dispositions.get(cacheKey);
    if (GlobalCache.isValid(cached, CONFIG.DISPOSITION_CACHE_TTL_MS)) {
      log.debug("disposition cache hit", { cacheKey, count: cached.data.length });
      return cached.data;
    }

    return Utils.dedupedAsync(`dispo_${cacheKey}`, async () => {
      const startTime = Date.now();

      let dispositions = [];

      if (workstreamId) {
        dispositions = await this._fetchWorkstreamDispositions(workstreamId);
        log.debug("workstream dispositions", { workstreamId, count: dispositions.length });
      }

      if (dispositions.length === 0) {
        dispositions = await this._fetchGlobalDispositions();
        log.debug("global dispositions", { count: dispositions.length });
      }

      if (dispositions.length === 0) {
        dispositions = await this._fetchAllDispositions();
        log.debug("all dispositions fallback", { count: dispositions.length });
      }

      if (dispositions.length >= CONFIG.DISPOSITION_FETCH_LIMIT) {
        log.warn("disposition fetch limit reached - some codes may be missing from AI recommendations and search", {
          limit: CONFIG.DISPOSITION_FETCH_LIMIT
        });
      }

      GlobalCache.dispositions.set(cacheKey, { data: dispositions, timestamp: Date.now() });

      log.perf("getDispositions", startTime);
      log.debug("dispositions loaded", { cacheKey, count: dispositions.length });
      return dispositions;
    });
  },

  _mapDisposition(d, source) {
    return {
      id: d.msdyn_ocdispositioncodeid,
      label: d.msdyn_dispositioncodevalue || "",
      code: d.msdyn_name || "",
      categoryId: d._msdyn_dispositioncodecategoryid_value || null,
      source
    };
  },

  // Fetch dispositions linked to a specific workstream via the N:N intersect table
  // msdyn_ocdispositioncode_msdyn_liveworkstream
  async _fetchWorkstreamDispositions(workstreamId) {
    const cleanId = Utils.cleanGuid(workstreamId);

    const fetchXml = `
      <fetch top="${CONFIG.DISPOSITION_FETCH_LIMIT}" distinct="true">
        <entity name="msdyn_ocdispositioncode">
          <attribute name="msdyn_ocdispositioncodeid" />
          <attribute name="msdyn_name" />
          <attribute name="msdyn_dispositioncodevalue" />
          <attribute name="msdyn_dispositioncodecategoryid" />
          <attribute name="statecode" />
          <filter>
            <condition attribute="statecode" operator="eq" value="0" />
          </filter>
          <link-entity name="msdyn_ocdispositioncode_msdyn_liveworkstream" from="msdyn_ocdispositioncodeid" to="msdyn_ocdispositioncodeid" intersect="true">
            <filter>
              <condition attribute="msdyn_liveworkstreamid" operator="eq" value="${cleanId}" />
            </filter>
          </link-entity>
          <order attribute="msdyn_dispositioncodevalue" />
        </entity>
      </fetch>
    `.trim();

    try {
      const res = await Xrm.WebApi.retrieveMultipleRecords(
        CONFIG.DISPOSITION_ENTITY,
        `?fetchXml=${encodeURIComponent(fetchXml)}`
      );
      return (res?.entities || []).map(d => this._mapDisposition(d, "workstream"));
    } catch (e) {
      log.warn("workstream dispositions fetch failed, will use global", { error: e?.message });
      return [];
    }
  },

  // Fetch all global disposition codes (msdyn_appliestoallworkstreams = true)
  async _fetchGlobalDispositions() {
    return this._fetchByFilter("statecode eq 0 and msdyn_appliestoallworkstreams eq true", "global");
  },

  // Fetch ALL active disposition codes (fallback)
  async _fetchAllDispositions() {
    return this._fetchByFilter("statecode eq 0", "all");
  },

  async _fetchByFilter(filter, source) {
    try {
      const query =
        `?$select=msdyn_ocdispositioncodeid,msdyn_name,msdyn_dispositioncodevalue,_msdyn_dispositioncodecategoryid_value` +
        `&$filter=${filter}` +
        `&$orderby=msdyn_dispositioncodevalue asc` +
        `&$top=${CONFIG.DISPOSITION_FETCH_LIMIT}`;

      const res = await Xrm.WebApi.retrieveMultipleRecords(CONFIG.DISPOSITION_ENTITY, query);
      return (res?.entities || []).map(d => this._mapDisposition(d, source));
    } catch (e) {
      log.error(`${source} dispositions fetch failed`, { error: e?.message });
      return [];
    }
  }

  // NOTE: The Copilot summary is fetched by the Cloud Flow, and the selected
  // codes are saved by the Custom Page. This keeps the JS non-blocking.
};

// ===== FORM STATE MANAGER =====
// Per-form instance state (each form has its own lifecycle)
class FormState {
  constructor(formContext) {
    this.formContext = formContext;
    this.conversationId = null;
    this.workstreamId = null;
    this.dispositions = [];
    this.isInitialized = false;
    this.isLoading = false;
    this.cifHandlerId = null;
    this.modalOpened = false;
    this.initPromise = null;
  }

  // Initialize all data in parallel - non-blocking
  async initialize() {
    if (this.isInitialized || this.isLoading) {
      return this.initPromise;
    }

    this.isLoading = true;
    const startTime = Date.now();

    this.initPromise = (async () => {
      try {
        this.conversationId = Utils.cleanGuid(this.formContext.data.entity.getId());

        if (!this.conversationId) {
          log.warn("no conversation ID on form");
          return;
        }

        // Fetch the workstream and global dispositions simultaneously
        const [workstreamId, globalDispositions] = await Promise.all([
          DataService.getWorkstreamId(this.conversationId),
          DataService.getDispositions(null)
        ]);

        this.workstreamId = workstreamId;

        if (workstreamId) {
          const wsDispositions = await DataService.getDispositions(workstreamId);
          this.dispositions = wsDispositions.length > 0 ? wsDispositions : globalDispositions;
        } else {
          this.dispositions = globalDispositions;
        }

        this.isInitialized = true;
        log.perf("form state initialized", startTime);
        log.debug("form ready", {
          conversationId: this.conversationId,
          workstreamId: this.workstreamId,
          dispositionCount: this.dispositions.length
        });

      } catch (e) {
        log.error("form state init failed", { error: e?.message });
      } finally {
        this.isLoading = false;
      }
    })();

    return this.initPromise;
  }

  // Ensure data is ready (used before opening modal)
  async ensureReady() {
    if (!this.isInitialized && !this.isLoading) {
      await this.initialize();
    } else if (this.isLoading) {
      await this.initPromise;
    }
    return this.isInitialized;
  }
}

const formStates = new WeakMap();

function getFormState(formContext) {
  if (!formStates.has(formContext)) {
    formStates.set(formContext, new FormState(formContext));
  }
  return formStates.get(formContext);
}

// ===== CIF EVENT HANDLING =====
const CIFHandler = {
  // Conversations already handled in this page (across all form instances)
  _handledConversations: new Set(),

  register(formContext) {
    if (!(global.Microsoft?.CIFramework)) {
      log.debug("CIF not available");
      return;
    }

    const state = getFormState(formContext);
    if (state.cifHandlerId) return;  // Already registered

    const callback = async (eventData) => {
      if (disposed) return;
      try {
        await this.handleEndConversation(formContext, eventData);
      } catch (e) {
        log.error("CIF handler error", { error: e?.message });
      }
    };
    registeredCallbacks.push(callback);
    state.cifHandlerId = global.Microsoft.CIFramework.addHandler(CONFIG.CIF_END_CONVERSATION_EVENT, callback);

    log.debug("CIF handler registered", { handlerId: state.cifHandlerId });
  },

  _isWorkstreamAllowed(workstreamId) {
    const allow = CONFIG.ENABLED_WORKSTREAM_IDS;
    if (!allow || allow.length === 0) return true;
    return allow.map(Utils.cleanGuid).includes(Utils.cleanGuid(workstreamId));
  },

  _releaseGuards(state) {
    state.modalOpened = false;
    this._handledConversations.delete(state.conversationId);
    SessionGuard.unmark(state.conversationId);
  },

  async handleEndConversation(formContext, eventData) {
    if (!CONFIG.ENABLED) {
      log.debug("disabled via CONFIG.ENABLED, skipping");
      return;
    }

    const state = getFormState(formContext);

    if (state.modalOpened) {
      log.debug("modal already opened for this form instance, skipping");
      return;
    }

    // Validate this event is for our conversation
    const eventLwi = this._getLwiFromEvent(eventData);
    if (eventLwi && state.conversationId &&
        Utils.cleanGuid(eventLwi) !== state.conversationId) {
      log.debug("ignoring end event for different conversation");
      return;
    }

    const conversationKey = state.conversationId || eventLwi;
    if (conversationKey && this._handledConversations.has(conversationKey)) {
      log.debug("conversation already handled globally, skipping", { conversationKey });
      return;
    }

    // sessionStorage survives form reloads unlike the in-memory guards above
    if (conversationKey && SessionGuard.isHandled(conversationKey)) {
      log.debug("conversation already handled (sessionStorage), skipping", { conversationKey });
      return;
    }

    // Data should already be cached from onLoad
    await state.ensureReady();

    if (!state.conversationId) {
      log.warn("cannot open modal - no conversation ID");
      return;
    }

    if (!this._isWorkstreamAllowed(state.workstreamId)) {
      log.debug("workstream not in ENABLED_WORKSTREAM_IDS, skipping", { workstreamId: state.workstreamId });
      return;
    }

    if (!state.dispositions || state.dispositions.length === 0) {
      log.debug("no disposition codes available for this conversation, skipping");
      return;
    }

    state.modalOpened = true;
    this._handledConversations.add(state.conversationId);
    SessionGuard.markHandled(state.conversationId);

    // Don't keep the in-memory guard forever
    const guardedId = state.conversationId;
    setTimeout(() => {
      this._handledConversations.delete(guardedId);
    }, CONFIG.HANDLED_GUARD_TTL_MS);

    log.debug("opening modal for conversation", { conversationId: state.conversationId });
    const outcome = await ModalService.open(state);

    // A failed open must not consume the single chance to prompt the agent.
    // Cancelling / closing the dialog is intentional and stays handled (see v2.1).
    if (outcome === "failed") {
      this._releaseGuards(state);
    }
  },

  _getLwiFromEvent(eventData) {
    try {
      const raw = eventData?.get?.("value");
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return parsed?.liveWorkItemId || null;
    } catch {
      return null;
    }
  }
};

// ===== MODAL SERVICE =====
const ModalService = {

  // Returns "closed" | "cancelled" | "failed"
  async open(formState) {
    const startTime = Date.now();

    const payload = {
      summary: "",  // Summary is fetched by the Cloud Flow (async)
      conversationId: formState.conversationId || "",
      workstreamId: formState.workstreamId || "",
      dispositions: formState.dispositions || [],
      version: CONFIG.VERSION
    };

    const pageInput = {
      pageType: "custom",
      name: CONFIG.MODAL_CUSTOM_PAGE,
      recordId: JSON.stringify(payload)
    };

    if (pageInput.recordId.length > CONFIG.MAX_PAYLOAD_CHARS) {
      log.warn("modal payload is very large - the custom page may fail to load", {
        chars: pageInput.recordId.length,
        dispositionCount: payload.dispositions.length
      });
    }

    const navOptions = {
      target: 2,      // Dialog
      width: 850,
      height: 750,
      position: 1     // Center
    };

    log.debug("opening modal", {
      conversationId: payload.conversationId,
      dispositionCount: payload.dispositions.length
    });

    try {
      // Resolves when the modal closes (Save, Cancel and the X all resolve)
      await Xrm.Navigation.navigateTo(pageInput, navOptions);
      log.perf("modal closed", startTime);
    } catch (e) {
      if (e?.message?.toLowerCase?.().includes("cancel") || e?.code === 1) {
        log.debug("modal cancelled by user");
        return "cancelled";
      }
      log.error("modal open failed", { error: e?.message });
      return "failed";
    }

    // The Custom Page saves via Power Fx Patch; refresh the form to show the new codes
    await this.refreshForm(formState.formContext);
    return "closed";
  },

  async refreshForm(formContext) {
    try {
      if (typeof formContext?.data?.refresh === "function") {
        await formContext.data.refresh(false);
        log.debug("form refreshed via formContext.data.refresh");
        return true;
      }
    } catch (e) {
      log.warn("formContext.data.refresh failed, trying Refresh button fallback", { error: e?.message });
    }
    return this._clickRefreshButton();
  },

  // Fallback only. Dynamics renders inside iframes, so look in parent/top too.
  _clickRefreshButton() {
    try {
      const selectors = [
        '[data-lp-id*="Refresh"]',
        '[aria-label="Refresh"]',
        'button[title="Refresh"]',
        '[data-id*="Refresh"]'
      ];

      const contexts = [];
      try { if (global.document) contexts.push(global.document); } catch {}
      try { if (global.parent?.document) contexts.push(global.parent.document); } catch {}
      try { if (global.top?.document) contexts.push(global.top.document); } catch {}

      for (const ctx of contexts) {
        for (const sel of selectors) {
          let button = null;
          try { button = ctx.querySelector(sel); } catch {}
          if (button) {
            button.click();
            log.debug("refresh button clicked (fallback)", { selector: sel });
            return true;
          }
        }
      }
      log.warn("refresh button not found in any context");
    } catch (e) {
      log.warn("refresh button click failed", { error: e?.message });
    }
    return false;
  }
};

// ===== MAIN ENTRY POINT =====
// Registered on the Active Conversation form (onLoad, passExecutionContext = true).
async function onLoad(executionContext) {
  const formContext = executionContext.getFormContext();
  const startTime = Date.now();

  try {
    global.top.__ccaasfdeCopilotVersion = CONFIG.VERSION;
  } catch {}

  log.debug("onLoad started", { version: CONFIG.VERSION });

  const state = getFormState(formContext);

  // Synchronous, fast
  CIFHandler.register(formContext);

  // Fire-and-forget: the form loads instantly while data fetches in parallel
  state.initialize().then(() => {
    log.perf("background init complete", startTime);
  }).catch(e => {
    log.error("background init failed", { error: e?.message });
  });

  log.perf("onLoad complete (sync)", startTime);
}

// ===== TESTING / DEBUG UTILITIES =====
// Run from the F12 console: __ccaasfdeCopilot.testOpenModal()
async function testOpenModal() {
  return ModalService.open({
    conversationId: "test-conversation-123",
    workstreamId: "test-workstream-456",
    dispositions: [
      { id: "d1", code: "BILL_INQUIRY", label: "Billing Inquiry" },
      { id: "d2", code: "TECH_SUPPORT", label: "Technical Support" },
      { id: "d3", code: "ACCOUNT_UPDATE", label: "Account Update" }
    ]
  });
}

function debugCache() {
  return {
    dispositions: Object.fromEntries(GlobalCache.dispositions),
    workstreams: Object.fromEntries(GlobalCache.workstreams),
    pendingRequests: GlobalCache.pendingRequests.size
  };
}

function clearCache() {
  GlobalCache.dispositions.clear();
  GlobalCache.workstreams.clear();
  GlobalCache.pendingRequests.clear();
  log.debug("cache cleared");
}

// Form event handler - must be a global function
global.onLoad = onLoad;

try {
  global.__ccaasfdeCopilot = {
    version: CONFIG.VERSION,
    cleanupTimer,
    dispose,
    debugCache,
    clearCache,
    testOpenModal,
    GlobalCache,
    DataService,
    SessionGuard,
    CIFHandler,
    ModalService
  };
} catch {}

})(typeof window !== "undefined" ? window : globalThis);
