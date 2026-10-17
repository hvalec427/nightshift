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
  expect_line "the prompt: a plain repo line auto-merges" "$(run_prompt)" \
    "^This repo auto-merges: once its pull request is open or updated, use the merge skill\.$"
  expect "no --resume on a first run" "$(run_opt --resume)" ""
  expect "the permission mode: auto" "$(run_opt --permission-mode)" auto
  expect "no model set: no --model" "$(run_opt --model)" ""
  expect "no effort set: no --effort" "$(run_opt --effort)" ""
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
  expect "the status labels are created" "$(LC_ALL=C sort "$(gh_dir o/r)/labels" | tr '\n' ,)" \
    "nightshift: PR open,nightshift: answering,nightshift: building,nightshift: merging,nightshift: needs you,nightshift: planning,nightshift: proposed,nightshift: queued,nightshift: stopped,nightshift: thinking,nightshift: updating,"
  poll
  expect "nothing new: no run" "$(runs)" 1
  expect "the status labels are created once" "$(gh_calls '^label create' | wc -l | tr -d ' ')" 11
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
  printf 'repo %s %s auto_merge=false\n' "$REPO" "$CLONE" >"$NS/config"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "auto_merge=false: the run still works in the clone's worktree" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$CLONE/.claude/worktrees/issue-7"
  expect_line "the prompt: auto_merge=false doesn't auto-merge" "$(run_prompt)" \
    "^This repo doesn't auto-merge (auto_merge=false): leave merging to the user\.$")

(world
  printf 'repo %s %s auto_merge=no\n' "$REPO" "$CLONE" >"$NS/config"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "the prompt: only auto_merge=false turns it off" "$(run_prompt)" \
    "^This repo auto-merges: once its pull request is open or updated, use the merge skill\.$")

(world
  echo "Use tabs." >"$W/ours.md"
  printf 'repo %s %s auto_merge=false instructions=%s\n' "$REPO" "$CLONE" "$W/ours.md" >"$NS/config"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "the prompt: auto_merge=false beside another option" "$(run_prompt)" \
    "^This repo doesn't auto-merge (auto_merge=false): leave merging to the user\.$")

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
  expect "no plugin copy: still the clone's CLAUDE.md and CLAUDE.local.md excluded" "$(run_opt --settings)" \
    "{\"claudeMdExcludes\":[\"$CLONE/CLAUDE.md\",\"$CLONE/.claude/CLAUDE.md\",\"$CLONE/CLAUDE.local.md\"]}"
  expect_ok "no plugin copy: no CLAUDE.local.md" test ! -e "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  echo "Write in Slovenian." >"$NS/instructions.md"
  gh_issue o/r 7 alice agent
  poll
  expect "this machine's instructions.md: still only nightshift's defaults" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "$(cat "$ROOT/plugin/instructions.md")")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  gh_issue o/r 7 alice agent
  poll
  expect "isolated: only the project's settings" "$(run_opt --setting-sources)" "project,local"
  expect "isolated: attribution off, the clone's CLAUDE.md and CLAUDE.local.md excluded" "$(run_opt --settings)" \
    "{\"attribution\":{\"commit\":\"\",\"pr\":\"\"},\"claudeMdExcludes\":[\"$CLONE/CLAUDE.md\",\"$CLONE/.claude/CLAUDE.md\",\"$CLONE/CLAUDE.local.md\"]}"
  expect "isolated: nightshift's plugin" "$(run_opt --plugin-dir)" "$NS/plugin"
  expect "no instructions in the system prompt" "$(run_args | grep -cx -- --append-system-prompt)" 0
  expect "the run's CLAUDE.local.md: nightshift's instructions" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "$(cat "$ROOT/plugin/instructions.md")"
  expect "CLAUDE.local.md stays out of the worktree's git status" "$(git -C "$CLONE/.claude/worktrees/issue-7" status --porcelain)" ""
  expect_line "the allowed tools: nightshift label" "$(run_args)" "^Bash(nightshift$")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  echo "New instructions." >"$NS/plugin/instructions.md"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "the next run: CLAUDE.local.md rewritten" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "New instructions."
  rm -r "$NS/plugin"
  gh_comment o/r 7 alice "and?" >/dev/null
  poll
  expect_ok "then no plugin copy: no CLAUDE.local.md" test ! -e "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  echo "The repo's own." >"$CLONE/CLAUDE.local.md"
  git -C "$CLONE" add CLAUDE.local.md && git -C "$CLONE" commit -q -m "chore: local" && git -C "$CLONE" push -q origin master
  gh_issue o/r 7 alice agent
  poll
  expect "a tracked CLAUDE.local.md: left alone" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "The repo's own."
  expect_line "a tracked CLAUDE.local.md: the log says so" "$(cat "$(idir 7)/log")" \
    "^0	=== CLAUDE.local.md is tracked in the repo: nightshift's instructions aren't in it$")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  printf 'Use tabs.\nRun make check.\n' >"$W/ours.md"
  printf 'repo %s %s instructions=%s\n' "$REPO" "$CLONE" "$W/ours.md" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "a project's instructions=: after nightshift's, under a heading" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" \
    "$(cat "$ROOT/plugin/instructions.md")

# This project's instructions

These come after nightshift's and win where the two disagree.

Use tabs.
Run make check."
  expect "a project's instructions=: the file is only read" "$(cat "$W/ours.md")" "Use tabs.
Run make check.")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  printf 'repo %s %s instructions=%s\n' "$REPO" "$CLONE" "$W/gone.md" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "instructions= missing: nightshift's only" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "$(cat "$ROOT/plugin/instructions.md")"
  expect_line "instructions= missing: the log says so" "$(cat "$(idir 7)/log")" \
    "^0	=== $W/gone.md (this repo's instructions=) doesn't exist: runs on with nightshift's instructions only$")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  echo "Ours." >"$W/ours.md"
  printf 'repo %s %s instructions=%s plugins=x,y\n' "$REPO" "$CLONE" "$W/ours.md" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "instructions= before another option: still the clone's worktree, with the project's" "$(tail -1 "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "Ours.")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  mkdir -p "$HOME/notes" && echo "Ours." >"$HOME/notes/ours.md"
  printf 'repo %s %s instructions=~/notes/ours.md\n' "$REPO" "$CLONE" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "instructions=~/ written by hand: home expanded" "$(tail -1 "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "Ours.")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  mkdir "$W/dir.md"
  printf 'repo %s %s instructions=%s\n' "$REPO" "$CLONE" "$W/dir.md" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "instructions= a directory: nightshift's only" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "$(cat "$ROOT/plugin/instructions.md")")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  gh_issue o/r 7 alice agent
  poll
  expect "only the root CLAUDE.local.md is excluded" "$(grep -c CLAUDE.local.md "$(git -C "$CLONE" rev-parse --path-format=absolute --git-common-dir)/info/exclude")$(grep -x /CLAUDE.local.md "$(git -C "$CLONE" rev-parse --path-format=absolute --git-common-dir)/info/exclude")" "1/CLAUDE.local.md")

(world
  echo "Ours." >"$W/ours.md"
  printf 'repo %s %s instructions=%s\n' "$REPO" "$CLONE" "$W/ours.md" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "no plugin copy, a project's instructions=: the project's alone" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "Ours.")

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
  expect "isolated=false is ignored: still isolated" "$(run_opt --setting-sources)" "project,local"
  expect "isolated=false is ignored: still nightshift's plugin" "$(run_opt --plugin-dir)" "$NS/plugin"
  expect "permission_mode is ignored: still auto" "$(run_opt --permission-mode)" auto
  expect "isolated=false is ignored: still nightshift's instructions" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "$(cat "$ROOT/plugin/instructions.md")")

(world
  set_config model sonnet
  set_config effort high
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "the model from the config" "$(run_opt --model)" sonnet
  expect "the effort from the config" "$(run_opt --effort)" high
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "a resumed run: still the model" "$(run_opt --model)" sonnet
  expect "a resumed run: still the effort" "$(run_opt --effort)" high)

report
