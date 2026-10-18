#!/usr/bin/env bash
# Tests for an issue's first run: its worktree, what Claude is given, and the
# status labels a run sets as it goes.
#   bash scripts/test-runs.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# The issue's labels on GitHub as a run sees them, into $RUN/<name>.
LABELS_NOW='gh api "repos/$NIGHTSHIFT_REPO/issues/$NIGHTSHIFT_ISSUE" --jq ".labels[].name" >"$RUN/'

(world
  gh_issue o/r 7 alice agent bug
  runs_do "$LABELS_NOW"'start"; say "Reading the code."; comment questions'
  poll
  wt="$CLONE/.claude/worktrees/issue-7"
  expect "labelled by an allowed user: a run" "$(runs)" 1
  expect "the run works in the issue's worktree" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$wt"
  expect "the worktree is on the issue's branch" "$(git -C "$wt" branch --show-current)" "nightshift/issue-7"
  expect "the branch starts at the default branch" "$(git -C "$wt" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse master)"
  expect_line "the worktrees stay out of the clone's git status" \
    "$(cat "$(git -C "$CLONE" rev-parse --path-format=absolute --git-common-dir)/info/exclude")" "^\.claude/worktrees/$"
  expect_line "the prompt: the issue" "$(run_prompt)" "^You are nightshift, working GitHub issue #7 in o/r, unattended"
  expect_line "the prompt: its type" "$(run_prompt)" '^Its type label: `bug`\.$'
  expect_line "the prompt: a first run" "$(run_prompt)" "^This is your first run for this issue\.$"
  expect_line "the prompt: a plain repo line auto-merges" "$(run_prompt)" \
    "^This repo auto-merges: once its pull request is open or updated, use the merge skill\.$"
  expect "no --resume on a first run" "$(run_opt --resume)" ""
  expect "the permission mode: auto" "$(run_opt --permission-mode)" auto
  expect "no model set: no --model" "$(run_opt --model)" ""
  expect "no effort set: no --effort" "$(run_opt --effort)" ""
  expect "stream-json out" "$(run_opt --output-format)" stream-json
  expect "the run knows its issue" "$(grep -E '^NIGHTSHIFT_(ISSUE|REPO)=' "$CLAUDE_FAKE/runs/1/env")" "NIGHTSHIFT_ISSUE=7
NIGHTSHIFT_REPO=o/r"
  expect "git's editors are off in a run" "$(grep -E '^GIT_(SEQUENCE_)?EDITOR=' "$CLAUDE_FAKE/runs/1/env")" "GIT_EDITOR=true
GIT_SEQUENCE_EDITOR=true"
  expect "while it runs: thinking" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/start")" "nightshift: thinking"
  expect "after questions: needs you" "$(status_label 7)" "needs you"
  expect "its session is kept" "$(state 7 session)" session-1
  expect "its type is kept" "$(state 7 type)" bug
  expect_ok "the run is marked finished" test -f "$(idir 7)/finished"
  expect_ok "no pid once it's done" test ! -f "$(idir 7)/pid"
  log=$(cat "$(idir 7)/log")
  expect_line "its log: the run" "$log" "^0	=== [0-9-]* [0-9:]* run$"
  expect_line "its log: the agent's text" "$log" "^1	[0-9:]* Reading the code\.$"
  expect_line "its log: the comment and its stage" "$log" "^0	[0-9:]* commented (questions)$"
  expect_line "its log: how it ended" "$log" "^0	=== [0-9:]* run done in [0-9]*s$"
  expect_line "watch.log: the run, with the issue" "$(cat "$NS/watch.log")" "o/r#7: run done in"
  expect "the status labels are created" "$(LC_ALL=C sort "$(gh_dir o/r)/labels" | tr '\n' ,)" \
    "nightshift: PR open,nightshift: answering,nightshift: building,nightshift: merging,nightshift: needs you,nightshift: planning,nightshift: proposed,nightshift: queued,nightshift: stopped,nightshift: thinking,nightshift: updating,nightshift: waiting,"
  poll
  expect "nothing new: no run" "$(runs)" 1
  expect "the status labels are created once" "$(gh_calls '^label create' | wc -l | tr -d ' ')" 12
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do 'label planning; '"$LABELS_NOW"'planning"; comment plan'
  poll
  expect "nightshift label in a run sets it" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/planning")" "nightshift: planning"
  expect "after a plan: needs you" "$(status_label 7)" "needs you"
  expect_line "the prompt: no type label" "$(run_prompt)" "^It has no type label\.$"
  expect_no_unexpected)

# The skill a run is in: its status label, its skill file and its log.
# (The watcher sets the label as the stream goes by, so wait for it.)
AT_LABEL='i=0; until gh api "repos/$NIGHTSHIFT_REPO/issues/$NIGHTSHIFT_ISSUE" --jq ".labels[].name" | grep -qx "nightshift: $1" || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done'
(world
  gh_issue o/r 7 alice agent
  runs_do 'at() { '"$AT_LABEL"'; '"$LABELS_NOW"'$2"; }
    skill nightshift:issue; sleep 0.3; '"$LABELS_NOW"'issue"
    skill nightshift:plan; at planning plan
    skill other:thing; sleep 0.3; '"$LABELS_NOW"'other"
    skill nightshift:build; at building build
    comment plan'
  poll
  expect "the issue skill: the label as it was" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/issue")" "nightshift: thinking"
  expect "the plan skill: planning" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/plan")" "nightshift: planning"
  expect "another plugin's skill: the label as it was" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/other")" "nightshift: planning"
  expect "the build skill: building" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/build")" "nightshift: building"
  expect "the skill is kept: the last nightshift one" "$(state 7 skill)" "nightshift:build"
  log=$(cat "$(idir 7)/log")
  expect_line "its log: the skill, at the runs level" "$log" "^0	[0-9:]* skill nightshift:plan$"
  expect_line "its log: not the issue skill" "$log" "skill nightshift:issue$" no
  expect_line "watch.log: the skill, with the issue" "$(cat "$NS/watch.log")" "o/r#7: skill nightshift:build$"
  expect "after the run: from its comment" "$(status_label 7)" "needs you"
  runs_do ''
  gh_comment o/r 7 alice "and?" >/dev/null
  poll
  expect "a resumed run: the last one's skill is kept" "$(state 7 skill)" "nightshift:build"
  expect_no_unexpected)

# A resumed session has its skill loaded already, so it starts at that skill's
# label: the label a resumed run starts at, after a first run doing $1.
resumed_label() {
  gh_issue o/r 7 alice agent
  runs_do "$1; comment questions"
  poll
  runs_do "$LABELS_NOW"'start"'
  gh_comment o/r 7 alice "and?" >/dev/null
  poll
  grep '^nightshift: ' "$CLAUDE_FAKE/runs/2/start"
}
(world
  expect "a resumed build run: building from the start" "$(resumed_label 'skill nightshift:build')" "nightshift: building"
  expect "the reply resumes the session" "$(run_opt --resume)" session-1
  gh_comment o/r 7 alice "and?" >/dev/null
  poll
  expect "resumed again, with no skill: still building" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/3/start")" "nightshift: building"
  expect "resumed again: the skill is kept" "$(state 7 skill)" "nightshift:build"
  expect_no_unexpected)
(world
  expect "a resumed tdd run: building from the start" "$(resumed_label 'skill nightshift:tdd')" "nightshift: building"
  expect_no_unexpected)
(world
  gh_issue o/r 7 alice agent bug
  runs_do 'at() { '"$AT_LABEL"'; '"$LABELS_NOW"'$2"; }
    skill nightshift:plan; at planning plan
    skill nightshift:diagnose; at thinking diagnose
    comment questions'
  poll
  expect "the diagnose skill: thinking, not the last skill's planning" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/diagnose")" "nightshift: thinking"
  expect "the diagnose skill is kept" "$(state 7 skill)" "nightshift:diagnose"
  expect_no_unexpected)
(world
  expect "a resumed run after diagnose: thinking from the start" "$(resumed_label 'skill nightshift:plan; skill nightshift:diagnose')" "nightshift: thinking"
  expect_no_unexpected)
(world
  expect "a resumed plan run: planning from the start" "$(resumed_label 'skill nightshift:plan')" "nightshift: planning"
  expect_no_unexpected)
(world
  expect "a resumed run with no skill: thinking" "$(resumed_label 'say hi')" "nightshift: thinking"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent question
  runs_do 'at() { '"$AT_LABEL"'; '"$LABELS_NOW"'$2"; }
    skill nightshift:answer; at answering answer'
  poll
  expect "the answer skill: answering" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/answer")" "nightshift: answering")

(world
  gh_issue o/r 7 alice agent
  runs_do 'at() { '"$AT_LABEL"'; '"$LABELS_NOW"'$2"; }
    skill nightshift:merge; at merging merge
    comment look'
  poll
  expect "the merge skill: merging" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/merge")" "nightshift: merging"
  expect "a run ending on a look comment: needs you" "$(status_label 7)" "needs you")

(world
  gh_issue o/r 7 alice agent
  runs_do 'at() { '"$AT_LABEL"'; '"$LABELS_NOW"'$2"; }
    skill nightshift:plan; at planning plan
    skill nightshift:review; at building review'
  poll
  expect "the review skill: building" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/review")" "nightshift: building")

(world
  gh_issue o/r 7 alice agent
  runs_do ''
  poll
  expect "a run that posts nothing: needs you" "$(status_label 7)" "needs you")

# A reply to a run that needs you: the label goes as the watcher sees it,
# before the run sets its own.
(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  runs_do "$LABELS_NOW"'start"'
  : >"$GH_FAKE/calls"
  gh_comment o/r 7 alice "yes, both" >/dev/null
  poll
  expect "a reply: needs you removed first, nothing added" \
    "$(gh_calls '^issue edit' | head -1)" "issue edit 7 --repo o/r --remove-label nightshift: needs you"
  expect "then the run's own status" "$(gh_calls '^issue edit' | sed -n 2p)" "issue edit 7 --repo o/r --add-label nightshift: thinking"
  expect "while it runs: thinking" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/2/start")" "nightshift: thinking"
  expect_no_unexpected)

report
