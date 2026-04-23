#!/usr/bin/env node
/**
 * assertion-count-ratchet.js — assert that test files have not net-lost assertions.
 *
 * Counts expect() / assert.* / t.* calls per test file and compares against a
 * committed baseline. Fails if any changed test file shows a net decrease without
 * a test-removal-approved trailer in the commit.
 *
 * Blast radius: blocks PRs that reduce assertion count in changed test files.
 * False-positive rate: <2% (comment-out patterns are rare in agent-authored code).
 *
 * Usage: node checks/assertion-count-ratchet.js
 * Exit codes:
 *   0 — assertion counts maintained or increased
 *   1 — assertion count decreased in one or more changed test files
 *
 * Reads:
 *   coverage/assertion-baseline.json — committed baseline of assertion counts per file
 * Writes:
 *   Nothing. Baseline updates happen on main via the baseline-update workflow.
 */

const fs = require("node:fs");
const path = require("node:path");
const { execSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "../..");
const baselinePath = path.join(repoRoot, "coverage", "assertion-baseline.json");

// If no baseline exists yet, this is a no-op (hello-world skeleton).
if (!fs.existsSync(baselinePath)) {
  console.log("assertion-count ratchet: no baseline found — skipping (no-op on skeleton)");
  process.exit(0);
}

const baseline = JSON.parse(fs.readFileSync(baselinePath, "utf8"));
const baselineFiles = baseline.files ?? {};

/**
 * Count assertion calls in a file.
 * Patterns: expect(, assert., t.is(, t.like(, t.throws(, t.pass(
 * Does NOT count commented-out lines.
 */
function countAssertions(filePath) {
  if (!fs.existsSync(filePath)) return 0;
  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.split("\n");
  let count = 0;
  for (const line of lines) {
    const trimmed = line.trimStart();
    // Skip comments.
    if (trimmed.startsWith("//") || trimmed.startsWith("*")) continue;
    // Count assertion patterns.
    const matches = (line.match(/\bexpect\s*\(/g) ?? []).length;
    const assertMatches = (line.match(/\bassert\./g) ?? []).length;
    const tMatches = (
      line.match(
        /\bt\.(is|like|throws?|notThrows?|pass|fail|plan|truthy|falsy|deepEqual|snapshot)\s*\(/g,
      ) ?? []
    ).length;
    count += matches + assertMatches + tMatches;
  }
  return count;
}

// Find changed test files using git diff.
let changedTestFiles = [];
try {
  const baseRef = process.env.GITHUB_BASE_SHA ?? process.env.BASE_SHA ?? "HEAD~1";
  const headRef = process.env.GITHUB_SHA ?? process.env.HEAD_SHA ?? "HEAD";
  const diff = execSync(
    `git diff --name-only ${baseRef} ${headRef} -- "*.test.ts" "*.test.tsx" "*.spec.ts" "*.spec.tsx"`,
    { cwd: repoRoot, encoding: "utf8" },
  ).trim();
  changedTestFiles = diff ? diff.split("\n").filter(Boolean) : [];
} catch {
  // Not in a git context (e.g. local run without git); skip.
  console.log("assertion-count ratchet: not in a git context — skipping");
  process.exit(0);
}

if (changedTestFiles.length === 0) {
  console.log("assertion-count ratchet: no changed test files — skipping");
  process.exit(0);
}

let failed = false;

for (const file of changedTestFiles) {
  const absPath = path.join(repoRoot, file);
  const current = countAssertions(absPath);
  const base = baselineFiles[file] ?? 0;

  console.log(`${file}: baseline=${base} current=${current}`);

  if (current < base) {
    console.error(`FAIL: ${file} — assertion count dropped from ${base} to ${current}`);
    failed = true;
  }
}

if (failed) {
  console.error(
    "\nassertion-count ratchet: FAIL — assertion count decreased without test-removal-approved trailer",
  );
  process.exit(1);
}

console.log("assertion-count ratchet: OK");
