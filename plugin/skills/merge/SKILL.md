---
name: merge
description: Squash-merge an issue's pull request once its checks pass and nothing needs a human look, or list what does in a look comment. Started by the build, update and issue skills when the run prompt says the repo auto-merges.
allowed-tools: Bash(gh pr *) Bash(gh issue *) Bash(git fetch *) Bash(git log *) Bash(git diff *) Bash(git rev-parse *)
user-invocable: false
model: sonnet
effort: high
---

# Merge a pull request

The issue skill's rules (comments, the status label, bounds) hold throughout. You merge
only under nightshift, when the run prompt says "This repo auto-merges". Told the repo
doesn't auto-merge, or told neither, stop here: merging is the user's.

This issue's pull request is open and up to date. Merge it yourself when nothing in it
needs a human; otherwise tell the user exactly what does, and let them say **merge**.

1. **Hard gates.** `gh pr view <pr> --json number,headRefOid,mergeable,body`; its
   `headRefOid` is the head you check and merge (`mergeable` is `UNKNOWN` for a moment
   after a push: ask again). A failing gate means no merge:
   - **Goes after another.** For each `<!-- nightshift:after #N -->` in the body, find
     #N's pull request (`gh pr list --state all --head nightshift/issue-N --json
     number,state`). Not merged yet: post a one-line `progress` comment ("Waiting for
     #N's PR to merge first; then I'll rebase and check it again.") and end the run.
     When #N merges, the watcher's update run rebases this one and comes back here.
     Closed without merging: a look item.
   - **Conflicts** (`mergeable` is `CONFLICTING`): a look item.
   - **Checks.** `gh pr checks <pr> --watch --interval 30`, run with the Bash tool's
     10-minute timeout so it can't hang the run; still pending when it times out, run it
     again, three times at most (30 minutes). "no checks reported" counts as passing.
     Failing, or still pending after 30 minutes: a look item, naming the checks.

   Done when each gate has passed or become a look item.
2. **Triggers.** Read the issue and its thread, the approved plan, the review's report
   (the build's `done` comment, the PR body's open findings), the PR body's Merge Danger
   (its door and blast radius), the commits and the diff
   (`git log -p origin/<default branch>..<head>`). The author graded its own Merge Danger:
   judge the blast radius from the diff yourself, and take the wider call. Any of these is
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
     and leave the branch: the watcher deletes it. Then a `done` comment: merged, and why
     nothing needed a look.
   - **Something to look at:** a `look` comment, starting with the head you checked
     (`` At `<head>`: ``), then one line per item, exactly what the user needs to know,
     ending "Reply **merge** to merge it, or tell me what to change." End the run there:
     the issue waits on the user.

   Done when the pull request is merged and the `done` comment is up, or the `look`
   comment is.

## After a look comment

When the user replies **merge**, run the hard gates again, and skip the triggers they just
approved; for commits since the look comment's head, run the triggers on what's new only.
All clear: close out as in step 3. A gate failing now: a new `look` comment saying which.

Merge only with passing checks, no conflicts, and the pull request this one goes after
already merged.
