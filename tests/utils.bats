#!/usr/bin/env bats

setup() {
  export LEAP_HOME="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  source "${LEAP_HOME}/lib/utils.sh"
  source "${LEAP_HOME}/lib/config.sh"
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── slugify ────────────────────────────────────────────────────────────────────

@test "slugify converts to kebab-case" {
  result="$(slugify "My Cool Project")"
  [ "$result" = "my-cool-project" ]
}

@test "slugify collapses consecutive hyphens" {
  result="$(slugify "foo---bar")"
  [ "$result" = "foo-bar" ]
}

@test "slugify strips leading and trailing hyphens" {
  result="$(slugify "--foo-bar--")"
  [ "$result" = "foo-bar" ]
}

@test "slugify handles special characters" {
  result="$(slugify "hello@world!123")"
  [ "$result" = "hello-world-123" ]
}

# ── render_conditional_content ─────────────────────────────────────────────────

@test "IF block kept when value is truthy" {
  declare -A cfg=([FEATURE]="true")
  template=$'before\n%%IF FEATURE%%\nkept\n%%ENDIF%%\nafter'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" == *"kept"* ]]
  [[ "$result" == *"before"* ]]
  [[ "$result" == *"after"* ]]
}

@test "IF block stripped when value is false" {
  declare -A cfg=([FEATURE]="false")
  template=$'before\n%%IF FEATURE%%\nremoved\n%%ENDIF%%\nafter'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" != *"removed"* ]]
  [[ "$result" == *"before"* ]]
  [[ "$result" == *"after"* ]]
}

@test "IF block stripped when value is empty" {
  declare -A cfg=([FEATURE]="")
  template=$'before\n%%IF FEATURE%%\nremoved\n%%ENDIF%%\nafter'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" != *"removed"* ]]
}

@test "IF block stripped when key is missing" {
  declare -A cfg=()
  template=$'before\n%%IF MISSING_KEY%%\nremoved\n%%ENDIF%%\nafter'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" != *"removed"* ]]
  [[ "$result" == *"before"* ]]
}

@test "IF block stripped when value is none" {
  declare -A cfg=([DB]="none")
  template=$'%%IF DB%%\nhas db\n%%ENDIF%%'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" != *"has db"* ]]
}

@test "ELSE branch taken when IF is false" {
  declare -A cfg=([FEATURE]="false")
  template=$'%%IF FEATURE%%\nprimary\n%%ELSE%%\nfallback\n%%ENDIF%%'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" == *"fallback"* ]]
  [[ "$result" != *"primary"* ]]
}

@test "ELSE branch skipped when IF is true" {
  declare -A cfg=([FEATURE]="true")
  template=$'%%IF FEATURE%%\nprimary\n%%ELSE%%\nfallback\n%%ENDIF%%'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" == *"primary"* ]]
  [[ "$result" != *"fallback"* ]]
}

@test "multiple IF blocks in one template" {
  declare -A cfg=([A]="true" [B]="false")
  template=$'%%IF A%%\nalpha\n%%ENDIF%%\nmiddle\n%%IF B%%\nbeta\n%%ENDIF%%\nend'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" == *"alpha"* ]]
  [[ "$result" != *"beta"* ]]
  [[ "$result" == *"middle"* ]]
}

@test "IF/ELSE/ENDIF markers do not appear in output" {
  declare -A cfg=([X]="true")
  template=$'%%IF X%%\nkept\n%%ELSE%%\nskipped\n%%ENDIF%%'
  result="$(render_conditional_content "$template" cfg)"
  [[ "$result" != *"%%IF"* ]]
  [[ "$result" != *"%%ELSE%%"* ]]
  [[ "$result" != *"%%ENDIF%%"* ]]
}

# ── render_template ────────────────────────────────────────────────────────────

@test "render_template substitutes variables" {
  mkdir -p .leap
  printf 'NAME=world\n' > .leap/config
  printf 'hello %%%%NAME%%%%\n' > tmpl.txt
  render_template tmpl.txt out.txt .leap/config
  result="$(cat out.txt)"
  [[ "$result" == *"hello world"* ]]
}

@test "render_template handles special chars in values" {
  mkdir -p .leap
  printf 'DESC=foo & bar | baz\n' > .leap/config
  printf 'desc: %%%%DESC%%%%\n' > tmpl.txt
  render_template tmpl.txt out.txt .leap/config
  result="$(cat out.txt)"
  [[ "$result" == *"foo & bar | baz"* ]]
}

@test "render_template handles URL with equals sign" {
  mkdir -p .leap
  printf 'URL=https://example.com?a=1&b=2\n' > .leap/config
  printf 'url: %%%%URL%%%%\n' > tmpl.txt
  render_template tmpl.txt out.txt .leap/config
  result="$(cat out.txt)"
  [[ "$result" == *"https://example.com?a=1&b=2"* ]]
}

# ── config_set / config_get ────────────────────────────────────────────────────

@test "config_set creates new key" {
  mkdir -p .leap
  config_set FOO bar
  result="$(config_get FOO)"
  [ "$result" = "bar" ]
}

@test "config_set updates existing key" {
  mkdir -p .leap
  config_set FOO bar
  config_set FOO baz
  result="$(config_get FOO)"
  [ "$result" = "baz" ]
}

@test "config_set preserves special chars" {
  mkdir -p .leap
  config_set DESC "foo & bar | baz"
  result="$(config_get DESC)"
  [ "$result" = "foo & bar | baz" ]
}

@test "config_set preserves URL with ampersand and equals" {
  mkdir -p .leap
  config_set REMOTE "git@github.com:user/repo.git"
  result="$(config_get REMOTE)"
  [ "$result" = "git@github.com:user/repo.git" ]
}

@test "config_set preserves value with pipe character" {
  mkdir -p .leap
  config_set VAL "a|b|c"
  result="$(config_get VAL)"
  [ "$result" = "a|b|c" ]
}

@test "config_set does not corrupt other keys" {
  mkdir -p .leap
  config_set A "first"
  config_set B "second"
  config_set A "updated"
  resultA="$(config_get A)"
  resultB="$(config_get B)"
  [ "$resultA" = "updated" ]
  [ "$resultB" = "second" ]
}

@test "config_get returns empty for missing key" {
  mkdir -p .leap
  printf 'FOO=bar\n' > .leap/config
  result="$(config_get MISSING || true)"
  [ -z "$result" ]
}
