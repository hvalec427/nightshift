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
pull request it goes after or overlaps merged). Make it fit what's there now, so the pull
requests can merge in any order:

- `git fetch origin`, check out this branch at `origin/nightshift/issue-<n>`, and
  rebase it onto `origin/<default branch>`, fixing the conflicts.
- Then reread what merged (`git log -p` of the new commits where they touch what this
  change touches) and update this change wherever it relied on that work or now
  duplicates it: use what landed instead of a copy, follow a rename, drop what's done.
  Rebasing alone isn't enough.
- Run the full checks again, as for a ticket (the build skill), then
  `git push --force-with-lease origin HEAD`. Run them in the foreground and wait for
  them: a run ends when you stop.
- Update the overlap lines in the PR body (`gh pr edit --body-file`): drop the ones
  about the merged work, and add any new ones.
- A `progress` comment: what conflicted and how you fixed it, then what changed beyond
  the conflict fixes, and the checks you ran. A conflict that's a real decision between
  the two changes gets a `blocked` comment instead (after `git rebase --abort`, so the
  branch stays as it was).
- After the `progress` comment (not a `blocked` one), when the run prompt says "This repo
  auto-merges", invoke the `nightshift:merge` skill with the Skill tool: it checks the
  pull request again and merges it, or says what needs a look. That's how one that goes
  after another merges once the other has.
