#!/usr/bin/env bash
# Tests for what an issue cost: each run's dollars, tokens and time added up
# in its `cost`, shown by `status`, and posted on the issue once it's done.
#   bash scripts/test-cost.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# Issue $1's `cost`, its seconds (field 5) as S.
cost() { state "$1" cost | awk '{ $5 = "S"; print }'; }

(world
  gh_issue o/r 7 alice agent
  runs_do 'costs 0.5 opus 100 200 300 400; costs 0.25 haiku 10 20 30 40; comment questions'
  poll
  expect "a run: its dollars and tokens, of every model" "$(cost 7)" "0.75 110 220 770 S 1 -"
  expect_ok "its time: whole seconds" grep -Eq '^[^ ]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+ ' "$(idir 7)/cost"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do 'costs 1.25 opus 1000 2000 0 5; comment plan'
  poll
  expect "a second run: added" "$(cost 7)" "2 1110 2220 775 S 2 -"
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do 'costs 0.1 opus 1 1 1 1; fail_result'
  poll
  expect "a failed run: counted" "$(cost 7)" "2.1 1111 2221 777 S 3 -"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "a run that reports no cost: its time and the run" "$(cost 7)" "0 0 0 0 S 1 -")

(world
  gh_issue o/r 7 alice agent
  runs_do 'costs 0.5 opus 1 1 1 1; hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  ns stop o/r#7 >/dev/null
  wait "$bg"
  expect "a stopped run (no result): its time and the run" "$(cost 7)" "0 0 0 0 S 1 -")

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  rm "$(idir 7)/cost"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "counting from a later run: since today" "$(cost 7)" "0 0 0 0 S 1 $(date +%Y-%m-%d)")

report
