#!/usr/bin/env bash
#
# verify-task-done.sh TASK-NNN
#
# Single source of truth for "is this task really done?". CTO shells out to this
# before flipping any task's status. Every check must pass or the task is blocked.
#
# Exit codes:
#   0  — all checks passed; task is verifiably done
#   1  — invocation error (bad args, missing files, missing tooling)
#   2  — one or more verification checks failed; details on stderr
#
# Reads task metadata from docs/backlog/TASK-NNN.md frontmatter.
# Requires: git, gh (GitHub CLI), yq, rg.

set -euo pipefail

TASK_ID="${1:-}"
if [[ -z "$TASK_ID" ]]; then
  echo "usage: $0 TASK-NNN" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
TASK_FILE="${REPO_ROOT}/docs/backlog/${TASK_ID}.md"

if [[ ! -f "$TASK_FILE" ]]; then
  echo "task file not found: $TASK_FILE" >&2
  exit 1
fi

for bin in yq rg gh git; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "missing required tool: $bin" >&2
    exit 1
  fi
done

frontmatter() {
  yq --front-matter=extract ".$1 // \"\"" "$TASK_FILE"
}

frontmatter_list() {
  yq --front-matter=extract ".$1[]? // empty" "$TASK_FILE"
}

COMMIT="$(frontmatter commit)"
PR="$(frontmatter pr)"
FILES_ALLOWLIST=()
while IFS= read -r line; do FILES_ALLOWLIST+=("$line"); done < <(frontmatter_list files_allowlist)
MUST_NOT_TOUCH=()
while IFS= read -r line; do MUST_NOT_TOUCH+=("$line"); done < <(frontmatter_list must_not_touch)

fail() {
  echo "FAIL [$TASK_ID]: $*" >&2
  FAILED=1
}

FAILED=0

# 1. Commit exists and references the task id.
if [[ -z "$COMMIT" ]]; then
  fail "commit field empty in frontmatter"
else
  if ! git cat-file -e "${COMMIT}^{commit}" 2>/dev/null; then
    fail "commit $COMMIT not found in git"
  elif ! git log -1 --format=%B "$COMMIT" | rg -q "$TASK_ID"; then
    fail "commit $COMMIT message does not reference $TASK_ID"
  fi
fi

# 2. PR is merged and ci-gatekeeper/approved is green.
if [[ -z "$PR" || "$PR" == "null" ]]; then
  fail "pr field empty in frontmatter"
else
  PR_STATE="$(gh pr view "$PR" --json state --jq .state 2>/dev/null || echo "")"
  if [[ "$PR_STATE" != "MERGED" ]]; then
    fail "pr #$PR state is '$PR_STATE', expected MERGED"
  fi
  APPROVED_CHECK="$(gh pr checks "$PR" --json name,state --jq '.[] | select(.name=="ci-gatekeeper/approved") | .state' 2>/dev/null || echo "")"
  if [[ "$APPROVED_CHECK" != "SUCCESS" ]]; then
    fail "ci-gatekeeper/approved check state is '$APPROVED_CHECK', expected SUCCESS"
  fi
fi

# 3. Every changed file is within files_allowlist.
# 4. No changed file is within must_not_touch.
if [[ -n "$COMMIT" ]] && git cat-file -e "${COMMIT}^{commit}" 2>/dev/null; then
  CHANGED_FILES="$(git diff-tree --no-commit-id --name-only -r "$COMMIT")"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    matched=0
    for glob in "${FILES_ALLOWLIST[@]}"; do
      case "$f" in
        $glob) matched=1; break ;;
      esac
    done
    if [[ $matched -eq 0 ]]; then
      fail "changed file '$f' is outside files_allowlist"
    fi
    for glob in "${MUST_NOT_TOUCH[@]}"; do
      case "$f" in
        $glob) fail "changed file '$f' hits must_not_touch ($glob)"; break ;;
      esac
    done
  done <<<"$CHANGED_FILES"
fi

# 5. Acceptance criteria that name a symbol/file must be greppable.
#    Heuristic: any backticked `token` inside an acceptance bullet is treated as a
#    symbol and must appear somewhere under apps/, packages/, or docs/.
while IFS= read -r criterion; do
  [[ -z "$criterion" ]] && continue
  while IFS= read -r symbol; do
    [[ -z "$symbol" ]] && continue
    if ! rg -q --fixed-strings "$symbol" "${REPO_ROOT}/apps" "${REPO_ROOT}/packages" "${REPO_ROOT}/docs" 2>/dev/null; then
      fail "acceptance criterion references '$symbol' but it is not present in apps/, packages/, or docs/"
    fi
  done < <(printf '%s\n' "$criterion" | rg -o '`[^`]+`' | sed 's/`//g')
done < <(frontmatter_list acceptance_criteria)

if [[ $FAILED -eq 0 ]]; then
  STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  yq --front-matter=process -i ".last_verified = \"$STAMP\"" "$TASK_FILE"
  echo "OK [$TASK_ID]: all checks passed; last_verified=$STAMP"
  exit 0
fi

exit 2
