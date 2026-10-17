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

# The tdd skill: loaded by the ticket agent, not routed to as a stage.
tdd="$SKILLS/tdd/SKILL.md"
expect_ok "the tdd skill exists" test -f "$tdd"
expect "the tdd skill is named tdd" "$(field "$tdd" name 2>/dev/null)" tdd
expect "the tdd skill isn't user-invocable" "$(field "$tdd" user-invocable 2>/dev/null)" false
expect_ok "the tdd skill has a description" test -n "$(field "$tdd" description 2>/dev/null)"
tddtext=$(flat "$tdd" 2>/dev/null)
expect_line "the tdd skill has the loop: red before green" "$tddtext" "Red before green"
expect_line "the tdd skill has what a good test is" "$tddtext" "public interface"
expect_line "the tdd skill has the mocking rules" "$tddtext" "system boundaries"
expect_line "the tdd skill tests only at the plan's seams" "$tddtext" "plan.s testing decisions"
expect_line "a seam the plan didn't name is a blocked comment" "$tddtext" "\`blocked\` comment"
expect_line "the tdd skill covers a repo without tests at that seam" "$tddtext" "repo without tests at that seam"
expect_line "refactoring is the review's, not the loop's" "$tddtext" "Refactoring.*review"
expect_line "the review skill covers refactoring" "$(flat "$SKILLS/review/SKILL.md")" "refactor"

# The merge skill: started by the build, update and issue skills, not routed to as a stage.
merge="$SKILLS/merge/SKILL.md"
expect "the merge skill is named merge" "$(field "$merge" name 2>/dev/null)" merge
expect "the merge skill isn't user-invocable" "$(field "$merge" user-invocable 2>/dev/null)" false
expect_line "the merge skill says who starts it" "$(field "$merge" description 2>/dev/null)" "build, update and issue skills"
expect "the merge skill reaches only gh pr, gh issue and git" \
  "$(field "$merge" allowed-tools 2>/dev/null | grep -o '[A-Za-z]*([^)]*)' | grep -Ev '^Bash\((gh pr|gh issue|git [a-z-]+) \*\)$')" ""
expect_line "the merge skill merges only when the prompt says the repo auto-merges" "$(cat "$merge" 2>/dev/null)" '"This repo auto-merges"'
expect_line "the merge skill merges only the head it checked" "$(cat "$merge" 2>/dev/null)" "match-head-commit"

# A skill that hands the pull request to the merge skill does it only under the auto-merge line.
for s in issue build update; do
  expect_line "the $s skill routes to nightshift:merge when the repo auto-merges" "$(flat "$SKILLS/$s/SKILL.md")" \
    '"This repo auto-merges"[^.]*`nightshift:merge`'
done
expect_ok "the build posts its done comment (the review in it) before the merge skill" \
  test "$(line_of "$SKILLS/build/SKILL.md" '\*\*Review:\*\*')" -lt "$(line_of "$SKILLS/build/SKILL.md" 'nightshift:merge`')"
expect_line "with auto_merge=false, a merge reply doesn't merge" "$(flat "$ISSUE")" \
  '`auto_merge=false`[^.]*you don.t merge'
expect_line "the issue skill lists the look stage" "$(flat "$ISSUE")" 'The stages are [^.]*`look`'

for s in build update; do
  expect_line "the $s skill says to wait for the checks" \
    "$(cat "$SKILLS/$s/SKILL.md")" "a run ends when you stop"
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

expect_line "comments name the skill that wrote them" "$(cat "$ISSUE")" \
  '^🤖 \*\*nightshift\*\* · <stage> · `nightshift:<skill>`$'
expect "no skill sets the status label: the watcher does, from the skill" \
  "$(grep -l 'nightshift label' "$SKILLS"/*/SKILL.md | sed "s|^$SKILLS/||")" ""

expect "no skill names a project's own plugin or its tools" \
  "$(grep -liE 'rn-agent|run-app|signalbox|boop' "$SKILLS"/*/SKILL.md | sed "s|^$SKILLS/||")" ""

# Each skill and plugin agent runs on its own model and effort, from its frontmatter.
model_effort() {
  expect "$1: its model" "$(field "$2" model)" "$3"
  expect "$1: its effort" "$(field "$2" effort)" "$4"
}
model_effort "the issue skill" "$ISSUE" sonnet low
for s in questions plan; do model_effort "the $s skill" "$SKILLS/$s/SKILL.md" opus high; done
for s in build update review merge tdd; do model_effort "the $s skill" "$SKILLS/$s/SKILL.md" sonnet high; done
for s in answer finish; do model_effort "the $s skill" "$SKILLS/$s/SKILL.md" sonnet medium; done
bad="" nomodel=""
for f in "$SKILLS"/*/SKILL.md; do
  case "$(field "$f" effort)" in low|medium|high|max) ;; *) bad="$bad${f#"$SKILLS"/} " ;; esac
  [ -n "$(field "$f" model)" ] || nomodel="$nomodel${f#"$SKILLS"/} "
done
expect "every skill's effort is low, medium, high or max" "$bad" ""
expect "every skill sets a model" "$nomodel" ""

AGENTS="$ROOT/plugin/agents"
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

# The build skill hands each ticket to a subagent; a real run's log shows its `→ Agent:` lines.
build=$(cat "$SKILLS/build/SKILL.md")
expect_line "the build hands each ticket to a subagent" "$build" "ticket subagent"
expect_line "the subagent is started with the Agent tool" "$build" "Agent tool"
expect_line "the subagent is the plugin's ticket agent" "$build" "\`nightshift:ticket\`"
expect_line "its model is its agent's own" "$build" "without a \`model\`"
expect_line "a stuck subagent replies BLOCKED:" "$build" "\`BLOCKED:\`"
expect_line "the subagent doesn't comment on the issue" "$build" "comments on the issue, changes labels"
expect_line "the run checks each ticket's commit and a clean tree" "$build" "the tree clean"
expect_line "a one-ticket plan is built without a subagent" "$build" "plan with one ticket"

# Test-first is the tdd skill's alone; the build's brief points at the plan and the worktree.
expect_line "the ticket agent loads nightshift:tdd with the Skill tool" "$(flat "$AGENTS/ticket.md")" "Skill tool[^.]*\`nightshift:tdd\`"
for t in "A good test" "Tautological" "Horizontal" "Red before green" "^## Test first" "^## Mocks" "^## The loop"; do
  expect_line "the build skill doesn't carry the test-first text ($t)" "$build" "$t" no
done
expect_line "the build skill points to the tdd skill" "$build" "nightshift:tdd"
brief=$(flat "$SKILLS/build/SKILL.md")
expect_line "the brief points at the plan comment through gh" "$brief" "issue number[^.]*gh"
expect_line "the brief gives the worktree's absolute path" "$brief" "worktree's absolute path"
expect_line "the brief gives the commits so far" "$brief" "commits so far"
expect_line "the brief says to pass the issue number, not paste the ticket" "$brief" "not pasted"

# On go, each ticket becomes a sub-issue (no agent label) that the brief and the PR body name.
expect_line "the build makes a sub-issue per ticket with --parent" "$brief" "one sub-issue per ticket[^.]*gh issue create --parent"
expect_line "the build falls back to the sub_issues API" "$brief" "sub_issues"
expect_line "the fallback adds the new issue's id, not its number" "$brief" "new issue.s \`id\` field.*not its number"
expect_line "a sub-issue is titled by its ticket ID" "$brief" "\`T1: <ticket title>\`"
expect_line "a sub-issue carries the ticket's text, blockers and criteria" "$brief" "blockers and acceptance criteria"
expect_line "a sub-issue has no agent label" "$brief" "No \`agent\` label"
expect_line "the build reuses sub-issues found by title under the parent" "$brief" "reuses[^.]*by title"
expect_line "the build makes the sub-issues before the first ticket" "$brief" "Before the first ticket"
expect_line "the brief names the ticket's sub-issue" "$brief" "its sub-issue[^.]*number"
expect_line "the build hands the sub-issue numbers to the finish skill" "$brief" "nightshift:finish[^.]*sub-issue numbers"
finish=$(flat "$SKILLS/finish/SKILL.md")
expect_line "the PR body closes the issue" "$finish" "Closes #<issue>"
expect_line "the PR body closes each sub-issue" "$finish" "Closes #<sub>"
expect_line "the closing lines end the PR body" "$finish" "ends with[^.]*Closes #"
# The PR body follows the pr skill: Summary, Evidence, Merge Danger, then what nightshift adds.
for h in Summary Evidence "Merge Danger"; do
  expect_line "the finish skill's PR body has a $h section" "$(cat "$SKILLS/finish/SKILL.md")" "^## $h\$"
done
expect_ok "the PR body's sections run Summary, Evidence, Merge Danger" \
  test "$(line_of "$SKILLS/finish/SKILL.md" '^## Summary$')" -lt "$(line_of "$SKILLS/finish/SKILL.md" '^## Evidence$')" \
    -a "$(line_of "$SKILLS/finish/SKILL.md" '^## Evidence$')" -lt "$(line_of "$SKILLS/finish/SKILL.md" '^## Merge Danger$')"
expect_line "the summary is the smallest visual" "$finish" "smallest visual"
expect_line "the evidence is a before and after" "$finish" "Before:.*After:"
expect_line "the merge danger names the door" "$finish" "one-way or two-way"
expect_line "the merge danger names the blast radius in one word, narrow or wide" "$finish" "Blast radius:[^.]*narrow.*wide"
expect_line "the PR body keeps the open review findings" "$finish" "open review findings"
expect_line "the PR body keeps the overlap lines and their markers" "$finish" "overlap lines[^.]*<!-- nightshift:after #N -->[^.]*<!-- nightshift:overlaps #N -->"
expect_line "the closing lines and overlap lines are for nightshift only" "$finish" "Outside nightshift[^.]*no \`Closes\`"
expect_line "the PR skill is credited in the notices" "$(cat "$ROOT/plugin/THIRD_PARTY.md")" "\`pr\` in \`finish\`"

# The merge skill takes a wide blast radius, defined, as a look item; a one-way door alone isn't one.
merge_flat=$(flat "$SKILLS/merge/SKILL.md")
expect_line "a wide blast radius is a look item" "$merge_flat" "a wide blast radius"
expect_line "wide means the change reaches past its feature" "$merge_flat" "wide when the change reaches past its feature"
for r in "config" "persisted state or data layout" "installer" "commands or flags" "what a run can reach"; do
  expect_line "the wide definition names $r" "$merge_flat" "wide when[^;]*$r"
done
expect_line "the wide definition works for any worked repo, with nightshift's examples" "$merge_flat" "the repo.s persisted state[^.]*\`~/.nightshift\`"
expect_line "the merge skill reads Merge Danger and judges the diff itself" "$merge_flat" "Merge Danger[^.]*the diff"
expect_line "a one-way door alone isn't a look item" "$merge_flat" "one-way door alone"
expect_line "the plan says tickets become sub-issues on go" "$(flat "$SKILLS/plan/SKILL.md")" "on \*\*go\*\*[^.]*sub-issue"
expect_line "the plan no longer says tickets are only in the comment" "$(flat "$SKILLS/plan/SKILL.md")" "All tickets are in this comment" no

# The plugin's SessionStart hook, as Claude Code runs it: your own sessions get
# nightshift's defaults, a run (which has them in its system prompt) nothing.
hook=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$ROOT/plugin/hooks/hooks.json")
expect "the hook prints nightshift's defaults" \
  "$(env -u NIGHTSHIFT_ISSUE CLAUDE_PLUGIN_ROOT="$ROOT/plugin" sh -c "$hook")" "$(cat "$ROOT/plugin/instructions.md")"
expect "the hook prints nothing in a run" \
  "$(NIGHTSHIFT_ISSUE=7 CLAUDE_PLUGIN_ROOT="$ROOT/plugin" sh -c "$hook")" ""
expect "the defaults have the CLAUDE.md rules, with the root's budget" \
  "$(grep -c -e '^# CLAUDE.md$' -e '200 lines' "$ROOT/plugin/instructions.md")" 2
expect "the defaults say a run ends when you stop" \
  "$(tr '\n' ' ' <"$ROOT/plugin/instructions.md" | grep -c 'A run ends when you stop')" 1

# A run files a real defect it finds outside its issue, held as proposed until the user comments.
issue=$(cat "$ISSUE")
expect_line "a run files a defect it finds as a proposed issue" "$issue" "\`nightshift: proposed\`"
expect_line "it looks for a duplicate first, open or closed" "$issue" "gh issue list --state all"
expect_line "it files at most three a run" "$issue" "at most three"
expect_line "filing finishes before the run ends" "$issue" "run_in_background: false"
expect_line "the filed issue says where it was found" "$issue" "Found while working #<n>."
expect_line "a ticket subagent reports defects to the run, not files them" "$build" "files no issues"

report
