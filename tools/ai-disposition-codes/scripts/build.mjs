// Builds the solution from sources in src/ and packages the importable zip.
//
//   node scripts/build.mjs          sync src -> solution/ and write the zip
//   node scripts/build.mjs --check  verify solution/ and the zip are in sync (no writes)
//
// Canvas app formulas are NOT built here: the .msapp is edited in place (see README
// "Building"), and src/canvas/ is a readable reference verified by the tests.
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath, pathToFileURL } from "node:url";
import { readZip, writeZip } from "./zip.mjs";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const SOLUTION_DIR = path.join(ROOT, "solution");
const WEBRESOURCE_PREFIX = "ccaasfde_dispositioncodeformhandler";

const xmlUnescape = (s) =>
  s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&");
const xmlEscape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export function webResourcePath() {
  const dir = path.join(SOLUTION_DIR, "WebResources");
  const file = fs.readdirSync(dir).find((f) => f.startsWith(WEBRESOURCE_PREFIX));
  if (!file) throw new Error("web resource file not found in solution/WebResources");
  return path.join(dir, file);
}

export function solutionVersion() {
  const xml = fs.readFileSync(path.join(SOLUTION_DIR, "solution.xml"), "utf8");
  const m = xml.match(/<SolutionManifest>[\s\S]*?<Version>([\d.]+)<\/Version>/) || xml.match(/<Version>([\d.]+)<\/Version>/);
  if (!m) throw new Error("Version not found in solution.xml");
  return m[1];
}

export function zipFileName() {
  return `AIDispositionCode_${solutionVersion().replace(/\./g, "_")}.zip`;
}

export function readPromptSource() {
  return fs.readFileSync(path.join(ROOT, "src", "prompt", "disposition-classifier.prompt.txt"), "utf8").replace(/\r\n/g, "\n");
}

// Split the prompt template into AI Builder literal / inputVariable parts.
export function promptParts(template) {
  const parts = [];
  for (const piece of template.split(/(\{\{Summary\}\}|\{\{Codes\}\})/)) {
    if (piece === "{{Summary}}") parts.push({ type: "inputVariable", id: "Summary" });
    else if (piece === "{{Codes}}") parts.push({ type: "inputVariable", id: "Codes" });
    else if (piece !== "") parts.push({ type: "literal", text: piece });
  }
  return parts;
}

const CONFIG_RE = /(<msdyn_customconfiguration>)([\s\S]*?)(<\/msdyn_customconfiguration>)/;
const SPEC_RE = /(<msdyn_modelrundataspecification>)(H4s[A-Za-z0-9+/=]+)(<\/msdyn_modelrundataspecification>)/;

export const QUICK_TEST_CODES = JSON.stringify([
  { dispositionId: "a1", code: "BILL", label: "Billing Inquiry", categoryId: "c1" },
  { dispositionId: "b2", code: "PORT", label: "Port Number", categoryId: "c1" },
]);

export function buildCustomizations(xml, template = readPromptSource()) {
  const cfgMatch = xml.match(CONFIG_RE);
  if (!cfgMatch) throw new Error("msdyn_customconfiguration not found");
  const cfg = JSON.parse(xmlUnescape(cfgMatch[2]));

  cfg.prompt = promptParts(template);
  cfg.definitions.inputs = [
    { id: "Summary", text: "Summary", type: "text", quickTestValue: "Customer wants to move their phone number to another carrier." },
    { id: "Codes", text: "Codes", type: "text", quickTestValue: QUICK_TEST_CODES },
  ];
  cfg.definitions.output = {
    formats: ["json"],
    jsonSchema: {
      type: "object",
      properties: {
        recommendations: {
          type: "array",
          items: {
            type: "object",
            properties: { id: { type: "string" }, confidence: { type: "number" }, reason: { type: "string" } },
          },
        },
      },
    },
    jsonExamples: [{ recommendations: [{ id: "b2", confidence: 0.92, reason: "Customer wants to move their number" }] }],
  };

  let out = xml.replace(CONFIG_RE, (_, a, _b, c) => a + xmlEscape(JSON.stringify(cfg)) + c);

  const specMatch = out.match(SPEC_RE);
  if (!specMatch) throw new Error("msdyn_modelrundataspecification (gzip) not found");
  const spec = JSON.parse(zlib.gunzipSync(Buffer.from(specMatch[2], "base64")).toString("utf8"));
  spec.OutputRootEntity.Attributes.structuredOutput.Entity.Attributes = {
    recommendations: { Type: "Array", Entity: { DisplayName: "", Attributes: {} } },
  };
  const newSpec = zlib.gzipSync(Buffer.from(JSON.stringify(spec), "utf8"), { level: 9 }).toString("base64");
  out = out.replace(SPEC_RE, (_, a, _b, c) => a + newSpec + c);
  return out;
}

export function readPromptConfig(xml) {
  return JSON.parse(xmlUnescape(xml.match(CONFIG_RE)[2]));
}

function listFiles(dir, base = dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...listFiles(full, base));
    else out.push(path.relative(base, full).split(path.sep).join("/"));
  }
  return out;
}

const isText = (buf) => !buf.subarray(0, 8000).includes(0);
// Text entries are stored with LF so the zip is identical on Windows (autocrlf) and Linux.
const toLf = (buf) => (isText(buf) ? Buffer.from(buf.toString("latin1").replace(/\r\n/g, "\n"), "latin1") : buf);

export function solutionEntries() {
  const names = listFiles(SOLUTION_DIR).sort((a, b) => {
    if (a === "[Content_Types].xml") return -1;
    if (b === "[Content_Types].xml") return 1;
    return a.localeCompare(b);
  });
  return names.map((name) => ({ name, data: toLf(fs.readFileSync(path.join(SOLUTION_DIR, name))) }));
}

export function checkInSync() {
  const problems = [];

  const wrSrc = toLf(fs.readFileSync(path.join(ROOT, "src", "webresource", "dispositioncodeformhandler.js")));
  if (!wrSrc.equals(toLf(fs.readFileSync(webResourcePath())))) problems.push("web resource is out of sync with src/webresource");

  const cust = fs.readFileSync(path.join(SOLUTION_DIR, "customizations.xml"), "utf8");
  if (buildCustomizations(cust) !== cust) problems.push("customizations.xml prompt is out of sync with src/prompt");

  const zipPath = path.join(ROOT, zipFileName());
  if (!fs.existsSync(zipPath)) {
    problems.push(`${zipFileName()} is missing`);
  } else {
    const inZip = new Map(readZip(fs.readFileSync(zipPath)).map((e) => [e.name, e.data]));
    const expected = solutionEntries();
    for (const e of expected) {
      if (!inZip.has(e.name)) problems.push(`zip is missing ${e.name}`);
      else if (!inZip.get(e.name).equals(e.data)) problems.push(`zip content differs: ${e.name}`);
    }
    for (const n of inZip.keys()) if (!expected.some((e) => e.name === n)) problems.push(`zip has extra entry ${n}`);
  }
  return problems;
}

function build() {
  fs.copyFileSync(path.join(ROOT, "src", "webresource", "dispositioncodeformhandler.js"), webResourcePath());

  const custPath = path.join(SOLUTION_DIR, "customizations.xml");
  fs.writeFileSync(custPath, buildCustomizations(fs.readFileSync(custPath, "utf8")), "utf8");

  for (const f of fs.readdirSync(ROOT)) {
    if (/^AIDispositionCode_.*\.zip$/.test(f) && f !== zipFileName()) fs.unlinkSync(path.join(ROOT, f));
  }
  fs.writeFileSync(path.join(ROOT, zipFileName()), writeZip(solutionEntries()));
  console.log(`Built ${zipFileName()}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes("--check")) {
    const problems = checkInSync();
    if (problems.length) {
      console.error(problems.map((p) => `- ${p}`).join("\n"));
      process.exit(1);
    }
    console.log("solution/ and zip are in sync");
  } else {
    build();
  }
}
