// Generates src/embedded-items.ts from data/palworld-items.json so the Palworld
// item catalog ships inside the bundled JS (and therefore inside
// PalworldBridge.exe) reliably, without depending on pkg's snapshot filesystem.
// Mirrors scripts/generate-embedded-mod.js. Runs automatically before every
// `npm run build` (via the "prebuild" script).
//
// Regenerate data/palworld-items.json after every Palworld game patch: internal
// item ids change. Source + method are documented in
// context/games/palworld/research/palworld-items.SOURCES.md (gamingconnectors).
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', 'data', 'palworld-items.json');
const items = JSON.parse(fs.readFileSync(src, 'utf-8'));

if (!Array.isArray(items) || items.length === 0) {
  throw new Error('data/palworld-items.json is not a non-empty array');
}
const seen = new Set();
for (const item of items) {
  if (!item || typeof item.code !== 'string' || !item.code) {
    throw new Error('item without a string "code": ' + JSON.stringify(item));
  }
  if (typeof item.name !== 'string' || !item.name) {
    throw new Error('item without a string "name": ' + item.code);
  }
  if (seen.has(item.code)) throw new Error('duplicate item code: ' + item.code);
  seen.add(item.code);
}
items.sort((a, b) => (a.code < b.code ? -1 : a.code > b.code ? 1 : 0));

const content =
  '// AUTO-GENERATED from data/palworld-items.json by scripts/generate-embedded-items.js. Do not edit.\n' +
  'export interface PalworldItem { code: string; name: string; description?: string }\n' +
  'export const items: PalworldItem[] = ' + JSON.stringify(items) + ';\n' +
  'export const itemCodes: Set<string> = new Set(items.map((i) => i.code));\n' +
  'export default items;\n';

fs.writeFileSync(path.join(__dirname, '..', 'src', 'embedded-items.ts'), content);
console.log('Embedded ' + items.length + ' Palworld items into src/embedded-items.ts');
