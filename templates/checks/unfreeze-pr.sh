#!/usr/bin/env bash
# checks/unfreeze-pr.sh — validate and process ci-gatekeeper:unfreeze comments.
#
# Called by ci-gatekeeper when it detects a `ci-gatekeeper:unfreeze <hash>` comment
# on a frozen PR. Validates that the comment was posted by a human (not an agent
# service account) before clearing the circuit-breaker state.
#
# Recognized human accounts: any GitHub user NOT in the AGENT_ACCOUNTS list.
# Agent accounts that can NEVER post a valid unfreeze: ci-gatekeeper, bot accounts.
# devex-engineer IS allowed to unfreeze (it's a human-controlled role).
#
# Usage:
#   unfreeze-pr.sh <pr_number> <comment_id> <sig_hash>
#
# Env vars:
#   GH_TOKEN            — ci-gatekeeper token (for reading comment details)
#   GH_REPO             — repository in owner/name format (default: $GITHUB_REPOSITORY)
#   CIRCUIT_BREAKER_DIR — state dir (passed through to circuit-breaker.sh)
#   AGENT_ACCOUNTS      — space-separated list of blocked service account logins
#                         (default: "ci-gatekeeper opencode-bot")
#
# Exit codes:
#   0 — unfreeze accepted and circuit-breaker state cleared
#   1 — invocation error
#   2 — unfreeze rejected (non-human author or invalid hash)
#   3 — PR was not frozen; nothing to do

set -euo pipefail

GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
GH_TOKEN="${GH_TOKEN:-}"
AGENT_ACCOUNTS="${AGENT_ACCOUNTS:-ci-gatekeeper opencode-bot}"

PR_NUMBER="${1:-}"
COMMENT_ID="${2:-}"
SIG_HASH="${3:-}"

if [[ -z "${PR_NUMBER}" || -z "${COMMENT_ID}" || -z "${SIG_HASH}" ]]; then
  echo "usage: $0 <pr_number> <comment_id> <sig_hash>" >&2
  exit 1
fi

if [[ -z "${GH_TOKEN}" ]]; then
  echo "ERROR: GH_TOKEN is not set" >&2
  exit 1
fi

if [[ -z "${GH_REPO}" ]]; then
  echo "ERROR: GH_REPO is not set. Set GH_REPO=owner/repo or GITHUB_REPOSITORY." >&2
  exit 1
fi

# Fetch the comment to get its author
COMMENT_JSON="$(curl -sf \
  -H "Authorization: token ${GH_TOKEN}" \
  "https://api.github.com/repos/${GH_REPO}/issues/comments/${COMMENT_ID}" 2>/dev/null)"

if [[ -z "${COMMENT_JSON}" ]]; then
  echo "ERROR: could not fetch comment #${COMMENT_ID} from PR #${PR_NUMBER}" >&2
  exit 1
fi

AUTHOR="$(printf '%s' "${COMMENT_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('user',{}).get('login',''))" 2>/dev/null)"
COMMENT_BODY="$(printf '%s' "${COMMENT_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('body',''))" 2>/dev/null)"

if [[ -z "${AUTHOR}" ]]; then
  echo "ERROR: could not determine comment author" >&2
  exit 1
fi

# Block agent service accounts from posting valid unfreeze comments
for acct in ${AGENT_ACCOUNTS}; do
  if [[ "${AUTHOR}" == "${acct}" ]]; then
    echo "REJECT: unfreeze comment from agent account '${AUTHOR}' is not valid — only humans or devex-engineer may unfreeze" >&2
    exit 2
  fi
done

# Verify the comment body contains the correct hash
if ! printf '%s' "${COMMENT_BODY}" | grep -qF "ci-gatekeeper:unfreeze ${SIG_HASH}"; then
  echo "REJECT: comment body does not contain 'ci-gatekeeper:unfreeze ${SIG_HASH}'" >&2
  exit 2
fi

echo "[unfreeze-pr] Unfreeze authorized by '${AUTHOR}' for sig_hash=${SIG_HASH} on PR #${PR_NUMBER}"

STATE_DIR="${CIRCUIT_BREAKER_DIR:-/tmp/%%PROJECT_NAME%%-circuit-breaker}"
STATE_FILE="${STATE_DIR}/pr${PR_NUMBER}-${SIG_HASH}.state"

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "[unfreeze-pr] No frozen state found for PR #${PR_NUMBER} hash=${SIG_HASH} — nothing to do" >&2
  exit 3
fi

rm -f "${STATE_FILE}"
echo "[unfreeze-pr] State file cleared. PR #${PR_NUMBER} (hash=${SIG_HASH}) is unfrozen. Fresh attempt budget on next push."
exit 0
