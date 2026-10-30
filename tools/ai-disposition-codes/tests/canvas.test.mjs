import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { ROOT } from "../scripts/build.mjs";
import { lintPowerFx, msappEntry, readText, yamlFormulas } from "./helpers.mjs";

const screenYaml = readText(path.join(ROOT, "src", "canvas", "Screen1.pa.yaml"));
const formulas = yamlFormulas(screenYaml);
const onVisible = formulas.find((f) => f.name === "OnVisible").formula.replace(/^=/, "");
const save = formulas.find((f) => f.name === "OnSelect" && /Patch\(/.test(f.formula)).formula.replace(/^=/, "");

test("src/canvas mirrors the Src folder inside the .msapp", () => {
  for (const f of ["Screen1.pa.yaml", "App.pa.yaml"]) {
    const inApp = msappEntry(`Src/${f}`).toString("utf8");
    assert.equal(readText(path.join(ROOT, "src", "canvas", f)), inApp.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n"), f);
  }
});

test("the runtime formulas in Controls/4.json match the YAML source", () => {
  const json = JSON.parse(msappEntry("Controls/4.json").toString("utf8"));
  const rules = [];
  (function walk(o) {
    if (Array.isArray(o)) return o.forEach(walk);
    if (o && typeof o === "object") {
      if (o.Property && typeof o.InvariantScript === "string") rules.push(o);
      Object.values(o).forEach(walk);
    }
  })(json);
  const jsonVisible = rules.find((r) => r.Property === "OnVisible").InvariantScript;
  const jsonSave = rules.find((r) => r.Property === "OnSelect" && /Patch\(/.test(r.InvariantScript)).InvariantScript;
  assert.equal(jsonVisible.trimEnd(), onVisible.trimEnd());
  const norm = (t) => t.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).join("\n");
  assert.equal(norm(jsonSave), norm(save));
});

test("all YAML formulas are syntactically balanced", () => {
  assert.ok(formulas.length > 20);
  for (const f of formulas) lintPowerFx(f.formula, `${f.name} (line ${f.line})`);
});

test("test mode and mock data are gone from the shipped app", () => {
  assert.doesNotMatch(screenYaml, /varTestMode|TEST MODE|test-conv-12345|Port Number1/);
  const raw = msappEntry("Controls/4.json").toString("utf8");
  assert.doesNotMatch(raw, /varTestMode|TEST MODE|test-conv-12345/);
});

test("flow and parse failures degrade to the manual picker instead of breaking the screen", () => {
  assert.match(onVisible, /IfError\(\s*Set\(varFlowResponse, DispositionRecommender\.Run\(/);
  assert.match(onVisible, /flow_unavailable/);
  assert.match(onVisible, /IfError\(\s*Set\(varResult, ParseJSON\(varFlowResponse\.response\)\)/);
  assert.match(onVisible, /Clear\(colRecommendations\)/);
});

// Verified on a real environment: with Set(varFlowResponse, IfError(Flow.Run(...), ...)) the app never
// calls the flow and stays on the loading spinner. IfError(Set(...), Set(...)) works.
test("the flow is never called from inside an IfError expression passed to Set()", () => {
  assert.doesNotMatch(onVisible, /IfError\(\s*\w+\.Run\(/);
  assert.doesNotMatch(onVisible, /IfError\(\s*DispositionRecommender\.Run\(/);
});
test("recommendations are validated against the codes that were sent and labels come from our list", () => {
  assert.match(onVisible, /LookUp\(colDispositions, Lower\(dispositionId\) = Rec\.dispositionId\)/);
  assert.match(onVisible, /code: match\.code,\s*label: match\.label/);
  const recBlock = onVisible.slice(onVisible.indexOf("ClearCollect(colRecommendations"), onVisible.indexOf("Clear(colRecommendations)"));
  assert.ok(recBlock.length > 100);
  assert.doesNotMatch(recBlock, /Text\(ThisRecord\.Value\.(label|code)\)/);
});

// The Save formula is intentionally the original one. A rewritten version (With + IfError(ForAll(Patch))) could not
// be verified on a real environment and did not save, so it was not shipped.
test("save: unchanged original formula (verified behavior)", () => {
  assert.match(save, /ForAll\(\s*colSelectedCodes As SelectedCode,\s*Patch\(/);
  assert.match(save, /Notify\("Saved successfully",NotificationType\.Success\)/);
  assert.match(save, /Back\(\)/);
  assert.doesNotMatch(save, /varSaveFailed|IfError|Distinct\(/);
});
test("save button stays disabled while saving or when nothing is selected", () => {
  assert.match(screenYaml, /DisplayMode: =If\(IsEmpty\(colSelectedCodes\) \|\| varIsSaving, DisplayMode\.Disabled, DisplayMode\.Edit\)/);
});
test("picker suggestions exclude selected codes and narrow as the user types", () => {
  const sugg = formulas.find((f) => f.name === "Suggestions_Items").formula;
  assert.match(sugg, /Filter\(\s*colDispositions,/);
  assert.match(sugg, /Not\(label in colSelectedCodes\.label\)/);
  assert.match(sugg, /Len\(Self\.SearchTerm\) = 0 \|\| Self\.SearchTerm in label/);
  const json = msappEntry("Controls/4.json").toString("utf8");
  assert.match(json, /Self\.SearchTerm in label/);
});
test("when the AI has no recommendation a clickable code list is shown and it narrows with the picker search", () => {
  const items = formulas.find((f) => f.name === "Items" && /Picker1\.SearchTerm/.test(f.formula));
  assert.ok(items, "gallery Items formula");
  assert.match(items.formula, /Not\(label in colSelectedCodes\.label\)/);
  assert.match(items.formula, /Len\(Picker1\.SearchTerm\) = 0 \|\| Picker1\.SearchTerm in label/);
  assert.match(screenYaml, /OnSelect: =Collect\(colSelectedCodes, ThisItem\)/);
  assert.match(screenYaml, /Visible: =!varHasError && CountRows\(colRecommendations\) = 0/);
  const json = msappEntry("Controls/4.json").toString("utf8");
  assert.match(json, /"Name":\s*"galCodes"/);
  assert.match(json, /Collect\(colSelectedCodes, ThisItem\)/);
});

test("error paths stop the loading spinner so the error message can be shown", () => {
  const errors = onVisible.match(/Set\(varHasError, true\);/g) || [];
  assert.equal(errors.length, 2);
  assert.equal((onVisible.match(/Set\(varHasError, true\);\s*Set\(varIsLoading, false\);/g) || []).length, 2);
  // visibility depends only on the loading flag, not on whether a payload was passed
  assert.match(screenYaml, /Visible: =!Coalesce\(varIsLoading, true\)/);
  assert.match(screenYaml, /Visible: =Coalesce\(varIsLoading, true\)/);
  assert.doesNotMatch(screenYaml, /Visible: =.*IsBlank\(varPayload\)/);
  const json = msappEntry("Controls/4.json").toString("utf8");
  assert.doesNotMatch(json, /IsBlank\(varPayload\) \|\| varIsLoading/);
});
