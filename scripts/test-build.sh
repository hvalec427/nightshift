#!/usr/bin/env bash
# Tests for the build session: an approved plan is built in a fresh session,
# not the planning one, and the runs after resume the build's.
#   bash scripts/test-build.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A first run that posts a plan, done, on an issue with a body.
planned() {
  gh_issue o/r 7 alice agent enhancement
  gh_edit "$(gh_dir o/r)/issues/7.json" '.body = "Make it faster."'
  runs_do 'skill nightshift:plan; comment plan "T1: the fast path."'
  poll
}

(world
  planned
  id=$(gh_comment o/r 7 alice "Go!")
  runs_do 'gh api "repos/$NIGHTSHIFT_REPO/issues/$NIGHTSHIFT_ISSUE" --jq ".labels[].name" >"$RUN/start"; comment progress'
  poll
  expect "go to a plan: a run" "$(runs)" 2
  expect "it's a fresh session" "$(run_opt --resume)" ""
  expect_line "the prompt: the plan is approved" "$(run_prompt)" "^The plan is approved: build it with the nightshift:build skill"
  expect_line "the prompt: the issue's title" "$(run_prompt)" "^Issue 7$"
  expect_line "the prompt: the issue's body" "$(run_prompt)" "^Make it faster\.$"
  expect_line "the prompt: the plan" "$(run_prompt)" "^T1: the fast path\.$"
  expect_line "the prompt: the approval" "$(run_prompt)" "^- @alice (comment $id):$"
  expect "while it runs: building" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/2/start")" "nightshift: building"
  expect_line "the prompt: not a first run" "$(run_prompt)" "first run" no
  expect "the planning session is kept" "$(state 7 plan-session)" session-1
  expect "the build's is the session now" "$(state 7 session)" session-2
  expect_ok "nothing is left pending" test ! -f "$(idir 7)/build"
  expect "the planning session's skill is cleared" "$(state 7 skill)" ""
  gh_comment o/r 7 alice "rename it" >/dev/null
  poll
  expect "a later comment resumes the build session" "$(run_opt --resume)" session-2
  expect "the planning session stays" "$(state 7 plan-session)" session-1
  expect_no_unexpected)

(world
  planned
  gh_comment o/r 7 alice "go, but call it fast" >/dev/null
  poll
  expect "more than go: the planning session resumes" "$(run_opt --resume)" session-1
  expect "no planning session kept" "$(state 7 plan-session)" "")

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  gh_comment o/r 7 alice "go" >/dev/null
  poll
  expect "go to questions: the session resumes" "$(run_opt --resume)" session-1)

(world
  planned
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do 'comment progress'
  poll
  gh_comment o/r 7 alice "go" >/dev/null
  poll
  expect "go again after the hand-off: the build session resumes" "$(run_opt --resume)" session-2
  expect "the planning session stays" "$(state 7 plan-session)" session-1)

(world
  planned
  echo "https://github.com/o/r/pull/9" >"$(idir 7)/pr"
  gh_comment o/r 7 alice "go" >/dev/null
  poll
  expect "with a pull request: the session resumes" "$(run_opt --resume)" session-1)

# Any other approval: the planning run hands off with `nightshift build`.
(world
  planned
  id=$(gh_comment o/r 7 alice "looks good, build it")
  runs_do 'nightshift build >"$RUN/said"; [ "$k" = 2 ] || comment progress'
  poll
  expect "the reply resumes the planning session" "$(run_opt --resume)" session-1
  expect_line "the run is told to end" "$(cat "$CLAUDE_FAKE/runs/2/said")" "fresh session"
  expect "the build waits: queued" "$(status_label 7)" queued
  poll
  expect "the next poll: the build run" "$(runs)" 3
  expect "it's a fresh session" "$(run_opt --resume)" ""
  expect_line "the prompt: the plan" "$(run_prompt)" "^T1: the fast path\.$"
  expect_line "the prompt: the approval" "$(run_prompt)" "^- @alice (comment $id):$"
  expect "the planning session is kept" "$(state 7 plan-session)" session-1
  expect "the build's is the session now" "$(state 7 session)" session-3
  expect_line "the build session builds" "$(cat "$CLAUDE_FAKE/runs/3/said")" "in this session"
  expect_ok "and hands nothing off" test ! -f "$(idir 7)/build"
  poll
  expect "then nothing new: no run" "$(runs)" 3
  expect_no_unexpected)

(world
  planned
  echo "https://github.com/o/r/pull/9" >"$(idir 7)/pr"
  gh_comment o/r 7 alice "build it" >/dev/null
  runs_do 'nightshift build >"$RUN/said"'
  poll
  expect_line "with a pull request: no hand-off" "$(cat "$CLAUDE_FAKE/runs/2/said")" "in this session"
  expect_ok "nothing pending" test ! -f "$(idir 7)/build")

(world
  gh_issue o/r 7 alice agent
  runs_do 'nightshift build >"$RUN/said"'
  poll
  expect_line "a first run: no hand-off" "$(cat "$CLAUDE_FAKE/runs/1/said")" "in this session"
  expect_ok "nothing pending" test ! -f "$(idir 7)/build")

report
