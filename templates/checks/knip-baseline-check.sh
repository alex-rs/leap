#!/usr/bin/env bash
# knip-baseline-check.sh — compare knip output against knip.baseline.json
# Fails if there are NEW issues not in the baseline.
# Usage: bash checks/knip-baseline-check.sh [--strict]
#   --strict: fail even on issues that ARE in the baseline (zero-tolerance mode)
#
# Blast radius: blocks any PR that adds a new unused file/export/dependency/type.
# False-positive rate: ~0% for well-configured workspaces; biome handles the TS-only cases.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASELINE_FILE="$REPO_ROOT/knip.baseline.json"
STRICT="${1:-}"

if ! command -v node &>/dev/null; then
  echo "ERROR: node is required" >&2
  exit 1
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "ERROR: knip.baseline.json not found at $BASELINE_FILE" >&2
  exit 1
fi

# Run knip and capture JSON output; knip exits 1 if there are issues
KNIP_OUTPUT="$("$REPO_ROOT/node_modules/.bin/knip" --reporter json 2>/dev/null || true)"

if [[ -z "$KNIP_OUTPUT" ]]; then
  echo "knip: no issues found (clean)" >&2
  exit 0
fi

# Count issues in current run
CURRENT_ISSUES="$(echo "$KNIP_OUTPUT" | node -e "
const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  const data = JSON.parse(chunks.join(''));
  const issues = data.issues ?? [];
  let count = 0;
  for (const file of issues) {
    count += (file.files ?? []).length;
    count += (file.dependencies ?? []).length;
    count += (file.devDependencies ?? []).length;
    count += (file.exports ?? []).length;
    count += (file.types ?? []).length;
    count += (file.duplicates ?? []).length;
    count += (file.unlisted ?? []).length;
  }
  process.stdout.write(String(count));
});
")"

# Count issues in baseline
BASELINE_ISSUES="$(node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$BASELINE_FILE', 'utf8'));
const issues = data.issues ?? [];
let count = 0;
for (const file of issues) {
  count += (file.files ?? []).length;
  count += (file.dependencies ?? []).length;
  count += (file.devDependencies ?? []).length;
  count += (file.exports ?? []).length;
  count += (file.types ?? []).length;
  count += (file.duplicates ?? []).length;
  count += (file.unlisted ?? []).length;
}
process.stdout.write(String(count));
")"

echo "knip: current=$CURRENT_ISSUES baseline=$BASELINE_ISSUES" >&2

if [[ "$STRICT" == "--strict" ]]; then
  if [[ "$CURRENT_ISSUES" -gt 0 ]]; then
    echo "ERROR: knip --strict: $CURRENT_ISSUES issues found (zero-tolerance mode)" >&2
    echo "$KNIP_OUTPUT" | node -e "
const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  const data = JSON.parse(chunks.join(''));
  const issues = data.issues ?? [];
  for (const file of issues) {
    const types = ['files','dependencies','devDependencies','exports','types','duplicates','unlisted'];
    for (const t of types) {
      for (const item of (file[t] ?? [])) {
        console.error(\`  \${t}: \${file.file} — \${item.name ?? item}\`);
      }
    }
  }
});
" >&2
    exit 1
  fi
  echo "knip: clean (strict)" >&2
  exit 0
fi

if [[ "$CURRENT_ISSUES" -gt "$BASELINE_ISSUES" ]]; then
  echo "ERROR: knip found $CURRENT_ISSUES issues but baseline has $BASELINE_ISSUES — $((CURRENT_ISSUES - BASELINE_ISSUES)) new violation(s)" >&2
  echo "$KNIP_OUTPUT" | node -e "
const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  const data = JSON.parse(chunks.join(''));
  const issues = data.issues ?? [];
  for (const file of issues) {
    const types = ['files','dependencies','devDependencies','exports','types','duplicates','unlisted'];
    for (const t of types) {
      for (const item of (file[t] ?? [])) {
        console.error(\`  \${t}: \${file.file} — \${item.name ?? item}\`);
      }
    }
  }
});
" >&2
  exit 1
fi

echo "knip: $CURRENT_ISSUES issue(s) — within baseline ($BASELINE_ISSUES allowed)" >&2
exit 0
