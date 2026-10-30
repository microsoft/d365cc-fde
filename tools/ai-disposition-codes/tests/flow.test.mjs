import { test } from "node:test";
import assert from "node:assert/strict";
import { FLOW, readText } from "./helpers.mjs";

const flow = JSON.parse(readText(FLOW));
const def = flow.properties.definition;

// Flatten all actions with their container so runAfter can be checked per scope.
function collect(actions, container = "root", acc = []) {
  for (const [name, a] of Object.entries(actions || {})) {
    acc.push({ name, action: a, container, siblings: actions });
    collect(a.actions, name, acc);
    collect(a.else?.actions, name + "/else", acc);
  }
  return acc;
}
const all = collect(def.actions);
const byName = new Map(all.map((x) => [x.name, x]));

function strings(node, acc = []) {
  if (typeof node === "string") acc.push(node);
  else if (Array.isArray(node)) node.forEach((n) => strings(n, acc));
  else if (node && typeof node === "object") Object.values(node).forEach((n) => strings(n, acc));
  return acc;
}

test("action names are unique and operationMetadataIds are unique", () => {
  assert.equal(byName.size, all.length, "duplicate action names");
  const ids = [];
  const walk = (o) => {
    if (Array.isArray(o)) o.forEach(walk);
    else if (o && typeof o === "object") {
      if (o.operationMetadataId) ids.push(o.operationMetadataId);
      Object.values(o).forEach(walk);
    }
  };
  walk(def);
  assert.equal(new Set(ids).size, ids.length, "duplicate operationMetadataId");
});

test("every runAfter points at a sibling action", () => {
  for (const { name, action, siblings } of all) {
    for (const dep of Object.keys(action.runAfter || {})) {
      assert.ok(siblings[dep], `${name} runs after missing sibling ${dep}`);
    }
  }
});

test("every referenced action and variable exists", () => {
  const vars = new Set();
  for (const { action } of all) {
    if (action.type === "InitializeVariable") action.inputs.variables.forEach((v) => vars.add(v.name));
  }
  for (const s of strings(def.actions)) {
    for (const m of s.matchAll(/(?:outputs|body|actions)\('([^']+)'\)/g)) {
      assert.ok(byName.has(m[1]), `expression references unknown action '${m[1]}': ${s}`);
    }
    for (const m of s.matchAll(/variables\('([^']+)'\)/g)) {
      assert.ok(vars.has(m[1]), `expression references undeclared variable '${m[1]}'`);
    }
  }
});

test("expressions have balanced parentheses and quotes", () => {
  for (const s of strings(def.actions).filter((x) => x.startsWith("@"))) {
    let depth = 0, inStr = false;
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (c === "'") { if (inStr && s[i + 1] === "'") { i++; continue; } inStr = !inStr; }
      else if (!inStr && c === "(") depth++;
      else if (!inStr && c === ")") depth--;
      assert.ok(depth >= 0, `unbalanced ) in ${s}`);
    }
    assert.equal(depth, 0, `unbalanced ( in ${s}`);
    assert.equal(inStr, false, `unterminated string in ${s}`);
  }
});

test("a response is always returned: Respond runs after Catch for every outcome", () => {
  const respond = Object.entries(def.actions).filter(([, a]) => a.type === "Response");
  assert.equal(respond.length, 1);
  const [name, a] = respond[0];
  assert.equal(name, "Respond_to_PowerApp");
  assert.deepEqual(Object.keys(a.runAfter), ["Catch_failure"]);
  for (const s of ["Succeeded", "Skipped", "Failed", "TimedOut"]) assert.ok(a.runAfter.Catch_failure.includes(s), s);
  assert.equal(a.inputs.body.response, "@variables('result')");
});

test("Catch_failure handles Failed and TimedOut of the Try scope and the AI call is inside Try", () => {
  const catchRun = def.actions.Catch_failure.runAfter.Try_recommend;
  assert.ok(catchRun.includes("Failed") && catchRun.includes("TimedOut"));
  assert.equal(def.actions.Try_recommend.type, "Scope");
  const inTry = collect(def.actions.Try_recommend.actions).map((x) => x.name);
  for (const n of ["Run_a_prompt", "Parse_model_output", "Filter_valid_recommendations", "List_conversation_insights"]) {
    assert.ok(inTry.includes(n), `${n} should be inside Try_recommend`);
  }
});

test("model output is validated: ids must exist in the input codes and confidence is thresholded", () => {
  const f = byName.get("Filter_valid_recommendations").action.inputs;
  assert.match(f.where, /contains\(body\('Valid_ids'\)/);
  assert.match(f.where, /minConfidence/);
  const select = byName.get("Valid_ids").action.inputs;
  assert.match(select.select, /dispositionId/);
  const build = byName.get("Build_success_response").action.inputs;
  assert.match(build.recommendations, /take\(reverse\(sort\(/);
  assert.match(build.recommendations, /maxRecommendations/);
  assert.equal(build.success, true);
});

test("code fences and non-JSON output are handled before parsing", () => {
  const clean = byName.get("Clean_model_output").action.inputs;
  assert.match(clean, /```json/);
  assert.equal(byName.get("Parse_model_output").action.type, "ParseJson");
});

test("polling only stops on a non-empty summary and is bounded", () => {
  const until = byName.get("Do_until_summary_found").action;
  assert.match(until.expression, /not\(empty\(variables\('summaryText'\)\)\)/);
  assert.match(until.expression, /Config'\)\?\['pollMaxAttempts'\]/);
  assert.ok(["PT1M", "PT2M"].includes(until.limit.timeout), `timeout ${until.limit.timeout}`);
  const cond = JSON.stringify(byName.get("Check_if_summary_exists").action.expression);
  assert.match(cond, /msdyn_copilotsummary/);
  const list = byName.get("List_conversation_insights").action.inputs.parameters;
  assert.equal(list.$select, "msdyn_copilotsummary");
  assert.equal(list.$orderby, "createdon desc");
});

test("conversationId is validated before being concatenated into the OData filter", () => {
  const check = byName.get("Check_input_valid").action;
  const expr = JSON.stringify(check.expression);
  assert.match(expr, /length\(trim/);
  assert.match(expr, /contains/);
  const run = byName.get("Check_input_valid").action.actions;
  assert.ok(run.Do_until_summary_found, "polling must only happen in the valid-input branch");
  assert.ok(check.else.actions.Set_result_invalid_input);
});

test("thresholds are defined once in the Config action", () => {
  assert.deepEqual(def.actions.Config.inputs, { pollMaxAttempts: 15, minConfidence: 0.4, maxRecommendations: 3 });
});

test("every result path sets the result variable with the documented response shape", () => {
  for (const n of ["Build_success_response", "Build_no_summary_response", "Build_invalid_input_response", "Build_error_response"]) {
    const keys = Object.keys(byName.get(n).action.inputs).sort();
    assert.deepEqual(keys, ["error", "recommendations", "success", "summary"], n);
  }
  for (const n of ["Set_result_success", "Set_result_no_summary", "Set_result_invalid_input", "Set_result_error"]) {
    assert.equal(byName.get(n).action.inputs.name, "result", n);
  }
});

test("trigger contract is unchanged (the canvas app depends on it)", () => {
  const props = def.triggers.manual.inputs.schema.properties;
  assert.deepEqual(Object.keys(props), ["text", "text_1", "text_2"]);
  assert.deepEqual(props.text.title, "conversationId");
  assert.deepEqual(props.text_2.title, "dispositionCodes");
});

test("empty arrays use json('[]'): createArray() needs arguments in Power Automate", () => {
  for (const s of strings(def.actions)) assert.doesNotMatch(s, /createArray\(\s*\)/, s);
  assert.match(byName.get("Filter_valid_recommendations").action.inputs.from, /json\('\[\]'\)/);
});

test("confidence must be a number in [0, 1]", () => {
  const schema = byName.get("Parse_model_output").action.inputs.schema.properties.recommendations.items.properties;
  assert.deepEqual(schema.confidence.type, ["number", "null"]);
  const where = byName.get("Filter_valid_recommendations").action.inputs.where;
  assert.match(where, /greaterOrEquals\(.*minConfidence/);
  assert.match(where, /lessOrEquals\(.*,1\)\)$/);
});

test("the code list is parsed and validated before polling or the AI call", () => {
  const parse = byName.get("Parse_codes");
  assert.equal(parse.container, "Try_recommend");
  assert.equal(parse.action.type, "ParseJson");
  assert.equal(parse.action.inputs.schema.minItems, 1);
  assert.deepEqual(parse.action.inputs.schema.items.required, ["dispositionId"]);
  assert.deepEqual(Object.keys(byName.get("Check_input_valid").action.runAfter), ["Parse_codes"]);
  assert.equal(byName.get("Valid_ids").action.inputs.from, "@body('Parse_codes')");
  const inCheck = collect(byName.get("Check_input_valid").action.actions).map((x) => x.name);
  assert.ok(inCheck.includes("Do_until_summary_found") && inCheck.includes("Run_a_prompt"));
});

test("a malformed code list is reported as invalid input", () => {
  const err = byName.get("Build_error_response").action.inputs.error;
  assert.match(err, /actions\('Parse_codes'\)\?\['status'\],'Failed'/);
  assert.match(err, /Invalid input/);
});
