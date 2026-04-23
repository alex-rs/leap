#!/usr/bin/env bash
# checks/waiver-expiry-check.sh — CI-side waiver expiry enforcer.
#
# Runs on every PR (not only when waivers.yaml changes) so that waivers
# which expire between pushes are caught before merge.
#
# This is the CI counterpart to pre-receive/waiver-schema.sh, which
# validates the schema and expiry only when docs/waivers.yaml is modified.
# Together they provide defense-in-depth:
#   - pre-receive: blocks malformed or immediately-expired waivers at push time.
#   - waiver-expiry-check.sh (this file): blocks any PR while ANY waiver is expired,
#     even if waivers.yaml was not changed in the PR itself.
#
# Requires: python3 + PyYAML.
# Exits 0 if all waivers are valid and unexpired.
# Exits 1 if any waiver is expired or the file is malformed.
# Exits 0 with a warning if python3/PyYAML is unavailable (fails open).
#
# Usage (from CI workflow):
#   bash checks/waiver-expiry-check.sh
#
# Usage (manual):
#   bash checks/waiver-expiry-check.sh [path/to/waivers.yaml]

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WAIVERS_FILE="${1:-${REPO_ROOT}/docs/waivers.yaml}"

if [[ ! -f "$WAIVERS_FILE" ]]; then
  echo "[waiver-expiry] ERROR: ${WAIVERS_FILE} does not exist." >&2
  echo "[waiver-expiry] The waiver ledger is mandatory. Create docs/waivers.yaml." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[waiver-expiry] WARNING: python3 not available — expiry check skipped." >&2
  exit 0
fi

python3 - "$WAIVERS_FILE" << 'PYEOF'
import sys
import re
from datetime import date

try:
    import yaml
except ImportError:
    print("WARNING: PyYAML not installed — waiver expiry check skipped.", file=sys.stderr)
    sys.exit(0)

waivers_path = sys.argv[1]

try:
    with open(waivers_path, "r") as f:
        content = f.read()
except OSError as e:
    print(f"[waiver-expiry] Cannot read {waivers_path}: {e}", file=sys.stderr)
    sys.exit(1)

if not content.strip():
    print("[waiver-expiry] docs/waivers.yaml is empty — no waivers to check.", file=sys.stderr)
    sys.exit(0)

try:
    entries = yaml.safe_load(content)
except yaml.YAMLError as e:
    print(f"[waiver-expiry] Invalid YAML in {waivers_path}: {e}", file=sys.stderr)
    sys.exit(1)

if entries is None:
    print("[waiver-expiry] No entries found — OK.", file=sys.stderr)
    sys.exit(0)

if not isinstance(entries, list):
    print("[waiver-expiry] docs/waivers.yaml must be a YAML list.", file=sys.stderr)
    sys.exit(1)

REQUIRED = {"id", "kind", "path", "issue", "reason", "approved_by", "added", "expires"}
ALLOWED_KINDS = {
    "eslint-disable", "nolint", "knip-ignore", "ts-ignore",
    "flaky-test", "mutation-exception", "test-removal-approved"
}
MAX_DAYS = 90
FLAKY_TEST_DEFAULT_DAYS = 14
TODAY = date.today()
errors = []
warnings = []

for i, entry in enumerate(entries):
    eid = entry.get("id", f"<entry #{i+1}>")
    missing = REQUIRED - set(entry.keys())
    if missing:
        errors.append(f"  {eid}: missing required fields: {', '.join(sorted(missing))}")
        continue

    if entry["kind"] not in ALLOWED_KINDS:
        errors.append(f"  {eid}: invalid kind '{entry['kind']}' — allowed: {sorted(ALLOWED_KINDS)}")

    issue = str(entry.get("issue", ""))
    if not re.match(r'^ISSUE-[0-9]+$', issue):
        errors.append(f"  {eid}: issue must match ISSUE-[0-9]+ (got '{issue}')")

    try:
        added = date.fromisoformat(str(entry["added"]))
        expires = date.fromisoformat(str(entry["expires"]))
    except (ValueError, TypeError) as e:
        errors.append(f"  {eid}: date parse error: {e}")
        continue

    max_days = MAX_DAYS
    if entry.get("kind") == "flaky-test":
        max_days = FLAKY_TEST_DEFAULT_DAYS

    from datetime import timedelta
    if expires > added + timedelta(days=max_days):
        errors.append(
            f"  {eid}: expires {expires} exceeds {max_days}-day maximum from added={added} "
            f"(kind={entry['kind']})"
        )

    if expires <= TODAY:
        errors.append(
            f"  {eid}: EXPIRED on {expires} — remove this entry or renew it "
            f"(renewals are new entries referencing old id in reason)"
        )
    elif (expires - TODAY).days <= 14:
        warnings.append(
            f"  {eid}: expires in {(expires - TODAY).days} day(s) on {expires} — "
            f"plan renewal soon"
        )

if warnings:
    print("[waiver-expiry] Waiver expiry warnings (not blocking):", file=sys.stderr)
    for w in warnings:
        print(w, file=sys.stderr)

if errors:
    print("[waiver-expiry] Waiver ledger violations (blocking):", file=sys.stderr)
    for e in errors:
        print(e, file=sys.stderr)
    print("", file=sys.stderr)
    print("[waiver-expiry] Fix: remove expired entries, or renew them (new entry referencing old id).", file=sys.stderr)
    sys.exit(1)

total = len(entries)
print(f"[waiver-expiry] OK — {total} waiver(s) checked, all unexpired.", file=sys.stderr)
sys.exit(0)
PYEOF
