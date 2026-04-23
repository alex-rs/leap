# leap

Governance scaffolder for AI-agent-driven codebases. Sets up the structure, enforcement, and agent definitions that let multiple AI coding agents (Claude Code, opencode, etc.) collaborate on a single repo without stepping on each other.

## Problem

When you use AI agents to write production code, you need mechanical guardrails: protected paths agents cannot modify, coverage ratchets they cannot regress, a gatekeeper that reviews their PRs independently, and a task system that tracks what each agent is doing. Setting this up from scratch for every project takes days and the rules drift as agents find creative ways around them.

## What leap does

Two commands. Both interactive, both re-runnable.

`leap init` asks about your project (name, language, package manager, database) and scaffolds the full governance layer:

- `CLAUDE.md` and `docs/cto.md` for the orchestrator role and delegation contracts
- A task system (`docs/backlog/TASK-NNN.md`) with lifecycle rules and verification scripts
- A plan system (`docs/plans/`) with mandatory human approval gates
- A waiver ledger (`docs/waivers.yaml`) with enforced expiry
- CI check scripts: coverage ratchet, circuit breaker, forbidden token scanner, test deletion detector, assertion count ratchet, waiver expiry enforcer
- Server-side git hooks: forbidden tokens, gitleaks, lockfile drift, protected paths, waiver schema validation
- GitHub Actions workflows (PR gate and nightly)
- Client-side hooks via lefthook, configured for your language
- Lint configs (biome, golangci-lint, knip, ruff, clippy) matched to your stack

`leap agents` asks about your domain and generates agent definitions:

- Four core agents always created: ci-gatekeeper (haiku, never writes product code), devex-engineer, task-planner, and security-engineer (opus, has veto)
- Conditional agents based on your answers: frontend, backend, infra, billing, GTM
- Custom agents from names and descriptions you provide
- Automatic CLAUDE.md update with routing table and escalation matrix
- Optional opencode agent mirroring for cost-saving delegation

## Install

```
git clone https://github.com/alex-rs/leap.git ~/leap
export PATH="$HOME/leap:$PATH"
```

## Usage

```
cd your-project
leap init
leap agents
```

## Use cases

**Solo founder with Claude Code as the primary developer.** You need agents that own different parts of the stack (frontend, infra, billing) without any single agent being able to modify the CI pipeline, coverage baselines, or its own role definition. leap scaffolds the protected paths, the gatekeeper, and the verification scripts that enforce this.

**Team using multiple AI coding tools.** Your repo has contributors from Claude Code, Codex, and opencode. You need a shared task format so any agent can pick up work, a plan approval gate so humans stay in the loop on architecture, and CI checks that no agent can bypass. leap generates the task/plan system and the pre-receive hooks that block forbidden patterns regardless of which tool made the commit.

**Open source maintainer adding AI agent support.** You want to let AI agents submit PRs but need guardrails: no test deletion without approval, no coverage regression, mandatory waiver expiry for lint exceptions, and a circuit breaker that freezes PRs after repeated CI failures. leap installs these as shell scripts that work with any CI provider.

**Rapid prototyping across multiple projects.** You start new repos frequently and want the same governance structure in each one without copying files between projects. leap init takes 30 seconds and gives you the full skeleton. leap agents adds role definitions tuned to each project's stack.

## Supported stacks

| Language | Lint | Test runner | Coverage |
|---|---|---|---|
| TypeScript | biome, knip | vitest | istanbul |
| Python | ruff | pytest | coverage.py |
| Go | golangci-lint | go test | go tool cover |
| Rust | clippy, rustfmt | cargo test | cargo-tarpaulin |

Database options: SQLite, PostgreSQL, MySQL, or none.

## What gets generated

```
CLAUDE.md                        # orchestrator instructions
docs/cto.md                      # CTO role, delegation contracts
docs/backlog/                    # task file system
docs/plans/                      # plan file system
docs/waivers.yaml                # waiver ledger
ops/checks/                      # CI enforcement scripts
ops/pre-receive/                 # server-side git hooks
.github/workflows/               # PR gate + nightly CI
.claude/agents/                  # agent role definitions
.claude/hooks/                   # post-edit lint enforcement
lefthook.yml                     # client-side hooks
coverage/baseline.json           # coverage ratchet seed
Makefile                         # dev/lint/test/check targets
```

Plus language-specific lint configs, and optionally opencode executor scripts.

## Configuration

leap stores project settings in `.leap/config` and agent roster settings in `.leap/agents-config`, both as simple KEY=VALUE files. Re-running either command reads existing values as defaults.

After scaffolding, customize by editing the generated files directly. The governance docs, agent definitions, and enforcement scripts are plain text with no runtime dependency on leap.

## Tests

```
bats tests/
```

68 tests covering the template engine, config persistence, scaffold completeness across all supported stacks, agent generation and cleanup, lint hooks, and re-run idempotency.

## Requirements

bash 4+, git, and standard unix tools (awk, grep, find).

## License

MIT
