#!/usr/bin/env bash
# Validates the `const CO = [...]` array embedded in index.html before committing.
#
# index.html has no build step and no type system — it's hand-edited JS
# inside a <script> tag — so this is the only safety net. Run it after any
# edit to CO and before `git commit`. Non-zero exit means don't commit yet.
#
# Usage: bash .claude/skills/pipeline-update/scripts/validate.sh [path-to-index.html]

set -euo pipefail
FILE="${1:-index.html}"
TMP_JS="$(mktemp -t co-check-XXXXXX.js)"
trap 'rm -f "$TMP_JS"' EXIT

node -e "
const fs = require('fs');
const html = fs.readFileSync('$FILE', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
if (!match) { console.error('Could not find a <script> block in $FILE'); process.exit(1); }
fs.writeFileSync('$TMP_JS', match[1]);
"

node --check "$TMP_JS"
echo "Syntax OK"

node -e "
const fs = require('fs');
const html = fs.readFileSync('$FILE', 'utf8');
const match = html.match(/const CO = (\[[\s\S]*?\n  \])/);
if (!match) { console.error('Could not find const CO = [...] in $FILE'); process.exit(1); }
const CO = eval(match[1]);
console.log('Total companies:', CO.length);

const ids = CO.map(c => c.id);
const dupeIds = [...new Set(ids.filter((id, i) => ids.indexOf(id) !== i))];
const aids = CO.map(c => c.aid);
const dupeAids = [...new Set(aids.filter((a, i) => aids.indexOf(a) !== i))];

let ok = true;
if (dupeIds.length) { console.error('Duplicate ids:', dupeIds); ok = false; }
if (dupeAids.length) { console.error('Duplicate aids:', dupeAids); ok = false; }

const tbd = CO.filter(c => (c.nrd || '').toUpperCase() === 'TBD' || c.q === 'tbd');
if (tbd.length) console.log('Still undated (q/nrd TBD) — fine if intentional:', tbd.map(c => c.name).join(', '));

if (!ok) process.exit(1);
console.log('Validation passed: no duplicate ids or aids.');
"
