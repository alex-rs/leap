#!/usr/bin/env bash
# pre-receive/waiver-schema.sh — waiver ledger schema validator.
#
# If the push modifies docs/waivers.yaml, validates that:
#   1. The file is valid YAML.
#   2. Every entry has the mandatory fields: id, kind, path, issue, reason,
#      approved_by, added, expires.
#   3. No expires date is more than 90 days after its added date.
#   4. No entry is already expired (today >= expires).
#   5. kind is one of the allowed values.
#   6. issue field matches ISSUE-### pattern.
#
# If docs/waivers.yaml was NOT changed in this push, exits 0.
#
# Requires: python3 + PyYAML. Fails open (warns + exits 0) if tooling is absent.
#
# Context passed by pre-receive dispatcher:
#   HOOK_COMMITS_FILE — one commit sha per line
#   HOOK_FILES_FILE   — one changed filename per line
#
# Exit 0 = valid or not modified. Exit 1 = schema violation (push blocked).

set -uo pipefail

GIT_BIN="${GIT_BIN:-git}"
WAIVERS_PATH="docs/waivers.yaml"

# Check if waivers.yaml was changed in this push.
WAIVERS_CHANGED=false
while IFS= read -r FILE; do
  if [[ "$FILE" == "$WAIVERS_PATH" ]]; then
    WAIVERS_CHANGED=true
    break
  fi
done < "${HOOK_FILES_FILE:-/dev/null}"

$WAIVERS_CHANGED || exit 0

# Locate the most recent commit that modified docs/waivers.yaml.
WAIVERS_SHA=""
while IFS= read -r SHA; do
  [[ -z "$SHA" ]] && continue
  if $GIT_BIN diff-tree --no-commit-id -r --name-only "$SHA" 2>/dev/null \
     | grep -qF "$WAIVERS_PATH"; then
    WAIVERS_SHA="$SHA"
  fi
done < "${HOOK_COMMITS_FILE:-/dev/null}"

if [[ -z "$WAIVERS_SHA" ]]; then
  echo "[waiver-schema] WARNING: cannot locate commit for ${WAIVERS_PATH}." >&2
  exit 0
fi

# Extract content from git object.
WAIVERS_CONTENT=$($GIT_BIN show "${WAIVERS_SHA}:${WAIVERS_PATH}" 2>/dev/null || true)

if [[ -z "$WAIVERS_CONTENT" ]]; then
  echo "[waiver-schema] ${WAIVERS_PATH} deleted or empty — waiver ledger must exist." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[waiver-schema] WARNING: python3 not available — validation skipped." >&2
  exit 0
fi

VALIDATE_SCRIPT=$(cat << 'PYEOF'
import sys
import os
import re
from datetime import date, timedelta

try:
    import yaml
except ImportError:
    print("WARNING: PyYAML not installed — skipping.", file=sys.stderr)
    sys.exit(0)

content = os.environ.get("WAIVERS_YAML_CONTENT", "")
if not content.strip():
    sys.exit(0)

try:
    entries = yaml.safe_load(content)
except yaml.YAMLError as e:
    print(f"[waiver-schema] Invalid YAML: {e}", file=sys.stderr)
    sys.exit(1)

if entries is None:
    sys.exit(0)

if not isinstance(entries, list):
    print("[waiver-schema] docs/waivers.yaml must be a YAML list.", file=sys.stderr)
    sys.exit(1)

REQUIRED = {"id", "kind", "path", "issue", "reason", "approved_by", "added", "expires"}
ALLOWED_KINDS = {
    "eslint-disable", "nolint", "knip-ignore", "ts-ignore",
    "flaky-test", "mutation-exception", "test-removal-approved"
}
MAX_DAYS = 90
TODAY = date.today()
errors = []

for i, entry in enumerate(entries):
    eid = entry.get("id", f"<entry #{i+1}>")
    missing = REQUIRED - set(entry.keys())
    if missing:
        errors.append(f"  {eid}: missing fields: {', '.join(sorted(missing))}")
        continue

    if entry["kind"] not in ALLOWED_KINDS:
        errors.append(f"  {eid}: invalid kind '{entry['kind']}'")

    issue = str(entry.get("issue", ""))
    if not re.match(r'^ISSUE-[0-9]+$', issue):
        errors.append(f"  {eid}: issue must match ISSUE-### (got '{issue}')")

    try:
        added = date.fromisoformat(str(entry["added"]))
        expires = date.fromisoformat(str(entry["expires"]))
    except (ValueError, TypeError) as e:
        errors.append(f"  {eid}: date parse error: {e}")
        continue

    if expires > added + timedelta(days=MAX_DAYS):
        errors.append(f"  {eid}: expires {expires} exceeds {MAX_DAYS}-day max from added {added}")

    if expires < TODAY:
        errors.append(f"  {eid}: expired {expires} — renew or remove before pushing")

if errors:
    print("[waiver-schema] Waiver ledger validation failed:", file=sys.stderr)
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
)

WAIVERS_YAML_CONTENT="$WAIVERS_CONTENT" python3 -c "$VALIDATE_SCRIPT"
PY_EXIT=$?

if [[ $PY_EXIT -ne 0 ]]; then
  echo "[waiver-schema] Push blocked. Fix docs/waivers.yaml violations above." >&2
  exit 1
fi

exit 0
