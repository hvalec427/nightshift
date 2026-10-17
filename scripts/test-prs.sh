#!/usr/bin/env bash
# Tests for an issue's pull request: opened by a run, updated when it
# conflicts or what it goes after merges, and the issue retired once it
# merges or the issue closes (and brought back by a comment).
#   bash scripts/test-prs.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# What a run that builds issue 7 and opens its pull request does, with the
# pull request's body $1.
BUILDS='label building; commit feature.txt; open_pr "${PR_BODY:-Closes #7}"; comment done'

# A script step: the issue's labels as the run starts, into $RUN/start.
LABELS_AT_START='gh api "repos/$NIGHTSHIFT_REPO/issues/$NIGHTSHIFT_ISSUE" --jq ".labels[].name" >"$RUN/start"; '

# Issue 7, built, its pull request open (its body: $1).
built() {
  gh_issue o/r 7 alice agent
  runs_do "PR_BODY='${1:-Closes #7}'; $BUILDS"
  poll
  PR=$(state 7 pr)
}

# Another nightshift issue's pull request, merged: issue $1's, as PR number
# printed.
merged_other() {
  git -C "$CLONE" push -q origin "master:refs/heads/nightshift/issue-$1"
  url=$(gh_pr o/r "nightshift/issue-$1" master "Closes #$1")
  gh_pr_set o/r "${url##*/}" state '"MERGED"'
  echo "${url##*/}"
}

# The pull request's number.
prn() { echo "${PR##*/}"; }

(world
  built
  wt="$CLONE/.claude/worktrees/issue-7"
  expect "a run that opens a pull request: it's kept" "$PR" "https://github.com/o/r/pull/100"
  expect "its status: PR open" "$(status_label 7)" "PR open"
  expect_ok "a clean worktree is removed" test ! -d "$wt"
  expect_ok "its branch stays" git -C "$CLONE" rev-parse -q --verify refs/heads/nightshift/issue-7
  expect_line "the watch log: the pull request" "$(cat "$NS/watch.log")" "o/r#7: pull request $PR$"
  expect_line "status: the pull request" "$(ns status)" "^o/r#7  *PR $PR · waiting "
  gh_comment o/r 7 alice "rename it please" >/dev/null
  runs_do "$LABELS_AT_START"'commit rename.txt; git push -q origin HEAD; comment progress'
  poll
  expect "a comment on it: a run, back in its worktree" "$(cat "$CLAUDE_FAKE/runs/2/cwd")" "$wt"
  expect "on its branch, from where it was" "$(git -C "$CLONE" log --format=%s -2 nightshift/issue-7 | tr '\n' ,)" "feat: rename.txt,feat: feature.txt,"
  expect "while it runs: building" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/2/start")" "nightshift: building"
  expect "done again: PR open" "$(status_label 7)" "PR open"
  expect_no_unexpected)

(world
  gh_issue o/r 7 alice agent
  runs_do "$BUILDS; echo wip >notes.txt"
  poll
  expect_ok "a dirty worktree is kept" test -f "$CLONE/.claude/worktrees/issue-7/notes.txt")

# Update runs.
(world
  built
  gh_pr_set o/r "$(prn)" mergeable '"CONFLICTING"'
  runs_do "$LABELS_AT_START"'comment progress'
  poll
  expect "a conflict: an update run" "$(runs)" 2
  expect_line "the issue is told" "$(gh_comments o/r 7)" \
    "^master moved, and this pull request conflicts with master now, so I'm rebasing it onto master and updating it to fit\.$"
  expect_line "the run is told" "$(run_prompt)" "^- the watcher: master moved, and this pull request conflicts with master now"
  expect_line "the run is told it's an update run" "$(run_prompt)" "^This is an update run: the update skill's job\.$"
  expect "while it runs: updating" "$(grep '^nightshift: ' "$CLAUDE_FAKE/runs/2/start")" "nightshift: updating"
  expect "it's noted for the default branch's commit" "$(state 7 conflict)" "$(git -C "$ORIGIN" rev-parse master)"
  expect_ok "and no longer waits" test ! -f "$(idir 7)/update"
  expect_ok "and isn't updating after" test ! -f "$(idir 7)/updating"
  expect "after: PR open" "$(status_label 7)" "PR open"
  poll
  expect "still conflicting, same commit: no second run" "$(runs)" 2
  echo more >"$CLONE/more" && git -C "$CLONE" add more && git -C "$CLONE" commit -q -m "feat: more"
  git -C "$CLONE" push -q origin master
  poll
  expect "the default branch moves on, still conflicting: another" "$(runs)" 3
  expect_no_unexpected)

(world
  built 'Closes #7. Merge after #5. <!-- nightshift:after #5 -->'
  poll
  expect_line "status: what it goes after" "$(ns status)" "PR $PR · after #5 · waiting"
  p=$(merged_other 5)
  runs_do 'comment progress'
  poll
  expect "what it goes after merged: an update run" "$(runs)" 2
  expect_line "the issue is told why" "$(gh_comments o/r 7)" \
    "^#5 (PR #$p) merged, and this pull request goes after it, so I'm rebasing it onto master and updating it to fit what merged\.$"
  expect_line "the watch log says so" "$(cat "$NS/watch.log")" "o/r#7: pull request updating after #5$"
  poll
  expect "that merge once: no second run" "$(runs)" 2)

(world
  built 'Overlaps with #5. <!-- nightshift:overlaps #5 -->'
  p=$(merged_other 5)
  poll
  expect_line "what it overlaps merged: an update run" "$(gh_comments o/r 7)" \
    "^#5 (PR #$p) merged, and this pull request overlaps it, so I'm rebasing"
  expect "with a run" "$(runs)" 2)

(world
  merged_other 5 >/dev/null
  built 'Merge after #5. <!-- nightshift:after #5 -->'
  poll
  expect "a merge from before the first poll: no update run" "$(runs)" 1)

(world
  built
  p=$(merged_other 5)
  poll
  expect "another merge it doesn't go after: no update run" "$(runs)" 1)

# Retired.
(world
  built
  gh_pr_set o/r "$(prn)" state '"MERGED"'
  poll
  expect "merged: done" "$(state 7 "done")" "PR merged"
  expect_ok "its local branch is deleted" test -z "$(git -C "$CLONE" branch --list nightshift/issue-7)"
  expect_ok "its branch on GitHub is deleted" test -z "$(git -C "$ORIGIN" branch --list nightshift/issue-7)"
  expect "its run state goes" "$(cd "$(idir 7)" && ls finished label type news worktree 2>/dev/null)" ""
  expect "what's worth keeping stays" "$(cd "$(idir 7)" && ls "done" log pr session started)" "done
log
pr
session
started"
  expect "its status label goes" "$(status_label 7)" ""
  expect_line "the watch log says so" "$(cat "$NS/watch.log")" "o/r#7: done (PR merged), branch deleted$"
  expect_line "status: hidden" "$(ns status)" "^no issues in progress$"
  expect_line "status: counted" "$(ns status)" "^(1 done: nightshift status --all)$"
  expect_line "status --all: shown" "$(ns status --all)" "^o/r#7  *done · PR $PR merged .* ago · spent .*$"
  poll
  expect "done: no run" "$(runs)" 1
  gh_comment o/r 7 alice "one more thing" >/dev/null
  runs_do 'comment questions'
  poll
  expect "a comment on a done issue: a run" "$(runs)" 2
  expect "it resumes the session" "$(run_opt --resume)" session-1
  expect_ok "no longer done" test ! -f "$(idir 7)/done"
  expect "its merged pull request is noted" "$(state 7 revived)" "$PR"
  poll
  expect "brought back: not done again by the same merge" "$(state 7 "done")" ""
  expect_no_unexpected)

(world
  built
  # A commit after the pull request's head, locally and on GitHub.
  (cd "$CLONE" && git worktree add -q "$W/wt" nightshift/issue-7 && cd "$W/wt" && echo x >x && git add x &&
    git commit -q -m "feat: x" && git push -q origin HEAD && cd "$CLONE" && git worktree remove "$W/wt")
  gh_pr_set o/r "$(prn)" state '"MERGED"'
  poll
  expect "merged, with commits it doesn't have: done" "$(state 7 "done")" "PR merged"
  expect_ok "the local branch is kept" git -C "$CLONE" rev-parse -q --verify refs/heads/nightshift/issue-7
  expect_ok "the branch on GitHub is kept" git -C "$ORIGIN" rev-parse -q --verify refs/heads/nightshift/issue-7
  expect_line "the watch log: why the branch stays" "$(cat "$NS/watch.log")" \
    "o/r#7: kept nightshift/issue-7: it has commits the merged pull request doesn't$"
  expect_line "the watch log: why it stays on GitHub" "$(cat "$NS/watch.log")" \
    "o/r#7: kept nightshift/issue-7 on GitHub: it has commits the merged pull request doesn't$"
  expect_line "done, without a branch deleted" "$(cat "$NS/watch.log")" "o/r#7: done (PR merged)$")

(world
  built
  git -C "$ORIGIN" update-ref -d refs/heads/nightshift/issue-7
  gh_pr_set o/r "$(prn)" state '"MERGED"'
  poll
  expect_line "GitHub deleted the branch already: done, no deletion" "$(cat "$NS/watch.log")" "o/r#7: done (PR merged)$"
  expect "no deletion asked" "$(gh_calls '^api -X DELETE' | wc -l | tr -d ' ')" 0)

(world
  built
  echo 'api -X DELETE *' >"$GH_FAKE/fail"
  gh_pr_set o/r "$(prn)" state '"MERGED"'
  poll
  expect_line "the branch can't be deleted on GitHub: logged" "$(cat "$NS/watch.log")" "o/r#7: couldn't delete nightshift/issue-7 on GitHub: "
  expect "and still done" "$(state 7 "done")" "PR merged")

(world
  gh_issue o/r 7 alice agent
  runs_do 'comment questions'
  poll
  gh_state o/r 7 closed
  poll
  expect "closed, nothing running: done" "$(state 7 "done")" "issue closed"
  expect_ok "its worktree is removed" test ! -d "$CLONE/.claude/worktrees/issue-7"
  expect_ok "its branch stays (nothing merged)" git -C "$CLONE" rev-parse -q --verify refs/heads/nightshift/issue-7
  expect_line "status --all: closed" "$(ns status --all)" "^o/r#7  *done · issue closed .* ago · spent .*$")

(world
  built
  gh_pr_set o/r "$(prn)" state '"MERGED"'
  gh_state o/r 7 closed
  poll
  expect "closed by its merge: done, merged" "$(state 7 "done")" "PR merged")

# A run that merges its own pull request (which closes the issue) while a poll
# comes: not stopped, and retired done once it exits.
MERGES='commit feature.txt; open_pr; merge_pr; hold; comment done'
(world
  gh_issue o/r 7 alice agent
  runs_do "$MERGES"
  "$ROOT/nightshift" once &
  BG=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  poll
  expect_ok "merged mid-run, a poll: it isn't marked interrupted" test ! -f "$(idir 7)/interrupted"
  expect_line "the watch log: finishing" "$(cat "$NS/watch.log")" "o/r#7: issue closed: finishing$"
  touch "$CLAUDE_FAKE/runs/1/go"
  wait "$BG"
  poll
  expect "it ends done, merged" "$(state 7 "done")" "PR merged"
  expect "no status label left" "$(status_label 7)" ""
  expect_ok "its worktree is gone" test ! -d "$CLONE/.claude/worktrees/issue-7"
  expect_line "a cost comment" "$(gh_comments o/r 7)" "^<!-- nightshift --> <!-- nightshift:cost -->$"
  expect_line "status --all: done, merged" "$(ns status --all)" "^o/r#7  *done · PR .* merged "
  expect_no_unexpected)

# Closed mid-run after its done comment, nothing merged: it finishes too.
(world
  gh_issue o/r 7 alice agent
  runs_do 'commit feature.txt; open_pr; comment done; gh_state "$NIGHTSHIFT_REPO" "$NIGHTSHIFT_ISSUE" closed; hold'
  "$ROOT/nightshift" once &
  BG=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  poll
  expect_ok "closed after its done comment, a poll: the run isn't stopped" test ! -f "$(idir 7)/interrupted"
  expect_line "the watch log: finishing" "$(cat "$NS/watch.log")" "o/r#7: issue closed: finishing$"
  touch "$CLAUDE_FAKE/runs/1/go"
  wait "$BG"
  poll
  expect "it ends done, closed" "$(state 7 "done")" "issue closed")

# Closed mid-run with no merge and no done comment: stopped, as before.
(world
  gh_issue o/r 7 alice agent
  runs_do 'commit feature.txt; open_pr; gh_state "$NIGHTSHIFT_REPO" "$NIGHTSHIFT_ISSUE" closed; hang'
  "$ROOT/nightshift" once &
  BG=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  poll
  wait "$BG"
  expect_ok "closed with nothing merged or done: the run is stopped" test -f "$CLAUDE_FAKE/runs/1/stopped"
  expect "it's interrupted" "$(state 7 interrupted)" "issue closed"
  expect_ok "not done" test ! -f "$(idir 7)/done"
  expect_line "status: reopen to resume" "$(ns status)" "(issue closed) · reopen to resume"
  expect "a stopped run records its pr" "$(state 7 pr)" "https://github.com/o/r/pull/100")

# Brought back from its merge, then closed mid-run with nothing new merged:
# the old merge doesn't make it finishing.
(world
  built
  gh_pr_set o/r "$(prn)" state '"MERGED"'
  poll
  gh_comment o/r 7 alice "one more thing" >/dev/null
  gh_state o/r 7 open
  runs_do 'gh_state "$NIGHTSHIFT_REPO" "$NIGHTSHIFT_ISSUE" closed; hold'
  "$ROOT/nightshift" once &
  BG=$!
  wait_for "$CLAUDE_FAKE/runs/2/waiting"
  poll
  expect "revived, closed mid-run, nothing new merged: stopped" "$(state 7 interrupted)" "issue closed"
  touch "$CLAUDE_FAKE/runs/2/go"
  wait "$BG"
  poll
  expect "not done again by the old merge" "$(state 7 "done")" "")

# Already stopped this way (closed, interrupted, idle): retired on the next poll
# when its branch's pull request merged, or its run had posted its done comment.
STUCK='commit feature.txt; open_pr; gh_state "$NIGHTSHIFT_REPO" "$NIGHTSHIFT_ISSUE" closed; hang'
stuck() {
  gh_issue o/r 7 alice agent
  runs_do "$STUCK"
  "$ROOT/nightshift" once &
  BG=$!
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  poll
  wait "$BG"
  rm -f "$(idir 7)/pr"
}

(world
  stuck
  poll
  expect "closed, stopped, nothing merged or done: stays stopped" "$(state 7 interrupted)" "issue closed"
  expect_ok "not done" test ! -f "$(idir 7)/done"
  gh_pr_set o/r 100 state '"MERGED"'
  poll
  expect "its pr merged, none recorded: done, merged" "$(state 7 "done")" "PR merged"
  expect_ok "no longer interrupted" test ! -f "$(idir 7)/interrupted"
  expect "no status label left" "$(status_label 7)" ""
  expect_ok "its worktree is gone" test ! -d "$CLONE/.claude/worktrees/issue-7"
  expect_line "status --all: done, merged" "$(ns status --all)" "^o/r#7  *done · PR .* merged "
  expect_no_unexpected)

(world
  stuck
  printf '0\t12:00:00  commented (done)\n' >>"$(idir 7)/log"
  poll
  expect "its run had posted its done comment: done, closed" "$(state 7 "done")" "issue closed"
  expect_ok "no longer interrupted" test ! -f "$(idir 7)/interrupted"
  expect "no status label left" "$(status_label 7)" "")

report
