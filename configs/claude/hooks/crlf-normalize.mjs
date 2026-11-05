// PreToolUse + PostToolUse (Write): make Write land CRLF, like Alex's rule says.
//
// Edit already keeps a file's line endings, but Write always emits LF - even when
// overwriting a CRLF file. Agents knew that and worked around it with Python
// scripts. This hook makes the tools correct so they never need to.
//
// Pre: if the target exists and is LF-only, drop a marker so Post leaves it LF
//      (an overwrite should not flip every line).
// Post: convert the written file to CRLF unless it is a shell script, starts with
//       a shebang, is eol=lf in .gitattributes, or was marked LF above.
// Bytes round-trip as latin1, so a BOM or any UTF-8 passes through untouched.
// NEVER blocks and emits nothing; any failure is silent.

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

try {
	const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
	const file = payload.tool_input?.file_path;
	if (payload.tool_name === 'Write' && file) {
		const marker = path.join(os.tmpdir(), 'crlf-normalize', createHash('sha1').update(path.resolve(file).toLowerCase()).digest('hex'));
		if (payload.hook_event_name === 'PreToolUse') pre(file, marker);
		else if (payload.hook_event_name === 'PostToolUse') post(file, marker);
	}
} catch {}

function read(file) {
	try { return fs.readFileSync(file, 'latin1'); } catch { return null; }
}

function isLfOnly(text) {
	return text.includes('\n') && !text.includes('\r\n');
}

function pre(file, marker) {
	const text = read(file);
	if (text !== null && isLfOnly(text)) {
		fs.mkdirSync(path.dirname(marker), { recursive: true });
		fs.writeFileSync(marker, '');
	} else {
		fs.rmSync(marker, { force: true });
	}
}

function post(file, marker) {
	if (fs.existsSync(marker)) {
		fs.rmSync(marker, { force: true });
		return;
	}
	const text = read(file);
	if (text === null || !isLfOnly(text) || text.includes('\0')) return;
	if (/\.(sh|bash|zsh)$/i.test(file) || text.replace(/^\xEF\xBB\xBF/, '').startsWith('#!')) return;
	if (gitEol(file) === 'lf') return;
	fs.writeFileSync(file, text.replace(/\r?\n/g, '\r\n'), 'latin1');
}

function gitEol(file) {
	try {
		const out = execFileSync('git', ['check-attr', 'eol', '--', path.basename(file)], { cwd: path.dirname(path.resolve(file)), encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 3000 });
		return out.trim().split(': ').pop();
	} catch { return null; }
}
