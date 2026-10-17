#!/usr/bin/env bash
# Tests for nightshift's command line itself: the version, help and unknown
# commands; and for the test lib's own checks.
#   bash scripts/test-cli.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

(world
  expect "--version: the version" "$(ns --version)" "nightshift dev"
  expect "version: the same" "$(ns version)" "nightshift dev"
  expect_line "help: the usage" "$(ns help)" "^  nightshift watch "
  expect_line "help: points to the logs' help" "$(ns --help)" "nightshift logs --help"
  set +e
  out=$(ns frobnicate 2>&1)
  expect "an unknown command: exit 2" "$?" 2
  set -e
  expect_line "an unknown command: the usage" "$out" "^  nightshift status "
  set +e
  ns >/dev/null 2>&1
  expect "no command: exit 2" "$?" 2
  set -e)

# expect_line under pipefail, on an input far bigger than a pipe holds whose
# first line matches: grep quits at line 1, and that is still a match.
(big=$(awk 'BEGIN { print "the line"; for (i = 0; i < 100000; i++) print "another line" }')
  got=$(FAILS=$(mktemp)
    set -o pipefail
    out=$(expect_line "big" "$big" "^the line$")
    printf '%s|%s' "${out%%$'\n'*}" "$(cat "$FAILS")")
  expect "expect_line: a match on line 1 of a large input" "$got" "ok   big|")

# A test's world is removed when it ends; KEEP_WORLD=1 keeps it and says where.
w=$( (world; echo "$W") )
expect "world: removed when its test ends" "$([ -e "$w" ] && echo there || echo gone)" "gone"
both=$( (export KEEP_WORLD=1; world; echo "W=$W") 2>&1 )
w=${both%%$'\n'*}
w=${w#W=}
expect "KEEP_WORLD=1: the world stays" "$([ -d "$w" ] && echo there || echo gone)" "there"
expect_line "KEEP_WORLD=1: says where it is" "$both" "^kept $w\$"
rm -rf "$w"

# A test file's FAILS file is removed when the file exits, passed or failed.
(world
  printf '%s\n' '. "$1/scripts/test-lib.sh"' 'echo "$FAILS" >"$2"' 'expect "pass" 1 1' 'report' >"$W/pass.sh"
  printf '%s\n' '. "$1/scripts/test-lib.sh"' 'echo "$FAILS" >"$2"' 'expect "fail" 1 2' 'report' >"$W/fail.sh"
  for f in pass fail; do
    bash "$W/$f.sh" "$ROOT" "$W/$f.fails" >/dev/null || true
    expect "FAILS: removed when a $f file exits" "$([ -e "$(cat "$W/$f.fails")" ] && echo there || echo gone)" "gone"
  done)

report
