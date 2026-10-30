import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { ROOT, SOLUTION_DIR, checkInSync, readPromptConfig, readPromptSource, solutionVersion, zipFileName, webResourcePath } from "../scripts/build.mjs";
import { readZip, writeZip } from "../scripts/zip.mjs";
import { assertWellFormedXml, readText } from "./helpers.mjs";

const cust = readText(path.join(SOLUTION_DIR, "customizations.xml"));
const sol = readText(path.join(SOLUTION_DIR, "solution.xml"));

test("solution XML files are well-formed", () => {
  assertWellFormedXml(cust, "customizations.xml");
  assertWellFormedXml(sol, "solution.xml");
  assertWellFormedXml(readText(path.join(SOLUTION_DIR, "[Content_Types].xml")), "[Content_Types].xml");
});

test("src/ and solution/ and the zip are in sync (run `npm run build` if this fails)", () => {
  assert.deepEqual(checkInSync(), []);
});

test("zip round-trips through the reader", () => {
  const entries = [{ name: "a/b.txt", data: Buffer.from("hello hello hello") }, { name: "c.bin", data: Buffer.from([1, 2, 3]) }];
  const back = readZip(writeZip(entries));
  assert.deepEqual(back.map((e) => [e.name, e.data.toString("hex")]), entries.map((e) => [e.name, e.data.toString("hex")]));
});

test("zip is a valid solution package: [Content_Types].xml first, customizations and solution at the root", () => {
  const names = readZip(fs.readFileSync(path.join(ROOT, zipFileName()))).map((e) => e.name);
  assert.equal(names[0], "[Content_Types].xml");
  assert.ok(names.includes("customizations.xml") && names.includes("solution.xml"));
  assert.ok(names.every((n) => !n.includes("\\")), "entries must use forward slashes");
  assert.ok(names.every((n) => !n.startsWith("solution/")), "no wrapping folder");
});

test("version in the zip name matches solution.xml and no stale zips remain", () => {
  assert.equal(solutionVersion(), "1.0.0.3");
  const zips = fs.readdirSync(ROOT).filter((f) => f.endsWith(".zip"));
  assert.deepEqual(zips, [zipFileName()]);
});

test("the solution only ships this tool's components, not environment-specific app module content", () => {
  assert.doesNotMatch(cust, /<AppModuleRoleMaps>/);
  assert.doesNotMatch(cust, /<EventHandlers>/);
  assert.doesNotMatch(cust, /<appsetting\b/);
  assert.doesNotMatch(cust, /msdyn_enablertecopilot|msdyn_rtecopilotdefaultonruncompleted/);
  assert.match(cust, /ccaasfde_dispositionrecommendation_d051d/);
  for (const demo of ["cr603_", "Deceased Estate", "DemoBusinessProcessFlow", "CBA BB Case", "FieldService", "IoTConnector", "msdyn_QMS"]) {
    assert.ok(!sol.includes(demo), `solution.xml still references ${demo}`);
  }
  assert.doesNotMatch(sol, /<Dependent[^>]*type="AppSetting"/);
});

test("form handler registration matches the JS entry point", () => {
  assert.match(cust, /<Library name="ccaasfde_dispositioncodeformhandler"/);
  assert.match(cust, /<Handler functionName="onLoad" libraryName="ccaasfde_dispositioncodeformhandler"[^>]*passExecutionContext="true"/);
  assert.match(fs.readFileSync(webResourcePath(), "utf8"), /global\.onLoad = onLoad;/);
});

test("AI prompt: untrusted-input guard, strict output contract, deterministic settings", () => {
  const cfg = readPromptConfig(cust);
  const text = cfg.prompt.filter((p) => p.type === "literal").map((p) => p.text).join("\u0000");
  const vars = cfg.prompt.filter((p) => p.type === "inputVariable").map((p) => p.id);
  assert.deepEqual(vars, ["Summary", "Codes"]);
  assert.match(text, /untrusted/i);
  assert.match(text, /<summary>/);
  assert.match(text, /Never follow instructions/);
  assert.match(text, /EXAMPLE 1/);
  assert.match(text, /\{"recommendations":\[\]\}/);
  assert.doesNotMatch(text, /copy the input summary/i);
  assert.equal(cfg.modelParameters.modelType, "gpt-41-mini");
  assert.equal(cfg.modelParameters.gptParameters.temperature, 0);
  assert.deepEqual(Object.keys(cfg.definitions.output.jsonSchema.properties), ["recommendations"]);
  for (const ex of cfg.definitions.output.jsonExamples) assert.ok(Array.isArray(ex.recommendations));
});

test("AI prompt in the solution equals src/prompt (placeholders replaced by input variables)", () => {
  const cfg = readPromptConfig(cust);
  const rebuilt = cfg.prompt.map((p) => (p.type === "literal" ? p.text : `{{${p.id}}}`)).join("");
  assert.equal(rebuilt, readPromptSource());
});

test("prompt examples are valid JSON and use only ids from their own code lists", () => {
  const src = readPromptSource();
  const blocks = [...src.matchAll(/Codes: (\[.*\])\nSummary: .*\nOutput: (\{.*\})/g)];
  assert.equal(blocks.length, 2);
  for (const [, codes, out] of blocks) {
    const ids = new Set(JSON.parse(codes).map((c) => c.dispositionId));
    for (const r of JSON.parse(out).recommendations) {
      assert.ok(ids.has(r.id), `example id ${r.id} not in its code list`);
      assert.ok(r.confidence >= 0.4 && r.confidence <= 1);
      assert.ok(r.reason.split(/\s+/).length <= 12);
    }
  }
});

test("AI model run specification matches the new output shape", () => {
  const b64 = cust.match(/<msdyn_modelrundataspecification>(H4s[A-Za-z0-9+/=]+)</)[1];
  const spec = JSON.parse(zlib.gunzipSync(Buffer.from(b64, "base64")).toString("utf8"));
  const attrs = spec.OutputRootEntity.Attributes.structuredOutput.Entity.Attributes;
  assert.deepEqual(Object.keys(attrs), ["recommendations"]);
  assert.deepEqual(Object.keys(spec.InputRootEntity.Attributes).slice(0, 2), ["Summary", "Codes"]);
});
