#!/usr/bin/env bash
# Tests for all_issues=true: an allowed user's new unlabelled issues are worked
# like labelled ones. Driven through the watcher and the fake gh.
#   bash scripts/test-all-issues.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# The option, committed to o/r's default branch. A poll fetches it.
all_on() { origin_config "all_issues=true"; }
LONG_AGO=2000-01-01T00:00:00Z

(world
  runs_do 'comment questions'
  all_on
  poll
  expect "the option on: the on-time is recorded" "$(cat "$NS/all_issues/o_r" | grep -c '^20[0-9-]*T[0-9:]*Z$')" 1
  gh_issue o/r 7 alice
  gh_issue o/r 8 mallory
  gh_issue o/r 6 alice
  gh_created o/r 6 $LONG_AGO
  poll
  expect "an allowed user's new unlabelled issue: a run" "$(runs)" 1
  expect_ok "the run is for that issue" test -f "$(idir 7)/started"
  expect_ok "a stranger's issue: no dir" test ! -d "$(idir 8)"
  expect_ok "an issue from before the on-time: no dir" test ! -d "$(idir 6)"
  poll
  expect "nothing new: no more runs" "$(runs)" 1
  expect_no_unexpected)

(world
  runs_do 'comment questions'
  gh_issue o/r 7 alice
  poll
  expect "the option unset: an unlabelled issue gets no run" "$(runs)" 0
  expect_ok "the option unset: no on-time" test ! -e "$NS/all_issues/o_r"
  origin_config "all_issues=false"
  poll
  expect "the option false: an unlabelled issue gets no run" "$(runs)" 0
  origin_config "all_issues=yes"
  poll
  expect "the option anything but true: no run" "$(runs)" 0
  expect_no_unexpected)

(world
  runs_do 'comment questions'
  all_on
  poll
  origin_config "# all_issues=true"
  poll
  expect_ok "the option read off: the on-time is cleared" test ! -e "$NS/all_issues/o_r"
  gh_issue o/r 7 alice
  poll
  expect "the option off: no run" "$(runs)" 0
  all_on
  gh_created o/r 7 $LONG_AGO
  poll
  expect "on again: the on-time is new, so an older issue stays alone" "$(runs)" 0
  expect_no_unexpected)

(world
  runs_do 'comment questions'
  all_on
  poll
  # An allowed user's label on a stranger's issue still works; a stranger's own label doesn't.
  gh_issue o/r 7 mallory
  gh_label_add o/r 7 alice agent
  gh_issue o/r 8 mallory
  gh_label_add o/r 8 mallory agent
  poll
  expect "a stranger's issue labelled by an allowed user: a run" "$(runs)" 1
  expect_ok "the labelled one is worked" test -f "$(idir 7)/started"
  expect_ok "labelled by a stranger: ignored, as before" test -f "$(idir 8)/ignored"
  expect_no_unexpected)

(world
  runs_do 'comment questions'
  all_on
  poll
  gh_issue o/r 7 alice
  gh_issue o/r 8 alice
  poll
  expect "two unlabelled issues: two runs" "$(runs)" 2
  gh_state o/r 7 closed
  gh_label_add o/r 8 alice wontfix
  poll
  expect "a closed unlabelled issue: done" "$(state 7 "done")" "issue closed"
  expect "wontfix on an unlabelled issue: off" "$(state 8 off)" "wontfix label added"
  gh_label_remove o/r 8 alice wontfix
  poll
  expect_ok "wontfix gone: back on" test ! -f "$(idir 8)/off"
  expect_no_unexpected)

(world
  runs_do 'comment questions'
  all_on
  poll
  gh_issue o/r 7 alice
  gh_comment o/r 7 alice "hello" >/dev/null
  poll
  expect "a comment on a worked unlabelled issue: the same run path" "$(runs)" 1
  gh_comment o/r 7 alice "and then?" >/dev/null
  poll
  expect "a later comment: a resumed run" "$(runs)" 2
  expect_no_unexpected)

report
