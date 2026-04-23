#!/usr/bin/env bash
# pre-receive/test-deletion.sh — test-deletion detector.
#
# Blocks pushes where test files are deleted or have net line-count decrease
# without a corresponding docs/waivers.yaml entry (kind: test-removal-approved)
# OR a commit trailer `test-removal-approved:`.
#
# Test file patterns:
#   *.test.ts, *.test.tsx, *.test.js, *.test.jsx
#   *.spec.ts, *.spec.tsx, *.spec.js, *.spec.jsx
#   **/__tests__/**
#   *_test.go
#
# Context passed by pre-receive dispatcher:
#   HOOK_COMMITS_FILE  — one commit sha per line
#   HOOK_FILES_FILE    — one changed filename per line
#   GIT_DIR            — set by the git server to the bare repo path
#
# Exit 0 = clean. Exit 1 = violation (push blocked).

set -uo pipefail

EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

git_files_in_commit() {
  local sha="$1"
  if git cat-file -e "${sha}^" 2>/dev/null; then
    git diff-tree --no-commit-id -r --name-status "$sha" 2>/dev/null || true
  else
    git diff-tree --no-commit-id -r --name-status "${EMPTY_TREE}" "$sha" 2>/dev/null || true
  fi
}

git_numstat_in_commit() {
  local sha="$1"
  if git cat-file -e "${sha}^" 2>/dev/null; then
    git diff-tree --no-commit-id -r --numstat "$sha" 2>/dev/null || true
  else
    git diff-tree --no-commit-id -r --numstat "${EMPTY_TREE}" "$sha" 2>/dev/null || true
  fi
}

is_test_file() {
  local f="$1"
  case "$f" in
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx) return 0 ;;
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) return 0 ;;
    */__tests__/*)                              return 0 ;;
    *_test.go)                                  return 0 ;;
    *) return 1 ;;
  esac
}

COMMITS_FILE="${HOOK_COMMITS_FILE:-/dev/null}"
FILES_FILE="${HOOK_FILES_FILE:-/dev/null}"

TOTAL_ADDED=0
TOTAL_REMOVED=0
DELETED_TEST_FILES=()

while IFS= read -r SHA; do
  [[ -z "$SHA" ]] && continue

  # Check for deleted test files.
  # The test-removal-approved trailer must appear on the commit that
  # performs the deletion — a trailer on a different commit in the same
  # push is not sufficient.
  COMMIT_MSG_FOR_SHA=$(git log -1 --format='%B' "$SHA" 2>/dev/null || true)
  COMMIT_APPROVES_REMOVAL=false
  if printf '%s' "$COMMIT_MSG_FOR_SHA" | grep -qiE '^test-removal-approved:'; then
    COMMIT_APPROVES_REMOVAL=true
  fi

  while IFS=$'\t' read -r STATUS FILENAME; do
    [[ -z "$FILENAME" ]] && continue
    is_test_file "$FILENAME" || continue
    if [[ "$STATUS" == D ]]; then
      if ! $COMMIT_APPROVES_REMOVAL; then
        DELETED_TEST_FILES+=("${SHA:0:8}:${FILENAME}")
      fi
    fi
  done < <(git_files_in_commit "$SHA")

  # Count added/removed lines in test files.
  while IFS=$'\t' read -r ADDED REMOVED FILE; do
    [[ -z "$FILE" ]] && continue
    is_test_file "$FILE" || continue
    [[ "$ADDED" =~ ^[0-9]+$ ]]   && TOTAL_ADDED=$(( TOTAL_ADDED + ADDED ))
    [[ "$REMOVED" =~ ^[0-9]+$ ]] && TOTAL_REMOVED=$(( TOTAL_REMOVED + REMOVED ))
  done < <(git_numstat_in_commit "$SHA")
done < "$COMMITS_FILE"

FOUND=0

if [[ ${#DELETED_TEST_FILES[@]} -gt 0 ]]; then
  echo "[test-deletion] Test file(s) deleted without test-removal-approved trailer:" >&2
  for F in "${DELETED_TEST_FILES[@]}"; do
    echo "  deleted: $F" >&2
  done
  FOUND=1
fi

if [[ $TOTAL_REMOVED -gt $TOTAL_ADDED ]]; then
  NET=$(( TOTAL_REMOVED - TOTAL_ADDED ))
  echo "[test-deletion] Net test line reduction: ${NET} lines removed across test files." >&2
  echo "  Add 'test-removal-approved: <reason>' trailer + docs/waivers.yaml entry." >&2
  FOUND=1
fi

if [[ $FOUND -ne 0 ]]; then
  # Check if docs/waivers.yaml in the latest commit has a waiver AND was pushed.
  LATEST_SHA=""
  while IFS= read -r SHA; do
    [[ -n "$SHA" ]] && LATEST_SHA="$SHA"
  done < "$COMMITS_FILE"

  if [[ -n "$LATEST_SHA" ]]; then
    WAIVERS=$(git show "${LATEST_SHA}:docs/waivers.yaml" 2>/dev/null || true)
    if printf '%s' "$WAIVERS" | grep -qE '^[[:space:]]*kind:[[:space:]]*test-removal-approved'; then
      WAIVERS_IN_PUSH=false
      while IFS= read -r FILE; do
        if [[ "$FILE" == "docs/waivers.yaml" ]]; then
          WAIVERS_IN_PUSH=true
          break
        fi
      done < "$FILES_FILE"
      if $WAIVERS_IN_PUSH; then
        echo "[test-deletion] Waiver found in docs/waivers.yaml — allowing test removal." >&2
        exit 0
      fi
    fi
  fi

  echo "" >&2
  echo "[test-deletion] Push blocked." >&2
  echo "  Add 'test-removal-approved: <reason>' trailer AND a docs/waivers.yaml entry." >&2
  exit 1
fi

exit 0
