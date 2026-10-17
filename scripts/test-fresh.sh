#!/usr/bin/env bash
# Tests for a fresh session once the last one's context is half the window:
# the run starts without --resume, with a summary prompt, and the old session
# id is kept in `sessions`.
#   bash scripts/test-fresh.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A first run that ends with a context of $1 tokens, in a window of $2.
first() {
  gh_issue o/r 7 alice agent enhancement
  gh_edit "$(gh_dir o/r)/issues/7.json" '.body = "Make it faster."'
  runs_do "window $OPUS $2; turn $OPUS $1 0 0; comment questions"
  poll
}

(world
  first 500 1000
  id=$(gh_comment o/r 7 alice "1 yes")
  runs_do "window $OPUS 1000; turn $OPUS 100 0 0; comment progress"
  poll
  prompt=$(run_prompt)
  expect "half the window: a run" "$(runs)" 2
  expect "it's a fresh session" "$(run_opt --resume)" ""
  expect_line "the prompt: why" "$prompt" "^This is a fresh session: .*context grew large"
  expect_line "the prompt: the issue's title" "$prompt" "^Issue 7$"
  expect_line "the prompt: the issue's body" "$prompt" "^Make it faster\.$"
  expect_line "the prompt: the thread holds the rest" "$prompt" "thread holds the rest"
  expect_line "the prompt: the news" "$prompt" "^- @alice (comment $id):$"
  expect_line "the prompt: no plan yet" "$prompt" "^The latest plan:$" no
  expect_line "the prompt: no pull request yet" "$prompt" "^The pull request:" no
  expect_line "the prompt: not a first run" "$prompt" "first run" no
  expect "the old session is kept" "$(state 7 sessions)" session-1
  expect "the new one is the session" "$(state 7 session)" session-2
  gh_comment o/r 7 alice "ok" >/dev/null
  poll
  expect "the next run resumes the new session" "$(run_opt --resume)" session-2
  expect_no_unexpected)

# The plan and the pull request are in the prompt; sessions add up, oldest first.
(world
  first 100 1000
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "window $OPUS 1000; turn $OPUS 500 0 0; comment plan 'T1: the fast path.'"
  poll
  expect "below half: it resumes" "$(run_opt --resume)" session-1
  expect "nothing kept yet" "$(state 7 sessions)" ""
  echo "https://github.com/o/r/pull/9" >"$(idir 7)/pr"
  gh_comment o/r 7 alice "rename it" >/dev/null
  runs_do "window $OPUS 1000; turn $OPUS 500 0 0; comment progress"
  poll
  prompt=$(run_prompt)
  expect "at exactly half: a fresh session" "$(run_opt --resume)" ""
  expect_line "the prompt: the plan" "$prompt" "^T1: the fast path\.$"
  expect_line "the prompt: the pull request" "$prompt" "^The pull request: https://github.com/o/r/pull/9$"
  expect "the old session is kept" "$(state 7 sessions)" session-1
  gh_comment o/r 7 alice "again" >/dev/null
  poll
  expect "and again: another fresh session" "$(run_opt --resume)" ""
  expect "the sessions, oldest first" "$(state 7 sessions | paste -sd, -)" session-1,session-3)

# A fresh session's run without a turn doesn't leave it on the old figure.
(world
  first 500 1000
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do 'comment progress'
  poll
  expect "a fresh session" "$(run_opt --resume)" ""
  gh_comment o/r 7 alice "ok" >/dev/null
  poll
  expect "the next run resumes it" "$(run_opt --resume)" session-2
  expect "one session kept" "$(state 7 sessions)" session-1)

# An unknown window never resets.
(world
  first 900000 0
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "an unknown window: it resumes" "$(run_opt --resume)" session-1
  expect "nothing kept" "$(state 7 sessions)" "")

# No context yet (a run without a turn): it resumes.
(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "no context: it resumes" "$(run_opt --resume)" session-1)

# A stopped run resumes, whatever its size.
(world
  first 900 1000
  echo "label removed" >"$(idir 7)/interrupted"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do 'comment progress'
  poll
  expect "interrupted: it resumes" "$(run_opt --resume)" session-1
  expect_line "told to carry on" "$(run_prompt)" "carry on from where it stopped"
  expect "nothing kept" "$(state 7 sessions)" "")

# So does a stalled one.
(world
  gh_issue o/r 7 alice agent
  runs_do "window $OPUS 1000; turn $OPUS 900 0 0; label building"
  poll
  runs_do 'comment progress'
  poll
  expect "stalled: it resumes" "$(run_opt --resume)" session-1
  expect_line "told to carry on" "$(run_prompt)" "^Your last run ended without finishing"
  expect "nothing kept" "$(state 7 sessions)" "")

# "go" after a reset hands off to a fresh build session; the sessions stay
# once the issue is done.
(world
  gh_issue o/r 7 alice agent enhancement
  runs_do "window $OPUS 1000; turn $OPUS 600 0 0; skill nightshift:plan; comment plan 'T1: the fast path.'"
  poll
  gh_comment o/r 7 alice "can it be cached too?" >/dev/null
  runs_do 'comment plan "T1: the cached fast path."'
  poll
  expect "after the reset: a fresh session" "$(run_opt --resume)" ""
  expect "the planning session is kept" "$(state 7 sessions)" session-1
  runs_do 'comment progress'
  gh_comment o/r 7 alice "go" >/dev/null
  poll
  expect "go: a run" "$(runs)" 3
  expect "a fresh build session" "$(run_opt --resume)" ""
  expect_line "the prompt: the plan is approved" "$(run_prompt)" "^The plan is approved: build it with the nightshift:build skill"
  expect_line "the latest plan" "$(run_prompt)" "^T1: the cached fast path\.$"
  expect "the session after the reset is the planning one" "$(state 7 plan-session)" session-2
  expect "the build's is the session" "$(state 7 session)" session-3
  gh_state o/r 7 closed
  poll
  expect_ok "done" test -f "$(idir 7)/done"
  expect "the old sessions stay" "$(state 7 sessions)" session-1)

report
