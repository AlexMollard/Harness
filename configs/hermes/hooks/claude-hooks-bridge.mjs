// Hermes shell hook (pre_tool_call / post_tool_call) that runs the Claude Code hooks
// in configs/claude/hooks unchanged, so each rule has one implementation.
//
// Hermes sends {hook_event_name, tool_name, tool_input} with its own tool names
// (terminal, write_file, patch) and `path` rather than `file_path`. This maps that
// onto the Claude payload, runs the hooks, and maps their answers back:
//   pre:  billing gate deny -> {"decision":"block"}; rtk rewrite -> {"action":"modify"};
//         crlf-normalize pre marker for write_file
//   post: crlf-normalize for write_file
// Fails open like the Claude hooks (any error -> no output), except that the
// billing gate fails closed for workflow files, as it does under Claude Code.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const hooks = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../claude/hooks');
const toolMap = { terminal: 'Bash', write_file: 'Write', patch: 'Edit' };
const bash = [process.env.HERMES_GIT_BASH_PATH, 'C:/Program Files/Git/bin/bash.exe']
	.find(p => p && fs.existsSync(p)) ?? 'bash';

function run(cmd, args, payload) {
	const r = spawnSync(cmd, args, { input: JSON.stringify(payload), encoding: 'utf8', timeout: 8000 });
	try { return JSON.parse(r.stdout || 'null'); } catch { return null; }
}

// A V4A patch has no single path; gate each "*** Add/Update File:" section on its added lines.
function v4aFiles(text) {
	const files = [];
	for (const line of String(text).split('\n')) {
		const m = line.match(/^\*\*\* (?:Add|Update) File:\s*(.+?)\s*$/);
		if (m) files.push({ file_path: m[1], content: '' });
		else if (files.length && line.startsWith('+')) files.at(-1).content += line.slice(1) + '\n';
	}
	return files;
}

function denied(out) {
	const h = out?.hookSpecificOutput;
	return h?.permissionDecision === 'deny' ? h.permissionDecisionReason || 'Blocked by agent-core hook.' : null;
}

try {
	const hermes = JSON.parse(fs.readFileSync(0, 'utf8'));
	const tool = toolMap[hermes.tool_name];
	const ti = hermes.tool_input ?? {};
	if (!tool) process.exit(0);
	const pre = hermes.hook_event_name === 'pre_tool_call';
	const event = pre ? 'PreToolUse' : 'PostToolUse';
	// Hooks run inside Hermes' gateway process, which cannot see the session's
	// directory, so a relative path is unresolvable before the call. After it, only a
	// successful write reports resolved_path; a refused write must never be converted.
	let resolved;
	try { resolved = JSON.parse(hermes.extra?.result ?? '{}').resolved_path; } catch { }
	const given = ti.file_path ?? ti.path;
	const file = pre ? (given && path.isAbsolute(given) ? given : null) : resolved;
	const inputs = ti.mode === 'patch' && ti.patch ? v4aFiles(ti.patch) : [{ ...ti, file_path: file ?? given }];

	if (pre) {
		for (const input of inputs) {
			const reason = denied(run(bash, [path.join(hooks, 'github-billing-gate')], { tool_name: tool, tool_input: input }));
			if (reason) { process.stdout.write(JSON.stringify({ decision: 'block', reason })); process.exit(0); }
		}
	}
	// shortcut: a relative-path overwrite of an LF-only file skips the pre marker and
	// becomes CRLF; the adapter tells Hermes to pass absolute paths to write_file.
	if (tool === 'Write' && file) {
		run(process.execPath, [path.join(hooks, 'crlf-normalize.mjs')], { hook_event_name: event, tool_name: 'Write', tool_input: inputs[0] });
	}
	if (pre && tool === 'Bash') {
		const cmd = run('rtk', ['hook', 'claude'], { hook_event_name: event, tool_name: 'Bash', tool_input: ti })
			?.hookSpecificOutput?.updatedInput?.command;
		if (cmd && cmd !== ti.command) process.stdout.write(JSON.stringify({ action: 'modify', args: { ...ti, command: cmd } }));
	}
} catch {
	// fail open: a broken bridge must never block real work
}
