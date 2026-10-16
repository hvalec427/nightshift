#!/usr/bin/env bash
# Tests for the plugin's skills: each stage of an issue is its own skill, the
# issue skill routes to each by name, and no skill links a file that isn't
# there. Static: the fake claude can't see a run invoke a skill, so this checks
# the wiring a real run relies on.
#   bash scripts/test-skills.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

SKILLS="$ROOT/plugin/skills"
ISSUE="$SKILLS/issue/SKILL.md"
STAGES="plan"

# The value of the frontmatter field $2 in the skill file $1.
field() { sed -n '/^---$/,/^---$/p' "$1" | sed -n "s/^$2: *//p"; }

for s in $STAGES; do
  f="$SKILLS/$s/SKILL.md"
  expect_ok "the $s skill exists" test -f "$f"
  [ -f "$f" ] || continue
  expect "the $s skill is named $s" "$(field "$f" name)" "$s"
  expect "the $s skill isn't user-invocable" "$(field "$f" user-invocable)" false
  expect_ok "the $s skill has a description" test -n "$(field "$f" description)"
  expect_line "the issue skill routes to nightshift:$s" "$(cat "$ISSUE")" "nightshift:$s\`"
done

# Every relative link to a markdown file in a skill, as "<file>: <target>", that doesn't resolve.
dangling=""
while IFS= read -r f; do
  for t in $(grep -o '](\([^)#:]*\.md\))' "$f" | sed 's/^](//; s/)$//'); do
    [ -e "$(dirname "$f")/$t" ] || dangling="$dangling${f#"$SKILLS"/}: $t
"
  done
done < <(find "$SKILLS" -name '*.md')
expect "every link in a skill resolves" "$dangling" ""

for old in spec.md tickets.md; do
  expect_ok "the issue skill no longer has $old" test ! -e "$SKILLS/issue/$old"
done

report
