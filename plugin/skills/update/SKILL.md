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
3. **Check and push.** Run the full checks once, the whole test suite included, as after the
   build's review, in the foreground, and wait for them: a run ends when you stop. Then
   `git push --force-with-lease origin HEAD`. Done when the checks pass and the push
   succeeds.
4. **Overlap lines.** In the PR body (`gh pr edit --body-file`), drop the lines about the
   merged work and add any new ones. Done when the body's lines match the work still open.
5. **Report.** A `progress` comment: what conflicted and how you fixed it, then what
   changed beyond the conflict fixes, and the checks you ran. After it, when the run prompt
   says "This repo auto-merges", invoke the `nightshift:merge` skill with the Skill tool: it
   checks the pull request again and merges it, or says what needs a look. That's how one
   that goes after another merges once the other has.
