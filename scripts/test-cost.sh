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

# Shown by status.
(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  echo "1.5 12000 85000 1700000 6000 12 -" >"$(idir 7)/cost"
  expect_line "status: what it cost so far" "$(ns status)" '^o/r#7  *needs you · [0-9]*s · spent \$1\.50, 1\.8M tokens, 1h 40m$'
  echo "0.004 500 0 0 45 1 -" >"$(idir 7)/cost"
  expect_line "status: small sums" "$(ns status)" '^o/r#7  *needs you · [0-9]*s · spent \$0\.00, 500 tokens, 45s$'
  echo "12.345 1000 2000 6000 90000 3 -" >"$(idir 7)/cost"
  expect_line "status: thousands" "$(ns status)" '^o/r#7  *needs you · [0-9]*s · spent \$12\.35, 9k tokens, 1d 1h$'
  rm "$(idir 7)/cost"
  expect_line "status: nothing counted, nothing shown" "$(ns status)" '^o/r#7  *needs you · [0-9]*s$')

# Posted once it's done.
COMMENT="🤖 \*\*nightshift\*\* · cost"
(world
  gh_issue o/r 7 alice agent
  runs_do 'costs 2.5 opus 12000 85000 1700000 0; commit feature.txt; open_pr; comment done'
  poll
  echo "4.123 12000 85000 1700000 6000 12 -" >"$(idir 7)/cost"
  gh_pr_set o/r "$(state 7 pr | sed 's|.*/||')" state '"MERGED"'
  poll
  expect "merged: done" "$(state 7 "done")" "PR merged"
  comments=$(gh_comments o/r 7)
  expect_line "merged: a cost comment" "$comments" "^$COMMENT$"
  expect_line "it says the dollars, tokens and time" "$comments" \
    '^\*\*\$4\.12\*\* at API prices · \*\*1\.8M tokens\*\* (12k in, 85k out, 1\.7M cache) · \*\*1h 40m\*\* over 12 runs$'
  expect_line "it has the marker" "$comments" "^<!-- nightshift --> <!-- nightshift:cost -->$"
  expect "its cost stays" "$(state 7 cost)" "4.123 12000 85000 1700000 6000 12 -"
  expect_line "status --all: what it spent" "$(ns status --all)" '^o/r#7  *done · PR .* merged .* ago · spent \$4\.12, 1\.8M tokens, 1h 40m$'
  poll
  expect "posted once" "$(gh_comments o/r 7 | grep -c "^$COMMENT$")" 1
  expect "its own comment starts no run" "$(runs)" 1
  gh_comment o/r 7 alice "one more thing" >/dev/null
  runs_do 'costs 1 opus 1 1 1 1; comment progress'
  poll
  expect "brought back: it adds up still" "$(cost 7)" "5.123 12001 85001 1700002 S 13 -"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  echo "0.5 10 20 30 61 1 2026-10-01" >"$(idir 7)/cost"
  gh_state o/r 7 closed
  poll
  expect "closed: done" "$(state 7 "done")" "issue closed"
  expect_line "closed: a cost comment, one run, since it was counted" "$(gh_comments o/r 7)" \
    '^\*\*\$0\.50\*\* at API prices · \*\*60 tokens\*\* (10 in, 20 out, 30 cache) · \*\*1m\*\* over 1 run (counted since 2026-10-01)$')

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  rm "$(idir 7)/cost"
  gh_state o/r 7 closed
  poll
  expect "nothing counted: no cost comment" "$(gh_comments o/r 7 | grep -c "^$COMMENT$" || true)" 0)

report
