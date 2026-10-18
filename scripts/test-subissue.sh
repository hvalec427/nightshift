#!/usr/bin/env bash
# Tests for `nightshift sub-issue`: a run of a large issue creating the
# sub-issues of its plan, against the fake gh. They check what GitHub and the
# issue's state end up as: the issues' labels and body, the links between them,
# and the parent's `subs` file.
#   bash scripts/test-subissue.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A command's output (stdout and stderr) and, in $ST, its exit status.
try() {
  set +e
  OUT=$("$@" 2>&1)
  ST=$?
  set -e
}

USE="usage: nightshift sub-issue --title <title> --body-file <file> [--after <n>]…"

# A world with issue 7 (a bug) as the run's parent, and a body file.
parent() {
  world
  gh_issue o/r 7 alice agent bug
  mkdir -p "$(idir 7)"
  printf 'The slice of the plan.\n\n- T1: do it\n' >"$W/body.md"
  export NIGHTSHIFT_REPO=o/r NIGHTSHIFT_ISSUE=7
}

# Whether issue $1 is open or closed on GitHub.
gh_state_of() { jq -r .state "$(gh_dir o/r)/issues/$1.json"; }

# Issue $1's body.
body_of() { jq -r .body "$(gh_dir o/r)/issues/$1.json"; }

# --- outside a run, and bad flags ---------------------------------------------------

(world
  printf 'b\n' >"$W/body.md"
  try ns sub-issue --title T --body-file "$W/body.md"
  expect "outside a run: fails" "$ST $OUT" "1 nightshift: nightshift sub-issue only works in a nightshift run"
  expect "outside a run: nothing asked of GitHub" "$(cat "$GH_FAKE/calls" 2>/dev/null)" ""
  expect_no_unexpected)

(parent
  try ns sub-issue --body-file "$W/body.md"
  expect "no title: usage" "$ST $OUT" "1 nightshift: $USE"
  try ns sub-issue --title T
  expect "no body file: usage" "$ST $OUT" "1 nightshift: $USE"
  try ns sub-issue --title T --body-file "$W/nope.md"
  expect "a body file that isn't there: usage" "$ST $OUT" "1 nightshift: $USE"
  try ns sub-issue --title T --body-file "$W/body.md" --after soon
  expect "--after not a number: usage" "$ST $OUT" "1 nightshift: $USE"
  try ns sub-issue --title T --body-file "$W/body.md" --after
  expect "--after with no value: usage" "$ST $OUT" "1 nightshift: $USE"
  try ns sub-issue --title T --body-file "$W/body.md" --soon
  expect "an unknown flag: usage" "$ST $OUT" "1 nightshift: $USE"
  expect "none of them created an issue" "$(gh_calls 'issue create')" ""
  expect "none of them wrote subs" "$(state 7 subs)" ""
  expect_no_unexpected)

# --- a sub-issue ---------------------------------------------------------------------

(parent
  try ns sub-issue --title "S1: the base" --body-file "$W/body.md"
  expect "creates it: prints its URL" "$ST $OUT" "0 https://github.com/o/r/issues/8"
  expect "labels it agent and the parent's type" "$(gh_labels o/r 8 | sort | paste -sd, -)" "agent,bug"
  expect "titles it" "$(jq -r .title "$(gh_dir o/r)/issues/8.json")" "S1: the base"
  expect "its body: the slice, then the parent marker" "$(body_of 8)" 'The slice of the plan.

- T1: do it

<!-- nightshift:parent #7 -->'
  expect "links it under the parent" "$(gh_sub_issues o/r 7)" "8"
  expect "it has no blockers" "$(gh_blockers o/r 8)" ""
  expect "the parent's subs: its number" "$(state 7 subs)" "8"
  expect "linked: no longer in subs-linking" "$(state 7 subs-linking)" ""
  expect "agent comes last, after the link" "$(grep -o 'issue create\|sub_issues\|add-label agent' "$GH_FAKE/calls" | paste -sd, -)" "issue create,sub_issues,add-label agent"

  try ns sub-issue --title "S2: on the base" --body-file "$W/body.md"
  try ns sub-issue --title "S3: on both" --body-file "$W/body.md" --after 8 --after 9
  expect "S3 is #10" "$OUT" "https://github.com/o/r/issues/10"
  expect "agent last for S3 too, after its blockers" "$(grep 'issues/10\|issue edit 10' "$GH_FAKE/calls" | grep -o 'blocked_by\|add-label agent' | paste -sd, -)" "blocked_by,blocked_by,add-label agent"
  expect "blocked-by links, one per --after" "$(gh_blockers o/r 10 | paste -sd, -)" "8,9"
  expect "the parent's sub-issues, in order" "$(gh_sub_issues o/r 7 | paste -sd, -)" "8,9,10"
  expect "subs: a number a line, in order" "$(state 7 subs | paste -sd, -)" "8,9,10"
  expect "the others are not blocked by it" "$(gh_blockers o/r 9)" ""
  expect_no_unexpected)

# A parent with no type label gives its sub-issues just agent.
(world
  gh_issue o/r 7 alice agent
  mkdir -p "$(idir 7)"
  printf 'b\n' >"$W/body.md"
  export NIGHTSHIFT_REPO=o/r NIGHTSHIFT_ISSUE=7
  ns sub-issue --title T --body-file "$W/body.md" >/dev/null
  expect "no parent type: only agent" "$(gh_labels o/r 8)" "agent"
  expect_no_unexpected)

# --- GitHub fails -----------------------------------------------------------------------

(parent
  echo 'issue create *' >"$GH_FAKE/fail"
  try ns sub-issue --title T --body-file "$W/body.md"
  expect "can't create: fails, says so" "$ST $OUT" "1 nightshift: couldn't create the sub-issue: nothing was created"
  expect "and wrote no subs" "$(state 7 subs)" ""
  expect_no_unexpected)

# A step that fails after the issue exists: the issue is closed, saying why,
# and dropped from subs, so the run can make it again.
(parent
  echo 'api -X POST repos/o/r/issues/7/sub_issues*' >"$GH_FAKE/fail"
  try ns sub-issue --title T --body-file "$W/body.md" --after 7
  expect "can't link: fails, says what it did" "$ST $OUT" "1 nightshift: created #8 but couldn't link it under #7: closed it and dropped it from #7's sub-issues; run it again"
  expect "the stray issue is closed" "$(gh_state_of 8)" "closed"
  expect_line "with a comment saying why" "$(gh_comments o/r 8)" "closed: nightshift made this sub-issue of #7 but couldn't link it under #7, so the run makes it again"
  expect "it never got agent" "$(gh_labels o/r 8 | paste -sd, -)" "bug"
  expect "the parent doesn't count it" "$(state 7 subs)" ""
  expect "nor holds it as linking" "$(state 7 subs-linking)" ""
  expect_no_unexpected)

(parent
  ns sub-issue --title A --body-file "$W/body.md" >/dev/null
  echo 'api -X POST repos/o/r/issues/9/dependencies/blocked_by*' >"$GH_FAKE/fail"
  try ns sub-issue --title B --body-file "$W/body.md" --after 8
  expect "can't block: fails, says what it did" "$ST $OUT" "1 nightshift: created #9 but couldn't make it wait for #8: closed it and dropped it from #7's sub-issues; run it again"
  expect "the stray issue is closed" "$(gh_state_of 9)" "closed"
  expect "the parent counts only the good one" "$(state 7 subs)" "8"
  expect "the good one is still open" "$(gh_state_of 8)" "open"
  rm "$GH_FAKE/fail"
  try ns sub-issue --title B --body-file "$W/body.md" --after 8
  expect "made again: a new issue" "$ST $OUT" "0 https://github.com/o/r/issues/10"
  expect "the parent counts it" "$(state 7 subs | paste -sd, -)" "8,10"
  expect "it waits for #8" "$(gh_blockers o/r 10)" "8"
  expect_no_unexpected)

(parent
  echo 'issue edit *' >"$GH_FAKE/fail"
  try ns sub-issue --title T --body-file "$W/body.md" --after 7
  expect "can't label: fails, says what it did" "$ST $OUT" "1 nightshift: created #8 but couldn't label it agent: closed it and dropped it from #7's sub-issues; run it again"
  expect "the stray issue is closed" "$(gh_state_of 8)" "closed"
  expect "the parent doesn't count it" "$(state 7 subs)" ""
  expect_no_unexpected)

(parent
  try ns sub-issue --title T --body-file "$W/body.md" --after 99
  expect "an --after that isn't an issue: fails, says what it did" "$ST $OUT" "1 nightshift: created #8 but couldn't make it wait for #99: closed it and dropped it from #7's sub-issues; run it again"
  expect "the stray issue is closed" "$(gh_state_of 8)" "closed")

# The close fails too: the issue stays in subs and subs-linking, so the watcher
# holds it, and the run is told to close it by hand.
(parent
  printf '%s\n' 'api -X POST repos/o/r/issues/7/sub_issues*' 'issue close *' >"$GH_FAKE/fail"
  try ns sub-issue --title T --body-file "$W/body.md"
  expect "can't close either: fails, says so" "$ST $OUT" "1 nightshift: created #8 but couldn't link it under #7, and couldn't close it: close #8 by hand (the watcher holds it until then)"
  expect "it stays open" "$(gh_state_of 8)" "open"
  expect "the parent still lists it" "$(state 7 subs)" "8"
  expect "held as linking" "$(state 7 subs-linking)" "8")

# --- the fake -----------------------------------------------------------------------------

# What the watcher will read: an issue's open blockers, as GitHub counts them,
# which a test sets.
(parent
  gh_issue o/r 8 alice agent
  expect "an issue has an id" "$(jq -r '.id | type' "$(gh_dir o/r)/issues/8.json")" number
  expect "no blockers to begin with" "$(gh api repos/o/r/issues?labels=agent\&state=open --jq '[.[] | .issue_dependencies_summary.blocked_by] | join(",")')" "0,0"
  gh_set_blocked_by o/r 8 2
  expect "a test sets the open blockers" "$(gh api repos/o/r/issues?labels=agent\&state=open --jq '.[] | select(.number == 8) | .issue_dependencies_summary.blocked_by')" 2)

report
