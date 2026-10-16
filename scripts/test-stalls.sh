#!/usr/bin/env bash
# Tests for a stalled run: one that ends while building or updating without
# commenting (it stopped to wait on something, but a run ends when it stops)
# is resumed, told to carry on.
#   bash scripts/test-stalls.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

STALL_LINE="^Your last run ended without finishing (it stopped, maybe to wait on something, but a run ends when you stop); carry on from where it stopped\.$"

(world
  gh_issue o/r 7 alice agent
  runs_do 'label building; [ "$k" = 1 ] || comment progress'
  poll
  expect "a building run that ends without a comment: queued" "$(status_label 7)" queued
  expect_line "status: queued to resume" "$(ns status)" "^o/r#7  *queued to resume"
  poll
  expect "the next poll resumes it" "$(runs)" 2
  expect "in its session" "$(run_opt --resume)" session-1
  expect_line "told to carry on" "$(run_prompt)" "$STALL_LINE"
  expect "it commented: needs you" "$(status_label 7)" "needs you"
  poll
  expect "then nothing new: no run" "$(runs)" 2
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do 'label building; [ "$k" = 1 ] || comment progress'
  poll
  id=$(gh_comment o/r 7 alice "also rename it")
  poll
  expect "a comment meanwhile: one resumed run" "$(runs)" 2
  prompt=$(run_prompt)
  expect_line "told to carry on" "$prompt" "$STALL_LINE"
  expect_line "then the comment, after it" "$(printf '%s\n' "$prompt" | sed -n '/^Your last run ended/,$p')" "^- @alice (comment $id):$")

(world
  gh_issue o/r 7 alice agent
  runs_do 'label building'
  poll
  poll
  expect "stalled again: resumed once" "$(runs)" 2
  poll
  expect "and not again" "$(runs)" 2
  expect_line "status: no longer queued to resume" "$(ns status)" "queued to resume" no)

# An updating run: an update of the open pull request.
(world
  gh_issue o/r 7 alice agent
  runs_do 'case $k in
    1) label building; commit feature.txt; open_pr; comment done ;;
    2) ;;
    *) comment progress ;;
    esac'
  poll
  pr=$(state 7 pr)
  gh_pr_set o/r "${pr##*/}" mergeable '"CONFLICTING"'
  poll
  expect "a conflict: an update run" "$(runs)" 2
  poll
  expect "an updating run that ends without a comment: resumed" "$(runs)" 3
  expect "in its session" "$(run_opt --resume)" session-1
  expect_line "told to carry on" "$(run_prompt)" "$STALL_LINE"
  poll
  expect "then nothing new: no run" "$(runs)" 3)

# Runs that didn't stall.
(world
  gh_issue o/r 7 alice agent
  runs_do 'label building; comment progress'
  poll
  poll
  expect "a building run that commented: no resume" "$(runs)" 1)

(world
  gh_issue o/r 7 alice agent
  runs_do 'label planning'
  poll
  poll
  expect "a run that wasn't building: no resume" "$(runs)" 1
  expect "it needs you" "$(status_label 7)" "needs you")

(world
  gh_issue o/r 7 alice agent
  runs_do 'label building; fail_result'
  poll
  poll
  expect "a building run that failed: no resume" "$(runs)" 1)

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment plan "T1: the fast path."'
  poll
  gh_comment o/r 7 alice "looks good, build it" >/dev/null
  runs_do 'label building; nightshift build >/dev/null; [ "$k" = 2 ] || comment progress'
  poll
  poll
  expect "a build hand-off: the build run" "$(runs)" 3
  expect "a fresh session" "$(run_opt --resume)" ""
  expect_line "not told it stalled" "$(run_prompt)" "^Your last run ended" no
  poll
  expect "then nothing new: no run" "$(runs)" 3
  expect_no_unexpected)

report
