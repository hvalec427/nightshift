#!/usr/bin/env bash
# Tests for working from a GitHub project board: the repo's `project=` makes
# the cards in the working columns its issues, in place of the `agent` label.
#   bash scripts/test-board.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# The board, alice's project 5, named in o/r's config.
BOARD=alice/5
board() {
  gh_project "$BOARD"
  origin_config "project=https://github.com/users/alice/projects/5"
}
QUERY="graphql .*query NightshiftBoard"
# How many issues repo $1 has on the fake GitHub.
issue_count() { find "$(gh_dir "$1")/issues" -name '[0-9]*.json' ! -name '*.*.json' | wc -l | tr -d ' '; }

# With no project=, the label list is read, and no board.
(world
  gh_issue o/r 7 alice agent
  poll
  expect "no project: the labelled issue runs" "$(runs)" 1
  expect "no project: the issues list is read" "$(gh_calls "^api -i.*repos/o/r/issues?labels=agent" | wc -l | tr -d ' ')" 1
  expect "no project: no board query" "$(gh_calls "$QUERY" | wc -l | tr -d ' ')" 0
  expect_no_unexpected)

# A board repo: the card's column decides, the label doesn't.
(world
  board
  gh_issue o/r 7 alice
  gh_issue o/r 8 alice
  gh_issue o/r 9 alice
  gh_issue o/r 10 alice agent
  gh_issue o/r 11 alice
  gh_card "$BOARD" o/r 7 Ready
  gh_card "$BOARD" o/r 8 Backlog
  gh_card "$BOARD" o/r 9 Done
  gh_card "$BOARD" o/r 11 "In progress"
  poll
  expect "the board is read by the query: once, and twice more for card 7's move to Needs you" "$(gh_calls "$QUERY" | wc -l | tr -d ' ')" 3
  expect "the board repo doesn't list by label" "$(gh_calls "repos/o/r/issues?labels" | wc -l | tr -d ' ')" 0
  expect "runs: Ready and In progress only" "$(runs)" 2
  expect_ok "a card in Ready: a first run" test -f "$(idir 7)/started"
  expect_ok "a card in In progress: a run" test -f "$(idir 11)/started"
  expect_ok "Backlog: no run" test ! -d "$(idir 8)"
  expect_ok "Done: no run" test ! -d "$(idir 9)"
  expect_ok "an agent issue off the board: no run" test ! -d "$(idir 10)"
  expect_no_unexpected)

# Other repos' cards on the same board start nothing.
(world
  board
  gh_repo x/y "$ORIGIN"
  gh_issue x/y 1 alice
  gh_card "$BOARD" x/y 1 Ready
  poll
  expect "another repo's card: no run" "$(runs)" 0
  expect_no_unexpected)

# A card moved back to Backlog stops its run; forward again, it resumes.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do '[ "$k" = 1 ] && hang; comment questions'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  gh_card_move "$BOARD" o/r 7 Backlog
  poll
  wait "$bg"
  expect_ok "moved to Backlog mid-run: the run is stopped" test -f "$CLAUDE_FAKE/runs/1/stopped"
  expect "it's marked off, and why" "$(state 7 off)" "moved to Backlog"
  expect "and interrupted" "$(state 7 interrupted)" "moved to Backlog"
  poll
  expect "still in Backlog: no run" "$(runs)" 1
  gh_card_move "$BOARD" o/r 7 Ready
  poll
  expect "moved forward again: it resumes" "$(runs)" 2
  expect "with its session" "$(run_opt --resume)" session-1
  expect "no longer off" "$(state 7 off)" ""
  expect_no_unexpected)

# A card moved to Done stops its run, as one moved to Backlog does.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do '[ "$k" = 1 ] && hang; comment questions'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  gh_card_move "$BOARD" o/r 7 Done
  poll
  wait "$bg"
  expect_ok "moved to Done mid-run: the run is stopped" test -f "$CLAUDE_FAKE/runs/1/stopped"
  expect "it's marked off, and why" "$(state 7 off)" "moved to Done"
  poll
  expect "still in Done: no run" "$(runs)" 1
  expect_no_unexpected)

# A card taken off the board is off.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'comment questions'
  poll
  gh_card_remove "$BOARD" o/r 7
  poll
  expect "off the board: marked off" "$(state 7 off)" "removed from the board")

# The board can't be read: that poll skips the repo, the next one reads it.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  echo "api graphql*" >"$GH_FAKE/fail"
  poll
  expect "no board: no run" "$(runs)" 0
  expect_line "and the log says so" "$(cat "$NS/watch.log")" "o/r: couldn't read the board"
  rm "$GH_FAKE/fail"
  poll
  expect "read again: a run" "$(runs)" 1)

# The project's URL: an organisation's, with a view on the end.
(world
  gh_project acme/3
  gh_issue o/r 7 alice
  gh_card acme/3 o/r 7 "Ready to merge"
  origin_config "project=https://github.com/orgs/acme/projects/3/views/2"
  poll
  expect "an org project with a view: read" "$(gh_calls "$QUERY" | wc -l | tr -d ' ')" 1
  expect "a card in Ready to merge: worked" "$(runs)" 1)

# A column that isn't one of the seven isn't worked; one that is, whatever its case.
(world
  gh_project alice/5 backlog ready "Blocked"
  origin_config "project=https://github.com/users/alice/projects/5"
  gh_issue o/r 7 alice
  gh_issue o/r 8 alice
  gh_card alice/5 o/r 7 Blocked
  gh_card alice/5 o/r 8 ready
  poll
  expect "a column of its own: no run" "$(state 7 started)" ""
  expect "a column in lower case: a run" "$(runs)" 1)

# A draft card in Ready becomes an issue in the repo, which is worked; drafts in
# other columns are left alone.
(world
  board
  d1=$(gh_draft "$BOARD" "Add a dark mode" Ready)
  d2=$(gh_draft "$BOARD" "Some idea" Backlog)
  d3=$(gh_draft "$BOARD" "Being built" "In progress")
  poll
  expect "the Ready draft is an issue now" "$(jq -r .title "$(gh_dir o/r)/issues/1.json")" "Add a dark mode"
  expect "and its card waits in Needs you after the run" "$(gh_card_column "$BOARD" o/r 1)" "Needs you"
  expect "the card kept its item id" "$(jq -r '.[0].id' "$(gh_project_dir "$BOARD")/items.json")" "$d1"
  expect "a run started on the new issue" "$(runs)" 1
  expect_ok "on issue 1" test -f "$(idir 1)/started"
  expect "the other drafts are still drafts" "$(jq '[.[] | select(.draft)] | length' "$(gh_project_dir "$BOARD")/items.json")" 2
  expect "Backlog and In progress drafts: no issue" "$(issue_count o/r)" 1
  expect_no_unexpected
  : "$d2$d3")

# A converted draft is converted once: the next poll makes no second issue.
(world
  board
  gh_draft "$BOARD" "Add a dark mode" Ready >/dev/null
  runs_do 'comment questions'
  poll
  poll
  expect "one issue, not two" "$(issue_count o/r)" 1
  expect "the convert mutation ran once" "$(gh_calls "graphql .*mutation NightshiftConvertDraft" | wc -l | tr -d ' ')" 1)

# A conversion that fails is logged and tried again on the next poll.
(world
  board
  gh_draft "$BOARD" "Add a dark mode" Ready >/dev/null
  echo "*NightshiftConvertDraft*" >"$GH_FAKE/fail"
  poll
  expect "no conversion: no run" "$(runs)" 0
  expect_line "the log says which draft" "$(cat "$NS/watch.log")" "o/r: couldn't turn the draft \"Add a dark mode\" into an issue"
  rm "$GH_FAKE/fail"
  poll
  expect "converted on the next poll: a run" "$(runs)" 1)

# Two repos name the project: the first in the config converts the drafts.
two() {
  board
  git clone -q "$ORIGIN" "$W/clone2" 2>/dev/null
  gh_repo x/y "$ORIGIN"
  printf 'repo %s %s\n' "$1" "$2" >"$NS/config"
  printf 'repo %s %s\n' "$3" "$4" >>"$NS/config"
  gh_draft "$BOARD" "Add a dark mode" Ready >/dev/null
  poll
}
(world
  two o/r "$CLONE" x/y "$W/clone2"
  expect "the first repo converts it" "$(issue_count o/r)" 1
  expect "the second doesn't" "$(issue_count x/y)" 0
  expect "one conversion" "$(gh_calls "mutation NightshiftConvertDraft" | wc -l | tr -d ' ')" 1)
(world
  two x/y "$W/clone2" o/r "$CLONE"
  expect "listed first, x/y converts it" "$(issue_count x/y)" 1
  expect "o/r doesn't" "$(issue_count o/r)" 0)

# A project= that isn't a project's URL: nothing is worked, and the log says so.
(world
  origin_config "project=my board"
  gh_issue o/r 7 alice agent
  poll
  expect "a bad project=: no run" "$(runs)" 0
  expect_line "and the log says so" "$(cat "$NS/watch.log")" "o/r: project= in .nightshift/config isn't a project URL"
  expect "and the label list isn't read" "$(gh_calls "issues?labels" | wc -l | tr -d ' ')" 0)

# A card moved to In progress, a plan waiting, is the plan's approval:
# a fresh build session, its approval the board line.
planned() {
  board
  gh_issue o/r 7 alice
  gh_edit "$(gh_dir o/r)/issues/7.json" '.body = "Make it faster."'
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:plan; comment plan "T1: the fast path."'
  poll
  expect "the plan is posted: the card waits in Needs you" "$(gh_card_column "$BOARD" o/r 7)" "Needs you"
}
(world
  planned
  expect "the plan is posted: one run" "$(runs)" 1
  expect "and the card stays in Needs you" "$(gh_card_column "$BOARD" o/r 7)" "Needs you"
  poll
  expect "nothing new: no second run" "$(runs)" 1
  gh_card_move "$BOARD" o/r 7 "In progress"
  runs_do 'comment progress'
  poll
  expect "the card moved to In progress: a run" "$(runs)" 2
  expect "it's a fresh session" "$(run_opt --resume)" ""
  expect_line "the prompt: the plan is approved" "$(run_prompt)" "^The plan is approved: build it with the nightshift:build skill"
  expect_line "the prompt: the plan" "$(run_prompt)" "^T1: the fast path\\.$"
  expect_line "the prompt: the approval is the board" "$(sed -n '/^The approval:/,$p' <<<"$(run_prompt)")" "^- the board: moved to In progress$"
  expect "the planning session is kept" "$(state 7 plan-session)" session-1
  expect_ok "nothing is left pending" test ! -f "$(idir 7)/build"
  poll
  expect "nothing new after: no run" "$(runs)" 2
  expect "no move of the watcher's but the plan's, to Needs you: the card is where the user put it" "$(gh_calls "mutation NightshiftMoveCard" | wc -l | tr -d ' ')" 1
  expect_no_unexpected)

# A comment of the user's with the move reaches the build, held out of the approval.
(world
  planned
  early=$(gh_comment o/r 7 alice "also handle the empty case")
  gh_card_move "$BOARD" o/r 7 "In progress"
  runs_do 'comment progress'
  poll
  p=$(run_prompt)
  expect "move and comment: a fresh session" "$(run_opt --resume)" ""
  expect_line "the approval holds the board line" "$(sed -n '/^The approval:/,$p' <<<"$p")" "^- the board: moved to In progress$"
  expect_line "and the comment" "$(sed -n '/^The approval:/,$p' <<<"$p")" "^- @alice (comment $early):$"
  expect_line "the comment isn't in the section before" "$(sed -n '/^Since the plan/,/^The approval:/p' <<<"$p")" "comment $early" no)

# Moved to In progress with questions waiting, not a plan: no hand-off.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'comment questions'
  poll
  gh_card_move "$BOARD" o/r 7 "In progress"
  poll
  expect "no plan to approve: no run" "$(runs)" 1
  expect_ok "and no build pending" test ! -f "$(idir 7)/build")

# Moved to In progress from any other column, a plan waiting, approves it too. A card
# in Backlog is off the list, so its column isn't recorded there; In review is.
(world
  planned
  gh_card_move "$BOARD" o/r 7 Backlog
  poll
  gh_card_move "$BOARD" o/r 7 "In progress"
  runs_do 'comment progress'
  poll
  expect "Backlog to In progress: a run" "$(runs)" 2
  expect "it's a fresh session" "$(run_opt --resume)" ""
  expect_line "the approval is the board" "$(sed -n '/^The approval:/,$p' <<<"$(run_prompt)")" "^- the board: moved to In progress$")
(world
  planned
  gh_card_move "$BOARD" o/r 7 "In review"
  poll
  expect "seen in In review: no run" "$(runs)" 1
  gh_card_move "$BOARD" o/r 7 "In progress"
  runs_do 'comment progress'
  poll
  expect "In review to In progress: a run" "$(runs)" 2
  expect_line "the approval is the board" "$(sed -n '/^The approval:/,$p' <<<"$(run_prompt)")" "^- the board: moved to In progress$")

# A card in In progress that no poll saw in Ready, a plan waiting: approved.
(world
  planned
  rm "$(idir 7)/column"
  gh_card_move "$BOARD" o/r 7 "In progress"
  runs_do 'comment progress'
  poll
  expect "no column recorded, now In progress: a run" "$(runs)" 2
  expect_line "the approval is the board" "$(sed -n '/^The approval:/,$p' <<<"$(run_prompt)")" "^- the board: moved to In progress$")

# A card already in In progress when the plan posts: nothing moved, no approval.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 "In progress"
  runs_do 'skill nightshift:plan; comment plan "T1: the fast path."'
  poll
  expect "the plan is posted: one run" "$(runs)" 1
  poll
  expect "the card was there already: no build" "$(runs)" 1
  expect_ok "and no build pending" test ! -f "$(idir 7)/build")

# Moved to In progress when a build session exists: not an approval again.
(world
  planned
  gh_card_move "$BOARD" o/r 7 "In progress"
  runs_do 'comment progress'
  poll
  gh_card_move "$BOARD" o/r 7 Ready
  poll
  gh_card_move "$BOARD" o/r 7 "In progress"
  poll
  expect "a second move forward: no new run" "$(runs)" 2)

# A go reply hands off as before, and the card goes to In progress.
(world
  planned
  id=$(gh_comment o/r 7 alice "Go!")
  runs_do 'comment progress'
  poll
  expect "go to a plan: the build run" "$(runs)" 2
  expect "a fresh session" "$(run_opt --resume)" ""
  expect_line "the approval is the go" "$(sed -n '/^The approval:/,$p' <<<"$(run_prompt)")" "^- @alice (comment $id):$"
  expect "the card moved to In progress" "$(gh_card_column "$BOARD" o/r 7)" "In progress"
  expect "with one move besides the plan's, to Needs you" "$(gh_calls "mutation NightshiftMoveCard" | wc -l | tr -d ' ')" 2
  poll
  expect "the move isn't a second approval" "$(runs)" 2
  expect_no_unexpected)

# A go on a board with no In progress column: the build starts, the card stays, the log says so.
(world
  gh_project "$BOARD" Backlog Ready Done
  origin_config "project=https://github.com/users/alice/projects/5"
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:plan; comment plan "T1: the fast path."'
  poll
  gh_comment o/r 7 alice "go" >/dev/null
  runs_do 'comment progress'
  poll
  expect "no In progress column: the build still starts" "$(runs)" 2
  expect "the card stays" "$(gh_card_column "$BOARD" o/r 7)" "Ready"
  expect_line "the log says why" "$(cat "$NS/watch.log")" "o/r#7: the board has no In progress column: card not moved")

# `nightshift build --carry-on` is refused on a board; a plain `nightshift build` is not.
(world
  planned
  gh_comment o/r 7 alice "x" >/dev/null
  runs_do 'nightshift build --carry-on >"$RUN/said" 2>&1 || echo "status $?" >>"$RUN/said"'
  poll
  expect_line "carry-on on a board: refused, with the reason" "$(cat "$CLAUDE_FAKE/runs/2/said")" "isn't allowed on a project board"
  expect_line "and it fails" "$(cat "$CLAUDE_FAKE/runs/2/said")" "^status 1$"
  expect_ok "nothing pending" test ! -f "$(idir 7)/build")
(world
  planned
  gh_comment o/r 7 alice "looks good, build it" >/dev/null
  runs_do 'nightshift build >"$RUN/said"'
  poll
  expect_line "a plain build on a board: a fresh session builds it" "$(cat "$CLAUDE_FAKE/runs/2/said")" "fresh session")

# The prompt of a board repo says so, in place of the merge line.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  poll
  p=$(run_prompt)
  expect_line "board repo: the board line" "$p" "^This repo works from a project board.*no carry-on.*no small-issue build.*no merge unless the card is in Ready to merge or the user replied merge"
  expect_line "board repo: not the auto-merge line" "$p" "This repo auto-merges" no
  expect_line "board repo: not the other merge line" "$p" "doesn't auto-merge" no)
(world
  gh_issue o/r 7 alice agent
  poll
  expect_line "no board: the merge line" "$(run_prompt)" "^This repo auto-merges"
  expect_line "no board: no board line" "$(run_prompt)" "project board" no)

# The card follows the work: the build skill moves it to In progress, the review
# skill to In review, and a run ending with its pull request open to Your review.
MOVES="mutation NightshiftMoveCard"
moves() { gh_calls "$MOVES" | wc -l | tr -d ' '; }
BUILDS='skill nightshift:build; commit feature.txt; open_pr; skill nightshift:review; skill nightshift:finish; comment done'
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do "$BUILDS"
  poll
  expect "the work done: the card is in Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  expect "a move for each column it passed through" "$(moves)" 3
  expect "in that order" "$(grep -o 'card moved to .*' "$NS/watch.log" | paste -sd, -)" "card moved to In progress,card moved to In review,card moved to Your review"
  poll
  expect "nothing new: no more moves" "$(moves)" 3

  # A comment on a card in Your review: it goes to In progress, and round again.
  gh_comment o/r 7 alice "please rename it" >/dev/null
  runs_do 'comment progress'
  poll
  expect "a comment in Your review: a run" "$(runs)" 2
  expect "and back in Your review after it" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  expect "In progress and Your review again" "$(grep -o 'card moved to .*' "$NS/watch.log" | tail -2 | paste -sd, -)" "card moved to In progress,card moved to Your review"
  expect_no_unexpected)

# A run that starts on a card in Your review has it in In progress while it works.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do "$BUILDS"
  poll
  gh_comment o/r 7 alice "please rename it" >/dev/null
  runs_do 'hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/2/waiting"
  expect "the run on a change request: the card is in In progress" "$(gh_card_column "$BOARD" o/r 7)" "In progress"
  kill "$(cat "$(idir 7)/pid")"
  wait "$bg" || true)

# A run that ends needing you before a pull request (questions, a plan waiting for its
# go) moves the card from Ready to Needs you; a reply puts it back in Ready for the run.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:questions; comment questions'
  poll
  expect "a questions run on a card in Ready: the card is in Needs you" "$(gh_card_column "$BOARD" o/r 7)" "Needs you"
  poll
  expect "nothing new: still in Needs you, one move" "$(moves)" 1

  gh_comment o/r 7 alice "yes, the fast path" >/dev/null
  runs_do 'hang'
  "$ROOT/nightshift" once &
  bg=$!
  wait_for "$CLAUDE_FAKE/runs/2/waiting"
  expect "a reply: the run starts with the card in Ready" "$(gh_card_column "$BOARD" o/r 7)" "Ready"
  kill "$(cat "$(idir 7)/pid")"
  wait "$bg" || true)
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:questions; comment questions'
  poll
  gh_comment o/r 7 alice "yes, the fast path" >/dev/null
  runs_do 'skill nightshift:plan; comment plan "T1: the fast path."'
  poll
  expect "the reply's run ends with a plan: the card is in Needs you again" "$(gh_card_column "$BOARD" o/r 7)" "Needs you"
  expect "Needs you, Ready, Needs you" "$(grep -o 'card moved to .*' "$NS/watch.log" | paste -sd, -)" "card moved to Needs you,card moved to Ready,card moved to Needs you"
  expect_no_unexpected)

# A run ending needing you with a pull request open still goes to Your review.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:build; commit feature.txt; open_pr; comment blocked'
  poll
  expect "a hand-off with a pull request open: Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  expect "never through Needs you" "$(grep -c 'card moved to Needs you' "$NS/watch.log" || true)" 0)

# A card in In progress with no pull request isn't moved back to Needs you.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 "In progress"
  runs_do 'comment blocked'
  poll
  expect "a run ending needing you on a card in In progress: it stays" "$(gh_card_column "$BOARD" o/r 7)" "In progress"
  expect "and nothing moved it" "$(moves)" 0)

# A board with no Needs you column: the card stays in Ready, and the log says so.
(world
  gh_project "$BOARD" Backlog Ready "In progress" "In review" "Your review" "Ready to merge" Done
  origin_config "project=https://github.com/users/alice/projects/5"
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:questions; comment questions'
  poll
  expect "no Needs you column: the card stays in Ready" "$(gh_card_column "$BOARD" o/r 7)" "Ready"
  expect_line "the log says so" "$(cat "$NS/watch.log")" "o/r#7: the board has no Needs you column: card not moved")

# Nothing moves a card back: one in Ready to merge stays there as a skill sets a status.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 "Ready to merge"
  runs_do 'skill nightshift:build; skill nightshift:review; comment progress'
  poll
  expect "the run happened" "$(runs)" 1
  expect "a card ahead of the skill's column: it stays" "$(gh_card_column "$BOARD" o/r 7)" "Ready to merge"
  expect "and nothing moved it" "$(moves)" 0
  expect_no_unexpected)

# A board with no In review column: the log says so, the card stays, the run goes on.
(world
  gh_project "$BOARD" Backlog Ready "In progress" "Your review" Done
  origin_config "project=https://github.com/users/alice/projects/5"
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do "$BUILDS"
  poll
  expect_line "no In review column: the log says so" "$(cat "$NS/watch.log")" "o/r#7: the board has no In review column: card not moved"
  expect "the card went on to Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review")

# A merged pull request moves its card to Done.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do "$BUILDS"
  poll
  gh_pr_set o/r "$(state 7 pr | sed 's|.*/||')" state '"MERGED"'
  gh_state o/r 7 closed
  poll
  expect "merged: the card is in Done" "$(gh_card_column "$BOARD" o/r 7)" "Done"
  expect "the issue is done" "$(state 7 "done")" "PR merged"
  poll
  expect "nothing more to move" "$(moves)" 4
  expect_no_unexpected)

# A run that merges its own pull request leaves its card for Done, not Your review.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 "In review"
  runs_do 'skill nightshift:merge; commit feature.txt; open_pr; merge_pr; comment done'
  poll
  expect "a merging run: the card isn't sent to Your review" "$(gh_card_column "$BOARD" o/r 7)" "In review"
  poll
  expect "the merged pull request: Done" "$(gh_card_column "$BOARD" o/r 7)" "Done")

# A hand-off through the planning run's `nightshift build` moves the card to In progress.
(world
  planned
  gh_comment o/r 7 alice "looks good, build it" >/dev/null
  runs_do 'nightshift build >"$RUN/said"'
  poll
  expect "a hand-off that isn't a go: the card is in In progress" "$(gh_card_column "$BOARD" o/r 7)" "In progress"
  expect_no_unexpected)

# A card moved to Ready to merge queues a run whose news says so; the card is Done once merged.
# The same 'prs' a build leaves: a pull request open, the card in Your review.
built() {
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do "$BUILDS"
  poll
}
(world
  built
  expect "a build: the card waits in Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  expect_line "the build run's prompt: no merge line of an auto-merging repo" "$(run_prompt)" "This repo auto-merges" no
  expect_line "and the board line" "$(run_prompt)" "^This repo works from a project board"
  poll
  expect "nothing moved: no second run" "$(runs)" 1
  gh_card_move "$BOARD" o/r 7 "Ready to merge"
  runs_do 'skill nightshift:merge; cp "$CLAUDE_FAKE/runs/1/pr" "$RUN/pr"; merge_pr; comment done'
  poll
  expect "the card moved to Ready to merge: a run" "$(runs)" 2
  expect "it resumes the session" "$(run_opt --resume)" "session-1"
  expect_line "its news says where the card is" "$(sed -n '/^New on the issue/,$p' <<<"$(run_prompt)")" "^- the board: the card is in Ready to merge$"
  poll
  expect "the pull request merged: the card is in Done" "$(gh_card_column "$BOARD" o/r 7)" "Done"
  poll
  expect "and no more runs" "$(runs)" 2
  expect_no_unexpected)

# A merge run that ends with the pull request unmerged sends the card back to Your review.
(world
  built
  gh_card_move "$BOARD" o/r 7 "Ready to merge"
  runs_do 'skill nightshift:merge; comment look'
  poll
  expect "the merge run ended unmerged: the card is back in Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  poll
  expect "and it stays: no third run" "$(runs)" 2
  expect_no_unexpected)

# A build run that ends on the merge skill's look comment (its status is "needs
# you", not "PR open") still hands the card to the user: Your review.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:build; commit feature.txt; open_pr; skill nightshift:review; skill nightshift:merge; comment look'
  poll
  expect "a build ending on a look: the card is in Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  expect "no merge run follows" "$(runs)" 1
  expect_no_unexpected)

# A card the user moved to Ready to merge while a run works stays there: neither
# the skill's move to In review nor the run's end undoes it, and the next poll
# starts the merge run.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:build; commit feature.txt; open_pr; gh_card_move alice/5 o/r 7 "Ready to merge"; skill nightshift:review; comment done'
  poll
  expect "moved to Ready to merge mid-run: the run's end leaves it" "$(gh_card_column "$BOARD" o/r 7)" "Ready to merge"
  expect "one run so far" "$(runs)" 1
  expect_ok "the merge is queued" test -f "$(idir 7)/merge-move"
  runs_do 'skill nightshift:merge; cp "$CLAUDE_FAKE/runs/1/pr" "$RUN/pr"; merge_pr; comment done'
  poll
  expect "the next poll starts the merge run" "$(runs)" 2
  expect_line "its news says where the card is" "$(sed -n '/^New on the issue/,$p' <<<"$(run_prompt)")" "^- the board: the card is in Ready to merge$"
  expect_ok "the merge run's marker is gone with the run" test ! -f "$(idir 7)/merging-board"
  poll
  expect "merged: the card is in Done" "$(gh_card_column "$BOARD" o/r 7)" "Done"
  expect_no_unexpected)

# A merge run that ends without merging and without needing the user (it waits
# on another pull request) leaves the card in Ready to merge. A comment on it
# after that is a request, not a merge: its run has no merge news, and the card
# goes back to Your review.
(world
  built
  gh_card_move "$BOARD" o/r 7 "Ready to merge"
  runs_do 'skill nightshift:merge; comment progress "Waiting for #3 to merge first."'
  poll
  expect "the merge run waited: two runs" "$(runs)" 2
  expect "the card stays in Ready to merge" "$(gh_card_column "$BOARD" o/r 7)" "Ready to merge"
  poll
  expect "and starts no third run" "$(runs)" 2
  gh_comment o/r 7 alice "rename the flag first" >/dev/null
  runs_do 'commit rename.txt; comment progress'
  poll
  expect "a comment: a third run" "$(runs)" 3
  expect_line "it carries no merge news" "$(run_prompt)" "^- the board: the card is in Ready to merge$" no
  expect_line "but the comment" "$(sed -n '/^New on the issue/,$p' <<<"$(run_prompt)")" "rename the flag"
  expect_ok "no merge run marker is left" test ! -f "$(idir 7)/merging-board"
  expect_ok "and no merge is queued" test ! -f "$(idir 7)/merge-move"
  expect "the card waits in Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  poll
  expect "and no merge run follows" "$(runs)" 3
  expect_no_unexpected)

# A move to Ready to merge and a comment in the same poll: the comment wins, no
# merge news, and the card goes back to Your review.
(world
  built
  gh_card_move "$BOARD" o/r 7 "Ready to merge"
  gh_comment o/r 7 alice "one more thing: fix the typo" >/dev/null
  runs_do 'commit typo.txt; comment progress'
  poll
  expect "the move and the comment: one run" "$(runs)" 2
  expect_line "it carries no merge news" "$(run_prompt)" "^- the board: the card is in Ready to merge$" no
  expect_line "but the comment" "$(sed -n '/^New on the issue/,$p' <<<"$(run_prompt)")" "fix the typo"
  expect_ok "no merge run marker is left" test ! -f "$(idir 7)/merging-board"
  expect_ok "and the queued merge is dropped" test ! -f "$(idir 7)/merge-move"
  expect "the card waits in Your review" "$(gh_card_column "$BOARD" o/r 7)" "Your review"
  poll
  expect "and no merge run follows" "$(runs)" 2
  expect_no_unexpected)

# A card already in Ready to merge when nightshift first sees it, or one with no pull
# request yet, starts no merge.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 "Ready to merge"
  runs_do 'comment progress'
  poll
  expect "a first run for a card in Ready to merge" "$(runs)" 1
  poll
  expect "and no merge run after it" "$(runs)" 1
  expect_no_unexpected)

# At capacity, the move waits for a slot and is still noticed.
(world
  built
  gh_card_move "$BOARD" o/r 7 "Ready to merge"
  set_config max_parallel 0
  poll
  expect "no slot: no run" "$(runs)" 1
  set_config max_parallel 2
  runs_do 'skill nightshift:merge; cp "$CLAUDE_FAKE/runs/1/pr" "$RUN/pr"; merge_pr; comment done'
  poll
  expect "a slot frees: the merge run starts" "$(runs)" 2
  expect_line "with the news" "$(run_prompt)" "^- the board: the card is in Ready to merge$")

# A card blocked by an open issue, never run: no run until the blocker closes.
# `blocked_card` puts card 7 in Ready, blocked by issue 3 (not on the board).
blocked_card() {
  board
  gh_issue o/r 3 alice
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  gh_block_add o/r 7 5003
}
(world
  blocked_card
  poll
  poll
  expect "open blocker, first run: no run" "$(runs)" 0
  expect "its status: waiting" "$(status_label 7)" waiting
  expect "its updated isn't recorded" "$(state 7 updated)" ""
  expect "its blockers are noted" "$(state 7 blockers)" "3"
  expect_line "the log says so" "$(cat "$NS/watch.log")" "#7 blocked"
  gh_comment o/r 7 alice "hello" >/dev/null
  poll
  expect "a comment while blocked: still no run" "$(runs)" 0
  gh_state o/r 3
  poll
  expect "the blocker closed: its first run" "$(runs)" 1
  expect_line "the comment made while it waited reaches the run" "$(run_prompt)" "^hello$"
  expect_ok "the blockers note is gone" test ! -f "$(idir 7)/blockers"
  expect_no_unexpected)

# A card that has run gets a blocker: a reply doesn't start a run until it closes, and
# then the run holds the reply.
(world
  board
  gh_issue o/r 7 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'comment questions'
  poll
  expect "a first run" "$(runs)" 1
  gh_issue o/r 3 alice
  gh_block_add o/r 7 5003
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "blocked, a reply: no run" "$(runs)" 1
  expect "its status: waiting" "$(status_label 7)" waiting
  expect "its blocker is noted" "$(state 7 blockers)" "3"
  runs_do 'comment progress'
  gh_state o/r 3
  poll
  expect "the blocker closed: a run" "$(runs)" 2
  expect_line "it holds the reply" "$(run_prompt)" "^1 yes$"
  expect_no_unexpected)

# A held card with a plan, moved to In progress: no build until released.
(world
  planned
  gh_issue o/r 3 alice
  gh_block_add o/r 7 5003
  gh_card_move "$BOARD" o/r 7 "In progress"
  poll
  poll
  expect "the move while blocked: no build" "$(runs)" 1
  expect "its status: waiting" "$(status_label 7)" waiting
  runs_do 'comment progress'
  gh_state o/r 3
  poll
  expect "released: the build starts" "$(runs)" 2
  expect "in a fresh session" "$(run_opt --resume)" ""
  expect_line "the prompt: the plan is approved" "$(run_prompt)" "^The plan is approved: build it with the nightshift:build skill"
  expect_line "the approval is the board" "$(sed -n '/^The approval:/,$p' <<<"$(run_prompt)")" "^- the board: moved to In progress$"
  expect_no_unexpected)

# A comment made while the build was held reaches the build.
(world
  planned
  gh_issue o/r 3 alice
  gh_block_add o/r 7 5003
  gh_card_move "$BOARD" o/r 7 "In progress"
  poll
  early=$(gh_comment o/r 7 alice "also handle the empty case")
  poll
  runs_do 'comment progress'
  gh_state o/r 3
  poll
  expect_line "the held comment is in the approval" "$(sed -n '/^The approval:/,$p' <<<"$(run_prompt)")" "^- @alice (comment $early):$"
  expect_no_unexpected)

# A held card with a pull request, moved to Ready to merge: no merge run until released.
(world
  built
  gh_issue o/r 3 alice
  gh_block_add o/r 7 5003
  gh_card_move "$BOARD" o/r 7 "Ready to merge"
  poll
  poll
  expect "the move while blocked: no merge run" "$(runs)" 1
  expect "its status: waiting" "$(status_label 7)" waiting
  runs_do 'skill nightshift:merge; cp "$CLAUDE_FAKE/runs/1/pr" "$RUN/pr"; merge_pr; comment done'
  gh_state o/r 3
  poll
  expect "released: the merge run starts" "$(runs)" 2
  expect_line "its news says where the card is" "$(sed -n '/^New on the issue/,$p' <<<"$(run_prompt)")" "^- the board: the card is in Ready to merge$"
  expect_no_unexpected)

# Released with nothing new: no run, and the status is what it was.
(world
  built
  expect "a build: the pull request is open" "$(status_label 7)" "PR open"
  gh_issue o/r 3 alice
  gh_block_add o/r 7 5003
  poll
  expect "blocked after its build: waiting" "$(status_label 7)" waiting
  gh_state o/r 3
  poll
  expect "released with nothing new: no run" "$(runs)" 1
  expect "its status: PR open again" "$(status_label 7)" "PR open"
  expect_ok "its blockers note is gone" test ! -f "$(idir 7)/blockers"
  expect_no_unexpected)

# A blocker added while a run goes doesn't stop it; the card is held after.
(world
  board
  gh_issue o/r 7 alice
  gh_issue o/r 3 alice
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'gh_block_add o/r 7 5003; comment questions'
  poll
  expect "the run finished: one run" "$(runs)" 1
  expect_ok "it wasn't stopped" test ! -f "$(idir 7)/interrupted"
  gh_comment o/r 7 alice "1 yes" >/dev/null
  poll
  expect "a reply after: held" "$(runs)" 1
  expect "its status: waiting" "$(status_label 7)" waiting
  expect_no_unexpected)

# `status` names what a held card waits on, and says so no more once it's released.
(world
  blocked_card
  poll
  expect_line "status: a card never run" "$(ns status)" '^o/r#7  *waiting · after #3$'
  gh_issue o/r 4 alice
  gh_block_add o/r 7 5004
  gh_state o/r 4
  gh_repo 1org/x "$TMPDIR/none"
  gh_issue 1org/x 5 alice
  gh_block_add_other o/r 7 1org/x 5
  poll
  expect_line "status: open blockers alone, across repos" "$(ns status)" '^o/r#7  *waiting · after #3, 1org/x#5$'
  gh_state 1org/x 5
  : >"$(idir 7)/blockers"
  expect_line "status: no blocker listed (past the first 50)" "$(ns status)" '^o/r#7  *waiting$'
  poll
  gh_state o/r 3
  poll
  expect "status: released, no longer waiting" "$(ns status | grep -c 'waiting')" 0
  expect_no_unexpected)

# A held proposed card stays proposed, in its label and in `status`.
(world
  blocked_card
  gh_label_add o/r 7 alice "nightshift: proposed"
  poll
  expect "held: no run" "$(runs)" 0
  expect "its status: proposed" "$(status_label 7)" proposed
  expect "status: not waiting" "$(ns status | grep -c 'waiting')" 0
  expect_no_unexpected)

# With a pull request open.
(world
  built
  gh_issue o/r 3 alice
  gh_block_add o/r 7 5003
  poll
  expect_line "status: a pull request, held" "$(ns status)" "^o/r#7  *PR https://github.com/o/r/pull/100 · waiting · after #3 · spent"
  gh_state o/r 3
  poll
  expect "status: released, it names no blocker" "$(ns status | grep -c 'after #')" 0
  expect_line "status: released, the pull request alone" "$(ns status)" "^o/r#7  *PR https://github.com/o/r/pull/100 · nightshift:finish"
  expect_no_unexpected)

report
