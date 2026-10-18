#!/usr/bin/env bash
# Tests for a parent issue (one with sub-issues, in its `subs`): it shows
# `waiting` while they're open, gets a one-line progress comment, once, as
# each merges, is closed by the watcher after the last, and retires with a
# cost comment that totals itself and each sub-issue.
#   bash scripts/test-parents.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# What the parent's run does: makes sub-issues 8 and 9, then comments. The
# sub-issues' runs build and open their pull requests.
RUNS='case $NIGHTSHIFT_ISSUE in
  7) printf "slice\n" >"$RUN/b"; nightshift sub-issue --title "S1" --body-file "$RUN/b"; nightshift sub-issue --title "S2" --body-file "$RUN/b"; comment progress ;;
  *) commit feature.txt; open_pr; comment done ;;
esac'

# Issue 7 with its sub-issues 8 and 9 made and built, their pull requests open;
# the costs they counted set.
parent() {
  gh_issue o/r 7 alice agent
  runs_do "$RUNS"
  poll
  poll
  echo "2.5 10 20 30 600 3 -" >"$(idir 7)/cost"
  echo "1.5 100 200 300 60 2 -" >"$(idir 8)/cost"
  echo "0.5 1 2 3 90 1 2026-10-02" >"$(idir 9)/cost"
  printf '%s 2.0\n%s 0.5\n' "${OPUS#claude-}" "${HAIKU#claude-}" | sed 's/-2025[0-9]*//' >"$(idir 7)/models"
  printf '%s 1.0\n%s 0.5\n' "${OPUS#claude-}" "${SONNET#claude-}" | sed 's/-2025[0-9]*//' >"$(idir 8)/models"
  printf '%s 0.5\n' "${OPUS#claude-}" >"$(idir 9)/models"
}

# Sub-issue $1's pull request merged.
merge() { gh_pr_set o/r "$(state "$1" pr | sed 's|.*/||')" state '"MERGED"'; }

# Issue $1's progress comments, a line each.
progress() { gh_comments o/r "$1" | grep 'merged (' || true; }

# Whether issue $1 is open or closed on GitHub.
gh_state_of() { jq -r .state "$(gh_dir o/r)/issues/$1.json"; }

# Issue $1's cost comment, from its headline to its marker.
cost_lines() { gh_comments o/r "$1" | sed -n '/at API prices/,/nightshift:cost/p' | sed 's/\*\*[0-9a-z ]*\*\* over/**T** over/'; }

(world
  parent
  expect "the parent's run made two sub-issues" "$(state 7 subs | paste -sd, -)" "8,9"
  expect "the parent is waiting, not needing you" "$(status_label 7)" "waiting"
  expect "both sub-issues built" "$(cat "$(idir 8)/pr" "$(idir 9)/pr" | sed "s|.*/||" | sort | paste -sd, -)" "100,101"
  expect "nothing merged: no progress" "$(progress 7)" ""
  merge 8
  poll
  expect "#8 merged: done" "$(state 8 "done")" "PR merged"
  expect "its progress line on the parent, with how many of how many" "$(progress 7)" "🤖 **nightshift**: #8 merged (1 of 2)"
  expect "the parent is still open" "$(gh_state_of 7)" "open"
  expect "and waiting" "$(status_label 7)" "waiting"
  poll
  poll
  expect "the line is posted once" "$(progress 7 | wc -l | tr -d ' ')" 1
  merge 9
  poll
  expect "#9 merged: its line" "$(progress 7 | tail -1)" "🤖 **nightshift**: #9 merged (2 of 2)"
  expect "all merged: the parent is closed" "$(gh_state_of 7)" "closed"
  poll
  expect "the parent retires as the issue closed" "$(state 7 "done")" "issue closed"
  expect "retiring keeps subs" "$(state 7 subs | paste -sd, -)" "8,9"
  expect "the cost comment totals the issues, a line each and the models summed, no agents table or size" "$(cost_lines 7)" '**$4.50** at API prices · **666 tokens** (111 in, 222 out, 333 cache) · **T** over 6 runs (counted since 2026-10-02)
opus-5-5 $3.50 · haiku-4-5 $0.50 · sonnet-4-5 $0.50

#7 planning: $2.50
#8: $1.50
#9: $0.50

<!-- nightshift --> <!-- nightshift:cost -->'
  expect "one cost comment" "$(gh_comments o/r 7 | grep -c "^$COMMENT$")" 1
  poll
  expect "nothing more is posted" "$(gh_comments o/r 7 | grep -c '^---$')" 4
  expect "the parent's progress lines are still two" "$(progress 7 | wc -l | tr -d ' ')" 2
  expect_no_unexpected)

# cost_breakdown=false: no models line, still a line each issue.
(world
  origin_config cost_breakdown=false
  parent
  merge 8
  merge 9
  poll
  poll
  expect "no models line, the lines stay" "$(cost_lines 7)" '**$4.50** at API prices · **666 tokens** (111 in, 222 out, 333 cache) · **T** over 6 runs (counted since 2026-10-02)

#7 planning: $2.50
#8: $1.50
#9: $0.50

<!-- nightshift --> <!-- nightshift:cost -->')

# cost_comment=false: the parent still closes and retires, with no cost comment.
(world
  origin_config cost_comment=false
  parent
  merge 8
  merge 9
  poll
  poll
  expect "retired" "$(state 7 "done")" "issue closed"
  expect "no cost comment" "$(gh_comments o/r 7 | grep -c 'at API prices' || true)" 0)

# Both merged in one poll: a line each, numbered in turn.
(world
  parent
  merge 9
  merge 8
  poll
  expect "two lines, one and two of two" "$(progress 7 | sed 's/.*(//' | paste -sd, -)" "1 of 2),2 of 2)"
  expect "closed" "$(gh_state_of 7)" "closed")

# A sub-issue closed without merging leaves the parent open.
(world
  parent
  gh_state o/r 8 closed
  merge 9
  poll
  poll
  expect "#8 closed: done as closed" "$(state 8 "done")" "issue closed"
  expect "#9 merged: its line" "$(progress 7)" "🤖 **nightshift**: #9 merged (1 of 2)"
  expect "the parent stays open" "$(gh_state_of 7)" "open"
  expect "and isn't done" "$(state 7 "done")" ""
  expect_no_unexpected)

# GitHub fails to close the parent: tried again on the next poll.
(world
  parent
  merge 8
  merge 9
  echo 'issue close *' >"$GH_FAKE/fail"
  poll
  expect "the close fails: open" "$(gh_state_of 7)" "open"
  rm "$GH_FAKE/fail"
  poll
  expect "the next poll closes it" "$(gh_state_of 7)" "closed"
  expect "the lines were posted once" "$(progress 7 | wc -l | tr -d ' ')" 2)

report
