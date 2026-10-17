#!/usr/bin/env bash
# Tests for who may start a run, how many run at once, what a run is isolated
# from, and the plugins and instructions it gets.
#   bash scripts/test-runs-limits.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

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
    "{\"claudeMdExcludes\":[\"$CLONE/CLAUDE.md\",\"$CLONE/.claude/CLAUDE.md\",\"$CLONE/CLAUDE.local.md\"],\"permissions\":{\"deny\":[\"Bash(pkill *)\",\"Bash(killall *)\",\"Bash(pkill)\",\"Bash(killall)\"]}}"
  expect "no plugin copy: pkill and killall denied" "$(run_opt --settings | jq -c '.permissions.deny')" \
    '["Bash(pkill *)","Bash(killall *)","Bash(pkill)","Bash(killall)"]'
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
    "{\"attribution\":{\"commit\":\"\",\"pr\":\"\"},\"claudeMdExcludes\":[\"$CLONE/CLAUDE.md\",\"$CLONE/.claude/CLAUDE.md\",\"$CLONE/CLAUDE.local.md\"],\"permissions\":{\"deny\":[\"Bash(pkill *)\",\"Bash(killall *)\",\"Bash(pkill)\",\"Bash(killall)\"]}}"
  expect "isolated: pkill and killall denied" "$(run_opt --settings | jq -c '.permissions.deny')" \
    '["Bash(pkill *)","Bash(killall *)","Bash(pkill)","Bash(killall)"]'
  expect "isolated: nightshift's plugin" "$(run_opt --plugin-dir)" "$NS/plugin"
  expect "no instructions in the system prompt" "$(run_args | grep -cx -- --append-system-prompt)" 0
  expect "the run's CLAUDE.local.md: nightshift's instructions" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "$(cat "$ROOT/plugin/instructions.md")"
  expect "CLAUDE.local.md stays out of the worktree's git status" "$(git -C "$CLONE/.claude/worktrees/issue-7" status --porcelain)" ""
  mkdir -p "$CLONE/.claude/worktrees/issue-7/.nightshift/tickets"
  echo "T1" >"$CLONE/.claude/worktrees/issue-7/.nightshift/tickets/T1.md"
  expect "a ticket file in .nightshift/tickets stays out of the worktree's git status" "$(git -C "$CLONE/.claude/worktrees/issue-7" status --porcelain)" ""
  expect_line "the allowed tools: nightshift label" "$(run_args)" "^Bash(nightshift$"
  expect "the allowed tools: no signalbox or boop" "$(run_args | grep -c -e signalbox -e boop)" 0)

# The plugins a repo line names: loaded, after nightshift's own.
# The --plugin-dir values of the last run, space-separated.
plugin_dirs() { run_args | grep -A1 -x -- --plugin-dir | grep -v -x -e --plugin-dir -e -- | tr '\n' ' '; }

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
  mkdir -p "$CLONE/.nightshift/instructions" && echo "Ours." >"$CLONE/.nightshift/instructions/ours.md"
  git -C "$CLONE" add CLAUDE.local.md .nightshift && git -C "$CLONE" commit -q -m "chore: local" && git -C "$CLONE" push -q origin master
  gh_issue o/r 7 alice agent
  poll
  expect "a tracked CLAUDE.local.md: left alone" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "The repo's own."
  expect_line "a tracked CLAUDE.local.md: the log says so" "$(cat "$(idir 7)/log")" \
    "^0	=== CLAUDE.local.md is tracked in the repo: nightshift's instructions aren't in it$")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  origin_file .nightshift/instructions/b-tests.md "Run make check."
  origin_file .nightshift/instructions/a-style.md "Use tabs.
Keep lines short."
  origin_file .nightshift/instructions/notes.txt "Not markdown."
  gh_issue o/r 7 alice agent
  poll
  expect "the instructions folder's .md files: after nightshift's, under a heading, in name order" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" \
    "$(cat "$ROOT/plugin/instructions.md")

# This project's instructions

These come after nightshift's and win where the two disagree.

Use tabs.
Keep lines short.

Run make check."
  expect "CLAUDE.local.md with the folder's files stays out of git status" "$(git -C "$CLONE/.claude/worktrees/issue-7" status --porcelain)" "")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  origin_file .nightshift/instructions/ours.md "Ours." nightshift/issue-7
  gh_issue o/r 7 alice agent
  poll
  expect "an instructions file on the issue's branch: read from the worktree" "$(tail -1 "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "Ours.")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  echo "Use tabs." >"$W/ours.md"
  printf 'repo %s %s instructions=%s\n' "$REPO" "$CLONE" "$W/ours.md" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "instructions= on a repo line: ignored, nightshift's only" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "$(cat "$ROOT/plugin/instructions.md")"
  expect "instructions= on a repo line: the clone path without the option" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$CLONE/.claude/worktrees/issue-7")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  gh_issue o/r 7 alice agent
  poll
  expect "only the root CLAUDE.local.md is excluded" "$(grep -c CLAUDE.local.md "$(git -C "$CLONE" rev-parse --path-format=absolute --git-common-dir)/info/exclude")$(grep -x /CLAUDE.local.md "$(git -C "$CLONE" rev-parse --path-format=absolute --git-common-dir)/info/exclude")" "1/CLAUDE.local.md")

(world
  origin_file .nightshift/instructions/ours.md "Ours."
  origin_file .nightshift/instructions/more.md "More."
  gh_issue o/r 7 alice agent
  poll
  expect "no plugin copy, the instructions folder: the project's alone" "$(cat "$CLONE/.claude/worktrees/issue-7/CLAUDE.local.md")" "More.

Ours.")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  gh_issue o/r 7 alice agent
  poll
  expect "a plugin installed but not named: not loaded" "$(plugin_dirs)" "$NS/plugin ")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  origin_config "plugins=rn-agent"
  gh_issue o/r 7 alice agent
  poll
  expect "plugins=rn-agent in .nightshift/config: its plugin too" "$(plugin_dirs)" "$NS/plugin $W/rn-agent ")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  printf 'repo %s %s plugins=rn-agent\n' "$REPO" "$CLONE" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "plugins= on a repo line: ignored" "$(plugin_dirs)" "$NS/plugin "
  expect "plugins= on a repo line: the clone path without the option" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$CLONE/.claude/worktrees/issue-7")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  origin_file .nightshift/config "plugins=rn-agent" nightshift/issue-7
  gh_issue o/r 7 alice agent
  poll
  expect "plugins= only on the issue's branch: not loaded" "$(plugin_dirs)" "$NS/plugin ")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  plugin web@other
  origin_config "# the plugins
plugins=rn-agent,web@other"
  printf 'repo %s %s  instructions=x.md   plugins=nope \n' "$REPO" "$CLONE" >"$NS/config"
  gh_issue o/r 7 alice agent
  poll
  expect "two plugins in the file, other options on an old line: the file's both load" "$(plugin_dirs)" "$NS/plugin $W/rn-agent $W/web "
  expect "options spaced out: the clone path without them" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$CLONE/.claude/worktrees/issue-7")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  plugin old@m false
  origin_config "plugins=nope,old,rn-agent@other"
  gh_issue o/r 7 alice agent
  poll
  expect "missing, disabled or another marketplace's: skipped" "$(plugin_dirs)" "$NS/plugin "
  log=$(cat "$(idir 7)/log")
  expect_line "its log: a missing plugin" "$log" "^0	=== plugin nope isn't installed: this run goes without it$"
  expect_line "its log: a disabled plugin" "$log" "^0	=== plugin old isn't enabled: this run goes without it$"
  expect_line "its log: another marketplace's" "$log" "^0	=== plugin rn-agent@other isn't installed: this run goes without it$")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  rmdir "$W/rn-agent"
  origin_config "plugins=rn-agent"
  gh_issue o/r 7 alice agent
  poll
  expect "a plugin whose folder is gone: skipped" "$(plugin_dirs)" "$NS/plugin "
  expect_line "its log: the missing folder" "$(cat "$(idir 7)/log")" "^0	=== plugin rn-agent's folder $W/rn-agent is missing: this run goes without it$")

(world
  cp -R "$ROOT/plugin" "$NS/plugin"
  plugin rn-agent@hvalec427
  mv "$CLONE" "$W/my clone"
  printf 'repo %s %s\n' "$REPO" "$W/my clone" >"$NS/config"
  origin_config "plugins=rn-agent"
  gh_issue o/r 7 alice agent
  poll
  expect "a clone path with a space: the run works in its worktree" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$W/my clone/.claude/worktrees/issue-7"
  expect "a clone path with a space: its plugins load" "$(plugin_dirs)" "$NS/plugin $W/rn-agent ")

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
  expect "model in the config: no --model" "$(run_opt --model)" ""
  expect "effort in the config: no --effort" "$(run_opt --effort)" ""
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "a resumed run: still no --model" "$(run_opt --model)" ""
  expect "a resumed run: still no --effort" "$(run_opt --effort)" "")

report
