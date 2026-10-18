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
  expect "the board is read by the query" "$(gh_calls "$QUERY" | wc -l | tr -d ' ')" 1
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
  expect "and its card is still in Ready" "$(gh_card_column "$BOARD" o/r 1)" "Ready"
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

# A card moved from Ready to In progress, a plan waiting, is the plan's approval:
# a fresh build session, its approval the board line.
planned() {
  board
  gh_issue o/r 7 alice
  gh_edit "$(gh_dir o/r)/issues/7.json" '.body = "Make it faster."'
  gh_card "$BOARD" o/r 7 Ready
  runs_do 'skill nightshift:plan; comment plan "T1: the fast path."'
  poll
}
(world
  planned
  expect "the plan is posted: one run" "$(runs)" 1
  expect "and the card stays in Ready" "$(gh_card_column "$BOARD" o/r 7)" "Ready"
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
  expect "no move of the watcher's: the card is where the user put it" "$(gh_calls "mutation NightshiftMoveCard" | wc -l | tr -d ' ')" 0
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
  expect "with one move" "$(gh_calls "mutation NightshiftMoveCard" | wc -l | tr -d ' ')" 1
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
  expect_line "its news says the card moved" "$(sed -n '/^New on the issue/,$p' <<<"$(run_prompt)")" "^- the board: moved to Ready to merge$"
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
  expect_line "with the news" "$(run_prompt)" "^- the board: moved to Ready to merge$")

report
