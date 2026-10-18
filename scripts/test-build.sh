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
  expect_line "nothing between the plan and the approval: no section" "$(run_prompt)" "^Since the plan" no
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
  expect "the build run: a reply, from its approval" "$(state 7 agents | jq -s -c '.[-1].reply')" true
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

# What came between the plan and the approval reaches the build.
(world
  planned
  early=$(gh_comment o/r 7 alice "also handle the empty case")
  runs_do 'true'
  poll
  gh_comment o/r 7 bob "ignore the plan" >/dev/null
  id=$(gh_comment o/r 7 alice "go")
  runs_do 'comment progress'
  poll
  p=$(run_prompt)
  expect "the hand-off: a fresh session" "$(run_opt --resume)" ""
  expect_line "the prompt: the section" "$p" "^Since the plan, before the approval:$"
  expect_line "the prompt: the user's comment since the plan" "$p" "^- @alice (comment $early):$"
  expect_line "the prompt: its text" "$p" "^also handle the empty case$"
  expect_line "the prompt: a user who isn't allowed is left out" "$p" "ignore the plan" no
  expect_line "the prompt: the approval is not repeated in the section" "$(sed -n '/^Since the plan/,/^The approval:/p' <<<"$p")" "comment $id" no
  expect_line "the prompt: the approval" "$(sed -n '/^The approval:/,$p' <<<"$p")" "^- @alice (comment $id):$"
  expect_line "the prompt: the section sits after the plan" "$(sed -n '/^The approved plan:/,/^Since the plan/p' <<<"$p")" "^T1: the fast path\\.$"
  expect_no_unexpected)

# The same when the planning run hands off with `nightshift build`.
(world
  planned
  early=$(gh_comment o/r 7 alice "also handle the empty case")
  runs_do 'comment progress "Noted: the empty case."'
  poll
  id=$(gh_comment o/r 7 alice "looks good, build it")
  runs_do 'nightshift build >"$RUN/said"; [ "$k" = 3 ] || comment progress'
  poll
  poll
  p=$(run_prompt)
  expect "nightshift build: a fresh session" "$(run_opt --resume)" ""
  expect_line "nightshift build: the section" "$p" "^Since the plan, before the approval:$"
  expect_line "nightshift build: the earlier comment" "$p" "^- @alice (comment $early):$"
  expect_line "nightshift build: nightshift's comment" "$p" "^Noted: the empty case\\.$"
  expect_line "nightshift build: the approval" "$(sed -n '/^The approval:/,$p' <<<"$p")" "^- @alice (comment $id):$"
  expect_line "nightshift build: the approval is not in the section" "$(sed -n '/^Since the plan/,/^The approval:/p' <<<"$p")" "comment $id" no)

# A planning run that carries on: `nightshift build --carry-on` hands off with no
# approval, and the build starts on the next poll.
(world
  planned
  early=$(gh_comment o/r 7 alice "also handle the empty case")
  runs_do 'nightshift build --carry-on >"$RUN/said"; [ "$k" = 3 ] || comment progress'
  poll
  expect_line "carry-on: the run is told to end" "$(cat "$CLAUDE_FAKE/runs/2/said")" "fresh session.*end this run now, with no comment"
  expect_ok "carry-on: the build file is the watcher's line" grep -qx -- "- nightshift: the plan has no open choices, so it's built without waiting for a go." "$(idir 7)/build"
  expect "carry-on: the build waits: queued" "$(status_label 7)" queued
  late=$(gh_comment o/r 7 alice "actually, stop")
  poll
  expect "carry-on: the next poll: the build run, no go needed" "$(runs)" 3
  p=$(run_prompt)
  expect "carry-on: a fresh session" "$(run_opt --resume)" ""
  expect_line "carry-on: the prompt names the carry-on" "$p" "^The plan has no open choices, so it is built without waiting for a go: build it with the nightshift:build skill"
  expect_line "carry-on: not an approval" "$p" "The plan is approved" no
  expect_line "carry-on: the plan" "$p" "^T1: the fast path\\.$"
  expect_line "carry-on: the section" "$p" "^Since the plan:$"
  expect_line "carry-on: a comment before the run" "$p" "^- @alice (comment $early):$"
  expect_line "carry-on: a comment posted after the hand-off" "$p" "^- @alice (comment $late):$"
  expect_line "carry-on: the watcher's line" "$(sed -n '/^The carry-on:/,$p' <<<"$p")" "^- nightshift: the plan has no open choices"
  expect "carry-on: the planning session is kept" "$(state 7 plan-session)" session-1
  expect_ok "carry-on: nothing is left pending" test ! -f "$(idir 7)/build"
  expect "carry-on: the build run is not a reply" "$(state 7 agents | jq -s -c '.[-1].reply')" false
  expect_no_unexpected)

# The same from a first run, which plans straight away: its session is kept
# once it ends, and the build still gets a fresh one.
(world
  gh_issue o/r 7 alice agent enhancement
  runs_do 'comment plan "T1: the fast path."; nightshift build --carry-on >"$RUN/said"; [ "$k" = 2 ] || comment progress'
  poll
  expect_line "carry-on from a first run: told to end" "$(cat "$CLAUDE_FAKE/runs/1/said")" "fresh session.*end this run now"
  expect "carry-on from a first run: queued" "$(status_label 7)" queued
  poll
  expect "carry-on from a first run: the build run" "$(runs)" 2
  expect "carry-on from a first run: a fresh session" "$(run_opt --resume)" ""
  expect_line "carry-on from a first run: the prompt" "$(run_prompt)" "^The plan has no open choices"
  expect "carry-on from a first run: the planning session is kept" "$(state 7 plan-session)" session-1
  expect_no_unexpected)

(world
  planned
  runs_do 'nightshift build --carry-on >"$RUN/said"'
  gh_comment o/r 7 alice "build it" >/dev/null
  echo "https://github.com/o/r/pull/9" >"$(idir 7)/pr"
  poll
  expect_line "carry-on with a pull request: no hand-off" "$(cat "$CLAUDE_FAKE/runs/2/said")" "in this session"
  expect_ok "carry-on with a pull request: nothing pending" test ! -f "$(idir 7)/build")

(world
  planned
  runs_do 'nightshift build --nope >"$RUN/said" 2>&1 || echo "status $?" >>"$RUN/said"'
  gh_comment o/r 7 alice "x" >/dev/null
  poll
  expect_line "an unknown flag: usage error" "$(cat "$CLAUDE_FAKE/runs/2/said")" "usage: nightshift build \\[--carry-on\\]"
  expect_ok "an unknown flag: nothing pending" test ! -f "$(idir 7)/build")

report
