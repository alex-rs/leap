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

  # Run init first (typescript, no opencode)
  printf 'testproj\nA test\n\n1\n1\n1\nn\ncto\nadm\n\n\n' \
    | "${LEAP_HOME}/leap" init > /dev/null 2>&1
}

teardown() {
  rm -rf "$TEST_DIR"
}

_run_agents() {
  printf '%s\n' "$@" | "${LEAP_HOME}/leap" agents 2>&1
}

# ── core agents always generated ──────────────────────────────────────────────

@test "agents generates 4 core agents" {
  _run_agents "A test app" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ -f .claude/agents/ci-gatekeeper.md ]
  [ -f .claude/agents/devex-engineer.md ]
  [ -f .claude/agents/task-planner.md ]
  [ -f .claude/agents/security-engineer.md ]
}

@test "core agents have valid frontmatter" {
  _run_agents "A test app" "api" "n" "y" "n" "n" "n" "" > /dev/null
  grep -q "^name: ci-gatekeeper" .claude/agents/ci-gatekeeper.md
  grep -q "^model: haiku" .claude/agents/ci-gatekeeper.md
  grep -q "^model: opus" .claude/agents/security-engineer.md
}

# ── conditional agents ────────────────────────────────────────────────────────

@test "frontend agent generated when requested" {
  _run_agents "A test app" "api,web" "y" "1" "y" "n" "n" "n" "" > /dev/null
  [ -f .claude/agents/frontend-engineer.md ]
  grep -q "nextjs" .claude/agents/frontend-engineer.md
}

@test "frontend agent not generated when declined" {
  _run_agents "A test app" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ ! -f .claude/agents/frontend-engineer.md ]
}

@test "backend agent generated when requested" {
  _run_agents "A test app" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ -f .claude/agents/backend-engineer.md ]
}

@test "infra agent generated with provider" {
  _run_agents "A test app" "api" "n" "y" "y" "1" "n" "n" "" > /dev/null
  [ -f .claude/agents/infra-engineer.md ]
  grep -q "aws" .claude/agents/infra-engineer.md
}

@test "billing agent generated with provider" {
  _run_agents "A test app" "api" "n" "y" "n" "y" "1" "n" "" > /dev/null
  [ -f .claude/agents/billing-engineer.md ]
  grep -q "stripe" .claude/agents/billing-engineer.md
}

@test "gtm agent generated when requested" {
  _run_agents "A test app" "api" "n" "y" "n" "n" "y" "" > /dev/null
  [ -f .claude/agents/gtm-analyst.md ]
}

# ── custom agents ─────────────────────────────────────────────────────────────

@test "custom agent created with slug name" {
  _run_agents "A test app" "api" "n" "y" "n" "n" "n" "data-pipeline" "Handles ETL jobs" > /dev/null
  [ -f .claude/agents/data-pipeline.md ]
  grep -q "Handles ETL jobs" .claude/agents/data-pipeline.md
}

# ── stale agent cleanup ──────────────────────────────────────────────────────

@test "deselected conditional agent removed on rerun" {
  _run_agents "A test" "api,web" "y" "1" "y" "n" "n" "n" "" > /dev/null
  [ -f .claude/agents/frontend-engineer.md ]

  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ ! -f .claude/agents/frontend-engineer.md ]
}

@test "deselected custom agent removed on rerun" {
  _run_agents "A test" "api" "n" "y" "n" "n" "n" "foo" "Does foo" > /dev/null
  [ -f .claude/agents/foo.md ]

  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ ! -f .claude/agents/foo.md ]
}

@test "renamed custom agent: old file removed, new file created" {
  _run_agents "A test" "api" "n" "y" "n" "n" "n" "alpha" "Does alpha" > /dev/null
  [ -f .claude/agents/alpha.md ]

  _run_agents "A test" "api" "n" "y" "n" "n" "n" "beta" "Does beta" > /dev/null
  [ ! -f .claude/agents/alpha.md ]
  [ -f .claude/agents/beta.md ]
}

# ── CLAUDE.md routing table ───────────────────────────────────────────────────

@test "CLAUDE.md routing table updated with agents" {
  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  grep -q "ci-gatekeeper" CLAUDE.md
  grep -q "backend-engineer" CLAUDE.md
}

@test "CLAUDE.md escalation matrix updated" {
  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  grep -q "CI pipeline change" CLAUDE.md
  grep -q "Protected path change" CLAUDE.md
}

@test "routing table updated on rerun" {
  _run_agents "A test" "api,web" "y" "1" "y" "n" "n" "n" "" > /dev/null
  grep -q "frontend-engineer" CLAUDE.md

  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  ! grep -q "frontend-engineer" CLAUDE.md
}

# ── opencode mirroring ────────────────────────────────────────────────────────

@test "opencode mirror created when enabled" {
  # Re-init with opencode enabled
  printf 'testproj\nA test\n\n1\n1\n1\ny\ncto\noc\nadm\n\n\n' \
    | "${LEAP_HOME}/leap" init > /dev/null 2>&1

  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ -d .opencode/agents ]
  [ -f .opencode/agents/ci-gatekeeper.md ]
  ! grep -q "^tools:" .opencode/agents/ci-gatekeeper.md
}

@test "opencode mirror cleaned when disabled" {
  # Init with opencode enabled, run agents
  printf 'testproj\nA test\n\n1\n1\n1\ny\ncto\noc\nadm\n\n\n' \
    | "${LEAP_HOME}/leap" init > /dev/null 2>&1
  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ -d .opencode/agents ]

  # Re-init with opencode disabled, run agents again
  printf 'testproj\nA test\n\n1\n1\n1\nn\ncto\nadm\n\n\n' \
    | "${LEAP_HOME}/leap" init > /dev/null 2>&1
  _run_agents "A test" "api" "n" "y" "n" "n" "n" "" > /dev/null
  [ ! -d .opencode/agents ]
}

# ── no residual template markers ──────────────────────────────────────────────

@test "no template markers in generated agent files" {
  _run_agents "A test" "api,web" "y" "1" "y" "y" "1" "y" "1" "y" "" > /dev/null
  for f in .claude/agents/*.md; do
    ! grep -q '%%[A-Z_]*%%' "$f"
  done
}
