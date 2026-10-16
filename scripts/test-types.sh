#!/usr/bin/env bash
# Tests for issue types: how nightshift reads an issue's type from its labels,
# with nightshift's functions loaded (NIGHTSHIFT_LIB) in a throwaway
# NIGHTSHIFT_HOME.
#   bash scripts/test-types.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

NIGHTSHIFT_HOME=$(mktemp -d)
export NIGHTSHIFT_HOME
set +u
# shellcheck source=../nightshift
NIGHTSHIFT_LIB=1 . "$ROOT/nightshift"
set -u


# The type of an issue with these labels, a line each.
type_of() { printf '%s\n' "$@" | issue_type; }

expect "no labels: no type" "$(type_of)" ""
expect "only agent and a status: no type" "$(type_of agent "nightshift: thinking")" ""
for t in bug enhancement documentation question duplicate invalid wontfix; do
  expect "$t: $t" "$(type_of agent "$t")" "$t"
done
expect "good first issue: no type" "$(type_of agent "good first issue")" ""
expect "help wanted: no type" "$(type_of agent "help wanted")" ""
expect "help wanted beside bug: bug" "$(type_of "help wanted" bug)" bug
expect "wontfix wins over bug" "$(type_of bug wontfix)" wontfix
expect "invalid wins over duplicate" "$(type_of duplicate invalid)" invalid
expect "duplicate wins over bug" "$(type_of bug duplicate)" duplicate
expect "bug wins over question" "$(type_of question bug)" bug
expect "question wins over documentation" "$(type_of documentation question)" question
expect "documentation wins over enhancement" "$(type_of enhancement documentation)" documentation

# What a run is told, with GitHub (gh) giving the issue the labels in LABELS.
LABELS=""
gh() { printf '%s\n' "$LABELS"; }
DIR=$(mktemp -d)
note() { LABELS=$1; type_note o/r 1 "$DIR"; }

expect "a first run, labelled: its type" "$(note "agent
bug")" 'Its type label: `bug`.'
expect "the next run, unchanged: no news" "$(note "agent
bug")" 'Its type label: `bug`.'
expect "the user swapped it: theirs stands" "$(note "agent
question")" 'Its type label: `question`. The user changed it since your last run, from bug: leave it as they set it.'
expect "the user removed it" "$(note agent)" 'It has no type label. The user changed it since your last run, from question: leave it as they set it.'
expect "the user added one" "$(note "agent
enhancement")" 'Its type label: `enhancement`. The user changed it since your last run, from none: leave it as they set it.'
rm -f "$DIR/type"
expect "a first run, unlabelled" "$(note agent)" "It has no type label."

# An issue's status once its last run posted a comment at stage $1.
after_comment() {
  printf '0\t=== 2026-10-16 10:00:00 run\n0\t10:00:05 commented (%s)\n0\t=== 10:00:09 run done in 9s\n' "$1" >"$DIR/log"
  idle_status "$DIR"
}
expect "after questions: needs you" "$(after_comment questions)" "needs you"
expect "after an answer: needs you" "$(after_comment answer)" "needs you"
expect "after a look: needs you" "$(after_comment look)" "needs you"
echo https://github.com/o/r/pull/2 >"$DIR/pr"
expect "done after merging its pull request: PR open, till the watcher sees the merge" "$(after_comment "done")" "PR open"
rm "$DIR/pr"

# What brings back an issue stopped for the reason $1.
hint() { echo "$1" >"$DIR/off"; resume_hint "$DIR"; }
expect "wontfix added: remove it to resume" "$(hint "wontfix label added")" "remove the wontfix label to resume"
expect "invalid added: remove it to resume" "$(hint "invalid label added")" "remove the invalid label to resume"
expect "agent removed: add it back" "$(hint "label removed")" "add the label back to resume"

report
