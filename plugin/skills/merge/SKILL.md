---
name: merge
description: Squash-merge an issue's pull request once its checks pass and nothing needs a human look, or list what does in a look comment. Started by the build, update and issue skills when the run prompt says the repo auto-merges.
allowed-tools: Bash(gh pr *) Bash(gh issue *) Bash(gh run *) Bash(git fetch *) Bash(git log *) Bash(git diff *) Bash(git rev-parse *)
user-invocable: false
model: sonnet
effort: high
---

# Merge a pull request

The issue skill's rules (comments, the status label, bounds) hold throughout. You merge
only under nightshift, when the run prompt says "This repo auto-merges". Told the repo
doesn't auto-merge, or told neither, stop here: merging is the user's.

You are handed a report (what was done, the pull request's link, the review) by the skill
that started you; it goes at the top of your one closing comment, so the issue gets one
comment where it would have got a report and a verdict. Started on the user's **merge** reply to a
`look` comment, you have none: the closing comment is the outcome alone.

This issue's pull request is open and up to date. Merge it yourself when nothing in it
needs a human; otherwise tell the user exactly what does, and let them say **merge**.

1. **Hard gates.** `gh pr view <pr> --json number,headRefOid,mergeable,body`; its
   `headRefOid` is the head you check and merge (`mergeable` is `UNKNOWN` for a moment
   after a push: ask again). A failing gate means no merge:
   - **Goes after another.** For each `<!-- nightshift:after #N -->` in the body, find
     #N's pull request (`gh pr list --state all --head nightshift/issue-N --json
     number,state,body`). Open: follow its after markers, and theirs in turn. If they lead
     back to this issue, that's a cycle, and no one in it can merge first. This issue the
     lowest in the cycle: rewrite its after markers on the cycle as
     `Overlaps with #N: … <!-- nightshift:overlaps #N -->` lines (`gh pr edit --body-file`),
     say so in the closing comment, and carry on with the gates. Not the lowest: wait as
     below, with the closing line "#M goes first in a cycle of after markers (#M, #N, this
     one); then I'll rebase on it." Not in a cycle, and not merged yet: post the report
     with a `progress` closing line ("Waiting for #N's PR to merge first; then I'll rebase
     and check it again.") and end the run.
     When #N merges, the watcher's update run rebases this one and comes back here.
     Closed without merging: a look item.
   - **Conflicts** (`mergeable` is `CONFLICTING`): a look item.
   - **Checks.** `gh pr checks <pr> --watch --interval 30`, run with the Bash tool's
     10-minute timeout so it can't hang the run; still pending when it times out, run it
     again, three times at most (30 minutes). "no checks reported" counts as passing.
     Still pending after 30 minutes: a look item, naming the checks.
     A failing check is yours to fix before you ask the user, in at most two fix rounds.
     A round: the run id is in the failing check's `link` (`gh pr checks <pr> --json
     name,state,link`); read `gh run view <run> --log-failed`, find the cause and fix it,
     run the checks for what the fix touched, commit, `git push`, take the new
     `headRefOid` as the head and run the Conflicts and Checks gates again on it, with
     30 minutes of their own. Still failing after two rounds: a look item. A failure you
     can't reproduce or fix (flaky, runner, network, quota), or a check with no `gh run`
     log behind it (external CI) whose cause its link doesn't show: a look item at once.
     Either look item names the check, the cause and what you tried.

   Done when each gate has passed or become a look item.
2. **Triggers.** Read the issue and its thread, the approved plan, the review's report
   (the PR body's open findings), the PR body's Merge Danger
   (its door and blast radius), the commits and the diff
   (`git log -p origin/<default branch>..<head>`). The author graded its own Merge Danger:
   judge the blast radius from the diff yourself, and take the wider call. A small issue
   has no plan: the issue and its thread stand in for it, so a decision they didn't settle
   is one the plan didn't cover; being small isn't a look item by itself. Any of these is
   a look item:
   - a decision made in the build that the approved plan didn't cover;
   - a review finding left unfixed, or a check that couldn't be run;
   - a breaking change, a migration, or a new dependency;
   - a security-relevant change: auth, secrets, permissions, allowed tools, what a run
     can reach;
   - a change to CI, releases or installing;
   - a wide blast radius, as [the finish skill's BODY.md](../finish/BODY.md) defines it
     (read the definition before you judge). A one-way door alone is not a look item; only
     wide is;
   - the issue or the user asked to see it before it merges.

   Done when each trigger is a look item or ruled out.
3. **Close out.**
   - **Nothing to look at:** add a line to the PR body, "Merged by nightshift: nothing
     needed a human look." and the one-line why (`gh pr view <pr> --json body -q .body` to
     a file, the line appended, `gh pr edit <pr> --body-file <file>`). Then
     `gh pr merge <pr> --squash --match-head-commit <head>`, with the head you checked,
     and leave the branch: the watcher deletes it. Then the closing `done` comment: the
     report you were handed, then merged, and why nothing needed a look; if you pushed
     fixes, it lists each fix (the check, the cause, the commit).
   - **Something to look at:** a `look` comment: the report you were handed, then the head
     you checked (`` At `<head>`: ``), then one line per item, exactly what the user needs
     to know, and a line per fix you pushed (the check, the cause, the commit), ending
     "Reply **merge** to merge it, or tell me what to change." End the run there: the issue
     waits on the user.

   Done when the pull request is merged and the `done` comment (report included) is up, or
   the `look` comment is.

## After a look comment

When the user replies **merge**, run the hard gates again, and skip the triggers they just
approved; for commits since the look comment's head, run the triggers on what's new only.
All clear: close out as in step 3. A failing check you fix the same way, with two fix
rounds of its own. Any other gate failing now, or a check you can't fix: a new `look`
comment saying which.

Merge only with passing checks, no conflicts, and the pull request this one goes after
already merged.
