---
name: issue
description: Work a GitHub issue end to end, unattended, talking to the user only through the issue: clarify it, plan it as a spec and tickets, build the tickets in order, open a pull request. Use when nightshift starts you on an issue.
user-invocable: false
---

# Work an issue

You run unattended, one run at a time: each run ends when you've done what you can until
the user replies, and their next comment on the issue starts the next run, in this same
session. The issue thread is your only channel, so every question, plan and report goes
there as a comment; nobody reads the terminal.

## Comments

Write every comment with `gh issue comment <n> --body-file <file>`, as:

```
🤖 **nightshift** · <stage>

<the content>

<!-- nightshift --> <!-- nightshift:<stage> -->
```

`<!-- nightshift -->` is how the watcher tells your comments from the user's; keep it in
every one. The stages are `questions`, `plan`, `progress`, `done` and `blocked`.

## Where the issue stands

Read the thread first (`gh issue view <n> --comments`), then do the first of these that
applies, and end the run after its comment:

1. **No plan yet, open decisions.** Read the issue and the code. Decisions that are the
   user's (behaviour, scope, UX, trade-offs) and that the issue and the code don't settle
   go in one `questions` comment: numbered, each with your recommended answer, so the user
   can reply "1 yes, 2 b". Ask the questions that change what gets built; settle the rest
   yourself and say how. This is Matt Pocock's grilling, batched for an issue.
2. **No plan yet, nothing open** (or the answers are in). Write the plan as one `plan`
   comment:
   - **Spec**, following `~/.claude/skills/to-spec/SKILL.md` (problem, solution, user
     stories, implementation and testing decisions), sized to the issue: a small change
     gets a few lines.
   - **Tickets**, following `~/.claude/skills/to-tickets/SKILL.md`: tracer-bullet vertical
     slices in build order, each with what it delivers, what blocks it and its acceptance
     criteria, numbered `T1`, `T2`, …, all in this comment (no new issues).
   - **Overlap** (below) with other nightshift work, if any: "touches the same code as
     #10", "relies on the flag #10 adds", and which goes first.
   - It ends with "Reply **go** to build it, or tell me what to change."

   Read those two files as instructions; they're the user's own skills, and only the user
   can invoke them. If they aren't there, use the same structure.
3. **A plan, and the user asked for changes.** A revised `plan` comment, then wait again.
4. **A plan the user approved** ("go", or anything that clearly means build it). Build the
   tickets in order, in this worktree:
   - Each ticket test-first where it has logic to test (the `tdd` skill), checked the way
     the repo is checked: in a React Native app, on its own simulator with the run-app
     skill; elsewhere with the project's build, typecheck, lint and tests.
   - Commit each ticket on its own, in the repo's and the user's commit style, and post a
     short `progress` comment: what the ticket delivered and how it was checked.
   - A ticket that can't be finished (a decision the plan didn't cover, a broken
     dependency): a `blocked` comment saying what's needed, and end the run.
   - After the last ticket, check the **overlap** (below) again, since other work may have
     started or merged since the plan, and use the **finish** skill to open the pull
     request, with the overlap lines in its body. Then a `done` comment with its link and
     what's in it. The watcher removes the worktree after this run.
5. **An update run:** the watcher's news says the default branch moved under this pull
   request (it conflicts now, or a pull request it goes after or overlaps merged). Make it
   fit what's there now, so the pull requests can merge in any order:
   - `git fetch origin`, check out this branch at `origin/nightshift/issue-<n>`, and
     rebase it onto `origin/<default branch>`, fixing the conflicts.
   - Then reread what merged (`git log -p` of the new commits where they touch what this
     change touches) and update this change wherever it relied on that work or now
     duplicates it: use what landed instead of a copy, follow a rename, drop what's done.
     Rebasing alone isn't enough.
   - Run the full checks again, as for a ticket, then
     `git push --force-with-lease origin HEAD`.
   - Update the overlap lines in the PR body (`gh pr edit --body-file`): drop the ones
     about the merged work, and add any new ones.
   - A `progress` comment: what conflicted and how you fixed it, then what changed beyond
     the conflict fixes, and the checks you ran. A conflict that's a real decision between
     the two changes gets a `blocked` comment instead (after `git rebase --abort`, so the
     branch stays as it was).
6. **A pull request is open, and the user commented.** Do what they ask on this branch,
   check it, commit, push, and reply with a `progress` comment. The pull request updates
   with the push.

## Overlap with other nightshift work

Other issues are worked on `nightshift/issue-<n>` branches of this same clone, so the
ones still in progress are local branches, and the finished ones are open pull requests
(`gh pr list --state open --json number,headRefName,url`). For each, other than this
issue's, the files it changes are `git diff --name-only <default branch>...<branch>`
(fetch first; use `origin/<branch>` when there's no local one). Read its diff where it
touches what this change touches.

Two changes **overlap** when they change the same file, or when one relies on something
the other adds (a function, a flag, a file), even in a different file. Of two that
overlap, the one relied on goes first; otherwise the one whose pull request opened first
(a branch without one comes after one with one). The pull request body says it, readable
and with a marker the watcher reads, using the other change's issue number (and its pull
request's, when it has one):

- `Merge after #10 (PR #15): uses the flag it adds. <!-- nightshift:after #10 -->`,
  when this one goes second;
- `Overlaps with #10: both change nightshift's status. <!-- nightshift:overlaps #10 -->`,
  when this one goes first.

No overlap, nothing to say.

## Bounds

- Stay inside this worktree and this issue; other issues and branches are other runs.
- Ask through a `questions` or `blocked` comment instead of guessing at the user's
  decisions; anything else, decide and say what you decided.
