import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { ROOT } from "../scripts/build.mjs";

const SOURCE = fs.readFileSync(path.join(ROOT, "src", "webresource", "dispositioncodeformhandler.js"), "utf8");
const CONV = "11111111-1111-1111-1111-111111111111";
const WS = "22222222-2222-2222-2222-222222222222";
const plain = (o) => JSON.parse(JSON.stringify(o));

const RAW_CODES = [
  { msdyn_ocdispositioncodeid: "a1", msdyn_name: "BILL", msdyn_dispositioncodevalue: "Billing Inquiry" },
  { msdyn_ocdispositioncodeid: "b2", msdyn_name: "CANCEL", msdyn_dispositioncodevalue: "Cancellation Request" },
];

class MemStorage {
  constructor() { this.m = new Map(); }
  getItem(k) { return this.m.has(k) ? this.m.get(k) : null; }
  setItem(k, v) { this.m.set(k, String(v)); }
  removeItem(k) { this.m.delete(k); }
}

// Loads the web resource in an isolated context with mocked Xrm / CIF.
function createEnv({ codes = RAW_CODES, navigate, source = SOURCE, refresh } = {}) {
  const handlers = {};
  const allCallbacks = [];
  const calls = { navigate: [], refresh: 0, retrieveMultiple: [] };
  const unref = (t) => { t?.unref?.(); return t; };

  const sandbox = {
    console: { log() {}, warn() {}, error() {} },
    setTimeout: (...a) => unref(setTimeout(...a)),
    setInterval: (...a) => unref(setInterval(...a)),
    clearInterval,
    sessionStorage: new MemStorage(),
    Microsoft: { CIFramework: {
      addHandler: (name, fn) => { handlers[name] = fn; allCallbacks.push(fn); return "handler-1"; },
      removeHandler: (name, fn) => { const i = allCallbacks.indexOf(fn); if (i >= 0) allCallbacks.splice(i, 1); },
    } },
    Xrm: {
      WebApi: {
        retrieveRecord: async () => ({ _msdyn_liveworkstreamid_value: WS }),
        retrieveMultipleRecords: async (entity, query) => {
          calls.retrieveMultiple.push(query);
          return { entities: codes };
        },
      },
      Navigation: {
        navigateTo: async (page, opts) => {
          calls.navigate.push({ page, opts });
          if (navigate) return navigate(calls.navigate.length);
        },
      },
    },
  };
  sandbox.window = sandbox;
  sandbox.addEventListener = () => {};
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);

  const formContext = {
    data: {
      entity: { getId: () => `{${CONV.toUpperCase()}}` },
      refresh: refresh ?? (async () => { calls.refresh++; }),
    },
  };
  const executionContext = { getFormContext: () => formContext };
  const endEvent = (id = CONV) => ({ get: () => JSON.stringify({ liveWorkItemId: id }) });

  return { sandbox, handlers, allCallbacks, calls, formContext, executionContext, endEvent };
}

async function loadForm(env) {
  await env.sandbox.onLoad(env.executionContext);
}

test("only onLoad and the debug object are exposed on window", () => {
  const env = createEnv();
  const globals = Object.keys(env.sandbox).filter((k) =>
    !["console", "setTimeout", "setInterval", "clearInterval", "sessionStorage", "Microsoft", "Xrm", "window", "addEventListener"].includes(k));
  assert.deepEqual(globals.sort(), ["__ccaasfdeCopilot", "onLoad"]);
});

test("onLoad registers the CIF end-conversation handler once", async () => {
  const env = createEnv();
  await loadForm(env);
  await loadForm(env);
  assert.equal(typeof env.handlers.EndConversationEvent, "function");
  assert.equal(Object.keys(env.handlers).length, 1);
});

test("end of conversation opens the modal once with workstream codes in the payload", async () => {
  const env = createEnv();
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());
  await env.handlers.EndConversationEvent(env.endEvent());

  assert.equal(env.calls.navigate.length, 1);
  const { page, opts } = env.calls.navigate[0];
  assert.equal(page.name, "ccaasfde_dispositionrecommendation_d051d");
  assert.equal(opts.target, 2);
  const payload = JSON.parse(page.recordId);
  assert.equal(payload.conversationId, CONV);
  assert.equal(payload.workstreamId, WS);
  assert.deepEqual(payload.dispositions.map((d) => d.id), ["a1", "b2"]);
  assert.deepEqual(Object.keys(payload.dispositions[0]).sort(), ["categoryId", "code", "id", "label", "source"]);
});

test("end event for a different conversation is ignored", async () => {
  const env = createEnv();
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent("99999999-9999-9999-9999-999999999999"));
  assert.equal(env.calls.navigate.length, 0);
});

test("form is refreshed via formContext.data.refresh after the modal closes", async () => {
  const env = createEnv();
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(env.calls.refresh, 1);
});

test("falls back to the Refresh button only when data.refresh throws", async () => {
  const env = createEnv({ refresh: async () => { throw new Error("boom"); } });
  let clicked = 0;
  env.sandbox.document = { querySelector: (sel) => (sel === 'button[title="Refresh"]' ? { click: () => clicked++ } : null) };
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(clicked, 1);
});

test("a failed modal open releases the guards so the next end event can retry", async () => {
  const env = createEnv({ navigate: (n) => { if (n === 1) throw new Error("page not found"); } });
  await loadForm(env);

  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(env.calls.navigate.length, 1);
  assert.equal(env.sandbox.sessionStorage.getItem(`ccaasfde_dispo_handled_${CONV}`), null);
  assert.equal(env.calls.refresh, 0);

  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(env.calls.navigate.length, 2);
  assert.ok(env.sandbox.sessionStorage.getItem(`ccaasfde_dispo_handled_${CONV}`));
});

test("a cancelled modal stays handled (no duplicate prompt on session close)", async () => {
  const env = createEnv({ navigate: () => { throw Object.assign(new Error("User cancelled"), { code: 1 }); } });
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());
  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(env.calls.navigate.length, 1);
  assert.ok(env.sandbox.sessionStorage.getItem(`ccaasfde_dispo_handled_${CONV}`));
});

test("sessionStorage guard survives a form reload (new FormContext) in the same session", async () => {
  const env = createEnv();
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());

  const reloaded = { data: { entity: { getId: () => CONV }, refresh: async () => {} } };
  await env.sandbox.onLoad({ getFormContext: () => reloaded });
  assert.equal(Object.keys(env.handlers).length, 1);
  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(env.calls.navigate.length, 1);
});

test("SessionGuard entries expire after the TTL", () => {
  const env = createEnv();
  const guard = env.sandbox.__ccaasfdeCopilot.SessionGuard;
  const key = `ccaasfde_dispo_handled_${CONV}`;
  env.sandbox.sessionStorage.setItem(key, String(Date.now() - 31 * 60 * 1000));
  assert.equal(guard.isHandled(CONV), false);
  assert.equal(env.sandbox.sessionStorage.getItem(key), null);

  guard.markHandled(CONV);
  assert.equal(guard.isHandled(CONV), true);
  guard.unmark(CONV);
  assert.equal(guard.isHandled(CONV), false);
});

test("modal is skipped when the workstream has no disposition codes", async () => {
  const env = createEnv({ codes: [] });
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(env.calls.navigate.length, 0);
  assert.equal(env.sandbox.sessionStorage.getItem(`ccaasfde_dispo_handled_${CONV}`), null);
});

test("kill switch (CONFIG.ENABLED=false) disables the modal", async () => {
  const source = SOURCE.replace("ENABLED: true,", "ENABLED: false,");
  assert.notEqual(source, SOURCE);
  const env = createEnv({ source });
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());
  assert.equal(env.calls.navigate.length, 0);
});

test("workstream allowlist skips workstreams that are not listed", async () => {
  const skip = SOURCE.replace("ENABLED_WORKSTREAM_IDS: [],", 'ENABLED_WORKSTREAM_IDS: ["33333333-3333-3333-3333-333333333333"],');
  assert.notEqual(skip, SOURCE);
  const a = createEnv({ source: skip });
  await loadForm(a);
  await a.handlers.EndConversationEvent(a.endEvent());
  assert.equal(a.calls.navigate.length, 0);

  const allow = SOURCE.replace("ENABLED_WORKSTREAM_IDS: [],", `ENABLED_WORKSTREAM_IDS: ["{${WS.toUpperCase()}}"],`);
  const b = createEnv({ source: allow });
  await loadForm(b);
  await b.handlers.EndConversationEvent(b.endEvent());
  assert.equal(b.calls.navigate.length, 1);
});

test("workstream-specific codes are fetched with a FetchXML intersect query, then cached", async () => {
  const env = createEnv();
  await loadForm(env);
  await env.sandbox.__ccaasfdeCopilot.DataService.getDispositions(WS);
  const fetchXmlCalls = env.calls.retrieveMultiple.filter((q) => q.includes("fetchXml"));
  assert.equal(fetchXmlCalls.length, 1);
  assert.match(decodeURIComponent(fetchXmlCalls[0]), /msdyn_ocdispositioncode_msdyn_liveworkstream/);
  assert.match(decodeURIComponent(fetchXmlCalls[0]), new RegExp(WS));
});

test("clearCache empties the caches", async () => {
  const env = createEnv();
  await loadForm(env);
  await env.handlers.EndConversationEvent(env.endEvent());
  const dbg = env.sandbox.__ccaasfdeCopilot;
  assert.ok(Object.keys(plain(dbg.debugCache().dispositions)).length > 0);
  dbg.clearCache();
  assert.equal(Object.keys(plain(dbg.debugCache().dispositions)).length, 0);
});

test("evaluating the script twice does not leak a second cleanup interval", () => {
  const env = createEnv();
  const first = env.sandbox.__ccaasfdeCopilot.cleanupTimer;
  vm.runInContext(SOURCE, env.sandbox);
  assert.notEqual(env.sandbox.__ccaasfdeCopilot.cleanupTimer, first);
});

test("re-evaluating the script retires the old CIF callback so one end event opens one modal", async () => {
  const env = createEnv();
  await loadForm(env);
  assert.equal(env.allCallbacks.length, 1);

  vm.runInContext(SOURCE, env.sandbox);
  await loadForm(env);
  assert.equal(env.allCallbacks.length, 1, "old callback unregistered");

  await Promise.all(env.allCallbacks.map((cb) => cb(env.endEvent())));
  assert.equal(env.calls.navigate.length, 1);
});

test("a retired copy ignores end events even if the host cannot remove the callback", async () => {
  const env = createEnv();
  await loadForm(env);
  const oldCallback = env.allCallbacks[0];
  delete env.sandbox.Microsoft.CIFramework.removeHandler;

  vm.runInContext(SOURCE, env.sandbox);
  await loadForm(env);
  await Promise.all([oldCallback, ...env.allCallbacks.filter((c) => c !== oldCallback)].map((cb) => cb(env.endEvent())));
  assert.equal(env.calls.navigate.length, 1);
});
