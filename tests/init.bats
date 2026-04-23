#!/usr/bin/env bats

setup() {
  export LEAP_HOME="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
  git init -q
  echo "test" > README.md
  git add .
  git commit -q -m "init"
  git remote add origin git@github.com:test/project.git 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

_run_init() {
  printf '%s\n' "$@" | "${LEAP_HOME}/leap" init 2>&1
}

# ── scaffold completeness ─────────────────────────────────────────────────────

@test "init scaffolds all core files for typescript" {
  _run_init "myproj" "A test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  [ -f CLAUDE.md ]
  [ -f docs/cto.md ]
  [ -f docs/backlog/TASK-000-template.md ]
  [ -f docs/backlog/README.md ]
  [ -f docs/plans/README.md ]
  [ -f docs/waivers.yaml ]
  [ -f coverage/baseline.json ]
  [ -f Makefile ]
  [ -f lefthook.yml ]
  [ -f .github/workflows/pr.yml ]
  [ -f .github/workflows/nightly.yml ]
  [ -d .claude/agents ]
  [ -f .claude/hooks/lint-on-edit.sh ]
  [ -x .claude/hooks/lint-on-edit.sh ]
  [ -f .claude/settings.local.json ]
}

@test "lint hook contains language-appropriate linter" {
  _run_init "myproj" "A test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "biome" .claude/hooks/lint-on-edit.sh
  # python/go blocks should not be present for typescript-only
  ! grep -q "ruff" .claude/hooks/lint-on-edit.sh
  ! grep -q "golangci-lint" .claude/hooks/lint-on-edit.sh
}

@test "lint hook for python uses ruff" {
  _run_init "myproj" "A test" "" "2" "4" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "ruff" .claude/hooks/lint-on-edit.sh
  ! grep -q "biome" .claude/hooks/lint-on-edit.sh
}

@test "lint hook settings has PostToolUse config" {
  _run_init "myproj" "A test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "PostToolUse" .claude/settings.local.json
  grep -q "lint-on-edit" .claude/settings.local.json
}

@test "init scaffolds typescript-specific files" {
  _run_init "myproj" "A test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  [ -f biome.json ]
  [ -f knip.config.ts ]
  [ -f knip.baseline.json ]
}

@test "init does not scaffold typescript files for python" {
  _run_init "myproj" "A test" "" "2" "4" "1" "n" "cto" "admin" "" "" > /dev/null
  [ ! -f biome.json ]
  [ ! -f knip.config.ts ]
  [ ! -f knip.baseline.json ]
}

@test "init scaffolds golangci for go" {
  _run_init "myproj" "A test" "" "3" "6" "1" "n" "cto" "admin" "" "" > /dev/null
  [ -f .golangci.yml ]
  [ ! -f biome.json ]
}

@test "init scaffolds check scripts" {
  _run_init "myproj" "A test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  [ -f ops/checks/forbidden-tokens.sh ]
  [ -f ops/checks/circuit-breaker.sh ]
  [ -f ops/checks/coverage-ratchet.js ]
  [ -f ops/checks/verify-task-done.sh ]
  [ -f ops/checks/waiver-expiry-check.sh ]
}

@test "init scaffolds pre-receive hooks" {
  _run_init "myproj" "A test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  [ -f ops/pre-receive/pre-receive ]
  [ -f ops/pre-receive/forbidden-tokens.sh ]
  [ -f ops/pre-receive/gitleaks.sh ]
  [ -f ops/pre-receive/lockfile-drift.sh ]
  [ -f ops/pre-receive/protected-paths.sh ]
  [ -f ops/pre-receive/waiver-schema.sh ]
  [ -f ops/pre-receive/test-deletion.sh ]
}

# ── variable substitution ─────────────────────────────────────────────────────

@test "CLAUDE.md contains project name" {
  _run_init "myproj" "A cool SaaS" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "^# myproj" CLAUDE.md
}

@test "CLAUDE.md contains project description" {
  _run_init "myproj" "A cool SaaS" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "A cool SaaS" CLAUDE.md
}

@test "circuit-breaker uses project name in state dir" {
  _run_init "myproj" "test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "myproj-circuit-breaker" ops/checks/circuit-breaker.sh
}

@test "no residual template markers in CLAUDE.md" {
  _run_init "myproj" "test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  ! grep -q '%%[A-Z_]*%%' CLAUDE.md
}

# ── lockfile drift per package manager ─────────────────────────────────────────

@test "lockfile-drift enforces pnpm rules for pnpm" {
  _run_init "myproj" "test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q 'PKG_MGR="pnpm"' ops/pre-receive/lockfile-drift.sh
  grep -q 'pnpm-lock.yaml' ops/pre-receive/lockfile-drift.sh
}

@test "lockfile-drift enforces pip for python" {
  _run_init "myproj" "test" "" "2" "4" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q 'PKG_MGR="pip"' ops/pre-receive/lockfile-drift.sh
}

@test "lockfile-drift enforces go rules for go" {
  _run_init "myproj" "test" "" "3" "6" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q 'LANG="go"' ops/pre-receive/lockfile-drift.sh
}

# ── Makefile per language ──────────────────────────────────────────────────────

@test "Makefile has vitest for typescript" {
  _run_init "myproj" "test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "vitest" Makefile
}

@test "Makefile has pytest for python" {
  _run_init "myproj" "test" "" "2" "4" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "pytest" Makefile
  ! grep -q "vitest" Makefile
}

@test "Makefile has go test for go" {
  _run_init "myproj" "test" "" "3" "6" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "go test" Makefile
  ! grep -q "vitest" Makefile
}

@test "Makefile has cargo test for rust" {
  _run_init "myproj" "test" "" "4" "5" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "cargo test" Makefile
  ! grep -q "vitest" Makefile
}

# ── opencode tier ──────────────────────────────────────────────────────────────

@test "init scaffolds opencode files when enabled" {
  _run_init "myproj" "test" "" "1" "1" "1" "y" "cto" "oc-bot" "admin" "" "" > /dev/null
  [ -f ops/opencode/oc-execute.sh ]
  [ -f ops/opencode/oc-gate.sh ]
  [ -f .claude/skills/opencode-execute/SKILL.md ]
  [ -f .claude/skills/opencode-review/SKILL.md ]
}

@test "init does not scaffold opencode files when disabled" {
  _run_init "myproj" "test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  [ ! -d ops/opencode ]
  [ ! -d .claude/skills/opencode-execute ]
}

# ── CI workflow correctness ───────────────────────────────────────────────────

@test "CI workflow references waiver-expiry-check.sh (not waiver-expiry.sh)" {
  _run_init "myproj" "test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "waiver-expiry-check.sh" .github/workflows/pr.yml
  ! grep -q "waiver-expiry\.sh" .github/workflows/pr.yml
}

# ── config persistence ────────────────────────────────────────────────────────

@test "config written correctly" {
  _run_init "myproj" "A test project" "" "1" "1" "2" "n" "cto" "admin" "" "" > /dev/null
  [ -f .leap/config ]
  grep -q "^PROJECT_NAME=myproj$" .leap/config
  grep -q "^DATABASE=postgres$" .leap/config
  grep -q "^LANGUAGE=typescript$" .leap/config
}

@test "init is re-runnable and preserves config" {
  _run_init "myproj" "first" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  _run_init "" "" "" "" "" "" "" "" "" "" "" > /dev/null
  grep -q "^PROJECT_NAME=myproj$" .leap/config
}

# ── forbidden tokens per language ──────────────────────────────────────────────

@test "typescript gets ts-ignore in forbidden tokens" {
  _run_init "myproj" "test" "" "1" "1" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "@ts-ignore" .leap/config
}

@test "go gets nolint in forbidden tokens" {
  _run_init "myproj" "test" "" "3" "6" "1" "n" "cto" "admin" "" "" > /dev/null
  grep -q "//nolint" .leap/config
}
