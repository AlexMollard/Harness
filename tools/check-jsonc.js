// Validate a .jsonc file parses, and that every `instructions` path exists.
// Usage: node tools/check-jsonc.js <path>
const fs = require('fs');
const file = process.argv[2];
const s = fs.readFileSync(file, 'utf8');

let out = '', inStr = false, esc = false;
for (let i = 0; i < s.length; i++) {
  const c = s[i], n = s[i + 1];
  if (inStr) {
    out += c;
    if (esc) esc = false;
    else if (c === '\\') esc = true;
    else if (c === '"') inStr = false;
    continue;
  }
  if (c === '"') { inStr = true; out += c; continue; }
  if (c === '/' && n === '/') { while (i < s.length && s[i] !== '\n') i++; out += '\n'; continue; }
  if (c === '/' && n === '*') { i += 2; while (i < s.length && !(s[i] === '*' && s[i + 1] === '/')) i++; i++; continue; }
  out += c;
}
// trailing commas are legal in jsonc, not in JSON
out = out.replace(/,(\s*[}\]])/g, '$1');

let j;
try {
  j = JSON.parse(out);
} catch (e) {
  console.error('INVALID JSON:', e.message);
  process.exit(1);
}

console.log('VALID. top-level keys:', Object.keys(j).join(', '));
if (!j.instructions) { console.error('no instructions array!'); process.exit(1); }
let bad = 0;
for (const p of j.instructions) {
  const ok = fs.existsSync(p);
  if (!ok) bad++;
  console.log(' ', ok ? 'exists ' : 'MISSING', p);
}
process.exit(bad ? 1 : 0);
