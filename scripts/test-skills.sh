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
STAGES="questions plan build update answer"

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

# The merge skill: started by the finish, update and issue skills, not routed to as a stage.
merge="$SKILLS/merge/SKILL.md"
expect "the merge skill is named merge" "$(field "$merge" name 2>/dev/null)" merge
expect "the merge skill isn't user-invocable" "$(field "$merge" user-invocable 2>/dev/null)" false
expect_line "the merge skill says who starts it" "$(field "$merge" description 2>/dev/null)" "finish, update and issue skills"
expect "the merge skill reaches only gh pr, gh issue and git" \
  "$(field "$merge" allowed-tools 2>/dev/null | grep -o '[A-Za-z]*([^)]*)' | grep -Ev '^Bash\((gh pr|gh issue|git [a-z-]+) \*\)$')" ""
expect_line "the merge skill merges only when the prompt says the repo auto-merges" "$(cat "$merge" 2>/dev/null)" '"This repo auto-merges"'
expect_line "the merge skill merges only the head it checked" "$(cat "$merge" 2>/dev/null)" "match-head-commit"

# Every relative link to a markdown file in a skill, as "<file>: <target>", that doesn't resolve.
dangling=""
while IFS= read -r f; do
  for t in $(grep -o '](\([^)#:]*\.md\))' "$f" | sed 's/^](//; s/)$//'); do
    [ -e "$(dirname "$f")/$t" ] || dangling="$dangling${f#"$SKILLS"/}: $t
"
  done
done < <(find "$SKILLS" -name '*.md')
expect "every link in a skill resolves" "$dangling" ""

expect_line "comments name the skill that wrote them" "$(cat "$ISSUE")" \
  '^🤖 \*\*nightshift\*\* · <stage> · `nightshift:<skill>`$'
expect "no skill sets the status label: the watcher does, from the skill" \
  "$(grep -l 'nightshift label' "$SKILLS"/*/SKILL.md | sed "s|^$SKILLS/||")" ""

expect "the issue skill is its SKILL.md alone, the stages' guidance in their skills" \
  "$(cd "$SKILLS/issue" && find . -type f)" "./SKILL.md"

# The build skill hands each ticket to a subagent; a real run's log shows its `→ Agent:` lines.
build=$(cat "$SKILLS/build/SKILL.md")
expect_line "the build hands each ticket to a subagent" "$build" "ticket subagent"
expect_line "the subagent is started with the Agent tool" "$build" "Agent tool"
expect_line "the subagent inherits the run's model" "$build" "without a \`model\`"
expect_line "a stuck subagent replies BLOCKED:" "$build" "\`BLOCKED:\`"
expect_line "the subagent doesn't comment on the issue" "$build" "comments on the issue, changes labels"
expect_line "the run checks each ticket's commit and a clean tree" "$build" "the tree clean"
expect_line "a one-ticket plan is built without a subagent" "$build" "plan with one ticket"

# The plugin's SessionStart hook, as Claude Code runs it: your own sessions get
# nightshift's defaults, a run (which has them in its system prompt) nothing.
hook=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$ROOT/plugin/hooks/hooks.json")
expect "the hook prints nightshift's defaults" \
  "$(env -u NIGHTSHIFT_ISSUE CLAUDE_PLUGIN_ROOT="$ROOT/plugin" sh -c "$hook")" "$(cat "$ROOT/plugin/instructions.md")"
expect "the hook prints nothing in a run" \
  "$(NIGHTSHIFT_ISSUE=7 CLAUDE_PLUGIN_ROOT="$ROOT/plugin" sh -c "$hook")" ""
expect "the defaults have the CLAUDE.md rules, with the root's budget" \
  "$(grep -c -e '^# CLAUDE.md$' -e '200 lines' "$ROOT/plugin/instructions.md")" 2

# A run files a real defect it finds outside its issue, held as proposed until the user comments.
issue=$(cat "$ISSUE")
expect_line "a run files a defect it finds as a proposed issue" "$issue" "\`nightshift: proposed\`"
expect_line "it looks for a duplicate first, open or closed" "$issue" "gh issue list --state all"
expect_line "it files at most three a run" "$issue" "at most three"
expect_line "filing finishes before the run ends" "$issue" "run_in_background: false"
expect_line "the filed issue says where it was found" "$issue" "Found while working #<n>."
expect_line "a ticket subagent reports defects to the run, not files them" "$build" "files no issues"

report
