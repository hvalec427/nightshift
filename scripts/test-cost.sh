#!/usr/bin/env bash
# Tests for what an issue cost: each run's dollars, tokens and time added up
# in its `cost`, shown by `status`, and posted on the issue once it's done.
#   bash scripts/test-cost.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# Issue $1's `cost`, its seconds (field 5) as S.
cost() { state "$1" cost | awk '{ $5 = "S"; print }'; }

(world
  gh_issue o/r 7 alice agent
  runs_do 'costs 0.5 opus 100 200 300 400; costs 0.25 haiku 10 20 30 40; comment questions'
  poll
  expect "a run: its dollars and tokens, of every model" "$(cost 7)" "0.75 110 220 770 S 1 -"
  expect_ok "its time: whole seconds" grep -Eq '^[^ ]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+ ' "$(idir 7)/cost"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do 'costs 1.25 opus 1000 2000 0 5; comment plan'
  poll
  expect "a second run: added" "$(cost 7)" "2 1110 2220 775 S 2 -"
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do 'costs 0.1 opus 1 1 1 1; fail_result'
  poll
  expect "a failed run: counted" "$(cost 7)" "2.1 1111 2221 777 S 3 -"
  expect_no_unexpected)

# A resumed run's result has the session's totals, its earlier runs' too:
# each run adds what it spent itself.
(world
  gh_issue o/r 7 alice agent
  runs_do 'costs 1 opus 10 10 10 10; comment questions'
  poll
  rm "$(idir 7)/usage"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do 'costs 1 opus 10 10 10 10; comment plan'
  poll
  expect "no totals kept (from before they were): the last run's out.jsonl's" "$(cost 7)" "2 20 20 40 S 2 -"
  gh_comment o/r 7 alice "2 no" >/dev/null
  runs_do 'forget; costs 0.5 opus 1 1 1 1; comment plan'
  poll
  expect "totals lower than the last: all of them" "$(cost 7)" "2.5 21 21 42 S 3 -"
  rm "$(idir 7)/session"
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do 'costs 5 opus 100 100 100 100; comment progress'
  poll
  expect "a new session: all of its totals" "$(cost 7)" "7.5 121 121 242 S 4 -"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "a run that reports no cost: its time and the run" "$(cost 7)" "0 0 0 0 S 1 -")

(world
  gh_issue o/r 7 alice agent
  runs_do 'costs 0.5 opus 1 1 1 1; hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  ns stop o/r#7 >/dev/null
  wait "$bg"
  expect "a stopped run (no result): its time and the run" "$(cost 7)" "0 0 0 0 S 1 -")

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  rm "$(idir 7)/cost"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "counting from a later run: since today" "$(cost 7)" "0 0 0 0 S 1 $(date +%Y-%m-%d)")

# A plan's "go" builds in a fresh session: all of its first result counts,
# whatever the planning session's totals were.
(world
  gh_issue o/r 7 alice agent enhancement
  runs_do 'costs 5 opus 100 100 100 100; comment plan'
  poll
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do 'costs 1 opus 10 10 10 10; comment progress'
  poll
  expect "the build session: a fresh one" "$(state 7 session)" session-2
  expect "its cost: all of it, added" "$(cost 7)" "6 110 110 220 S 2 -"
  expect_no_unexpected)

# Each run's end line: the models it used, the main one first, and its
# context at the end (its last turn's, not a subagent's).
OPUS=claude-opus-5-5 HAIKU=claude-haiku-4-5-20251001
(world
  gh_issue o/r 7 alice agent
  runs_do "costs 0.1 $HAIKU 1 1 1 1; costs 1 $OPUS 10 10 10 10; window $OPUS 1000000; window $HAIKU 200000
    turn $OPUS 5 60000 20000; turn $HAIKU 5 190000 0 toolu_1; comment questions"
  poll
  expect_line "its log: the models and the context" "$(cat "$(idir 7)/log")" \
    "^0	=== [0-9:]* run done in [0-9]*s · opus-5-5, haiku-4-5 · context 80k of 1M$"
  expect_line "watch.log too" "$(cat "$NS/watch.log")" "o/r#7: run done in [0-9]*s · opus-5-5, haiku-4-5 · context 80k of 1M$"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "costs 0.5 $OPUS 1 1 1 1; turn $OPUS 5 1500000 0; fail_result"
  poll
  expect_line "resumed: the models this run used" "$(tail -1 "$(idir 7)/log")" \
    "^0	=== [0-9:]* run failed (0) after [0-9]*s · opus-5-5 · context 1.5M of 1M$"
  gh_comment o/r 7 alice "again" >/dev/null
  runs_do "comment plan"
  poll
  expect_line "no models, no turns: nothing more" "$(tail -1 "$(idir 7)/log")" "^0	=== [0-9:]* run done in [0-9]*s$"
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do "turn $OPUS 5 200000 0; hang"
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/4/waiting"
  ns stop o/r#7 >/dev/null
  wait "$bg"
  expect_line "stopped (no result): its context" "$(tail -1 "$(idir 7)/log")" "^0	=== [0-9:]* run stopped after [0-9]*s · context 200k$"
  expect_no_unexpected)

# A run whose skill and two subagents ran on their own models: all three, the
# main one first.
SONNET=claude-sonnet-4-5-20250929
(world
  gh_issue o/r 7 alice agent
  runs_do "costs 0.2 $SONNET 1 1 1 1; costs 0.1 $HAIKU 1 1 1 1; costs 1 $OPUS 1 1 1 1
    turn $SONNET 5 1000 0 toolu_1; turn $HAIKU 5 1000 0 toolu_2; turn $OPUS 5 50000 0; comment questions"
  poll
  expect_line "its log: the main model, then its subagents'" "$(cat "$(idir 7)/log")" \
    "^0	=== [0-9:]* run done in [0-9]*s · opus-5-5, sonnet-4-5, haiku-4-5 · context 50k$")

# The agents a run had: its session's line, then a line for each subagent, in
# the order they ran. Their keys sorted, the session's seconds as S and the
# run marker (when the run started) as R.
agents() { state "$1" agents | jq -S -c '.run = "R" | if .kind == "session" then .secs = "S" else . end'; }

(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 100 200 300 400; turn $OPUS 5 1000 0; skill nightshift:issue; skill nightshift:questions
    agent toolu_1 nightshift:ticket 'Build T1'; skill nightshift:build toolu_1; turn $HAIKU 5 100 0 toolu_1
    agent_result toolu_1 $HAIKU 5000 12400 7
    agent toolu_2 Explore 'Find the cost code' Task; agent_result toolu_2 $SONNET 900 2000 3
    comment questions"
  poll
  expect "a run: its session, then each subagent" "$(agents 7)" \
'{"kind":"session","models":["opus-5-5"],"reply":false,"run":"R","secs":"S","session":"session-1","skills":["nightshift:issue","nightshift:questions"],"tokens":1000,"tools":5,"usd":1}
{"description":"Build T1","kind":"agent","model":"haiku-4-5","run":"R","secs":12,"session":"session-1","skills":["nightshift:build"],"tokens":5000,"tools":7,"type":"nightshift:ticket"}
{"description":"Find the cost code","kind":"agent","model":"sonnet-4-5","run":"R","secs":2,"session":"session-1","skills":[],"tokens":900,"tools":3,"type":"Explore"}'
  expect_line "its session ran for the run's seconds" "$(state 7 agents)" '^{"kind":"session",.*"secs":[0-9]*,'
  expect "a line's run marker: the run's start, the same for all its lines" \
    "$(state 7 agents | jq -r '.run' | sort -u | wc -l | tr -d ' ')" 1
  expect_ok "the run marker is a time" jq -e 'select(.run > 1700000000)' "$(idir 7)/agents"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "costs 0.5 $OPUS 10 10 10 10; skill nightshift:plan; comment plan"
  poll
  expect "a resumed run: its own share of the tokens, on the same session" "$(agents 7 | tail -1)" \
'{"kind":"session","models":[],"reply":true,"run":"R","secs":"S","session":"session-1","skills":["nightshift:plan"],"tokens":40,"tools":2,"usd":0.5}'
  expect "its lines are added to the run before's" "$(state 7 agents | wc -l | tr -d ' ')" 4
  expect "a later run starts later or at the same second" "$(state 7 agents | jq -s '.[3].run >= .[0].run')" true
  rm "$(idir 7)/session"
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do "costs 2 $OPUS 1 2 3 4; skill nightshift:build; comment progress"
  poll
  expect "a fresh session: all its tokens, its own id" "$(agents 7 | tail -1)" \
'{"kind":"session","models":[],"reply":true,"run":"R","secs":"S","session":"session-3","skills":["nightshift:build"],"tokens":10,"tools":2,"usd":2}'
  gh_state o/r 7 closed
  poll
  expect "done: the agents stay" "$(state 7 agents | wc -l | tr -d ' ')" 5
  expect_no_unexpected)

# A run that failed or was stopped records what its stream holds, a subagent
# that never finished included.
(world
  gh_issue o/r 7 alice agent
  runs_do "costs 0.5 $OPUS 1 1 1 1; skill nightshift:issue; agent toolu_1 nightshift:ticket 'Build T1'; skill nightshift:build toolu_1
    turn $HAIKU 5 100 0 toolu_1; fail_result"
  poll
  expect "a failed run: its session and its unfinished subagent" "$(agents 7)" \
'{"kind":"session","models":[],"reply":false,"run":"R","secs":"S","session":"session-1","skills":["nightshift:issue"],"tokens":4,"tools":2,"usd":0.5}
{"description":"Build T1","kind":"agent","model":"haiku-4-5","run":"R","secs":null,"session":"session-1","skills":["nightshift:build"],"tokens":null,"tools":1,"type":"nightshift:ticket"}'
  gh_comment o/r 7 alice "again" >/dev/null
  runs_do "turn $OPUS 5 1000 0; skill nightshift:plan; hang"
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/2/waiting"
  ns stop o/r#7 >/dev/null
  wait "$bg"
  expect "a stopped run (no result): its session, no tokens" "$(agents 7 | tail -1)" \
'{"kind":"session","models":["opus-5-5"],"reply":true,"run":"R","secs":"S","session":"session-1","skills":["nightshift:plan"],"tokens":0,"tools":1,"usd":0}')

(world
  gh_issue o/r 7 alice agent
  touch "$CLAUDE_FAKE/silent"
  poll
  expect "a run with no events: nothing recorded" "$(wc -c <"$(idir 7)/agents" | tr -d ' ')" 0)

# A run the user's comment started has reply true; an update run, with only
# the watcher's news, false, even when it resumes a session, and so is a resume
# after an interrupted run.
(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  printf 'conflicts\nit conflicts with master\n' >"$(idir 7)/update"
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:update; commit feature.txt"
  poll
  expect "an update run: no reply" "$(state 7 agents | jq -s -c 'map(.reply)')" "[false,false]"
  gh_comment o/r 7 alice "thanks" >/dev/null
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment progress"
  poll
  expect "a comment after: a reply" "$(state 7 agents | jq -s -c 'map(.reply)')" "[false,false,true]"
  echo "the machine slept" >"$(idir 7)/interrupted"
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment progress"
  poll
  expect "a resume the watcher started: no reply" "$(state 7 agents | jq -s -c 'map(.reply)')" "[false,false,true,false]")

# Shown by status.
(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  echo "1.5 12000 85000 1700000 6000 12 -" >"$(idir 7)/cost"
  expect_line "status: what it cost so far" "$(ns status)" '^o/r#7  *needs you · [0-9]*s · spent \$1\.50, 1\.8M tokens, 1h 40m$'
  echo "0.004 500 0 0 45 1 -" >"$(idir 7)/cost"
  expect_line "status: small sums" "$(ns status)" '^o/r#7  *needs you · [0-9]*s · spent \$0\.00, 500 tokens, 45s$'
  echo "12.345 1000 2000 6000 90000 3 -" >"$(idir 7)/cost"
  expect_line "status: thousands" "$(ns status)" '^o/r#7  *needs you · [0-9]*s · spent \$12\.35, 9k tokens, 1d 1h$'
  rm "$(idir 7)/cost"
  expect_line "status: nothing counted, nothing shown" "$(ns status)" '^o/r#7  *needs you · [0-9]*s$')

# status: the context at the end of the last run.
(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; window $OPUS 1000000; turn $OPUS 5 84000 0; comment questions"
  poll
  expect_line "status: its context" "$(ns status)" '^o/r#7  *needs you · [0-9]*s · spent \$1\.00, 4 tokens, [0-9]*s · context 84k of 1M$'
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "comment plan"
  poll
  expect_line "a run without a turn: the last one's" "$(ns status)" ' · context 84k of 1M$'
  gh_state o/r 7 closed
  poll
  expect_line "done: no context" "$(ns status --all)" '^o/r#7  *done · issue closed .* ago · spent \$1\.00, 4 tokens, [0-9]*s$')

# Posted once it's done.
COMMENT="🤖 \*\*nightshift\*\* · cost"
(world
  gh_issue o/r 7 alice agent
  runs_do 'costs 2.5 opus 12000 85000 1700000 0; commit feature.txt; open_pr; comment done'
  poll
  echo "4.123 12000 85000 1700000 6000 12 -" >"$(idir 7)/cost"
  gh_pr_set o/r "$(state 7 pr | sed 's|.*/||')" state '"MERGED"'
  poll
  expect "merged: done" "$(state 7 "done")" "PR merged"
  comments=$(gh_comments o/r 7)
  expect_line "merged: a cost comment" "$comments" "^$COMMENT$"
  expect_line "it says the dollars, tokens and time" "$comments" \
    '^\*\*\$4\.12\*\* at API prices · \*\*1\.8M tokens\*\* (12k in, 85k out, 1\.7M cache) · \*\*1h 40m\*\* over 12 runs$'
  expect_line "it has the marker" "$comments" "^<!-- nightshift --> <!-- nightshift:cost -->$"
  expect "its cost stays" "$(state 7 cost)" "4.123 12000 85000 1700000 6000 12 -"
  expect_line "status --all: what it spent" "$(ns status --all)" '^o/r#7  *done · PR .* merged .* ago · spent \$4\.12, 1\.8M tokens, 1h 40m$'
  poll
  expect "posted once" "$(gh_comments o/r 7 | grep -c "^$COMMENT$")" 1
  expect "its own comment starts no run" "$(runs)" 1
  gh_comment o/r 7 alice "one more thing" >/dev/null
  runs_do 'costs 1 opus 1 1 1 1; comment progress'
  poll
  expect "brought back: it adds up still" "$(cost 7)" "5.123 12001 85001 1700002 S 13 -"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  echo "0.5 10 20 30 61 1 2026-10-01" >"$(idir 7)/cost"
  gh_state o/r 7 closed
  poll
  expect "closed: done" "$(state 7 "done")" "issue closed"
  expect_line "closed: a cost comment, one run, since it was counted" "$(gh_comments o/r 7)" \
    '^\*\*\$0\.50\*\* at API prices · \*\*60 tokens\*\* (10 in, 20 out, 30 cache) · \*\*1m\*\* over 1 run (counted since 2026-10-01)$')

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  rm "$(idir 7)/cost"
  gh_state o/r 7 closed
  poll
  expect "nothing counted: no cost comment" "$(gh_comments o/r 7 | grep -c "^$COMMENT$" || true)" 0)

# The agents table in the cost comment. Nightshift's own plugin as installed
# has agents and skills, some with an effort in their frontmatter.
own_plugin() {
  local d
  mkdir -p "$NS/plugin/agents"
  for d in issue:low questions:high plan:high build:high; do
    mkdir -p "$NS/plugin/skills/${d%:*}"
    printf -- '---\nname: %s\nmodel: sonnet\neffort: %s\n---\n' "${d%:*}" "${d#*:}" >"$NS/plugin/skills/${d%:*}/SKILL.md"
  done
  printf -- '---\nname: ticket\nmodel: sonnet\neffort: high\n---\n' >"$NS/plugin/agents/ticket.md"
  printf -- '---\nname: spec-review\nmodel: opus\n---\n' >"$NS/plugin/agents/spec-review.md"
}
# The table's rows in the cost comment of issue $1, the time of a session
# (whatever the run took) as S.
table() { gh_comments o/r "$1" | grep '^|' | sed '/↳/!s/| [0-9][0-9]*s |/| S |/'; }
# Closed, so its cost is posted.
finish() { gh_state o/r "$1" closed; poll; }

(world
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1000 2000 3000 4000; turn $OPUS 5 100 0; skill nightshift:issue; skill nightshift:questions
    agent toolu_1 Explore 'Find the cost code'; turn $HAIKU 5 10 0 toolu_1; agent_result toolu_1 $HAIKU 30000 61000 12
    comment questions"
  poll
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "costs 1 $OPUS 500 500 500 500; turn $OPUS 5 1 0; skill nightshift:issue; skill nightshift:plan; comment plan"
  poll
  rm "$(idir 7)/session"
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do "costs 2 $SONNET 1000 1000 1000 1000; turn $OPUS 5 1 0; turn $SONNET 5 1 0; skill nightshift:issue; skill nightshift:build
    agent toolu_1 nightshift:ticket 'Build T1'; skill tdd toolu_1; agent_result toolu_1 $SONNET 60000 420000 16
    agent toolu_2 nightshift:spec-review 'Review the spec'; agent_result toolu_2 $OPUS 40000 120000 9
    comment progress"
  poll
  finish 7
  expect "the done comment: a row a run, each with its subagents and its cost" "$(table 7)" \
'| Agent | Model | Effort | Skills | Tokens | Cost | Time | Tools |
|---|---|---|---|---|---|---|---|
| questions run | opus-5-5 | per skill | issue (low), questions (high) | 10k | $1.00 | S | 4 |
| ↳ Explore · Find the cost code | haiku-4-5 | default | – | 30k | – | 1m | 12 |
| plan run | opus-5-5 | per skill | issue (low), plan (high) | 2k | $1.00 | S | 3 |
| build run | opus-5-5, sonnet-4-5 | per skill | issue (low), build (high) | 4k | $2.00 | S | 5 |
| ↳ ticket · Build T1 | sonnet-4-5 | high | tdd | 60k | – | 7m | 16 |
| ↳ spec-review · Review the spec | opus-5-5 | default | – | 40k | – | 2m | 9 |
| **Total** | – | – | – | 16k | $4.00 | S | 49 |'
  expect_line "three runs: a time line" "$(gh_comments o/r 7)" \
    '^\*\*Time:\*\* [0-9]*s: [0-9]*s working'
  expect "all runs recorded: no partial note" "$(gh_comments o/r 7 | grep -c 'starts from the first recorded run' || true)" 0
  expect_line "the table follows the headline in the one comment" "$(gh_comments o/r 7)" '^| Agent | Model '
  expect "one cost comment" "$(gh_comments o/r 7 | grep -c "^$COMMENT$")" 1
  expect_no_unexpected)

# Efforts come from a repo plugin's agents and skills too; a subagent that
# hadn't finished has no numbers; an unnamed stage is a plain session.
(world
  own_plugin
  plugin other@m
  mkdir -p "$W/other/agents" "$W/other/skills/lint"
  printf -- '---\neffort: max\n---\n' >"$W/other/agents/helper.md"
  printf -- '---\neffort: low\n---\n' >"$W/other/skills/lint/SKILL.md"
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; skill other:lint; skill other:nothing
    agent toolu_1 other:helper 'Help | out'; skill tdd toolu_1; turn $HAIKU 5 100 0 toolu_1; fail_result"
  poll
  finish 7
  expect "a repo plugin's agent and skill: their efforts, its prefix kept" "$(table 7 | tail -3)" \
'| run | – | per skill | issue (low), other:lint (low), other:nothing | 4 | $1.00 | S | 4 |
| ↳ other:helper · Help \| out | haiku-4-5 | max | tdd | – | – | – | 1 |
| **Total** | – | – | – | 4 | $1.00 | S | 5 |'
  expect_no_unexpected)

# No agents file: no table. Runs before the first record: a note.
(world
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  rm "$(idir 7)/agents"
  finish 7
  expect "no agents: no table" "$(gh_comments o/r 7 | grep -c '^|' || true)" 0
  expect_line "no agents: the headline is there" "$(gh_comments o/r 7)" 'at API prices.* over 1 run$')

(world
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; skill nightshift:questions; comment questions"
  poll
  rm "$(idir 7)/agents"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; skill nightshift:plan; comment plan"
  poll
  finish 7
  expect "records from the second run on: only that run's agents" "$(table 7 | tail -2)" \
'| plan run | – | per skill | issue (low), plan (high) | 4 | $1.00 | S | 3 |
| **Total** | – | – | – | 4 | $2.00 | S | 3 |'
  expect_line "and a note under the table" "$(gh_comments o/r 7)" '^_The table starts from the first recorded run: earlier runs have no agent records\._$')

# A session resumed after another ran: its later run comes after that one's,
# with its own subagents, not merged into the session's first row. A record
# without dollars has none; a run without a stage skill is a plain run. The
# total row has the issue's dollars (from `cost`, runs before records
# included) and what the rows add up to; the time line splits the time from
# the first run's start to the last one's end.
(world
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  echo "7.5 1000 0 0 100 5 -" >"$(idir 7)/cost"
  printf '%s\n' \
    '{"kind":"session","run":2000000300,"session":"s1","models":["opus-5-5"],"skills":["nightshift:plan"],"tools":2,"secs":50,"tokens":300,"usd":0.5,"reply":true}' \
    '{"kind":"agent","run":2000000300,"session":"s1","type":"Explore","description":"Late look","model":"haiku-4-5","skills":[],"tokens":10,"secs":5,"tools":1}' \
    '{"kind":"session","run":2000000100,"session":"s1","models":["opus-5-5"],"skills":["nightshift:issue","nightshift:questions"],"tools":4,"secs":60,"tokens":100,"usd":1.234,"reply":false}' \
    '{"kind":"session","run":2000000200,"session":"s2","models":["opus-5-5"],"skills":["nightshift:build"],"tools":3,"secs":70,"tokens":200,"reply":false}' \
    '{"kind":"agent","run":2000000200,"session":"s2","type":"Explore","description":"Early look","model":"haiku-4-5","skills":[],"tokens":20,"secs":5,"tools":2}' \
    '{"kind":"session","run":2000000400,"session":"s3","models":[],"skills":[],"tools":1,"secs":10,"tokens":0,"usd":0,"reply":false}' \
    >"$(idir 7)/agents"
  finish 7
  expect "runs in the order they ran, a session's later run after the other's, cost from usd, then the total" "$(table 7 | sed 1,2d)" \
'| questions run | opus-5-5 | per skill | issue (low), questions (high) | 100 | $1.23 | 1m | 4 |
| build run | opus-5-5 | per skill | build (high) | 200 | – | 1m | 3 |
| ↳ Explore · Early look | haiku-4-5 | default | – | 20 | – | 5s | 2 |
| plan run | opus-5-5 | per skill | plan (high) | 300 | $0.50 | S | 2 |
| ↳ Explore · Late look | haiku-4-5 | default | – | 10 | – | 5s | 1 |
| run | – | per skill | – | 0 | $0.00 | S | 1 |
| **Total** | – | – | – | 600 | $7.50 | 3m | 13 |'
  expect "the time line: gaps before a reply are waiting on you, the others other waits" \
    "$(gh_comments o/r 7 | grep '^\*\*Time')" \
    '**Time:** 5m: 3m working · 30s waiting on you · 1m other waits'
  expect "under the table, after a blank line" "$(gh_comments o/r 7 | grep -B2 '^\*\*Time' | sed -n '1p;2p' | tr '\n' '~')" '| **Total** | – | – | – | 600 | $7.50 | 3m | 13 |~~')

# Zero parts are left out of the time line; one run has none.
(world
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  printf '%s\n' \
    '{"kind":"session","run":2000000000,"session":"s1","models":[],"skills":[],"tools":1,"secs":600,"tokens":1,"usd":1,"reply":false}' \
    '{"kind":"session","run":2000004200,"session":"s1","models":[],"skills":[],"tools":1,"secs":300,"tokens":1,"usd":1,"reply":true}' \
    >"$(idir 7)/agents"
  finish 7
  expect "a wait for a reply only: no other waits" "$(gh_comments o/r 7 | grep '^\*\*Time')" \
    '**Time:** 1h 15m: 15m working · 1h 0m waiting on you')

(world
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  printf '%s\n' \
    '{"kind":"session","run":2000000000,"session":"s1","models":[],"skills":[],"tools":1,"secs":600,"tokens":1,"usd":1,"reply":false}' \
    '{"kind":"session","run":2000000600,"session":"s1","models":[],"skills":[],"tools":1,"secs":300,"tokens":1,"usd":1,"reply":false}' \
    '{"kind":"session","run":2000000900,"session":"s1","models":[],"skills":[],"tools":1,"secs":300,"tokens":1,"usd":1}' \
    >"$(idir 7)/agents"
  finish 7
  expect "touching runs, no reply fields: working alone" "$(gh_comments o/r 7 | grep '^\*\*Time')" \
    '**Time:** 20m: 20m working'
  expect "and the total row's time is the working time" "$(table 7 | tail -1)" '| **Total** | – | – | – | 3 | $1.00 | 20m | 3 |')

(world
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  finish 7
  expect "one run: no time line" "$(gh_comments o/r 7 | grep -c '^\*\*Time' || true)" 0
  expect "its total row" "$(table 7 | tail -1 | sed 's/| [0-9]*s |/| S |/')" '| **Total** | – | – | – | 4 | $1.00 | S | 2 |')

(world
  own_plugin
  gh_issue o/r 7 alice agent
  touch "$CLAUDE_FAKE/silent"
  poll
  rm "$CLAUDE_FAKE/silent"
  gh_comment o/r 7 alice "again" >/dev/null
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  finish 7
  expect "a first run with no events: no partial note" "$(gh_comments o/r 7 | grep -c 'starts from the first recorded run' || true)" 0)

# The cost comment's second line: the dollars of each model, and the pull
# request's size, each left out when unknown.
# The line after the headline, if there is one (the headline is the first line
# with the dollars; the table or the marker follows a blank line).
second() { gh_comments o/r "$1" | grep -A1 'at API prices' | sed -n 2p; }
# The pull request of issue $1 merged, with its size given as additions $2,
# deletions $3 and changed files $4.
merge_pr() {
  local n
  n=$(state "$1" pr | sed 's|.*/||')
  gh_pr_set o/r "$n" additions "$2"
  gh_pr_set o/r "$n" deletions "$3"
  gh_pr_set o/r "$n" changedFiles "$4"
  gh_pr_set o/r "$n" state '"MERGED"'
  poll
}

(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1.2 $OPUS 1 1 1 1; costs 0.2 $HAIKU 1 1 1 1; comment questions"
  poll
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "costs 0.5 $OPUS 1 1 1 1; costs 0.3 $SONNET 1 1 1 1; comment plan"
  poll
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do "costs 2.5 $OPUS 1 1 1 1; commit feature.txt; open_pr; comment done"
  poll
  merge_pr 7 412 37 9
  expect "dollars per model, summed over the runs (a resumed session's share each), most first, and the pull request's size" \
    "$(second 7)" "opus-5-5 \$4.20 · sonnet-4-5 \$0.30 · haiku-4-5 \$0.20 · PR +412 −37 in 9 files"
  expect_line "the headline is above it" "$(gh_comments o/r 7)" '^\*\*\$4\.70\*\* at API prices'
  expect "the models stay in the done issue's state" "$(state 7 models | wc -l | tr -d ' ')" 3
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; commit feature.txt; open_pr; comment done"
  poll
  merge_pr 7 3 0 1
  expect "one file, one model" "$(second 7)" "opus-5-5 \$1.00 · PR +3 −0 in 1 file")

(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; commit feature.txt; open_pr; comment done"
  poll
  gh_pr_set o/r "$(state 7 pr | sed 's|.*/||')" state '"MERGED"'
  poll
  expect "no size known (the pull request has none): the models alone" "$(second 7)" "opus-5-5 \$1.00"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; commit feature.txt; open_pr; comment done"
  poll
  echo "pr view *" >"$GH_FAKE/fail"
  merge_pr 7 5 6 7
  expect "gh fails on the pull request: the models alone" "$(second 7)" "opus-5-5 \$1.00")

(world
  gh_issue o/r 7 alice agent
  runs_do "comment questions"
  poll
  gh_state o/r 7 closed
  poll
  expect "no models, no pull request: no second line, the table or marker follows a blank line" \
    "$(second 7)" ""
  expect "and the comment is posted" "$(gh_comments o/r 7 | grep -c "^$COMMENT$")" 1)

(world
  gh_issue o/r 7 alice agent
  runs_do "comment questions"
  poll
  echo "1 1 1 1 1 1 -" >"$(idir 7)/cost"
  runs_do "commit feature.txt; open_pr; comment done"
  gh_comment o/r 7 alice "go" >/dev/null
  poll
  merge_pr 7 8 9 2
  expect "a pull request but no models: its size alone" "$(second 7)" "PR +8 −9 in 2 files")

report
