#!/usr/bin/env bash
# Tests for what a poll asks GitHub: the issues list with the ETag of the last
# answer, so an unchanged repo costs no rate limit.
#   bash scripts/test-polling.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

LIST="api -i.*repos/o/r/issues?labels=agent"

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "the first poll: no ETag to send" "$(gh_calls "$LIST" | grep -c If-None-Match)" 0
  expect_ok "the ETag is kept" test -s "$NS/poll/o_r.etag"
  poll
  expect "the run changed the issue: it's listed again" "$(gh_calls "$LIST" | tail -1 | grep -c If-None-Match)" 1
  etag=$(cat "$NS/poll/o_r.etag")
  poll
  expect "nothing changed: the same ETag" "$(cat "$NS/poll/o_r.etag")" "$etag"
  expect "nothing changed: no run" "$(runs)" 1
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "a comment changes the ETag" "$([ "$(cat "$NS/poll/o_r.etag")" != "$etag" ] && echo changed)" changed
  expect "a comment: a run" "$(runs)" 2
  expect_line "its news: the comment" "$(run_prompt)" "^1 yes$"
  expect_no_unexpected)

# A 304 still lets the rest of the poll work from the last answer: issues
# waiting for a slot start when one frees.
(world
  set_config max_parallel 0
  gh_issue o/r 7 alice agent
  gh_issue o/r 8 alice agent
  poll
  poll
  etag=$(cat "$NS/poll/o_r.etag")
  poll
  expect "no slot: both wait" "$(runs)" 0
  set_config max_parallel 2
  poll
  expect "the list hadn't changed" "$(gh_calls "$LIST" | sed -n '$p' | grep -c "If-None-Match: $etag")" 1
  expect "a slot frees after a 304: both start" "$(runs)" 2)

# The list failing: that poll skips the repo; the next lists it again.
(world
  gh_issue o/r 7 alice agent
  echo "api -i*" >"$GH_FAKE/fail"
  poll
  expect "no list: no run" "$(runs)" 0
  rm "$GH_FAKE/fail"
  poll
  expect "listed again: a run" "$(runs)" 1)

# A proposed issue (one a run filed): held until you comment.
(world
  gh_issue o/r 7 alice agent "nightshift: proposed"
  poll
  poll
  expect "proposed, no comment: no run" "$(runs)" 0
  gh_comment o/r 7 alice "worth fixing" >/dev/null
  poll
  expect "your comment: its first run" "$(runs)" 1
  expect_line "its prompt: the comment, after the first-run text" "$(run_prompt | sed -n '/This is your first run/,$p')" "^worth fixing$"
  expect_line "its status: proposed no more" "$(status_label 7)" "^proposed$" no)

(world
  gh_issue o/r 7 alice agent "nightshift: proposed"
  poll
  gh_comment o/r 7 mallory "do it" >/dev/null
  poll
  expect "proposed, someone else's comment: no run" "$(runs)" 0
  expect "its status: proposed" "$(status_label 7)" proposed)

(world
  gh_issue o/r 7 alice agent "nightshift: proposed"
  poll
  gh_label_remove o/r 7 alice "nightshift: proposed"
  poll
  expect "proposed, the label removed: its first run" "$(runs)" 1)

# A sub-issue waiting on open blockers: no run until they close.
(world
  gh_issue o/r 7 alice agent
  gh_set_blocked_by o/r 7 2
  poll
  poll
  expect "open blockers, first run: no run" "$(runs)" 0
  expect "its status: waiting" "$(status_label 7)" waiting
  expect "its updated isn't recorded" "$(state 7 updated)" ""
  gh_comment o/r 7 alice "hello" >/dev/null
  poll
  expect "a comment while blocked: still no run" "$(runs)" 0
  gh_set_blocked_by o/r 7 1
  poll
  expect "one blocker still open: no run" "$(runs)" 0
  gh_set_blocked_by o/r 7 0
  poll
  expect "no open blockers: its first run" "$(runs)" 1
  expect_line "the comment made while it waited reaches the run" "$(run_prompt)" "^hello$"
  expect_line "its status: waiting no more" "$(status_label 7)" "^waiting$" no)

# Blockers matter only before the first run.
(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "a first run" "$(runs)" 1
  gh_set_blocked_by o/r 7 1
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "worked on already: a comment still starts a run" "$(runs)" 2
  expect_line "its status: not waiting" "$(status_label 7)" "^waiting$" no)

# The pull requests: every 30 s at most.
(world
  unset NIGHTSHIFT_PR_INTERVAL
  poll
  poll
  expect "two polls in 30 s: the pull requests listed once" "$(gh_calls "^pr list .*--state open" | wc -l | tr -d ' ')" 1
  echo $(($(date +%s) - 31)) >"$NS/poll/o_r.prs"
  poll
  expect "30 s later: listed again" "$(gh_calls "^pr list .*--state open" | wc -l | tr -d ' ')" 2)

# Who gh is logged in as (allowed_users' default): asked once by a watch.
(world
  set_config interval 1
  "$ROOT/nightshift" watch &
  bg=$!
  i=0
  until [ "$(gh_calls '^api -i' | wc -l)" -ge 3 ] || [ $i -gt 100 ]; do sleep 0.1; i=$((i + 1)); done
  kill -TERM "$bg"
  wait "$bg" || true
  expect_ok "three polls" test "$(grep -c '^api -i' "$GH_FAKE/calls")" -ge 3
  expect "the login: asked once" "$(gh_calls "^api user " | wc -l | tr -d ' ')" 1)

report
