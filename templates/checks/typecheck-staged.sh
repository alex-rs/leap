#!/usr/bin/env bash
# checks/typecheck-staged.sh — scoped typecheck for staged TypeScript files
#
# Determines which pnpm workspace packages contain the staged files, then runs
# `tsc --noEmit` only for those packages via turbo --filter. This keeps the
# hook under the 10 s budget on typical single-package changes.
#
# Falls back to `pnpm typecheck` (full workspace) if no package boundary can
# be detected.
#
# Usage: typecheck-staged.sh [file ...]

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

if [[ $# -eq 0 ]]; then
  exit 0
fi

# Collect unique package names that own the staged files.
declare -A PACKAGES=()

for FILE in "$@"; do
  # Resolve relative to repo root.
  ABS_FILE="$REPO_ROOT/$FILE"
  [[ -f "$ABS_FILE" ]] || continue

  # Walk up the directory tree to find the nearest package.json with a "name".
  DIR="$(dirname "$ABS_FILE")"
  while [[ "$DIR" != "$REPO_ROOT" && "$DIR" != "/" ]]; do
    PKG_JSON="$DIR/package.json"
    if [[ -f "$PKG_JSON" ]]; then
      PKG_NAME=$(node -e "try{const p=require('$PKG_JSON');if(p.name)process.stdout.write(p.name)}catch(e){}" 2>/dev/null || true)
      if [[ -n "$PKG_NAME" ]]; then
        PACKAGES["$PKG_NAME"]=1
        break
      fi
    fi
    DIR="$(dirname "$DIR")"
  done
done

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  echo "[typecheck-staged] No package boundary found for staged files; running full typecheck."
  cd "$REPO_ROOT"
  pnpm typecheck
  exit $?
fi

# Build turbo --filter flags.
FILTER_ARGS=()
for PKG in "${!PACKAGES[@]}"; do
  FILTER_ARGS+=("--filter=$PKG")
done

echo "[typecheck-staged] Typechecking packages: ${!PACKAGES[*]}"
cd "$REPO_ROOT"
pnpm turbo typecheck "${FILTER_ARGS[@]}"
