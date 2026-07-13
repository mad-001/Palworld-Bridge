// Generates src/embedded-mod.ts from the TakaroChat/ folder so the mod ships
// inside the bundled JS (and therefore inside PalworldBridge.exe) reliably,
// without depending on pkg's snapshot filesystem. Runs automatically before
// every `npm run build` (via the "prebuild" script).
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'TakaroChat');
const out = {};

function walk(dir, prefix) {
  for (const entry of fs.readdirSync(dir)) {
    const full = path.join(dir, entry);
    const rel = prefix ? prefix + '/' + entry : entry; // forward slashes as keys
    if (fs.statSync(full).isDirectory()) walk(full, rel);
    else out[rel] = fs.readFileSync(full, 'utf-8');
  }
}

walk(root, '');

const content =
  '// AUTO-GENERATED from TakaroChat/ by scripts/generate-embedded-mod.js. Do not edit.\n' +
  'export const EMBEDDED_MOD: Record<string, string> = ' + JSON.stringify(out) + ';\n';

fs.writeFileSync(path.join(__dirname, '..', 'src', 'embedded-mod.ts'), content);
console.log('Embedded ' + Object.keys(out).length + ' TakaroChat files into src/embedded-mod.ts');
