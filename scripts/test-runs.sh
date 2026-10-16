#!/usr/bin/env bash
# Tests for an issue's first run: who starts one, its worktree, what Claude is
# given, the status labels, and how many run at once.
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
  expect "no --resume on a first run" "$(run_opt --resume)" ""
  expect "the permission mode: auto by default" "$(run_opt --permission-mode)" auto
  expect "stream-json out" "$(run_opt --output-format)" stream-json
  expect "the run knows its issue" "$(grep -E '^NIGHTSHIFT_(ISSUE|REPO)=' "$CLAUDE_FAKE/runs/1/env")" "NIGHTSHIFT_ISSUE=7
NIGHTSHIFT_REPO=o/r"
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
  expect "the status labels are created" "$(sort "$(gh_dir o/r)/labels" | tr '\n' ,)" \
    "nightshift: PR open,nightshift: building,nightshift: needs you,nightshift: planning,nightshift: queued,nightshift: stopped,nightshift: thinking,nightshift: updating,"
  poll
  expect "nothing new: no run" "$(runs)" 1
  expect "the status labels are created once" "$(gh_calls '^label create' | wc -l | tr -d ' ')" 8
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do 'label planning; '"$LABELS_NOW"'planning"; comment plan'
  poll
  expect "nightshift label in a run sets it" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/1/planning")" "nightshift: planning"
  expect "after a plan: needs you" "$(status_label 7)" "needs you"
  expect_line "the prompt: no type label" "$(run_prompt)" "^It has no type label\.$"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do ''
  poll
  expect "a run that posts nothing: needs you" "$(status_label 7)" "needs you")

# Who may start work.
(world
  gh_issue o/r 7 bob agent
  poll
  expect "labelled by someone not allowed: no run" "$(runs)" 0
  expect_ok "it's marked ignored" test -f "$(idir 7)/ignored"
  expect_line "the watch log says why" "$(cat "$NS/watch.log")" "o/r#7: labelled by bob, not an allowed user: ignored"
  gh_comment o/r 7 alice "please do it" >/dev/null
  poll
  expect "an ignored issue stays ignored" "$(runs)" 0
  expect "an ignored issue gets no status label" "$(status_label 7)" ""
  expect_no_unexpected)

(world
  set_config allowed_users "alice, bob"
  gh_issue o/r 7 bob agent
  poll
  expect "allowed_users: anyone listed starts work" "$(runs)" 1
  expect "allowed_users: gh's own login isn't asked" "$(gh_calls '^api user' | wc -l | tr -d ' ')" 0)

(world
  gh_issue o/r 7 alice bug
  poll
  expect "no agent label: no run" "$(runs)" 0)

# How many run at once.
(world
  set_config max_parallel 1
  gh_issue o/r 7 alice agent
  gh_issue o/r 8 alice agent
  runs_do 'comment questions'
  poll
  expect "max_parallel 1: one run" "$(runs)" 1
  expect "the other one waits, queued" "$(status_label 7)$(status_label 8)" "queuedneeds you"
  poll
  expect "the next poll starts it" "$(runs)" 2
  expect "both done: needs you" "$(status_label 7),$(status_label 8)" "needs you,needs you")

# What a run is isolated from.
(world
  gh_issue o/r 7 alice agent
  poll
  expect_line "no plugin copy: says the run isn't isolated" "$(cat "$(idir 7)/log")" "run install.sh again): this run isn't isolated"
  expect "no plugin copy: no --setting-sources" "$(run_opt --setting-sources)" ""
  expect "no plugin copy, no instructions.md: nothing appended" "$(run_opt --append-system-prompt)" "")

(world
  echo "Write in Slovenian." >"$NS/instructions.md"
  gh_issue o/r 7 alice agent
  poll
  expect "no plugin copy: this machine's instructions alone" "$(run_opt --append-system-prompt)" "Write in Slovenian.")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  gh_issue o/r 7 alice agent
  poll
  expect "isolated: only the project's settings" "$(run_opt --setting-sources)" "project,local"
  expect "isolated: attribution off" "$(run_opt --settings)" '{"attribution":{"commit":"","pr":""}}'
  expect "isolated: nightshift's plugin" "$(run_opt --plugin-dir)" "$NS/plugin"
  expect "isolated: nightshift's instructions" "$(run_opt --append-system-prompt)" "$(cat "$ROOT/plugin/instructions.md")"
  expect_line "the allowed tools: nightshift label" "$(run_args)" "^Bash(nightshift$")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  mkdir -p "$W/rn-agent"
  printf '[{"id":"rn-agent@hvalec427","enabled":true,"installPath":"%s"}]\n' "$W/rn-agent" >"$CLAUDE_FAKE/plugins.json"
  gh_issue o/r 7 alice agent
  poll
  expect "rn-agent installed: its plugin too" "$(run_args | grep -A1 -x -- --plugin-dir | grep -v -- -- | tr '\n' ' ')" "$NS/plugin $W/rn-agent ")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  set_config isolated false
  set_config permission_mode bypassPermissions
  gh_issue o/r 7 alice agent
  poll
  expect "isolated false: no --setting-sources" "$(run_opt --setting-sources)" ""
  expect "isolated false: no --plugin-dir" "$(run_opt --plugin-dir)" ""
  expect "isolated false: still the instructions" "$(run_opt --append-system-prompt)" "$(cat "$ROOT/plugin/instructions.md")"
  expect "permission_mode from the config" "$(run_opt --permission-mode)" bypassPermissions)

report
