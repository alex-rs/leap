#!/usr/bin/env bash
# lib/init.sh — leap init command implementation
# Sourced by bin/leap after lib/utils.sh is loaded.

source "${LEAP_HOME}/lib/config.sh"

leap_init() {
  local TMPL="${LEAP_HOME}/templates"

  # ── 1. Interview ─────────────────────────────────────────────────────────────

  info "Initializing leap governance skeleton..."
  echo ""

  # Read existing config as defaults (incremental re-run support).
  local existing_name
  existing_name="$(config_get PROJECT_NAME 2>/dev/null || basename "$(pwd)")"
  [[ -z "$existing_name" ]] && existing_name="$(basename "$(pwd)")"

  local existing_desc
  existing_desc="$(config_get PROJECT_DESCRIPTION 2>/dev/null || true)"

  local auto_remote
  auto_remote="$(git remote get-url origin 2>/dev/null || true)"
  local existing_remote
  existing_remote="$(config_get GIT_REMOTE 2>/dev/null || true)"
  [[ -z "$existing_remote" ]] && existing_remote="$auto_remote"


  local existing_opencode
  existing_opencode="$(config_get HAS_OPENCODE 2>/dev/null || true)"

  local existing_cto_bot
  existing_cto_bot="$(config_get CTO_BOT_USERNAME 2>/dev/null || true)"
  [[ -z "$existing_cto_bot" ]] && existing_cto_bot="cto-bot"

  local existing_opencode_bot
  existing_opencode_bot="$(config_get OPENCODE_BOT_USERNAME 2>/dev/null || true)"
  [[ -z "$existing_opencode_bot" ]] && existing_opencode_bot="opencode-bot"

  local existing_admin
  existing_admin="$(config_get ADMIN_USERNAME 2>/dev/null || true)"

  local existing_protected
  existing_protected="$(config_get PROTECTED_PATHS 2>/dev/null || true)"
  [[ -z "$existing_protected" ]] && existing_protected=".claude/agents/**,CLAUDE.md,ops/checks/**,ops/pre-receive/**,docs/waivers.yaml,coverage/baseline.json,.github/workflows/**"

  local existing_forbidden
  existing_forbidden="$(config_get FORBIDDEN_TOKENS 2>/dev/null || true)"
  [[ -z "$existing_forbidden" ]] && existing_forbidden=".only,.skip,xit,fdescribe"

  # Project name
  ask "Project name" "$existing_name"
  local PROJECT_NAME="$REPLY"

  # Project description
  ask "Project description" "$existing_desc"
  local PROJECT_DESCRIPTION="$REPLY"

  # Git remote
  ask "Git remote URL" "$existing_remote"
  local GIT_REMOTE="$REPLY"

  # Primary language
  ask_choice "Primary language" "typescript python go rust multi"
  local LANGUAGE="$REPLY"

  # Package manager
  ask_choice "Package manager" "pnpm npm yarn pip cargo go"
  local PACKAGE_MANAGER="$REPLY"

  # Database
  ask_choice "Database" "sqlite postgres mysql none"
  local DATABASE="$REPLY"

  # Opencode tier
  local HAS_OPENCODE
  if ask_yn "Use opencode for cost-saving executor tier?" "${existing_opencode:-n}"; then
    HAS_OPENCODE="true"
  else
    HAS_OPENCODE="false"
  fi

  # Bot username for CTO commits
  ask "Bot username for CTO commits" "$existing_cto_bot"
  local CTO_BOT_USERNAME="$REPLY"

  # Opencode bot username (only if enabled)
  local OPENCODE_BOT_USERNAME=""
  if [[ "$HAS_OPENCODE" == "true" ]]; then
    ask "Opencode bot username" "$existing_opencode_bot"
    OPENCODE_BOT_USERNAME="$REPLY"
  fi

  # Admin username — default to <project-slug>-admin
  local project_slug
  project_slug="$(slugify "$PROJECT_NAME")"
  local admin_default="${existing_admin:-${project_slug}-admin}"
  ask "Admin username for PRs" "$admin_default"
  local ADMIN_USERNAME="$REPLY"

  # Protected paths
  ask_multi "Protected paths" "$existing_protected"
  local PROTECTED_PATHS="$REPLY"

  # Forbidden tokens (user-provided base; language extras appended below)
  ask_multi "Forbidden tokens" "$existing_forbidden"
  local FORBIDDEN_TOKENS="$REPLY"

  # Append language-specific forbidden tokens
  case "$LANGUAGE" in
    typescript)
      FORBIDDEN_TOKENS="${FORBIDDEN_TOKENS},@ts-ignore,@ts-expect-error,eslint-disable"
      ;;
    go)
      FORBIDDEN_TOKENS="${FORBIDDEN_TOKENS},//nolint"
      ;;
    rust)
      FORBIDDEN_TOKENS="${FORBIDDEN_TOKENS},#[allow(dead_code)]"
      ;;
    python|multi|*)
      # no extras for python or multi — keep as-is
      ;;
  esac

  # ── 2. Write config ───────────────────────────────────────────────────────────

  echo ""
  info "Writing config to .leap/config..."

  config_set PROJECT_NAME        "$PROJECT_NAME"
  config_set PROJECT_DESCRIPTION "$PROJECT_DESCRIPTION"
  config_set GIT_REMOTE          "$GIT_REMOTE"
  config_set LANGUAGE            "$LANGUAGE"
  config_set PACKAGE_MANAGER     "$PACKAGE_MANAGER"
  config_set DATABASE            "$DATABASE"
  config_set HAS_OPENCODE        "$HAS_OPENCODE"
  config_set CTO_BOT_USERNAME    "$CTO_BOT_USERNAME"
  config_set OPENCODE_BOT_USERNAME "$OPENCODE_BOT_USERNAME"
  config_set ADMIN_USERNAME      "$ADMIN_USERNAME"
  config_set PROTECTED_PATHS     "$PROTECTED_PATHS"
  config_set FORBIDDEN_TOKENS    "$FORBIDDEN_TOKENS"

  # Derived flags for conditional template blocks
  config_set "LANGUAGE_TYPESCRIPT" "$( [[ "$LANGUAGE" == "typescript" ]] && echo "true" || echo "" )"
  config_set "LANGUAGE_PYTHON"     "$( [[ "$LANGUAGE" == "python" ]]     && echo "true" || echo "" )"
  config_set "LANGUAGE_GO"         "$( [[ "$LANGUAGE" == "go" ]]         && echo "true" || echo "" )"
  config_set "LANGUAGE_RUST"       "$( [[ "$LANGUAGE" == "rust" ]]       && echo "true" || echo "" )"
  config_set "LANGUAGE_MULTI"      "$( [[ "$LANGUAGE" == "multi" ]]      && echo "true" || echo "" )"

  # ── 3. Scaffold governance skeleton ──────────────────────────────────────────

  info "Scaffolding governance skeleton..."

  # Core governance docs
  copy_template "$TMPL/CLAUDE.md.tmpl"             "CLAUDE.md"
  copy_template "$TMPL/cto.md.tmpl"               "docs/cto.md"
  copy_template "$TMPL/task-template.md.tmpl"      "docs/backlog/TASK-000-template.md"
  copy_template "$TMPL/backlog-readme.md.tmpl"     "docs/backlog/README.md"
  copy_template "$TMPL/plans-readme.md.tmpl"       "docs/plans/README.md"
  copy_template "$TMPL/waivers.yaml.tmpl"          "docs/waivers.yaml"
  copy_template "$TMPL/coverage-baseline.json"     "coverage/baseline.json"
  copy_template "$TMPL/Makefile.tmpl"              "Makefile"

  # Check scripts
  for f in "$TMPL"/checks/*; do
    copy_template "$f" "ops/checks/$(basename "$f")"
  done

  # Pre-receive hooks
  for f in "$TMPL"/pre-receive/*; do
    copy_template "$f" "ops/pre-receive/$(basename "$f")"
  done

  # CI workflows (GitHub Actions)
  copy_template "$TMPL/ci/github-pr.yml.tmpl"      ".github/workflows/pr.yml"
  copy_template "$TMPL/ci/github-nightly.yml.tmpl" ".github/workflows/nightly.yml"

  # Lefthook config (language-specific; fall back to typescript if no template)
  local lefthook_tmpl="$TMPL/lefthook/${LANGUAGE}.yml.tmpl"
  if [[ -f "$lefthook_tmpl" ]]; then
    copy_template "$lefthook_tmpl" "lefthook.yml"
  elif [[ "$LANGUAGE" == "multi" && -f "$TMPL/lefthook/typescript.yml.tmpl" ]]; then
    copy_template "$TMPL/lefthook/typescript.yml.tmpl" "lefthook.yml"
  else
    warn "No lefthook template found for language '$LANGUAGE' — skipping lefthook.yml"
  fi

  # Lint configs (language-specific)
  if [[ "$LANGUAGE" == "typescript" ]]; then
    copy_template "$TMPL/lint/biome.json.tmpl"       "biome.json"
    copy_template "$TMPL/lint/knip.config.ts.tmpl"   "knip.config.ts"
    printf '{}' > "knip.baseline.json"
  fi
  if [[ "$LANGUAGE" == "go" || "$LANGUAGE" == "multi" ]]; then
    copy_template "$TMPL/lint/golangci.yml.tmpl"     ".golangci.yml"
  fi

  # Opencode tier (if enabled)
  if [[ "$HAS_OPENCODE" == "true" ]]; then
    copy_template "$TMPL/opencode/oc-execute.sh.tmpl" "ops/opencode/oc-execute.sh"
    copy_template "$TMPL/opencode/oc-gate.sh.tmpl"    "ops/opencode/oc-gate.sh"
    mkdir -p ".claude/skills/opencode-execute" ".claude/skills/opencode-review"
    copy_template "$TMPL/skills/opencode-execute.md.tmpl" ".claude/skills/opencode-execute/SKILL.md"
    copy_template "$TMPL/skills/opencode-review.md.tmpl"  ".claude/skills/opencode-review/SKILL.md"
  fi

  # Claude Code hooks (lint-on-edit)
  copy_template "$TMPL/hooks/lint-on-edit.sh.tmpl" ".claude/hooks/lint-on-edit.sh"
  if [[ -f ".claude/settings.local.json" ]]; then
    if ! grep -q '"hooks"' ".claude/settings.local.json" 2>/dev/null; then
      local _tmp_settings
      _tmp_settings="$(mktemp)"
      if command -v jq &>/dev/null; then
        if jq -s '.[0] * .[1]' ".claude/settings.local.json" "$TMPL/hooks/settings.json.tmpl" > "$_tmp_settings" 2>/dev/null; then
          mv "$_tmp_settings" ".claude/settings.local.json"
        else
          rm -f "$_tmp_settings"
        fi
      else
        rm -f "$_tmp_settings"
        warn "jq not found — add hooks config to .claude/settings.local.json manually"
      fi
    fi
  else
    cp "$TMPL/hooks/settings.json.tmpl" ".claude/settings.local.json"
  fi

  # Always create .claude/agents/ (populated by `leap agents`)
  mkdir -p ".claude/agents"

  # ── 4. Post-scaffold summary ──────────────────────────────────────────────────

  echo ""
  echo "✓ Governance skeleton scaffolded for ${PROJECT_NAME}"
  echo ""
  echo "Created:"
  echo "  CLAUDE.md                    — main session instructions"
  echo "  docs/cto.md                  — CTO role definition"
  echo "  docs/backlog/                — task file system"
  echo "  docs/plans/                  — plan file system"
  echo "  docs/waivers.yaml            — waiver ledger"
  echo "  ops/checks/                  — CI check scripts"
  echo "  ops/pre-receive/             — server-side git hooks"
  echo "  .github/workflows/           — CI pipelines"
  echo "  lefthook.yml                 — client-side git hooks"
  echo "  .claude/hooks/               — post-edit lint enforcement"
  echo "  coverage/baseline.json       — coverage ratchet baseline"
  echo ""
  echo "Next steps:"
  echo "  1. Run 'leap agents' to generate agent definitions"
  echo "  2. Run 'lefthook install' to enable client-side hooks"
  echo "  3. Edit CLAUDE.md to add your repo layout and tech stack details"
  if [[ "$HAS_OPENCODE" == "true" ]]; then
    echo "  4. Ensure 'opencode' is in your PATH"
  fi
  echo ""
}

leap_init
