#!/usr/bin/env bash
# Tests for the runs after the first: what comments start one and what it's
# told, failed runs, and runs stopped partway (by `nightshift stop`, the label
# going, the issue closing, a hold label) and resumed.
#   bash scripts/test-followups.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A first run that asks questions, done.
asked() {
  gh_issue o/r 7 alice agent "$@"
  runs_do 'comment questions'
  poll
}

# A poll in the background whose run waits to be stopped: $BG is the poll.
start_hanging() {
  runs_do '[ "$k" = 1 ] && hang; comment questions'
  "$ROOT/nightshift" once &
  BG=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
}

(world
  asked
  id=$(gh_comment o/r 7 alice "1 yes, 2 b")
  poll
  expect "a comment from an allowed user: a run" "$(runs)" 2
  expect "it resumes the session" "$(run_opt --resume)" session-1
  expect_line "it's told what's new" "$(run_prompt)" "^New on the issue since your last run:$"
  expect_line "the comment, with who wrote it" "$(run_prompt)" "^- @alice (comment $id):$"
  expect_line "the comment's text" "$(run_prompt)" "^1 yes, 2 b$"
  expect "the comment is marked seen" "$(state 7 seen)" "$id"
  expect "the session stays" "$(state 7 session)" session-1
  poll
  expect "a seen comment: no run" "$(runs)" 2
  gh_comment o/r 7 bob "me too" >/dev/null
  poll
  expect "a comment from someone not allowed: no run" "$(runs)" 2
  gh_comment o/r 7 alice "🤖 **nightshift** · progress
<!-- nightshift -->" >/dev/null
  poll
  expect "a nightshift comment: no run" "$(runs)" 2
  id2=$(gh_comment o/r 7 bob "from bob")
  id3=$(gh_comment o/r 7 alice "from alice")
  poll
  expect "the next comment: a run" "$(runs)" 3
  expect_line "only the allowed user's comment" "$(run_prompt)" "comment $id2" no
  expect_line "with the allowed user's comment" "$(run_prompt)" "^- @alice (comment $id3):$"
  expect_no_unexpected)

(world
  asked bug
  gh_label_remove o/r 7 alice bug
  gh_label_add o/r 7 alice question
  gh_comment o/r 7 alice "it's a question really" >/dev/null
  poll
  expect_line "a changed type: the run is told, and to leave it" "$(run_prompt)" \
    '^Its type label: `question`\. The user changed it since your last run, from bug: leave it as they set it\.$')

# Failed runs.
(world
  gh_issue o/r 7 alice agent
  runs_do 'say "Something broke."; code=3'
  poll
  expect_line "a failed run: a comment saying so" "$(gh_comments o/r 7)" "the last run failed. Reply to try again."
  expect_line "with the end of its log" "$(gh_comments o/r 7)" "Something broke\."
  expect_line "the comment is nightshift's" "$(gh_comments o/r 7)" "<!-- nightshift -->"
  expect "a failed run: needs you" "$(status_label 7)" "needs you"
  expect_line "its log: failed, with the exit status" "$(cat "$(idir 7)/log")" "^0	=== [0-9:]* run failed (3) after "
  poll
  expect "the failure comment doesn't start a run" "$(runs)" 1
  gh_comment o/r 7 alice "try again" >/dev/null
  runs_do 'comment questions'
  poll
  expect "a reply after a failure: a run" "$(runs)" 2)

(world
  gh_issue o/r 7 alice agent
  runs_do 'fail_result'
  poll
  expect_line "an error result: failed too" "$(gh_comments o/r 7)" "the last run failed"
  expect_line "its log: failed (0)" "$(cat "$(idir 7)/log")" "run failed (0) after ")

(world
  echo 'issue comment *' >"$GH_FAKE/fail"
  gh_issue o/r 7 alice agent
  runs_do 'code=1'
  poll
  expect_line "the failure comment can't be posted: logged" "$(cat "$NS/watch.log")" "o/r#7: couldn't comment the failure")

# Stopped by hand.
(world
  gh_issue o/r 7 alice agent
  start_hanging
  expect "stop <issue>: stops its run" "$(ns stop o/r#7)" "stopped o/r#7"
  wait "$BG"
  expect_ok "the run got TERM" test -f "$CLAUDE_FAKE/runs/1/stopped"
  expect "stopped: its label says so" "$(status_label 7)" stopped
  expect_line "its log: stopped" "$(cat "$(idir 7)/log")" "^0	=== [0-9:]* run stopped after "
  expect "the session is kept, to resume" "$(state 7 session)" session-1
  set +e
  out=$(ns stop o/r#7 2>&1)
  st=$?
  set -e
  expect "stop, when it isn't running: fails" "$st" 1
  expect "stop, when it isn't running: says so" "$out" "nightshift: o/r#7 isn't running"
  set +e
  out=$(ns stop o/r7 2>&1)
  set -e
  expect "stop, a bad issue: the usage" "$out" "nightshift: usage: nightshift stop [<owner/repo>#<n>]"
  gh_comment o/r 7 alice "go on" >/dev/null
  poll
  expect "a comment after a stop: it resumes" "$(run_opt --resume)" session-1)

# Stopped by the label going, and back.
(world
  gh_issue o/r 7 alice agent
  start_hanging
  gh_label_remove o/r 7 alice agent
  poll
  wait "$BG"
  expect_ok "the label removed mid-run: the run is stopped" test -f "$CLAUDE_FAKE/runs/1/stopped"
  expect "it's marked off" "$(state 7 off)" "label removed"
  expect "and interrupted" "$(state 7 interrupted)" "label removed"
  expect "its label: stopped" "$(status_label 7)" stopped
  expect_line "status: how to resume" "$(ns status)" "stopped .* ago (label removed) · add the label back to resume"
  poll
  expect "still off: no run" "$(runs)" 1
  gh_label_add o/r 7 alice agent
  poll
  expect "the label back: it resumes" "$(runs)" 2
  expect "with its session" "$(run_opt --resume)" session-1
  expect_line "told why it stopped" "$(run_prompt)" \
    "^Your last run was stopped partway because the agent label was removed; that's undone now, so carry on from where it stopped\.$"
  expect_ok "no longer off" test ! -f "$(idir 7)/off"
  expect_ok "no longer interrupted" test ! -f "$(idir 7)/interrupted"
  expect "done again: needs you" "$(status_label 7)" "needs you")

(world
  gh_issue o/r 7 alice agent
  start_hanging
  gh_state o/r 7 closed
  poll
  wait "$BG"
  expect "closed mid-run: off" "$(state 7 off)" "issue closed"
  expect_ok "closed mid-run: not done, it can resume" test ! -f "$(idir 7)/done"
  expect_line "status: reopen to resume" "$(ns status)" "(issue closed) · reopen to resume"
  gh_state o/r 7 open
  poll
  expect_line "reopened: it resumes, told why" "$(run_prompt)" "^Your last run was stopped partway because the issue was closed;")

(world
  gh_issue o/r 7 alice agent
  start_hanging
  gh_label_add o/r 7 alice wontfix
  poll
  wait "$BG"
  expect "wontfix added mid-run: off" "$(state 7 off)" "wontfix label added"
  expect_line "status: remove it to resume" "$(ns status)" "remove the wontfix label to resume"
  gh_label_remove o/r 7 alice wontfix
  poll
  expect_line "wontfix removed: it resumes, told why" "$(run_prompt)" "^Your last run was stopped partway because the wontfix label was added;")

(world
  gh_issue o/r 7 alice agent invalid
  poll
  expect "labelled, but invalid: no run" "$(runs)" 0)

# Off while idle, and back.
(world
  asked
  gh_label_remove o/r 7 alice agent
  poll
  expect "the label removed while idle: off" "$(state 7 off)" "label removed"
  expect "its status label goes" "$(status_label 7)" ""
  expect_line "status: what happened" "$(ns status)" "o/r#7 .*label removed .* ago"
  gh_label_add o/r 7 alice agent
  poll
  expect "the label back, nothing new: no run" "$(runs)" 1
  expect "its status label is back" "$(status_label 7)" "needs you"
  expect_no_unexpected)

report
