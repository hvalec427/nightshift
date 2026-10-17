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

report
