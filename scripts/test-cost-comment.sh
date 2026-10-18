#!/usr/bin/env bash
# Tests for the cost comment posted on an issue once it's done: its headline,
# the marker, its second line (the dollars of each model, the pull request's
# size) with cost_breakdown=true, the one line without it, and that it's posted
# once.
#   bash scripts/test-cost-comment.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# Posted once it's done.
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

# The cost comment's second line, with cost_breakdown=true: the dollars of
# each model, and the pull request's size, each left out when unknown.
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
  origin_config cost_breakdown=true
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
  origin_config cost_breakdown=true
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; commit feature.txt; open_pr; comment done"
  poll
  merge_pr 7 3 0 1
  expect "one file, one model" "$(second 7)" "opus-5-5 \$1.00 · PR +3 −0 in 1 file")

(world
  origin_config cost_breakdown=true
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; commit feature.txt; open_pr; comment done"
  poll
  gh_pr_set o/r "$(state 7 pr | sed 's|.*/||')" state '"MERGED"'
  poll
  expect "no size known (the pull request has none): the models alone" "$(second 7)" "opus-5-5 \$1.00"
  expect_no_unexpected)

(world
  origin_config cost_breakdown=true
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; commit feature.txt; open_pr; comment done"
  poll
  echo "pr view *" >"$GH_FAKE/fail"
  merge_pr 7 5 6 7
  expect "gh fails on the pull request: the models alone" "$(second 7)" "opus-5-5 \$1.00")

(world
  origin_config cost_breakdown=true
  gh_issue o/r 7 alice agent
  runs_do "comment questions"
  poll
  gh_state o/r 7 closed
  poll
  expect "no models, no pull request: no second line, the table or marker follows a blank line" \
    "$(second 7)" ""
  expect "and the comment is posted" "$(gh_comments o/r 7 | grep -c "^$COMMENT$")" 1)

(world
  origin_config cost_breakdown=true
  gh_issue o/r 7 alice agent
  runs_do "comment questions"
  poll
  echo "1 1 1 1 1 1 -" >"$(idir 7)/cost"
  runs_do "commit feature.txt; open_pr; comment done"
  gh_comment o/r 7 alice "go" >/dev/null
  poll
  merge_pr 7 8 9 2
  expect "a pull request but no models: its size alone" "$(second 7)" "PR +8 −9 in 2 files")

# cost_breakdown: unless it's true on the default branch, the comment is the
# headline and the pull request's size on one line, with no models and no table:
# a blank line, then the marker.
# The comment's lines, the marker's last, from the headline on, the time of a
# session (whatever the run took) as S.
cost_lines() { gh_comments o/r "$1" | sed -n '/at API prices/,/nightshift:cost/p' | sed 's/\*\*[0-9]*s\*\* over/**S** over/'; }
SHORT='**$1.00** at API prices · **4 tokens** (1 in, 1 out, 2 cache) · **S** over 1 run · PR +412 −37 in 9 files

<!-- nightshift --> <!-- nightshift:cost -->'
# Issue 7 built by one run with agents, on a pull request that merged with a size.
built() {
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; skill nightshift:build; agent toolu_1 Explore 'Look'; agent_result toolu_1 $HAIKU 30 60 2; commit feature.txt; open_pr; comment done"
  poll
  merge_pr 7 412 37 9
}

(world
  built
  expect "cost_breakdown unset: the headline and the size, then the marker" "$(cost_lines 7)" "$SHORT"
  expect_no_unexpected)

(world
  origin_config cost_breakdown=false
  built
  expect "cost_breakdown=false: the same" "$(cost_lines 7)" "$SHORT")

(world
  origin_config cost_breakdown=true
  built
  expect "cost_breakdown=true: the models and the size on their own line" "$(second 7)" "opus-5-5 \$1.00 · PR +412 −37 in 9 files"
  expect_line "and the agents table" "$(gh_comments o/r 7)" '^| Agent | Model ')

(world
  gh_issue o/r 7 alice agent
  runs_do "costs 1 $OPUS 1 1 1 1; comment questions"
  poll
  gh_state o/r 7 closed
  poll
  expect "cost_breakdown unset, no pull request: the headline alone" "$(cost_lines 7)" \
    '**$1.00** at API prices · **4 tokens** (1 in, 1 out, 2 cache) · **S** over 1 run

<!-- nightshift --> <!-- nightshift:cost -->')

(world
  origin_file .nightshift/config cost_breakdown=true nightshift/issue-7
  built
  expect "cost_breakdown=true only on the issue's branch: the short comment" "$(cost_lines 7)" "$SHORT")

report
