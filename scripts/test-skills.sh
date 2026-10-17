#!/usr/bin/env bash
# Tests for the plugin's skills, their structure and not their wording: each
# skill and agent has the frontmatter a run relies on (name, description, model,
# effort), every relative link resolves, and every `nightshift:<name>` a skill
# or agent writes names a skill or agent that exists, so a renamed skill breaks
# its callers here. Static: the fake claude can't see a run invoke a skill. Also
# runs the plugin's SessionStart hook.
#   bash scripts/test-skills.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

SKILLS="$ROOT/plugin/skills"
ISSUE="$SKILLS/issue/SKILL.md"
AGENTS="$ROOT/plugin/agents"
STAGES="questions plan build update answer diagnose"

# The value of the frontmatter field $2 in the skill file $1.
field() { sed -n '/^---$/,/^---$/p' "$1" | sed -n "s/^$2: *//p"; }

for s in $STAGES; do
  f="$SKILLS/$s/SKILL.md"
  expect_ok "the $s skill exists" test -f "$f"
  [ -f "$f" ] || continue
  expect "the $s skill is named $s" "$(field "$f" name)" "$s"
  expect "the $s skill isn't user-invocable" "$(field "$f" user-invocable)" false
  expect_ok "the $s skill has a description" test -n "$(field "$f" description)"
done

# The tdd skill: loaded by the ticket agent, not routed to as a stage.
tdd="$SKILLS/tdd/SKILL.md"
expect_ok "the tdd skill exists" test -f "$tdd"
expect "the tdd skill is named tdd" "$(field "$tdd" name 2>/dev/null)" tdd
expect "the tdd skill isn't user-invocable" "$(field "$tdd" user-invocable 2>/dev/null)" false
expect_ok "the tdd skill has a description" test -n "$(field "$tdd" description 2>/dev/null)"

# The merge skill: started by the build, update and issue skills, not routed to as a stage.
merge="$SKILLS/merge/SKILL.md"
expect "the merge skill is named merge" "$(field "$merge" name 2>/dev/null)" merge
expect "the merge skill isn't user-invocable" "$(field "$merge" user-invocable 2>/dev/null)" false
expect_ok "the merge skill has a description" test -n "$(field "$merge" description 2>/dev/null)"
expect "the merge skill reaches only gh pr, gh issue, gh run and git" \
  "$(field "$merge" allowed-tools 2>/dev/null | grep -o '[A-Za-z]*([^)]*)' | grep -Ev '^Bash\((gh pr|gh issue|gh run|git [a-z-]+) \*\)$')" ""
expect_line "the merge skill may read a failed run's log with gh run" "$(field "$merge" allowed-tools 2>/dev/null)" 'Bash(gh run \*)'

# Every relative link to a markdown file in a skill, as "<file>: <target>", that doesn't resolve.
dangling=""
while IFS= read -r f; do
  for t in $(grep -o '](\([^)#:]*\.md\))' "$f" | sed 's/^](//; s/)$//'); do
    [ -e "$(dirname "$f")/$t" ] || dangling="$dangling${f#"$SKILLS"/}: $t
"
  done
done < <(find "$SKILLS" -name '*.md')
expect "every link in a skill resolves" "$dangling" ""

# Reference that only some branches need lives in a sibling file of a SKILL.md: each one has
# something in it and is linked from its skill, or no run ever reads it.
unlinked=""
for f in "$SKILLS"/*/*.md; do
  b=$(basename "$f")
  [ "$b" = SKILL.md ] && continue
  { [ -s "$f" ] && grep -qF "]($b)" "$(dirname "$f")/SKILL.md"; } || unlinked="$unlinked${f#"$SKILLS"/} "
done
expect "every file beside a SKILL.md has something in it and is linked from its skill" "$unlinked" ""

# Each skill and plugin agent runs on its own model and effort, from its frontmatter.
model_effort() {
  expect "$1: its model" "$(field "$2" model)" "$3"
  expect "$1: its effort" "$(field "$2" effort)" "$4"
}
model_effort "the issue skill" "$ISSUE" sonnet low
for s in questions plan diagnose; do model_effort "the $s skill" "$SKILLS/$s/SKILL.md" opus high; done
for s in build update review merge tdd; do model_effort "the $s skill" "$SKILLS/$s/SKILL.md" sonnet high; done
for s in answer finish; do model_effort "the $s skill" "$SKILLS/$s/SKILL.md" sonnet medium; done
bad="" nomodel=""
for f in "$SKILLS"/*/SKILL.md; do
  case "$(field "$f" effort)" in low|medium|high|max) ;; *) bad="$bad${f#"$SKILLS"/} " ;; esac
  [ -n "$(field "$f" model)" ] || nomodel="$nomodel${f#"$SKILLS"/} "
done
expect "every skill's effort is low, medium, high or max" "$bad" ""
expect "every skill sets a model" "$nomodel" ""

while read -r a model effort; do
  f="$AGENTS/$a.md"
  expect_ok "the $a agent exists" test -f "$f"
  [ -f "$f" ] || continue
  expect "the $a agent is named $a" "$(field "$f" name)" "$a"
  expect_ok "the $a agent has a description" test -n "$(field "$f" description)"
  model_effort "the $a agent" "$f" "$model" "$effort"
  expect "the $a agent keeps the default tools" "$(field "$f" tools)" ""
done <<'EOF'
ticket sonnet high
spec-review opus high
standards-review sonnet medium
EOF

expect "the issue skill is its SKILL.md alone, the stages' guidance in their skills" \
  "$(cd "$SKILLS/issue" && find . -type f)" "./SKILL.md"

# Every `nightshift:<name>` in a skill or agent names a skill or an agent that exists, and every
# skill but the issue skill (the entry point) is named by a file outside its own directory.
refs=$(grep -roE '(<!-- )?nightshift:[a-z][a-z-]*' "$SKILLS" "$AGENTS" --include='*.md' | grep -v ':<!-- ')
unknown=""
while IFS=: read -r f _ name; do
  [ -n "$f" ] || continue
  [ -f "$SKILLS/$name/SKILL.md" ] || [ -f "$AGENTS/$name.md" ] || unknown="$unknown${f#"$ROOT"/}: nightshift:$name
"
done <<<"$refs"
expect "every nightshift:<name> names a skill or an agent" "$unknown" ""
orphans=""
for d in "$SKILLS"/*/; do
  s=$(basename "$d")
  [ "$s" = issue ] && continue
  grep -v "^$SKILLS/$s/" <<<"$refs" | grep -q ":nightshift:$s\$" || orphans="$orphans$s "
done
expect "every skill but issue is named by another skill or an agent" "$orphans" ""

# The plugin's SessionStart hook, as Claude Code runs it: your own sessions get
# nightshift's defaults, a run (which has them in its system prompt) nothing.
hook=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$ROOT/plugin/hooks/hooks.json")
expect "the hook prints nightshift's defaults" \
  "$(env -u NIGHTSHIFT_ISSUE CLAUDE_PLUGIN_ROOT="$ROOT/plugin" sh -c "$hook")" "$(cat "$ROOT/plugin/instructions.md")"
expect "the hook prints nothing in a run" \
  "$(NIGHTSHIFT_ISSUE=7 CLAUDE_PLUGIN_ROOT="$ROOT/plugin" sh -c "$hook")" ""

report
