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

# The diagnose skill: the issue skill starts it for a bug with no plan, and it ends in the plan.
diag="$SKILLS/diagnose/SKILL.md"
diagtext=$(flat "$diag" 2>/dev/null)
expect_line "a bug with no plan is diagnosed before it is planned" "$(flat "$ISSUE")" "\`bug\`[^.]*\`nightshift:diagnose\`"
expect_line "the issue skill diagnoses a bug only when there's no plan yet" "$(flat "$ISSUE")" "nothing open.*On a \`bug\`, invoke the \`nightshift:diagnose\`"
expect_line "open decisions on a bug are still asked first" "$(flat "$ISSUE")" "No plan yet, open decisions"
expect_line "diagnose builds a feedback loop that goes red" "$diagtext" "red-capable"
expect_line "diagnose reproduces and minimises" "$diagtext" "inimise"
expect_line "diagnose ranks 3-5 falsifiable hypotheses" "$diagtext" "3.5 ranked hypotheses"
expect_line "diagnose instruments one variable at a time" "$diagtext" "one variable at a time"
expect_line "the hypotheses go in the plan, not to the user to await" "$diagtext" "plan[^.]*wait"
expect_line "with no red-capable check it posts a questions comment" "$diagtext" "No red-capable check.*\`questions\` comment"
expect_line "that comment says what it tried" "$diagtext" "What you tried"
expect_line "that comment says what it needs" "$diagtext" "What you need"
expect_line "diagnose plans no guess without a red check" "$diagtext" "without a red check is a guess"
expect_line "diagnose ends by invoking nightshift:plan" "$diagtext" "invoke \`nightshift:plan\`"
expect_line "it hands the plan the cause, the red check and the hypotheses" "$diagtext" "cause[^.]*red check[^.]*hypotheses"
expect_line "the first ticket turns the minimised repro into the failing test" "$diagtext" "first ticket[^.]*minimised repro[^.]*failing test"
expect_line "diagnose commits no fix" "$diagtext" "no fix"
expect_line "diagnose says where the scratch repro lives" "$diagtext" "scratch"
expect_line "diagnose redacts secrets" "$diagtext" "REDACTED"
bugplan=$(flat "$SKILLS/plan/BUG.md" 2>/dev/null)
expect_line "a bug plan shows the cause" "$bugplan" "bug[^.]*the cause"
expect_line "a bug plan shows the red check" "$bugplan" "bug[^.]*red check"
expect_line "a bug plan shows the ranked hypotheses" "$bugplan" "bug[^.]*hypotheses"
expect_line "the diagnosing-bugs skill is credited in the notices" "$(cat "$ROOT/plugin/THIRD_PARTY.md")" "\`diagnosing-bugs\` in \`diagnose\`"

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
expect_ok "the build writes its report (the review in it) before the merge skill" \
  test "$(line_of "$SKILLS/build/SKILL.md" '\*\*Review:\*\*')" -lt "$(line_of "$SKILLS/build/SKILL.md" 'nightshift:merge`')"
expect_line "with auto_merge=false, a merge reply doesn't merge" "$(flat "$ISSUE")" \
  '`auto_merge=false`[^.]*you don.t merge'
expect_line "the issue skill lists the look stage" "$(flat "$ISSUE")" 'The stages are [^.]*`look`'

for s in build update; do
  expect_line "the $s skill says to wait for the checks" \
    "$(cat "$SKILLS/$s/SKILL.md")" "a run ends when you stop"
done

# Where the whole test suite runs follows the run prompt's whole-suite line (the CLI's suite_note):
# the build, the review and the update run it only under the local line, or the default line in a
# repo without CI, and never under the nothing line.
build_flat=$(flat "$SKILLS/build/SKILL.md")
review_flat=$(flat "$SKILLS/review/SKILL.md")
update_flat=$(flat "$SKILLS/update/SKILL.md")
expect_line "the build runs the whole suite under the local line" "$build_flat" \
  "full checks[^.]*only[^.]*local line"
expect_line "the build runs it under the default line only without CI" "$build_flat" \
  "local line, or the default line[^.]*no CI"
expect_line "the build quotes the default line" "$build_flat" '"This repo leaves its whole test suite to CI'
expect_line "the build quotes the local line" "$build_flat" '"This repo runs its whole test suite locally'
expect_line "the build never runs the whole suite under the nothing line" "$build_flat" \
  "[Nn]ever[^.]*nothing line"
expect_line "the build quotes the nothing line" "$build_flat" '"nightshift runs no whole test suite'
expect_line "the build defines has CI by a pull_request workflow" "$build_flat" \
  "has CI[^.]*\.github/workflows/[^.]*pull_request"
expect_line "has CI counts external checks on the latest merged pull request" "$build_flat" \
  "has CI.*latest merged pull request.*gh pr checks"
expect_line "has CI matters only under the default line" "$build_flat" "only[^.]*default line"
expect_line "the ticket bullet says where the whole suite runs instead" "$build_flat" \
  "Not the whole test suite: that runs once, after the review, where"
expect_line "the review's aside follows the same rule as the build's" "$review_flat" \
  "whole suite[^.]*local line, or the default line[^.]*no CI"
expect_line "the review's aside says never under the nothing line" "$review_flat" "[Nn]ever[^.]*nothing line"
expect_line "the review no longer says the whole suite always runs after it" "$review_flat" \
  "the whole suite runs once after this, in the build skill" no
expect_line "the update runs the whole suite under the local line" "$update_flat" \
  "whole test suite[^.]*local line, or the default line[^.]*no CI"
expect_line "the update never runs it under the nothing line" "$update_flat" "[Nn]ever[^.]*nothing line"
expect_line "the update points at the build's definition of has CI" "$update_flat" "has CI[^.]*build skill"
expect_line "the update checks what the rebase and adaptation touched" "$update_flat" \
  "checks for what the rebase and the adaptation touched"
expect_line "the update no longer always runs the whole suite" "$update_flat" \
  "Run the full checks once, the whole test suite included" no
expect_line "the repo's CLAUDE.md names the full_suite option" "$(flat "$ROOT/CLAUDE.md")" '`full_suite`'
expect_line "the repo's CLAUDE.md says what each full_suite setting means" "$(flat "$ROOT/CLAUDE.md")" \
  "unset.*local.*nothing"

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
expect_line "the brief gives the issue number and repo for what the file leaves open" "$brief" "issue number[^.]*repo[^.]*leaves open"
expect_line "the brief gives the worktree's absolute path" "$brief" "worktree's absolute path"
expect_line "the brief gives the commits so far" "$brief" "commits so far"
expect_line "the brief says to pass the issue number, not paste the ticket" "$brief" "not pasted"
expect_line "the brief lists the earlier tickets' replies" "$brief" "replies of the earlier tickets"
expect_line "those replies say what each delivered and flagged" "$brief" "earlier tickets[^.]*delivered[^.]*flagged"

# The build is silent until its closing comment: no tasks checklist, no comment per ticket.
merge_flat=$(flat "$SKILLS/merge/SKILL.md")
expect_ok "there is no TASKS.md" test ! -e "$SKILLS/build/TASKS.md"
expect "no skill or the README mentions a tasks comment" \
  "$(grep -rliE 'nightshift:tasks|`tasks`|tasks comment|tasks checklist' "$ROOT/plugin" "$ROOT/README.md" | sed "s|^$ROOT/||")" ""
expect_line "the issue skill lists no tasks stage" "$(flat "$ISSUE")" "The stages are[^.]*\`tasks\`" no
expect_line "the build posts no comment per ticket" "$brief" "no comment per ticket"
expect_line "the build ticks no box" "$brief" "tick its box" no
expect_line "the build posts no progress comment from a ticket's summary" "$brief" "post the \`progress\` comment from its summary" no
expect_line "a ticket is done with its commit" "$brief" "Done when every ticket has its commit\."
expect_line "the build posts done only when the repo doesn't auto-merge" "$brief" "\`done\` comment[^.]*only when the repo doesn.t auto-merge"
expect_line "with auto-merge the build hands its report to the merge skill" "$brief" "hand[^.]*report[^.]*to the \`nightshift:merge\` skill"
expect_line "the merge comment opens with the report it was handed" "$merge_flat" "handed a report[^.]*your one closing comment"
expect_line "the merge comment gives the pull request link and the review" "$merge_flat" "report[^.]*pull request.s link[^.]*review"
expect_line "the merge skill's review source is the PR body's open findings" "$merge_flat" "the PR body.s open findings"
expect_line "the merge skill no longer reads the build's done comment" "$merge_flat" "the build.s \`done\` comment" no
# An update run and a follow-up report once: through the merge comment with auto-merge, one progress comment without.
update_flat=$(flat "$SKILLS/update/SKILL.md")
issue_flat=$(flat "$ISSUE")
expect_line "the update skill posts its progress comment only when the repo doesn't auto-merge" "$update_flat" "\`progress\` comment[^.]*only when the repo doesn.t auto-merge"
expect_line "with auto-merge the update skill hands its report to the merge skill" "$update_flat" "hand[^.]*report[^.]*to the \`nightshift:merge\` skill"
expect_line "issue case 7 posts its progress comment only when the repo doesn't auto-merge" "$issue_flat" "\`progress\` comment[^.]*only when the repo doesn.t auto-merge"
expect_line "with auto-merge issue case 7 hands what it did to the merge skill" "$issue_flat" "hand[^.]*what it did[^.]*to the \`nightshift:merge\` skill"
expect_line "the brief points at the ticket's ID and its file" "$brief" "the ticket's ID[^.]*\`.nightshift/tickets/T<n>.md\`"
expect_line "the build writes a file per ticket before the first ticket" "$brief" "Before the first ticket[^.]*\`.nightshift/tickets/T<n>.md\`"
expect_line "the files come from the latest plan and the replies that changed it" "$brief" "write each ticket of the latest \`plan\` comment.*reply of the user's after the plan that changed it"
expect_line "a resumed build rewrites the files" "$brief" "resumed build rewrites them"
expect_line "the plan comment stays the source, the files a working copy" "$brief" "plan comment stays the source[^.]*working copy"
expect_line "the files are never committed" "$brief" "never committed"
expect_line "the brief no longer sends the subagent to the plan comment" "$brief" "reads the latest \`plan\` comment" no
expect_line "the ticket agent reads the ticket's file" "$(flat "$AGENTS/ticket.md")" "\`.nightshift/tickets/T<n>.md\`"
for w in "sub-issue" "sub_issue" "--parent" "Closes #<sub>"; do
  expect "no skill or agent mentions $w" "$(grep -rli -e "$w" "$ROOT/plugin" | sed "s|^$ROOT/||")" ""
done
finish=$(flat "$SKILLS/finish/BODY.md" 2>/dev/null)
expect_line "the finish skill writes the body by BODY.md" "$(flat "$SKILLS/finish/SKILL.md")" "by \[BODY.md\](BODY.md)"
expect_line "the PR body closes the issue" "$finish" "Closes #<issue>"
expect_line "the closing line ends the PR body" "$finish" "last, the closing line[^.]*Closes #<issue>"
# The PR body follows the pr skill: Summary, Evidence, Merge Danger, then what nightshift adds.
for h in Summary Evidence "Merge Danger"; do
  expect_line "the finish skill's PR body has a $h section" "$(cat "$SKILLS/finish/BODY.md" 2>/dev/null)" "^## $h\$"
done
expect_ok "the PR body's sections run Summary, Evidence, Merge Danger" \
  test "$(line_of "$SKILLS/finish/BODY.md" '^## Summary$')" -lt "$(line_of "$SKILLS/finish/BODY.md" '^## Evidence$')" \
    -a "$(line_of "$SKILLS/finish/BODY.md" '^## Evidence$')" -lt "$(line_of "$SKILLS/finish/BODY.md" '^## Merge Danger$')"
expect_line "the summary is the smallest visual" "$finish" "smallest visual"
expect_line "the evidence is a before and after" "$finish" "Before:.*After:"
expect_line "the merge danger names the door" "$finish" "one-way or two-way"
expect_line "the merge danger names the blast radius in one word, narrow or wide" "$finish" "Blast radius:[^.]*narrow.*wide"
expect_line "the PR body keeps the open review findings" "$finish" "open review findings"
expect_line "the PR body keeps the overlap lines and their markers" "$finish" "overlap lines[^.]*<!-- nightshift:after #N -->[^.]*<!-- nightshift:overlaps #N -->"
expect_line "the closing lines and overlap lines are for nightshift only" "$finish" "Outside nightshift[^.]*no \`Closes\`"
expect_line "implement-spec is credited in the notices" "$(flat "$ROOT/plugin/THIRD_PARTY.md")" "\`implement-spec\` in \`build\`"
expect_line "the PR skill is credited in the notices" "$(cat "$ROOT/plugin/THIRD_PARTY.md")" "\`pr\` in \`finish\`"

# The merge skill takes a wide blast radius as a look item; the one definition is the finish skill's BODY.md.
expect_line "a wide blast radius is a look item" "$merge_flat" "a wide blast radius"
expect_line "the merge skill points at the finish skill's definition of wide" "$merge_flat" "\[the finish skill.s BODY.md\](\.\./finish/BODY.md)"
expect "the wide definition lives in BODY.md alone" "$(grep -l 'Wide when' "$SKILLS"/*/*.md | sed "s|^$SKILLS/||")" "finish/BODY.md"
expect_line "wide means the change reaches past its feature" "$finish" "Wide when the change reaches past its feature"
for r in "config" "persisted state or data layout" "installer" "commands or flags" "what a run can reach"; do
  expect_line "the wide definition names $r" "$finish" "Wide when[^;]*$r"
done
expect_line "the wide definition works for any worked repo, with nightshift's examples" "$finish" "the repo.s persisted state[^.]*\`~/.nightshift\`"
expect_line "the merge skill reads Merge Danger and judges the diff itself" "$merge_flat" "Merge Danger[^.]*the diff"
expect_line "a one-way door alone isn't a look item" "$merge_flat" "one-way door alone"
expect_line "the plan says nothing of a tasks checklist" "$(flat "$SKILLS/plan/SKILL.md")" "tasks checklist" no
expect_line "the plan no longer says tickets are only in the comment" "$(flat "$SKILLS/plan/SKILL.md")" "All tickets are in this comment" no

# Reference that only some branches need lives in a sibling file, linked from its SKILL.md.
while read -r skill sibling; do
  expect_ok "the $skill skill has $sibling" test -s "$SKILLS/$skill/$sibling"
  expect_line "the $skill skill links $sibling" "$(cat "$SKILLS/$skill/SKILL.md")" "]($sibling)"
done <<'EOF'
plan BUG.md
plan WIDE-REFACTOR.md
finish BODY.md
review SMELLS.md
tdd tests.md
tdd mocking.md
EOF
expect_line "the plan points a wide refactor to expand-contract" "$(flat "$SKILLS/plan/WIDE-REFACTOR.md" 2>/dev/null)" "Expand.*Migrate.*Contract"
expect_line "the review's smell baseline names its smells" "$(flat "$SKILLS/review/SMELLS.md" 2>/dev/null)" "Mysterious Name.*Refused Bequest"
expect_line "the review skill pastes the smell baseline into the Standards brief" "$(flat "$SKILLS/review/SKILL.md")" "SMELLS.md[^.]*pasted in full"
expect_line "writing-for-agents is credited in the notices" "$(flat "$ROOT/plugin/THIRD_PARTY.md")" "every skill and agent is written by his \`writing-for-agents\`"

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

# The project's glossary is .nightshift/CONTEXT.md: read before asking, planning and diagnosing, kept current by every run.
for s in questions plan diagnose; do
  expect_line "the $s skill reads .nightshift/CONTEXT.md" "$(flat "$SKILLS/$s/SKILL.md")" '\.nightshift/CONTEXT\.md'
  expect_line "the $s skill no longer points at a GLOSSARY.md" "$(flat "$SKILLS/$s/SKILL.md")" "GLOSSARY" no
done
expect_line "the defaults have each run keep .nightshift/CONTEXT.md current, in its pull request" \
  "$(flat "$ROOT/plugin/instructions.md")" 'term[^.]*\.nightshift/CONTEXT\.md[^.]*same pull request'

# A run files a real defect it finds outside its issue, held as proposed until the user comments.
issue=$(cat "$ISSUE")
expect_line "a run files a defect it finds as a proposed issue" "$issue" "\`nightshift: proposed\`"
expect_line "it looks for a duplicate first, open or closed" "$issue" "gh issue list --state all"
expect_line "it files at most three a run" "$issue" "at most three"
expect_line "filing finishes before the run ends" "$issue" "run_in_background: false"
expect_line "the filed issue says where it was found" "$issue" "Found while working #<n>."
expect_line "a ticket subagent reports defects to the run, not files them" "$build" "files no issues"

report
