#!/usr/bin/env bash
# Tests for a stalled run: one that ends while building, updating or merging
# without commenting (it stopped to wait on something, but a run ends when it
# stops) is resumed, told to carry on; a second stall in a row asks the user.
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
  expect_line "status: no longer queued to resume" "$(ns status)" "queued to resume" no
  expect "the issue is told, once" "$(gh_comments o/r 7 | grep -c "the last run stalled twice")" 1
  expect_line "to reply to carry on" "$(gh_comments o/r 7)" "Reply to carry on\.$"
  expect_line "the comment is nightshift's" "$(gh_comments o/r 7)" "<!-- nightshift -->"
  expect "it needs you" "$(status_label 7)" "needs you"
  runs_do 'comment progress'
  id=$(gh_comment o/r 7 alice "go on")
  poll
  expect "a reply: a resumed run" "$(runs)" 3
  expect "in its session" "$(run_opt --resume)" session-1
  prompt=$(run_prompt)
  expect_line "not told it stalled" "$prompt" "^Your last run ended" no
  expect_line "told the reply" "$prompt" "^- @alice (comment $id):$"
  poll
  expect "then nothing new: no run" "$(runs)" 3
  expect "the stall comment isn't news" "$(gh_comments o/r 7 | grep -c "the last run stalled twice")" 1
  expect_no_unexpected)

# Stalled twice while updating, with a pull request open: it needs you too.
(world
  gh_issue o/r 7 alice agent
  runs_do 'case $k in
    1) label building; commit feature.txt; open_pr; comment done ;;
    *) ;;
    esac'
  poll
  pr=$(state 7 pr)
  gh_pr_set o/r "${pr##*/}" mergeable '"CONFLICTING"'
  poll
  poll
  expect "an update that stalled twice: no more runs" "$(runs)" 3
  expect_line "the issue is told" "$(gh_comments o/r 7)" "the last run stalled twice"
  expect "it needs you" "$(status_label 7)" "needs you")

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

# A run that went on to merge its pull request and stopped to wait on its checks.
(world
  gh_issue o/r 7 alice agent
  runs_do 'case $k in
    1) label building; commit feature.txt; open_pr; label merging ;;
    *) comment done ;;
    esac'
  poll
  poll
  expect "a merging run that ends without a comment: resumed" "$(runs)" 2
  expect_line "told to carry on" "$(run_prompt)" "$STALL_LINE")

# A resumed run that ends any other way: a later stall is a first one again.
# $1 says how, $2 what run 2 (the resumed one) does.
stall_after() {
  (world
    gh_issue o/r 7 alice agent
    runs_do 'case $k in
      1 | 3) label building ;;
      2) '"$2"' ;;
      *) comment progress ;;
      esac'
    poll
    if [ "$1" = stopped ]; then
      "$ROOT/nightshift" once &
      bg=$!
      wait_for "$CLAUDE_FAKE/runs/2/waiting"
      ns stop o/r#7 >/dev/null
      wait "$bg"
    else
      poll
    fi
    gh_comment o/r 7 alice "go on" >/dev/null
    poll
    poll
    expect "resumed run $1, then a stall: resumed" "$(runs)" 4
    expect_line "told to carry on" "$(run_prompt)" "$STALL_LINE"
    expect "not stalled twice" "$(gh_comments o/r 7 | grep -c "stalled twice" || true)" 0)
}
stall_after commented 'comment progress'
stall_after failed fail_result
stall_after stopped hang

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
