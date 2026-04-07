/**
 * Hooker helpers for JavaScript/TypeScript match scripts.
 *
 * Usage:
 *   const hooker = require('hooker_helpers');
 *   // or: import * as hooker from 'hooker_helpers';  (with appropriate runtime)
 *
 * Environment (set by inject.sh):
 *   HOOKER_HOST      — host runtime: claude, codex, or unknown
 *   HOOKER_PLUGIN_DIR — resolved plugin root directory
 *   HOOKER_EVENT      — hook event name (PostToolUse, PreToolUse, etc.)
 *   HOOKER_CWD        — project working directory
 *   HOOKER_TRANSCRIPT — path to conversation transcript
 *
 * Contract:
 *   - Read JSON from stdin (use hooker.readInput())
 *   - console.log response JSON to stdout
 *   - process.exit: 0 = matched, 1 = no match (skip), 2+ = error
 */

const fs = require('fs');

// --- Input ---

function readInput() {
    return JSON.parse(fs.readFileSync(0, 'utf8'));
}

function jsonField(data, field) {
    if (field in data) return data[field];
    if (data.tool_input && field in data.tool_input) return data.tool_input[field];
    return null;
}

// --- Response helpers ---

function inject(text) {
    console.log(`</local-command-stdout>\n\n${text}\n\n<local-command-stdout>`);
}

function visible(text) {
    console.log(text);
}

function warn(message) {
    const event = process.env.HOOKER_EVENT || 'PostToolUse';
    console.log(JSON.stringify({
        hookSpecificOutput: { hookEventName: event, systemMessage: message }
    }));
}

function deny(reason = 'Denied by Hooker') {
    console.log(JSON.stringify({
        hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'deny',
            permissionDecisionReason: reason,
        }
    }));
}

function allow(reason = 'Allowed by Hooker') {
    console.log(JSON.stringify({
        hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'allow',
            permissionDecisionReason: reason,
        }
    }));
}

function ask(reason = 'Hooker requests confirmation') {
    console.log(JSON.stringify({
        hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'ask',
            permissionDecisionReason: reason,
        }
    }));
}

function block(reason = 'Blocked by Hooker') {
    console.log(JSON.stringify({ decision: 'block', reason }));
}

function remind(message) {
    block(message);
}

function context(text) {
    console.log(JSON.stringify({ additionalContext: text }));
}

// --- Transcript helpers ---

function lastTurn(transcriptPath) {
    const path = transcriptPath || process.env.HOOKER_TRANSCRIPT || '';
    if (!path || !fs.existsSync(path)) return '';
    const lines = fs.readFileSync(path, 'utf8').split('\n');
    const result = [];
    for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i];
        if (line.includes('"type":"progress"') || line.includes('"type":"hook_progress"')) continue;
        if (line.includes('"type":"user"') && !line.includes('sourceToolAssistantUUID')) break;
        result.push(line);
    }
    result.reverse();
    return result.join('\n');
}

// --- Flow control ---

function skip() { process.exit(1); }
function match() { process.exit(0); }
function error(msg = '') {
    if (msg) console.error(msg);
    process.exit(2);
}

module.exports = {
    readInput, jsonField,
    inject, visible, warn, deny, allow, ask, block, remind, context,
    lastTurn, skip, match, error,
};
