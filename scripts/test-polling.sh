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
