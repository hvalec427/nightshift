---
name: update
description: Rebase an issue's pull request onto the default branch after it moved, and adapt the change to what merged. Started by the issue skill on an update run.
user-invocable: false
model: sonnet
effort: high
---

# Update a pull request

The issue skill sent you here, and its rules (comments, the status label, overlap, bounds)
hold throughout. The default branch moved under this pull request (it conflicts now, or a
pull request it goes after or overlaps merged). Make the change fit what's there now, so
the pull requests can merge in any order.

1. **Rebase.** `git fetch origin`, check out this branch at `origin/nightshift/issue-<n>`,
   and rebase it onto `origin/<default branch>`, fixing the conflicts. A conflict that's a
   real decision between the two changes gets a `blocked` comment instead, after
   `git rebase --abort`, so the branch stays as it was. Done when the rebase completes.
2. **Adapt.** Reread what merged (`git log -p` of the new commits where they touch what
   this change touches) and update the change wherever it relied on that work or now
   duplicates it: use what landed instead of a copy, follow a rename, drop what's done.
   A clean rebase is the start of this step. Done when no part of the change copies what
   landed.
3. **Check and push.** Run the checks for what the rebase and the adaptation touched, plus
   the build, typecheck and lint, in the foreground, and wait for them:
   a run ends when you stop. Run the whole test suite too, as after the build's review, only
   under the local line, or the default line in a repo with no CI (see "has CI" in the build
   skill), and never under the nothing line: with the command the line names, or else as the
   repo's instructions say. Then `git push --force-with-lease origin HEAD`.
   Done when the checks pass and the push succeeds.
4. **Overlap lines.** In the PR body (`gh pr edit --body-file`), drop the lines about the
   merged work and add any new ones. Done when the body's lines match the work still open.
   When the run prompt says the pull requests go after each other in a cycle, this one goes
   first: rewrite its `Merge after #N: … <!-- nightshift:after #N -->` lines for the cycle's
   issues (every one the run prompt names) as
   `Overlaps with #N: … <!-- nightshift:overlaps #N -->`, keeping the reason. The others
   keep their after markers; they update on top of this one once it merges. Done when none
   of this body's after markers lead back into the cycle.
5. **Report.** When the run prompt says a cycle, lead with it and the order: "#57 and #59
   were each marked to merge after the other; #57 goes first (lowest issue), #59 updates on
   top of it." Then what conflicted and how you fixed it, then what changed beyond the
   conflict fixes, and the checks you ran. Post it as a `progress` comment, the run's one
   comment, only when the repo doesn't auto-merge. When the run prompt says "This repo
   auto-merges", post nothing and hand that report to the `nightshift:merge` skill,
   invoked with the Skill tool: it puts it at the top of its one closing comment, after
   checking the pull request again and merging it, or saying what needs a look. That's how
   one that goes after another merges once the other has.
