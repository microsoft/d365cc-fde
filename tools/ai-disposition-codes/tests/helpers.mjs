import fs from "node:fs";
import path from "node:path";
import { ROOT } from "../scripts/build.mjs";
import { readZip } from "../scripts/zip.mjs";

export const SOLUTION = path.join(ROOT, "solution");
export const MSAPP = path.join(SOLUTION, "CanvasApps", "ccaasfde_dispositionrecommendation_d051d_DocumentUri.msapp");
export const FLOW = path.join(SOLUTION, "Workflows", "DispositionRecommender-EA73F750-74DD-F011-8543-000D3A3007F4.json");

export const readText = (p) => fs.readFileSync(p, "utf8").replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");

export const msappEntry = (name) => {
  const e = readZip(fs.readFileSync(MSAPP)).find((x) => x.name.replace(/\\/g, "/") === name);
  if (!e) throw new Error(`${name} not found in msapp`);
  return e.data;
};

// Minimal XML well-formedness check (tag balance). Throws on the first problem.
export function assertWellFormedXml(xml, label) {
  const stack = [];
  const re = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<\/([^\s>]+)\s*>|<([^\s/>!?]+)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/g;
  let m;
  while ((m = re.exec(xml))) {
    if (m[1]) {
      const open = stack.pop();
      if (open !== m[1]) throw new Error(`${label}: </${m[1]}> does not match <${open}> near offset ${m.index}`);
    } else if (m[2] && m[4] !== "/") {
      stack.push(m[2]);
    }
  }
  if (stack.length) throw new Error(`${label}: unclosed <${stack.pop()}>`);
}

// Lightweight Power Fx lint: balanced (), [], {} and terminated strings, ignoring
// string literals and // or /* */ comments.
export function lintPowerFx(formula, label) {
  const pairs = { ")": "(", "]": "[", "}": "{" };
  const stack = [];
  for (let i = 0; i < formula.length; i++) {
    const c = formula[i];
    if (c === '"' || c === "'") {
      // "text" literal or 'quoted identifier'; a doubled quote is an escaped quote
      const q = c;
      i++;
      for (; i < formula.length; i++) {
        if (formula[i] === q) {
          if (formula[i + 1] === q) { i++; continue; }
          break;
        }
      }
      if (i >= formula.length) throw new Error(`${label}: unterminated ${q === '"' ? "string" : "quoted identifier"}`);
    } else if (c === "/" && formula[i + 1] === "/") {
      while (i < formula.length && formula[i] !== "\n") i++;
    } else if (c === "/" && formula[i + 1] === "*") {
      const end = formula.indexOf("*/", i + 2);
      if (end < 0) throw new Error(`${label}: unterminated comment`);
      i = end + 1;
    } else if ("([{".includes(c)) {
      stack.push(c);
    } else if (")]}".includes(c)) {
      if (stack.pop() !== pairs[c]) throw new Error(`${label}: unbalanced '${c}' at ${i}`);
    }
  }
  if (stack.length) throw new Error(`${label}: unclosed '${stack.pop()}'`);
}

// Extract formula properties from the Power Apps YAML (block scalars and "=..." values).
export function yamlFormulas(yaml) {
  const lines = yaml.split("\n");
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(\s*)(\w+): (.*)$/);
    if (!m) continue;
    const [, indent, name, rest] = m;
    if (rest === "|+" || rest === "|-" || rest === "|") {
      const bodyIndent = indent + "  ";
      const body = [];
      let j = i + 1;
      while (j < lines.length && (lines[j].startsWith(bodyIndent) || lines[j].trim() === "")) {
        body.push(lines[j].startsWith(bodyIndent) ? lines[j].slice(bodyIndent.length) : "");
        j++;
      }
      out.push({ name, line: i + 1, formula: body.join("\n") });
    } else if (rest.startsWith('"=')) {
      out.push({ name, line: i + 1, formula: JSON.parse(rest) });
    } else if (rest.startsWith("=")) {
      out.push({ name, line: i + 1, formula: rest });
    }
  }
  return out;
}
