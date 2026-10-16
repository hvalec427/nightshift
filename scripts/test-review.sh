#!/usr/bin/env bash
# Tests for the review skill: it exists, it briefs its two reviewers, and the
# build skill runs it once before the finish skill. Static: the fake claude
# can't see a run invoke a skill, so this checks the wiring.
#   bash scripts/test-review.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

SKILLS="$ROOT/plugin/skills"
REVIEW="$SKILLS/review/SKILL.md"
BUILD="$SKILLS/build/SKILL.md"

# The value of the frontmatter field $2 in the skill file $1.
field() { sed -n '/^---$/,/^---$/p' "$1" | sed -n "s/^$2: *//p"; }
# The number of the first line in $1 matching the grep pattern $2, or 0.
line_of() { grep -n -m1 -- "$2" "$1" | cut -d: -f1 || echo 0; }

expect_ok "the review skill exists" test -f "$REVIEW"
if [ -f "$REVIEW" ]; then
  expect "it's named review" "$(field "$REVIEW" name)" review
  expect "it isn't user-invocable" "$(field "$REVIEW" user-invocable)" false
  expect_ok "it has a description" test -n "$(field "$REVIEW" description)"
  expect_line "it briefs a Spec reviewer" "$(cat "$REVIEW")" '^### Spec'
  expect_line "it briefs a Standards reviewer" "$(cat "$REVIEW")" '^### Standards'
  expect_line "it reviews against the default branch" "$(cat "$REVIEW")" 'git diff <default branch>\.\.\.HEAD'
  expect_line "it bounds the fixes to one pass" "$(cat "$REVIEW")" '^## .*One fix pass$'
fi

review=$(line_of "$BUILD" 'nightshift:review`')
finish=$(line_of "$BUILD" 'nightshift:finish`')
expect_ok "the build skill runs the review skill" test "$review" -gt 0
expect_ok "the review comes before the finish skill" test "$review" -gt 0 -a "$review" -lt "$finish"

expect_line "the done comment counts the review's findings" "$(cat "$BUILD")" '^ *\*\*Review:\*\* <n> found: <n> fixed, <n> dismissed, <n> left open\.$'
expect_line "the findings left open go in the pull request" "$(cat "$BUILD")" "findings left open go in the pull request"

report
