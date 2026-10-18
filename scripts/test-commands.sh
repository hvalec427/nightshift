#!/usr/bin/env bash
# Tests for the commands the user types: add, status, logs, label, doctor and
# watch.
#   bash scripts/test-commands.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A command's output (stdout and stderr) and, in $ST, its exit status.
try() {
  set +e
  OUT=$("$@" 2>&1)
  ST=$?
  set -e
}

# --- add --------------------------------------------------------------------------

USE="usage: nightshift add <owner/repo> <clone path>"
SCAFFOLD="created .nightshift/config and .nightshift/CONTEXT.md in the clone: commit them to the default branch"

(world
  : >"$NS/config"
  git init -q "$W/other"
  gh_repo o/x "$W/other"
  try ns add o/x "$W/other"
  expect "add: says so, that its PRs merge on their own, and to commit the scaffold" "$OUT" \
    "watching o/x (clone: $W/other); PRs merge on their own (auto_merge=false in .nightshift/config turns it off); add the \`agent\` label to an issue to start
$SCAFFOLD"
  expect "add: the repo line" "$(cat "$NS/config")" "repo o/x $W/other"
  expect_line "add: the agent label is created" "$(cat "$(gh_dir o/x)/labels")" "^agent$"
  expect_line "add: the status labels too" "$(cat "$(gh_dir o/x)/labels")" "^nightshift: needs you$"
  expect_line "add: proposed among them" "$(cat "$(gh_dir o/x)/labels")" "^nightshift: proposed$"
  try ns add o/x "$W/other"
  expect "add again: fails" "$ST $OUT" "1 nightshift: o/x is already watched"
  try ns add o/y "$W/nowhere"
  expect "add a missing clone: fails" "$ST $OUT" "1 nightshift: $W/nowhere doesn't exist"
  mkdir "$W/plain"
  try ns add o/y "$W/plain"
  expect "add a directory that isn't a clone: fails" "$ST $OUT" "1 nightshift: $W/plain isn't a git checkout"
  try ns add o/y
  expect "add without a clone: the usage" "$ST $OUT" "1 nightshift: $USE"
  git init -q "$W/my dir=1"
  before=$(cat "$NS/config")
  try ns add o/s "$W/my dir=1"
  expect "add a clone path ending in key=value: fails" "$ST $OUT" "1 nightshift: $W/my dir=1: a clone path can't end in a word like key=value"
  expect "add a clone path ending in key=value: nothing written" "$(cat "$NS/config")" "$before"
  git init -q "$W/my clone"
  gh_repo o/s "$W/my clone"
  try ns add o/s "$W/my clone"
  expect "add a clone path with a space: on the repo line" "$ST $(tail -1 "$NS/config")" "0 repo o/s $W/my clone"
  expect_no_unexpected)

(world
  : >"$NS/config"
  git init -q "$W/other"
  gh_repo o/x "$W/other"
  before=$(cat "$NS/config")
  try ns add o/x "$W/other" auto_merge=false
  expect "add auto_merge=false: fails, naming .nightshift/config" "$ST $OUT" \
    "1 nightshift: auto_merge= isn't an option of add any more: put it in the repo's .nightshift/config"
  try ns add o/x "$W/other" plugins=rn-agent,web@other
  expect "add plugins=: fails, naming .nightshift/config" "$ST $OUT" \
    "1 nightshift: plugins= isn't an option of add any more: put it in the repo's .nightshift/config"
  echo "Ours." >"$W/ours.md"
  try ns add o/x "$W/other" "instructions=$W/ours.md"
  expect "add instructions=: fails, naming .nightshift/instructions/" "$ST $OUT" \
    "1 nightshift: instructions= isn't an option of add any more: put the file in the repo's .nightshift/instructions/"
  try ns add o/x "$W/other" instructions=
  expect "add an empty instructions=: the same" "$ST $OUT" \
    "1 nightshift: instructions= isn't an option of add any more: put the file in the repo's .nightshift/instructions/"
  try ns add o/x "$W/other" colour=red
  expect "add an unknown option: the usage" "$ST $OUT" "1 nightshift: $USE (colour=red isn't an option)"
  try ns add o/x "$W/other" rn-agent
  expect "add any other word: the usage" "$ST $OUT" "1 nightshift: $USE (rn-agent isn't an option)"
  try ns add o/x "$W/other" auto_merge=false plugins=web
  expect "add several options: names the first" "$ST $OUT" \
    "1 nightshift: auto_merge= isn't an option of add any more: put it in the repo's .nightshift/config"
  expect "add with an option: nothing written to the config" "$(cat "$NS/config")" "$before"
  expect "add with an option: no .nightshift in the clone" "$([ -e "$W/other/.nightshift" ] && echo yes || echo no)" "no"
  expect_no_unexpected)

(world
  : >"$NS/config"
  git init -q "$W/other"
  gh_repo o/x "$W/other"
  try ns add o/x "$W/other"
  expect "add: .nightshift/config is scaffolded with the defaults, commented" "$(cat "$W/other/.nightshift/config")" \
    "# nightshift's settings for this repo. It reads this file from the default branch on origin,
# so a change applies once it's merged. Uncomment a line to change it.
#
# auto_merge=false: its pull requests wait for you to merge (default true: nightshift merges them).
# auto_merge=false
#
# plugins: the Claude Code plugins its runs load, comma-separated (default none).
# plugins=name,other@marketplace
#
# full_suite: where the whole test suite runs. Unset (the default): on CI, and locally only if the
# repo has no CI checks on its pull requests. local: before each push. nothing: never by nightshift.
# full_suite=local
#
# test_command: the command that runs the whole test suite (default: runs work it out from the repo's instructions).
# test_command=npm test
#
# cost_breakdown=false: the closing cost comment is one line of cost, tokens, time and the PR's size
# (default true: it adds the dollars of each model, a table of the agents that ran and where the time went).
# cost_breakdown=false
#
# cost_comment=false: no closing cost comment at all (default true).
# cost_comment=false"
  expect "add: CONTEXT.md is scaffolded with a heading and what goes in it" "$(cat "$W/other/.nightshift/CONTEXT.md")" \
    "# Context

The project's glossary: the terms it uses and what each means here, one entry per term.
nightshift's runs read this file and keep it up to date."
  expect "add: the scaffold is left uncommitted" "$(git -C "$W/other" status --porcelain)" "?? .nightshift/"

  # Never overwrites.
  printf 'auto_merge=false\n' >"$W/other/.nightshift/config"
  printf '# Mine\n' >"$W/other/.nightshift/CONTEXT.md"
  : >"$NS/config"
  try ns add o/x "$W/other"
  expect "add with both files there: says nothing about creating (the config is read from origin, not the clone)" "$ST $OUT" \
    "0 watching o/x (clone: $W/other); PRs merge on their own (auto_merge=false in .nightshift/config turns it off); add the \`agent\` label to an issue to start"
  expect "add with both files there: config untouched" "$(cat "$W/other/.nightshift/config")" "auto_merge=false"
  expect "add with both files there: CONTEXT.md untouched" "$(cat "$W/other/.nightshift/CONTEXT.md")" "# Mine"

  # Only what's missing.
  rm "$W/other/.nightshift/CONTEXT.md"
  : >"$NS/config"
  try ns add o/x "$W/other"
  expect "add with only config there: creates CONTEXT.md, says so" "$OUT" \
    "watching o/x (clone: $W/other); PRs merge on their own (auto_merge=false in .nightshift/config turns it off); add the \`agent\` label to an issue to start
created .nightshift/CONTEXT.md in the clone: commit it to the default branch"
  expect "add with only config there: config untouched" "$(cat "$W/other/.nightshift/config")" "auto_merge=false"
  expect_line "add with only config there: CONTEXT.md exists" "$(ls "$W/other/.nightshift")" "^CONTEXT.md$"
  rm "$W/other/.nightshift/config"
  : >"$NS/config"
  try ns add o/x "$W/other"
  expect "add with only CONTEXT.md there: creates config, says so" "$(echo "$OUT" | tail -1)" \
    "created .nightshift/config in the clone: commit it to the default branch"
  expect_no_unexpected)

# --- status -----------------------------------------------------------------------

(world
  expect "status, nothing yet" "$(ns status)" "service: not installed
pull requests merge on their own (auto_merge=false in a repo's .nightshift/config turns it off)
no issues yet"
  sh -c 'exit 0' &
  dead=$!
  wait "$dead"
  echo "$dead" >"$NS/watch.pid"
  expect "status: a watch.pid left by a watch that's gone" "$(ns status | head -1)" "service: not installed"
  try ns status --everything
  expect "status, a bad option: the usage" "$ST $OUT" "2 usage: nightshift status [--all]")

# A second watched repo, o/x, cloned in $W/other, with .nightshift/config $1
# on its default branch (none if empty).
second_repo() {
  git init -q --bare -b master "$W/x.git"
  git clone -q "$W/x.git" "$W/other" 2>/dev/null
  git -C "$W/other" config commit.gpgsign false
  mkdir -p "$W/other/.nightshift"
  echo hi >"$W/other/README"
  [ -z "$1" ] || printf '%s\n' "$1" >"$W/other/.nightshift/config"
  git -C "$W/other" add -A && git -C "$W/other" commit -q -m "chore: start"
  git -C "$W/other" push -q origin master
  gh_repo o/x "$W/x.git"
  printf 'repo o/x %s\n' "$W/other" >>"$NS/config"
}

(world
  second_repo "auto_merge=false"
  expect "status: the repos auto-merge is off for" "$(ns status | sed -n 2p)" \
    "pull requests merge on their own (off for: o/x; auto_merge=false in a repo's .nightshift/config turns it off)"
  origin_config "auto_merge=false"
  git -C "$CLONE" fetch -q origin
  expect "status: off for every repo, they wait" "$(ns status | sed -n 2p)" \
    "pull requests wait for you (auto_merge=false in every repo's .nightshift/config)")

(world
  printf 'repo %s %s auto_merge=false\n' "$REPO" "$CLONE" >"$NS/config"
  expect "status: auto_merge=false on a repo line is ignored" "$(ns status | sed -n 2p)" \
    "pull requests merge on their own (auto_merge=false in a repo's .nightshift/config turns it off)")

(world
  origin_config "auto_merge=false"
  expect "status: uses the last fetch, not origin's newest" "$(ns status | sed -n 2p)" \
    "pull requests merge on their own (auto_merge=false in a repo's .nightshift/config turns it off)"
  git -C "$CLONE" fetch -q origin
  expect "status: after the fetch" "$(ns status | sed -n 2p)" \
    "pull requests wait for you (auto_merge=false in every repo's .nightshift/config)")

(world
  : >"$NS/config"
  expect "status: no repos, no merge line" "$(ns status)" "service: not installed
no issues yet")

(world
  gh_issue o/r 7 alice agent bug
  runs_do 'hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  expect_line "status: a run going, its type, label and pid" "$(ns status)" \
    "^o/r#7  *bug · thinking [0-9]*s (pid $(state 7 pid)) · last activity [0-9]*s ago$"
  ns stop o/r#7 >/dev/null
  wait "$bg"
  gh_issue o/r 8 bob agent
  poll
  expect_line "status: an ignored issue" "$(ns status)" "^o/r#8  *ignored (labelled by someone else)$"
  mkdir -p "$(idir 9)"
  expect_line "status: one never run" "$(ns status)" "^o/r#9  *queued$"
  gh_issue o/r 10 alice agent "nightshift: proposed"
  poll
  expect_line "status: a proposed one, held" "$(ns status)" "^o/r#10  *proposed: waiting for your comment$")

(world
  gh_issue o/r 7 alice agent
  runs_do 'skill nightshift:plan; hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  wait_for "$(idir 7)/skill"
  expect_line "status: a run going, its skill" "$(ns status)" \
    "^o/r#7  *planning · nightshift:plan [0-9]*s (pid $(state 7 pid)) · now: Skill: nightshift:plan · last activity [0-9]*s ago$"
  ns stop o/r#7 >/dev/null
  wait "$bg"
  runs_do 'skill nightshift:questions; comment questions'
  gh_comment o/r 7 alice "go on" >/dev/null
  poll
  expect_line "status: waiting, the skill it ended in" "$(ns status)" "^o/r#7  *needs you · nightshift:questions · [0-9]*s · spent "
  echo https://github.com/o/r/pull/1 >"$(idir 7)/pr"
  echo "PR open" >"$(idir 7)/label"
  expect_line "status: a pull request, the skill it ended in" "$(ns status)" "^o/r#7  *PR https://github.com/o/r/pull/1 · nightshift:questions · waiting [0-9]*s · spent ")

(world
  gh_issue o/r 7 alice agent
  runs_do 'tool_use "bash scripts/test-runs.sh"; say "running the tests"; hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  wait_log 7 "running the tests"
  expect_line "status: a run's heartbeat, its last tool call and activity" "$(ns status)" \
    "^o/r#7  *thinking [0-9]*s (pid $(state 7 pid)) · now: Bash: bash scripts/test-runs.sh · last activity [0-9]*s ago$"
  touch -t "$(date -v-5M +%Y%m%d%H%M.%S)" "$(idir 7)/log"
  expect_line "status: a quiet run, in minutes" "$(ns status)" " · last activity 5m ago$"
  echo https://github.com/o/r/pull/1 >"$(idir 7)/pr"
  echo "rebasing" >"$(idir 7)/updating"
  expect_line "status: an update run's heartbeat" "$(ns status)" \
    "^o/r#7  *PR https://github.com/o/r/pull/1 · rebasing [0-9]*s (pid $(state 7 pid)) · now: Bash: bash scripts/test-runs.sh · last activity 5m ago$"
  rm "$(idir 7)/log"
  expect_line "status: no log, no heartbeat" "$(ns status)" "(pid $(state 7 pid))$"
  ns stop o/r#7 >/dev/null
  wait "$bg")

(world
  gh_issue o/r 7 alice agent
  runs_do 'tool_use "git status"; agent a1 nightshift:ticket T1; tool_use "bash scripts/test.sh review runs && shellcheck -S warning nightshift install.sh" a1; hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  wait_log 7 shellcheck
  expect_line "status: a subagent's tool call, cut to 60 characters" "$(ns status)" \
    " · now: Bash: bash scripts/test.sh review runs && shellcheck -S war… · last activity [0-9]*s ago$"
  ns stop o/r#7 >/dev/null
  wait "$bg"
  runs_do 'say "back on it"; hang'
  gh_comment o/r 7 alice "go on" >/dev/null
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/2/waiting"
  wait_log 7 "back on it"
  expect_line "status: the next run, no tool call yet: not the last run's" "$(ns status)" \
    "(pid $(state 7 pid)) · last activity [0-9]*s ago · spent "
  ns stop o/r#7 >/dev/null
  wait "$bg")

(world
  gh_issue o/r 7 alice agent
  runs_do 'tool_use "echo ······························································"; hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  wait_log 7 "echo ·"
  expect_line "status: a step cut by characters, not bytes" "$(ns status)" \
    " · now: Bash: echo ················································… · last activity [0-9]*s ago$"
  ns stop o/r#7 >/dev/null
  wait "$bg")

# --- logs -------------------------------------------------------------------------

LOG="0	2026-10-16 10:00:00 a run
1	2026-10-16 10:00:01 a message
2	2026-10-16 10:00:02 a tool
3	2026-10-16 10:00:03 a thought
an old line"

(world
  printf '%s\n' "$LOG" >"$NS/watch.log"
  only() { printf '%s\n' "$LOG" | sed -n "$1" | sed 's/^[0-3]	//'; }
  expect "logs: runs, and untagged lines" "$(ns logs)" "$(only '1p;5p')"
  expect "logs -v: and messages" "$(ns logs -v)" "$(only '1,2p;5p')"
  expect "logs -vv: and tools" "$(ns logs -vv)" "$(only '1,3p;5p')"
  expect "logs -vvv: all" "$(ns logs -vvv)" "$(only '1,5p')"
  expect "logs -v -v: they add up" "$(ns logs -v -v)" "$(ns logs -vv)"
  expect "logs -vv -vv: all at most" "$(ns logs -vv -vv)" "$(ns logs -vvv)"
  expect "logs -l tools" "$(ns logs -l tools)" "$(ns logs -vv)"
  expect "logs --level=1" "$(ns logs --level=1)" "$(ns logs -v)"
  expect "logs --level all" "$(ns logs --level all)" "$(ns logs -vvv)"
  try ns logs -l loud
  expect "logs, an unknown level: exit 2" "$ST" 2
  expect_line "logs, an unknown level: the usage" "$OUT" "^usage: nightshift logs "
  try ns logs -l
  expect "logs -l without a level: exit 2" "$ST" 2
  try ns logs --frobnicate
  expect "logs, an unknown option: exit 2" "$ST" 2
  expect_line "logs --help: the levels" "$(ns logs --help)" "^        runs      (0, the default)"
  try ns logs o/r#7
  expect "logs of an unknown issue" "$ST $OUT" "1 nightshift: nightshift doesn't know that issue"
  mkdir -p "$(idir 7)"
  try ns logs o/r#7
  expect "logs of an issue with nothing yet" "$ST $OUT" "1 nightshift: nothing logged there yet"
  printf '0\t10:00:00 its run\n1\t10:00:01 its message\n' >"$(idir 7)/log"
  expect "logs of an issue" "$(ns logs o/r#7)" "10:00:00 its run"
  expect "logs of an issue, -v" "$(ns logs o/r#7 -v)" "10:00:00 its run
10:00:01 its message")

(world
  rm -f "$NS/watch.log"
  try ns logs
  expect "logs, nothing logged yet" "$ST $OUT" "1 nightshift: nothing logged there yet")

(world
  for i in $(seq 1 60); do printf '0\t2026-10-16 10:00:00 line %s\n' "$i"; done >"$NS/watch.log"
  ns logs -f >"$W/followed" 2>&1 &
  bg=$!
  i=0
  until [ "$(wc -l <"$W/followed")" -ge 50 ] || [ $i -gt 50 ]; do sleep 0.1; i=$((i + 1)); done
  printf '1\t2026-10-16 10:00:01 a message\n0\t2026-10-16 10:00:02 line 61\n' >>"$NS/watch.log"
  i=0
  until grep -q "line 61" "$W/followed" || [ $i -gt 50 ]; do sleep 0.1; i=$((i + 1)); done
  pkill -f "$NS/watch.log" 2>/dev/null || true
  kill "$bg" 2>/dev/null || true
  wait "$bg" 2>/dev/null || true
  expect "logs -f: the last 50 lines" "$(head -1 "$W/followed")" "2026-10-16 10:00:00 line 11"
  expect "logs -f: then new ones at its level" "$(tail -n +51 "$W/followed")" "2026-10-16 10:00:02 line 61")

# --- label ------------------------------------------------------------------------

(world
  try ns label building
  expect "label outside a run: fails" "$ST $OUT" "1 nightshift: nightshift label only works in a nightshift run"
  gh_issue o/r 7 alice agent
  mkdir -p "$(idir 7)"
  export NIGHTSHIFT_REPO=o/r NIGHTSHIFT_ISSUE=7
  try ns label loud
  expect "label, an unknown status: the statuses" "$ST $OUT" \
    "1 nightshift: usage: nightshift label <status>: one of proposed, queued, thinking, planning, building, updating, merging, answering, needs you, PR open, stopped"
  ns label building
  expect "label: sets it" "$(status_label 7)" building
  ns label "needs you"
  expect "label again: in place of the last" "$(status_label 7)" "needs you"
  calls=$(wc -l <"$GH_FAKE/calls")
  ns label "needs you"
  expect "label it has: nothing asked of GitHub" "$(wc -l <"$GH_FAKE/calls")" "$calls"
  echo 'issue edit *' >"$GH_FAKE/fail"
  try ns label building
  expect "label, GitHub fails: says so" "$ST $OUT" "1 nightshift: couldn't set the label: see nightshift logs"
  expect_line "and logs it" "$(cat "$NS/watch.log")" "o/r#7: couldn't set the status label to building$"
  expect_no_unexpected)

# --- doctor -----------------------------------------------------------------------

# A world doctor finds all good in: a token, nightshift's plugin (copied and
# in Claude Code), and o/r's agent label.
healthy() {
  world
  echo token >"$NS/token"
  cp -R "$ROOT/plugin" "$NS/plugin"
  echo '[{"id":"nightshift@nightshift","enabled":true,"installPath":"/x"}]' >"$CLAUDE_FAKE/plugins.json"
  echo agent >>"$(gh_dir o/r)/labels"
}

# A PATH like the world's without the fake $1.
without() {
  mkdir -p "$W/only"
  for f in "$FAKES"/*; do [ "$(basename "$f")" = "$1" ] || ln -sf "$f" "$W/only/"; done
  printf '%s' "${PATH/$FAKES/$W/only}"
}

(healthy
  try ns doctor
  expect "doctor, all there: passes" "$ST" 0
  expect_line "doctor: the version" "$OUT" "^nightshift dev$"
  expect_line "doctor: gh" "$OUT" "^  ok      gh 2.99.0$"
  expect_line "doctor: gh's login" "$OUT" "^  ok      gh logged in as alice$"
  expect_line "doctor: claude" "$OUT" "^  ok      claude 2.1.300$"
  expect_line "doctor: the token" "$OUT" "^  ok      Claude token ($NS/token)$"
  expect_line "doctor: the plugin copy" "$OUT" "^  ok      nightshift's plugin for runs ($NS/plugin)$"
  expect_line "doctor: the plugin in Claude Code" "$OUT" "^  ok      nightshift's plugin in Claude Code"
  expect_line "doctor: the instructions" "$OUT" "^  ok      instructions: nightshift's defaults$"
  expect "doctor: no model or effort in the config: no line for them" "$(echo "$OUT" | grep -E '^  note    (model|effort) ')" ""
  expect_line "doctor: the repo, its PRs merge on their own" "$OUT" "^  ok      o/r: clone $CLONE, \`agent\` label, PRs merge on their own$"
  expect_line "doctor: a hint for merged branches" "$OUT" "^  hint    o/r: GitHub keeps merged branches"
  expect_line "doctor: no React Native section" "$OUT" "React Native" no
  expect_line "doctor: all good" "$OUT" "^all good$")

(healthy
  origin_config "auto_merge=false"
  git -C "$CLONE" fetch -q origin
  expect_line "doctor: auto_merge=false in .nightshift/config, its PRs wait" "$(ns doctor)" \
    "^  ok      o/r: clone $CLONE, \`agent\` label, PRs wait for you (auto_merge=false in .nightshift/config)$")

(healthy
  printf 'repo %s %s auto_merge=false plugins=rn-agent\n' "$REPO" "$CLONE" >"$NS/config"
  try ns doctor
  expect "doctor: options on a repo line: ignored, only a note" "$ST" 0
  expect_line "doctor: auto_merge=false on the repo line, its PRs still merge" "$OUT" \
    "^  ok      o/r: clone $CLONE, \`agent\` label, PRs merge on their own$"
  expect_line "doctor: a note for the ignored auto_merge=" "$OUT" \
    "^  note    o/r: auto_merge=false on its repo line is ignored now: put it in .nightshift/config on o/r's default branch$"
  expect_line "doctor: a note for the ignored plugins=" "$OUT" \
    "^  note    o/r: plugins=rn-agent on its repo line is ignored now: put it in .nightshift/config on o/r's default branch$"
  expect_line "doctor: its plugin isn't checked" "$OUT" "plugin rn-agent" no)

(healthy
  expect_line "doctor: no options on the repo line, no note" "$(ns doctor)" "^  note    o/r:" no)

(healthy
  set_config model sonnet
  set_config effort high
  try ns doctor
  expect "doctor: model and effort in the config: passes" "$ST" 0
  expect_line "doctor: model in the config: a note" "$OUT" "^  note    model in the config is ignored now: each skill sets its own model$"
  expect_line "doctor: effort in the config: a note" "$OUT" "^  note    effort in the config is ignored now: each skill sets its own effort$")

(healthy
  gh_edit "$(gh_dir o/r)/repo.json" '.delete_branch_on_merge = true'
  expect_line "doctor: no hint when GitHub deletes merged branches" "$(ns doctor)" "hint" no)

(healthy
  rm "$NS/token"
  try ns doctor
  expect_line "doctor: logged in, no token: fine" "$OUT" "^  ok      Claude logged in "
  touch "$CLAUDE_FAKE/logged-out"
  try ns doctor
  expect "doctor: no token, logged out: fails" "$ST" 1
  expect_line "doctor: says how to get one" "$OUT" "^  missing Claude token: claude setup-token"
  expect_line "doctor: counts it" "$OUT" "^1 to fix, then run nightshift doctor again$"
  expect_line "doctor: a token in the environment" "$(CLAUDE_CODE_OAUTH_TOKEN=x ns doctor)" "^  ok      Claude token (CLAUDE_CODE_OAUTH_TOKEN)$")

(healthy
  try env FAKE_GH_VERSION=2.40.1 FAKE_CLAUDE_VERSION=2.1.100 "$ROOT/nightshift" doctor
  expect "doctor: old tools: fails" "$ST" 1
  expect_line "doctor: an old gh" "$OUT" "^  old     gh 2.40.1: needs 2.99 or newer: brew upgrade gh$"
  expect_line "doctor: an old claude" "$OUT" "^  old     claude 2.1.100: needs 2.1.286 or newer: claude update$")

(healthy
  try env PATH="$(without claude)" "$ROOT/nightshift" doctor
  expect "doctor: no claude: fails" "$ST" 1
  expect_line "doctor: says how to install it" "$OUT" "^  missing claude: curl -fsSL https://claude.ai/install.sh | bash$")

(healthy
  try env PATH="$(without gh)" "$ROOT/nightshift" doctor
  expect_line "doctor: no gh" "$OUT" "^  missing gh: brew install gh, then gh auth login$"
  expect_line "doctor: no gh, the label can't be checked" "$OUT" "^  ?       o/r: its \`agent\` label: needs gh to check$")

(healthy
  echo 'api user*' >"$GH_FAKE/fail"
  try ns doctor
  expect_line "doctor: gh not logged in" "$OUT" "^  no      gh logged in: gh auth login$")

# A board repo: o/r names alice's project 5 (columns $1.. , the seven by default).
BOARD_URL=https://github.com/users/alice/projects/5
doctor_board() {
  healthy
  gh_project alice/5 "$@"
  origin_config "project=$BOARD_URL"
  git -C "$CLONE" fetch -q origin
}

(doctor_board
  try ns doctor
  expect "doctor: a board with all seven columns: passes" "$ST" 0
  expect_line "doctor: says the board is all there" "$OUT" "^  ok      o/r: board alice/5 (https://github.com/users/alice/projects/5), its seven columns$"
  expect "doctor: the board is read in one query" "$(gh_calls "graphql .*query NightshiftBoard" | wc -l | tr -d ' ')" 1)

(healthy
  expect_line "doctor: no project=: nothing about a board" "$(ns doctor)" "board" no
  expect "doctor: no project=: no board query" "$(gh_calls "graphql" | wc -l | tr -d ' ')" 0)

(doctor_board Backlog Ready "In progress" "in review" Done
  try ns doctor
  expect "doctor: columns missing: fails" "$ST" 1
  expect_line "doctor: names Your review" "$OUT" "^  missing o/r: the board's Your review column: add it to the Status field of $BOARD_URL$"
  expect_line "doctor: names Ready to merge" "$OUT" "^  missing o/r: the board's Ready to merge column: add it to the Status field of $BOARD_URL$"
  expect_line "doctor: a column in another case is there" "$OUT" "In review" no
  expect_line "doctor: counts them" "$OUT" "^2 to fix, then run nightshift doctor again$")

(doctor_board
  gh_scopes gist read:org repo
  try ns doctor
  expect "doctor: no project scope: fails" "$ST" 1
  expect_line "doctor: names the fix" "$OUT" "^  missing o/r: gh's \`project\` scope, for its board: gh auth refresh -s project$"
  expect "doctor: no scope: the board isn't read" "$(gh_calls "graphql" | wc -l | tr -d ' ')" 0
  gh_scopes gist project repo
  expect "doctor: with the project scope: passes" "$(ns doctor >/dev/null; echo $?)" 0)

(healthy
  gh_project alice/5
  origin_config "project=https://example.com/not-a-board"
  git -C "$CLONE" fetch -q origin
  try ns doctor
  expect "doctor: a malformed project=: fails" "$ST" 1
  expect_line "doctor: says what a project is" "$OUT" "^  bad     o/r: project=https://example.com/not-a-board in .nightshift/config: use a project's URL, https://github.com/users/<login>/projects/<n> (an organisation's: /orgs/<login>/projects/<n>)$")

(healthy
  origin_config "project=https://github.com/users/alice/projects/9"
  git -C "$CLONE" fetch -q origin
  try ns doctor
  expect "doctor: a project that can't be read: fails" "$ST" 1
  expect_line "doctor: says so, with what gh said" "$OUT" "^  no      o/r: its board (alice/9): gh: Could not resolve to a ProjectV2 with the number 9\. .*: check project= in .nightshift/config, and that gh may read it (gh auth refresh -s project)$")

(doctor_board
  jq 'del(.field)' "$(gh_project_dir alice/5)/project.json" >"$W/p.json" && mv "$W/p.json" "$(gh_project_dir alice/5)/project.json"
  try ns doctor
  expect "doctor: a project with no Status field: fails" "$ST" 1
  expect_line "doctor: says it has no Status field" "$OUT" "^  no      o/r: its board (alice/5): the project has no Status field")

(healthy
  rm -r "$NS/plugin"
  echo '[]' >"$CLAUDE_FAKE/plugins.json"
  try ns doctor
  expect_line "doctor: no plugin copy" "$OUT" "^  missing nightshift's plugin for runs ($NS/plugin): run install.sh again$"
  expect_line "doctor: no plugin in Claude Code" "$OUT" "^  missing nightshift's plugin in Claude Code"
  expect_line "doctor: no default instructions" "$OUT" "^  missing nightshift's default instructions"
  expect_line "doctor: counts them" "$OUT" "^3 to fix"
  set_config isolated false
  try ns doctor
  expect_line "doctor: isolated=false: still needs the plugin copy" "$OUT" "^  missing nightshift's plugin for runs ($NS/plugin): run install.sh again$")

(healthy
  set_config isolated false
  set_config permission_mode bypassPermissions
  try ns doctor
  expect_line "doctor: a note for isolated=" "$OUT" "^  note    isolated in the config is ignored now: runs are always isolated$"
  expect_line "doctor: a note for permission_mode=" "$OUT" "^  note    permission_mode in the config is ignored now: runs always use auto$"
  expect "doctor: notes aren't problems" "$ST" 0)

(healthy
  echo "mine" >"$NS/instructions.md"
  try ns doctor
  expect_line "doctor: a note for this machine's instructions.md" "$OUT" "^  note    $NS/instructions.md is ignored now: runs use nightshift's defaults$"
  expect "doctor: the note isn't a problem" "$ST" 0)

(healthy
  : >"$(gh_dir o/r)/labels"
  printf 'repo o/gone %s\n' "$W/gone" >>"$NS/config"
  try ns doctor
  expect_line "doctor: no agent label" "$OUT" "^  missing o/r: its \`agent\` label: gh label create agent --repo o/r --color 5319E7$"
  expect_line "doctor: a clone that's gone" "$OUT" "^  missing o/gone: its clone ($W/gone): clone it there"
  expect_line "doctor: counts both" "$OUT" "^2 to fix")

(healthy
  plugin rn-agent@hvalec427
  rmdir "$W/rn-agent"
  origin_config "plugins=rn-agent"
  git -C "$CLONE" fetch -q origin
  try ns doctor
  expect_line "doctor: a plugin whose folder is gone" "$OUT" "^  missing o/r: plugin rn-agent's folder $W/rn-agent: reinstall it: claude plugin install rn-agent$")

(healthy
  expect_line "doctor: no instructions=, no line for it" "$(ns doctor)" "o/r: .*instructions" no)

(healthy
  echo "Ours." >"$W/ours.md"
  printf 'repo o/r %s instructions=%s other=x\n' "$CLONE" "$W/ours.md" >"$NS/config"
  try ns doctor
  expect_line "doctor: instructions= on a repo line: a note to copy the file" "$OUT" \
    "^  note    o/r: instructions=$W/ours.md on its repo line is ignored now: copy the file into .nightshift/instructions/ in o/r$"
  expect "doctor: the note isn't a problem" "$ST" 0
  printf 'repo o/r %s instructions=%s\n' "$CLONE" "$W/gone.md" >"$NS/config"
  try ns doctor
  expect_line "doctor: instructions= of a missing file: still only the note" "$OUT" "^  note    o/r: instructions=$W/gone.md on its repo line is ignored now"
  expect "doctor: a missing file isn't a problem either" "$ST" 0)

(healthy
  echo "The repo's own." >"$CLONE/CLAUDE.local.md"
  git -C "$CLONE" add CLAUDE.local.md
  try ns doctor
  expect_line "doctor: a tracked CLAUDE.local.md" "$OUT" "^  tracked o/r: CLAUDE.local.md, so runs don't get nightshift's instructions: untrack it: git -C $CLONE rm --cached CLAUDE.local.md$"
  expect_line "doctor: counts it" "$OUT" "^1 to fix")

(healthy
  : >"$NS/config"
  expect_line "doctor: no repos yet" "$(ns doctor)" "^  none watched yet: nightshift add <owner/repo> <clone>$")

(healthy
  plugin rn-agent@hvalec427
  origin_config "plugins=rn-agent"
  git -C "$CLONE" fetch -q origin
  try ns doctor
  expect "doctor: the repo's plugins installed: passes" "$ST" 0)

(healthy
  plugin rn-agent@hvalec427
  plugin web@other false
  origin_config "plugins=rn-agent,web,nope"
  git -C "$CLONE" fetch -q origin
  try ns doctor
  expect "doctor: a missing or disabled plugin: fails" "$ST" 1
  expect_line "doctor: an installed plugin" "$OUT" "^  ok      o/r: plugin rn-agent$"
  expect_line "doctor: after the repo's label line" "$(grep -A1 '^  ok      o/r: clone' <<<"$OUT")" "^  ok      o/r: plugin rn-agent$"
  expect_line "doctor: a disabled plugin" "$OUT" "^  missing o/r: plugin web: enable it: claude plugin enable web@other$"
  expect_line "doctor: a missing plugin" "$OUT" "^  missing o/r: plugin nope: claude plugin install nope$"
  expect_line "doctor: counts both" "$OUT" "^2 to fix")

# --- watch ------------------------------------------------------------------------

(world
  : >"$NS/config"
  try ns watch
  expect "watch, no repos: says so" "$ST $OUT" "1 nightshift: no repos to watch yet: nightshift add <owner/repo> <clone>")

(world
  set_config interval 1
  echo secret >"$NS/token"
  for i in $(seq 1 40001); do echo "0	2026-10-16 10:00:00 old $i"; done >"$NS/watch.log"
  gh_issue o/r 7 alice agent
  runs_do 'hang'
  "$ROOT/nightshift" watch &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  expect "watch: its pid" "$(cat "$NS/watch.pid")" "$bg"
  expect_line "watch: runs get the token" "$(cat "$CLAUDE_FAKE/runs/1/env")" "^CLAUDE_CODE_OAUTH_TOKEN=secret$"
  expect_line "status: a watch by hand" "$(ns status)" "^service: not installed · nightshift watch runs by hand (pid $bg)$"
  i=0
  until [ "$(wc -l <"$NS/watch.log")" -lt 40000 ] || [ $i -gt 50 ]; do sleep 0.1; i=$((i + 1)); done
  expect_ok "watch: a long log is trimmed" test "$(wc -l <"$NS/watch.log")" -lt 20100
  kill -TERM "$bg"
  wait "$bg" || true
  expect_ok "watch stopped: its run got TERM" test -f "$CLAUDE_FAKE/runs/1/stopped"
  expect "watch stopped: the run's status" "$(status_label 7)" queued
  expect_line "watch stopped: logs what it stopped" "$(cat "$NS/watch.log")" "watch stopped: interrupted o/r#7$"
  expect_ok "watch stopped: no pid" test ! -f "$NS/watch.pid")

# A run the watch's stopping stopped (an upgrade, a restart) resumes with the
# next watch, with no comment needed.
(world
  set_config interval 1
  gh_issue o/r 7 alice agent
  runs_do '[ "$k" = 1 ] && hang; comment questions'
  "$ROOT/nightshift" watch &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  kill -TERM "$bg"
  wait "$bg" || true
  expect_line "watch stopped: queued to resume" "$(ns status)" "^o/r#7  *queued to resume"
  expect "watch stopped: no comment" "$(gh_comments o/r 7)" ""
  "$ROOT/nightshift" watch &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/2/args" || true
  wait_idle 7
  kill -TERM "$bg"
  wait "$bg" || true
  expect "watch again: it resumes its session" "$(run_opt --resume 2)" session-1
  expect_line "watch again: told to carry on" "$(run_prompt 2)" \
    "^Your last run was stopped partway because nightshift stopped (it was restarted or upgraded); carry on from where it stopped\.$")

# A run stopped by hand stays stopped, even when the watch stops while it's
# still ending.
(world
  set_config interval 1
  gh_issue o/r 7 alice agent
  runs_do '[ "$k" = 1 ] && linger; comment questions'
  "$ROOT/nightshift" watch &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  ns stop o/r#7 >/dev/null
  wait_for "$CLAUDE_FAKE/runs/1/stopped"
  kill -TERM "$bg"
  sleep 0.5
  touch "$CLAUDE_FAKE/runs/1/go"
  wait "$bg" || true
  expect "stopped by hand, then the watch: its status" "$(status_label 7)" stopped
  "$ROOT/nightshift" watch &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/2" || true
  kill -TERM "$bg"
  wait "$bg" || true
  expect "stopped by hand: the next watch doesn't resume it" "$(runs)" 1)

(world
  printf 'repo o/q %s\n' "$W/nothing" >>"$NS/config"
  poll
  expect_line "a clone that's gone: logged" "$(cat "$NS/watch.log")" "o/q: $W/nothing isn't a git checkout$")

(world
  echo 'api -i repos/o/r/issues\?*' >"$GH_FAKE/fail"
  poll
  expect_line "GitHub can't list the issues: logged" "$(cat "$NS/watch.log")" "o/r: couldn't list issues$")

report
