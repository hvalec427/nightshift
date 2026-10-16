#!/usr/bin/env bash
# Tests for nightshift's command line itself: the version, help and unknown
# commands.
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

report
