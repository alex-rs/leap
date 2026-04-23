#!/usr/bin/env bash
# pre-receive/gitleaks.sh — server-side secret scanning via gitleaks.
#
# Rejects pushes that introduce secrets (API keys, tokens, passwords, etc.)
# according to the gitleaks default ruleset. Scans all commits in the push.
#
# Requires: gitleaks >= 8.x on PATH. Fails closed (push rejected) if absent or
# below the minimum version. The git server container must have gitleaks installed.
#
# Context passed by pre-receive dispatcher:
#   HOOK_COMMITS_FILE — one commit sha per line
#   GIT_DIR           — set by the git server to the bare repo path
#
# Exit 0 = clean. Exit 1 = secrets found (push blocked).

set -uo pipefail

EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

# ------------------------------------------------------------------
# Locate gitleaks
# ------------------------------------------------------------------
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[gitleaks] ERROR: gitleaks not found on PATH — push rejected." >&2
  echo "[gitleaks] gitleaks >= 8.x must be installed on the git server." >&2
  exit 1
fi

GITLEAKS_VERSION=$(gitleaks version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0.0")
GITLEAKS_MAJOR=$(printf '%s' "$GITLEAKS_VERSION" | cut -d. -f1)
if [[ "$GITLEAKS_MAJOR" -lt 8 ]]; then
  echo "[gitleaks] ERROR: gitleaks ${GITLEAKS_VERSION} found; >= 8.x required — push rejected." >&2
  echo "[gitleaks] Upgrade gitleaks to >= 8.x." >&2
  exit 1
fi

# ------------------------------------------------------------------
# Scan each commit
# ------------------------------------------------------------------
FOUND=0
REPORT_FILE=$(mktemp)
trap 'rm -f "$REPORT_FILE"' EXIT

while IFS= read -r SHA; do
  [[ -z "$SHA" ]] && continue

  # Determine the parent for the log range.
  if git cat-file -e "${SHA}^" 2>/dev/null; then
    RANGE="${SHA}^..${SHA}"
  else
    RANGE="${EMPTY_TREE}..${SHA}"
  fi

  if ! gitleaks detect \
      --source="." \
      --log-opts="$RANGE" \
      --report-format=json \
      --report-path="$REPORT_FILE" \
      --no-banner \
      --exit-code=1 \
      2>/dev/null; then
    FOUND=1
    echo "[gitleaks] Secret detected in commit ${SHA:0:8}:" >&2
    if command -v jq >/dev/null 2>&1 && [[ -s "$REPORT_FILE" ]]; then
      jq -r '.[] | "  Rule: \(.RuleID) | File: \(.File):\(.StartLine) | Match: \(.Secret[0:20])..."' \
        "$REPORT_FILE" 2>/dev/null >&2 || true
    fi
  fi
done < "${HOOK_COMMITS_FILE:-/dev/null}"

if [[ $FOUND -ne 0 ]]; then
  echo "" >&2
  echo "[gitleaks] Push blocked: secrets detected. Remove secrets from all commits." >&2
  echo "[gitleaks] If this is a false positive, contact the security reviewer." >&2
  exit 1
fi

exit 0
