#!/usr/bin/env bash
# Tests for a repo's settings in a run: .nightshift/config on the default branch
# (auto_merge, full_suite), how a run reads it, and that the prompt lines the skills
# key on are the ones a run gets.
#   bash scripts/test-runs-config.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A repo's settings come from .nightshift/config on origin's default branch.
NO_MERGE="^This repo doesn't auto-merge (auto_merge=false in \.nightshift/config): leave merging to the user\.$"
MERGES="^This repo auto-merges: once its pull request is open or updated, use the merge skill\.$"

(world
  origin_config "auto_merge=false"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "auto_merge=false in .nightshift/config: the run still works in the clone's worktree" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$CLONE/.claude/worktrees/issue-7"
  expect_line "the prompt: auto_merge=false doesn't auto-merge" "$(run_prompt)" "$NO_MERGE"
  expect_line "the prompt: no auto-merge isn't also auto-merge" "$(run_prompt)" "$MERGES" no)

(world
  origin_config "auto_merge=no"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "the prompt: only auto_merge=false turns it off" "$(run_prompt)" "$MERGES")

(world
  origin_config "# the default: auto_merge=false turns it off
plugins=
auto_merge=false
auto_merge=true"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "a comment isn't a setting, and the last value of a key wins" "$(run_prompt)" "$MERGES")

(world
  origin_config "auto_merge=true
auto_merge=false"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "the last auto_merge wins: false" "$(run_prompt)" "$NO_MERGE")

(world
  origin_file other.md "unrelated"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "no .nightshift/config on the default branch: auto-merges" "$(run_prompt)" "$MERGES")

(world
  printf 'repo %s %s auto_merge=false\n' "$REPO" "$CLONE" >"$NS/config"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "auto_merge=false on a repo line: ignored" "$(run_prompt)" "$MERGES"
  expect "auto_merge=false on a repo line: the clone path without it" "$(cat "$CLAUDE_FAKE/runs/1/cwd")" "$CLONE/.claude/worktrees/issue-7")

(world
  origin_config "auto_merge=false"
  printf 'repo %s %s auto_merge=true\n' "$REPO" "$CLONE" >"$NS/config"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "a repo line's auto_merge=true doesn't beat the file" "$(run_prompt)" "$NO_MERGE")

# full_suite in .nightshift/config sets the suite line of the prompt.
SUITE_CI="^This repo leaves its whole test suite to CI: check what you touched, then push; run the whole suite yourself only if the repo has no CI checks on its pull requests\.$"
SUITE_LOCAL="^This repo runs its whole test suite locally (full_suite=local in \.nightshift/config): run it before you push\.$"
SUITE_NOTHING="^nightshift runs no whole test suite in this repo (full_suite=nothing in \.nightshift/config): check what you touched, then push\.$"

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "no .nightshift/config: the default suite line" "$(run_prompt)" "$SUITE_CI"
  expect_line "no .nightshift/config: not the local line" "$(run_prompt)" "$SUITE_LOCAL" no
  expect_line "no .nightshift/config: not the nothing line" "$(run_prompt)" "$SUITE_NOTHING" no)

(world
  origin_config "full_suite=local"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "full_suite=local: the local line" "$(run_prompt)" "$SUITE_LOCAL"
  expect_line "full_suite=local: not the default line" "$(run_prompt)" "$SUITE_CI" no)

(world
  origin_config "full_suite=nothing"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "full_suite=nothing: the nothing line" "$(run_prompt)" "$SUITE_NOTHING"
  expect_line "full_suite=nothing: not the default line" "$(run_prompt)" "$SUITE_CI" no)

(world
  origin_config "full_suite=ci"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "an unknown full_suite: the default line" "$(run_prompt)" "$SUITE_CI")

(world
  origin_config "auto_merge=false"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "a config without full_suite: the default line" "$(run_prompt)" "$SUITE_CI")

(world
  origin_file .nightshift/config "full_suite=local" nightshift/issue-7
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "full_suite only on the issue's branch: the default line" "$(run_prompt)" "$SUITE_CI")

# test_command in .nightshift/config names the command on the suite line: the
# line's pattern with RUN_IT in place of its closing `$`.
RUN_IT=" Run it with \`npm test\`\.$"

(world
  origin_config "test_command=npm test"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "test_command: the default line names it" "$(run_prompt)" "${SUITE_CI%\$}$RUN_IT")

(world
  origin_config "full_suite=local
test_command=npm test"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "test_command with full_suite=local: the local line names it" "$(run_prompt)" "${SUITE_LOCAL%\$}$RUN_IT")

(world
  origin_config "full_suite=nothing
test_command=npm test"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "test_command with full_suite=nothing: the nothing line, as it is" "$(run_prompt)" "$SUITE_NOTHING")

(world
  origin_config "test_command="
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "an empty test_command: the default line, as it is" "$(run_prompt)" "$SUITE_CI")

(world
  origin_file .nightshift/config "test_command=npm test" nightshift/issue-7
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "test_command only on the issue's branch: the default line, as it is" "$(run_prompt)" "$SUITE_CI")

# A branch can't change its own settings: only the default branch counts.
(world
  origin_file .nightshift/config "auto_merge=false" nightshift/issue-7
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "a change only on the issue's branch on origin: not read" "$(run_prompt)" "$MERGES")

(world
  gh_issue o/r 7 alice agent
  runs_do 'mkdir -p .nightshift; echo auto_merge=false >.nightshift/config; git add .nightshift; git commit -q -m "chore: config"; comment questions'
  poll
  expect_line "the first run: auto-merges" "$(run_prompt)" "$MERGES"
  gh_comment o/r 7 alice "more" >/dev/null
  poll
  expect_line "a change in the branch's own worktree: not read" "$(run_prompt)" "$MERGES")

# Fetched before each run, not only when the worktree is made.
(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "before the file: auto-merges" "$(run_prompt)" "$MERGES"
  origin_config "auto_merge=false"
  gh_comment o/r 7 alice "more" >/dev/null
  poll
  expect_line "committed to origin since: the next run reads it" "$(run_prompt)" "$NO_MERGE"
  origin_config "auto_merge=true"
  gh_comment o/r 7 alice "again" >/dev/null
  poll
  expect_line "changed back: the next run too" "$(run_prompt)" "$MERGES")

# The default branch from origin/HEAD when it's set, else from GitHub.
(world
  origin_config "auto_merge=false"
  git -C "$CLONE" fetch -q origin
  git -C "$CLONE" remote set-head origin master
  sed -i.bak 's/"master"/"gone"/' "$(gh_dir o/r)/repo.json"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "origin/HEAD set: the default branch from it" "$(run_prompt)" "$NO_MERGE")

(world
  origin_config "auto_merge=false"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "origin/HEAD missing: the default branch from GitHub" "$(run_prompt)" "$NO_MERGE")

(world
  echo "Use tabs." >"$W/ours.md"
  printf 'repo %s %s auto_merge=false instructions=%s\n' "$REPO" "$CLONE" "$W/ours.md" >"$NS/config"
  origin_config "auto_merge=false"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "the file's auto_merge=false, beside an old line's other option" "$(run_prompt)" "$NO_MERGE")

# base_branch in .nightshift/config: new worktrees start from origin/<it>, and the prompt
# says where pull requests merge.
BASE_LINE="^This repo's pull requests merge into \`develop\` (base_branch in \.nightshift/config), not the default branch: "

(world
  origin_file develop.md "on develop" develop
  origin_config "base_branch=develop"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "base_branch=develop: the worktree starts at origin/develop" "$(git -C "$CLONE/.claude/worktrees/issue-7" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse develop)"
  expect_line "base_branch=develop: the prompt names it" "$(run_prompt)" "$BASE_LINE"
  expect_line "base_branch=develop: nothing in the log" "$(cat "$(idir 7)/log")" "base_branch" no)

(world
  origin_file develop.md "on develop" develop
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "no base_branch: the worktree starts at origin/master" "$(git -C "$CLONE/.claude/worktrees/issue-7" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse master)"
  expect_line "no base_branch: no base branch line" "$(run_prompt)" "pull requests merge into" no)

(world
  origin_config "base_branch=master"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "base_branch=master: the worktree starts at origin/master" "$(git -C "$CLONE/.claude/worktrees/issue-7" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse master)"
  expect_line "base_branch equal to the default branch: no base branch line" "$(run_prompt)" "pull requests merge into" no)

(world
  origin_config "base_branch=nope"
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect "base_branch not on origin: the worktree starts at origin/master" "$(git -C "$CLONE/.claude/worktrees/issue-7" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse master)"
  expect_line "base_branch not on origin: no base branch line" "$(run_prompt)" "pull requests merge into" no
  expect_line "base_branch not on origin: the log says why" "$(cat "$(idir 7)/log")" "^0	=== base_branch nope isn't on origin: this run starts from master$")

(world
  origin_file develop.md "on develop" develop
  origin_file .nightshift/config "base_branch=develop" nightshift/issue-7
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  expect_line "base_branch only on the issue's branch: not read" "$(run_prompt)" "pull requests merge into" no)

# The skills branch on exact lines of the run prompt: the double-quoted strings in them that
# start "This repo" or "nightshift runs no". Rewording a line in the CLI, or a quote in a
# skill, would silently stop the skill acting (no merge, the wrong checks), so each quoted
# string must begin a line of the prompt of some run, under each setting that changes one.
PROMPTS=$(temp)
for setting in "" "auto_merge=false" "full_suite=local" "full_suite=nothing" "base_branch=develop"; do
  (world
    [ "$setting" != base_branch=develop ] || origin_file develop.md "on develop" develop
    [ -z "$setting" ] || origin_config "$setting"
    gh_issue o/r 7 alice agent
    runs_do 'comment questions'
    poll
    run_prompt >>"$PROMPTS")
done
QUOTED=$(grep -hoE '"(This repo|nightshift runs no)[^"]*"' "$ROOT"/plugin/skills/*/*.md | sed 's/^"//; s/"$//' | sort -u)
expect_ok "the skills quote prompt lines" test -n "$QUOTED"
while IFS= read -r quoted; do
  [ -n "$quoted" ] || continue
  begins=no
  awk -v q="$quoted" 'index($0, q) == 1 { found = 1 } END { exit !found }' "$PROMPTS" && begins=yes
  expect "a run's prompt has a line beginning \"$quoted\", as a skill quotes it" "$begins" yes
done <<<"$QUOTED"
rm -f "$PROMPTS"

report
