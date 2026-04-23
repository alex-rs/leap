#!/usr/bin/env node
/**
 * coverage-ratchet.js — per-file coverage ratchet against coverage/baseline.json
 *
 * Reads coverage/coverage-summary.json (Vitest/Istanbul JSON summary format) and
 * coverage/baseline.json (committed baseline). Fails if any file's statement
 * coverage dropped below its baseline value.
 *
 * Blast radius: blocks PRs that reduce per-file coverage for any changed file.
 * False-positive rate: <1% (coverage is deterministic given the same test suite).
 *
 * Usage: node checks/coverage-ratchet.js
 * Exit codes:
 *   0 — all files meet or exceed baseline
 *   1 — one or more files dropped below baseline
 */

const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "../..");
const baselinePath = path.join(repoRoot, "coverage", "baseline.json");
const summaryPath = path.join(repoRoot, "coverage", "coverage-summary.json");

if (!fs.existsSync(baselinePath)) {
  console.error(`ERROR: coverage/baseline.json not found at ${baselinePath}`);
  process.exit(1);
}

if (!fs.existsSync(summaryPath)) {
  console.error(`ERROR: coverage/coverage-summary.json not found at ${summaryPath}`);
  console.error("Run your test suite with --coverage to generate coverage-summary.json");
  process.exit(1);
}

const baseline = JSON.parse(fs.readFileSync(baselinePath, "utf8"));
const summary = JSON.parse(fs.readFileSync(summaryPath, "utf8"));

const baselineFiles = baseline.files ?? {};
let failed = false;

// Check each file in the baseline against the current coverage summary.
for (const [file, baselineCov] of Object.entries(baselineFiles)) {
  const current = summary[file];
  if (!current) {
    // File was deleted or renamed — not a ratchet violation.
    continue;
  }
  const currentStatements = current.statements?.pct ?? 0;
  const baselineStatements = baselineCov.statements ?? 0;

  if (currentStatements < baselineStatements) {
    console.error(
      `FAIL: ${file} — statement coverage dropped from ${baselineStatements}% to ${currentStatements}%`,
    );
    failed = true;
  }
}

// Also check new files in the summary that are not yet in the baseline.
// These are not ratchet violations — they just need to be added to the baseline
// on the next successful main run. Report them as informational.
for (const file of Object.keys(summary)) {
  if (file === "total") continue;
  if (!baselineFiles[file]) {
    const pct = summary[file]?.statements?.pct ?? 0;
    console.log(
      `INFO: new file not in baseline: ${file} (${pct}% statement coverage) — will be baselined on main`,
    );
  }
}

if (failed) {
  console.error("\ncoverage ratchet: FAIL — one or more files dropped below baseline");
  process.exit(1);
}

console.log("coverage ratchet: OK — all files meet or exceed baseline");
