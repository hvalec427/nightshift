#!/usr/bin/env bash
# Tests for the agents table in the cost comment: a row for each run and its
# subagents, their models, efforts, tokens, cost and time, and its total row.
#   bash scripts/test-cost-table.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# The agents table in the cost comment, which cost_breakdown=true turns on.
# Nightshift's own plugin as installed has agents and skills, some with an
# effort in their frontmatter.
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
  origin_config cost_breakdown=true
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1000 2000 3000 4000; turn $OPUS 5 100 0; skill nightshift:issue; skill nightshift:questions
    agent toolu_1 Explore 'Find the cost code'; turn $HAIKU 0 29999 0 toolu_1; agent_result toolu_1 $HAIKU 30000 61000 12
    comment questions"
  poll
  gh_comment o/r 7 alice "1 yes" >/dev/null
  runs_do "costs 1 $OPUS 500 500 500 500; turn $OPUS 5 1 0; skill nightshift:issue; skill nightshift:plan; comment plan"
  poll
  rm "$(idir 7)/session"
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do "costs 2 $SONNET 100000 100000 100000 100000; costs 0.5 $OPUS 20000 20000 20000 20000
    turn $OPUS 5 1 0; turn $SONNET 5 1 0; skill nightshift:issue; skill nightshift:build
    agent toolu_1 nightshift:ticket 'Build T1'; skill tdd toolu_1
    turn $SONNET 0 59999 0 toolu_1 msg_1; turn $SONNET 0 59999 0 toolu_1 msg_1; turn $SONNET 0 59999 0 toolu_1 msg_2
    agent_result toolu_1 $SONNET 60000 420000 16
    agent toolu_2 nightshift:spec-review 'Review the spec'; turn $OPUS 0 39999 0 toolu_2; agent_result toolu_2 $OPUS 40000 120000 9
    comment progress"
  poll
  finish 7
  expect "the done comment: a row a run, each with its subagents and its cost" "$(table 7)" \
'| Agent | Model | Effort | Skills | Tokens | Cost | Time | Tools |
|---|---|---|---|---|---|---|---|
| questions run | opus-5-5 | per skill | issue (low), questions (high) | 10k | $1.00 | S | 4 |
| ↳ Explore · Find the cost code | haiku-4-5 | default | – | 30k | – | 1m | 12 |
| plan run | opus-5-5 | per skill | issue (low), plan (high) | 2k | $1.00 | S | 3 |
| build run | opus-5-5, sonnet-4-5 | per skill | issue (low), build (high) | 480k | $1.65 | S | 5 |
| ↳ ticket · Build T1 | sonnet-4-5 | high | tdd | 120k | ~$0.60 | 7m | 16 |
| ↳ spec-review · Review the spec | opus-5-5 | default | – | 40k | ~$0.25 | 2m | 9 |
| **Total** | – | – | – | 492k | $4.50 | S | 49 |'
  expect_line "three runs: a time line" "$(gh_comments o/r 7)" \
    '^\*\*Time:\*\* [0-9]*s: [0-9]*s working'
  expect "all runs recorded: no partial note" "$(gh_comments o/r 7 | grep -c 'starts from the first recorded run' || true)" 0
  expect_line "the table follows the headline in the one comment" "$(gh_comments o/r 7)" '^| Agent | Model '
  expect "one cost comment" "$(gh_comments o/r 7 | grep -c "^$COMMENT$")" 1
  expect_no_unexpected)

# Efforts come from a repo plugin's agents and skills too; a subagent that
# hadn't finished has only the tokens of its turns so far; an unnamed stage is a plain session.
(world
  origin_config cost_breakdown=true
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
| ↳ other:helper · Help \| out | haiku-4-5 | max | tdd | 106 | – | – | 1 |
| **Total** | – | – | – | 4 | $1.00 | S | 5 |'
  expect_no_unexpected)

# No agents file: no table. Runs before the first record: a note.
(world
  origin_config cost_breakdown=true
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  rm "$(idir 7)/agents"
  finish 7
  expect "no agents: no table" "$(gh_comments o/r 7 | grep -c '^|' || true)" 0
  expect_line "no agents: the headline is there" "$(gh_comments o/r 7)" 'at API prices.* over 1 run$')

(world
  origin_config cost_breakdown=true
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
  origin_config cost_breakdown=true
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

# A subagent's tokens and cost are the tokens of its turns (`spent`, not its result's
# last-turn `tokens`; a message streamed as several events counted once) at
# the rate of its model in that run (the run's dollars over its tokens), `~`-marked as an estimate; its run's row is
# the run's dollars less those, never below 0. No split, an unfinished
# subagent or a model the run didn't use: no cost.
(world
  origin_config cost_breakdown=true
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  printf '%s\n' \
    '{"kind":"session","run":2000000100,"session":"s1","models":["opus-5-5"],"skills":["nightshift:plan"],"tools":2,"secs":60,"tokens":1000,"usd":1,"byModel":{"opus-5-5":{"tokens":600,"usd":0.9},"haiku-4-5":{"tokens":400,"usd":0.1}}}' \
    '{"kind":"agent","run":2000000100,"session":"s1","type":"Explore","description":"Two","model":"haiku-4-5","skills":[],"tokens":20,"spent":200,"secs":5,"tools":1}' \
    '{"kind":"agent","run":2000000100,"session":"s1","type":"Explore","description":"Three","model":"opus-5-5","skills":[],"tokens":30,"spent":300,"secs":5,"tools":1}' \
    '{"kind":"agent","run":2000000100,"session":"s1","type":"Explore","description":"Not done","model":"haiku-4-5","skills":[],"tokens":null,"spent":null,"secs":null,"tools":1}' \
    '{"kind":"agent","run":2000000100,"session":"s1","type":"Explore","description":"Other model","model":"sonnet-4-5","skills":[],"tokens":100,"spent":100,"secs":5,"tools":1}' \
    '{"kind":"session","run":2000000200,"session":"s1","models":["opus-5-5"],"skills":["nightshift:build"],"tools":2,"secs":60,"tokens":1000,"usd":0.5,"byModel":{"opus-5-5":{"tokens":1000,"usd":0.5}}}' \
    '{"kind":"agent","run":2000000200,"session":"s1","type":"Explore","description":"Most of it","model":"opus-5-5","skills":[],"tokens":900,"spent":900,"secs":5,"tools":1}' \
    '{"kind":"agent","run":2000000200,"session":"s1","type":"Explore","description":"Too much","model":"opus-5-5","skills":[],"tokens":900,"spent":900,"secs":5,"tools":1}' \
    '{"kind":"session","run":2000000300,"session":"s2","models":["opus-5-5"],"skills":["nightshift:plan"],"tools":2,"secs":60,"tokens":1000,"usd":0.5}' \
    '{"kind":"agent","run":2000000300,"session":"s2","type":"Explore","description":"Old record","model":"opus-5-5","skills":[],"tokens":100,"secs":5,"tools":1}' \
    >"$(idir 7)/agents"
  echo "1.5 0 0 0 0 3 -" >"$(idir 7)/cost"
  finish 7
  expect "estimates from the run's split; the run's row is the rest, at least 0" "$(table 7 | sed 1,2d | sed 's/| [0-9][0-9]*m |/| T |/;s/| [0-9][0-9]*s |/| T |/')" \
'| plan run | opus-5-5 | per skill | plan (high) | 1k | $0.50 | T | 2 |
| ↳ Explore · Two | haiku-4-5 | default | – | 200 | ~$0.05 | T | 1 |
| ↳ Explore · Three | opus-5-5 | default | – | 300 | ~$0.45 | T | 1 |
| ↳ Explore · Not done | haiku-4-5 | default | – | – | – | – | 1 |
| ↳ Explore · Other model | sonnet-4-5 | default | – | 100 | – | T | 1 |
| build run | opus-5-5 | per skill | build (high) | 1k | $0.00 | T | 2 |
| ↳ Explore · Most of it | opus-5-5 | default | – | 900 | ~$0.45 | T | 1 |
| ↳ Explore · Too much | opus-5-5 | default | – | 900 | ~$0.45 | T | 1 |
| plan run | opus-5-5 | per skill | plan (high) | 1k | $0.50 | T | 2 |
| ↳ Explore · Old record | opus-5-5 | default | – | 100 | – | T | 1 |
| **Total** | – | – | – | 3k | $1.50 | T | 13 |')

# Zero parts are left out of the time line; one run has none.
(world
  origin_config cost_breakdown=true
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
  origin_config cost_breakdown=true
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
  origin_config cost_breakdown=true
  own_plugin
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:issue; comment questions"
  poll
  finish 7
  expect "one run: no time line" "$(gh_comments o/r 7 | grep -c '^\*\*Time' || true)" 0
  expect "its total row" "$(table 7 | tail -1 | sed 's/| [0-9]*s |/| S |/')" '| **Total** | – | – | – | 4 | $1.00 | S | 2 |')

(world
  origin_config cost_breakdown=true
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
report
