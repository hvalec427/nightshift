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
every one. The stages are `questions`, `answer`, `plan`, `progress`, `done` and `blocked`.

Keep every comment as short as it can be: the user reads them between other things. Lead
with what they need to know or decide, cut what they already know (the issue, earlier
comments, what the diff shows), and fold detail they may want into a collapsed
`<details>` block. Lengths to aim for:

- `questions`: one line per question or option ([questions.md](questions.md));
- `plan`: a minute to read, the full spec collapsed (the plan skill);
- `progress`, `done`, `blocked`: one or two lines, e.g. "T2 done: short comments in the
  issue skill. Tests and shellcheck pass.";
- `answer`: the answer first, in a few lines, then where it comes from.

## Status label

The issue carries a `nightshift: <status>` label the user can see from the issue list. The
watcher sets it when a run starts and ends; you set it when you move to a step it can't
see, with `nightshift label <status>`: `planning` as you start writing or revising a plan,
`building` as you start building the tickets. If the command isn't there (an older
nightshift), skip it.

## The issue's type

The user gives an issue its type with one of GitHub's default labels next to `agent`; the
prompt names it ("Its type label: `bug`") or says it has none. It changes how you work it:

- **`bug`**: find the cause before anything else. The plan is short: the cause, the fix
  and the test, with the tickets. The first ticket is a test that fails the way the bug
  does; the fix makes it pass.
- **`enhancement`**: the steps below, as they are.
- **`documentation`**: the steps below, kept to the docs; a change to code it needs is a
  question for the user.
- **`question`**: answer it, from the code and the docs, in one `answer` comment, instead
  of the steps below: no plan, no branch, no commits. Say where the answer comes from
  (files, commands you ran). The user's reply is a follow-up (another `answer`), or asks
  for a change: then swap the label to `bug` or `enhancement` and carry on with the steps
  below from the top.
- **`duplicate`**: find the issue it duplicates (`gh issue list --state all --search …`)
  and post an `answer` linking it and saying how the two match; no plan, no pull request.
  Found none: say so, swap the label for the type it is, and carry on as that type.
- **`invalid`, `wontfix`**: the watcher doesn't run you while either is on the issue, and
  you never add them yourself.

With **no type label**, pick one of these from the issue and the code, add its label
(`gh issue edit <n> --add-label <type>`), and say in that run's comment which you took
and why. When the type turns out wrong (the issue, or the user's reply, says it's another
kind), swap it (`--remove-label <old> --add-label <new>`) and say why. Use only labels
the repo has (`gh label list`); if it lacks one, work it as that type anyway and say the
label is missing. Never set a label the prompt says the user changed since your last run:
theirs stands. Leave labels other than the type and status ones alone.

## Where the issue stands

Read the thread first (`gh issue view <n> --comments`), then do the first of these that
applies, and end the run after its comment:

1. **No plan yet, open decisions.** Read the issue and the code. Decisions that are the
   user's (behaviour, scope, UX, trade-offs) and that the issue and the code don't settle
   go in one `questions` comment: numbered, each with your recommended answer, so the user
   can reply "1 yes, 2 b". Ask the questions that change what gets built; settle the rest
   yourself and say how. How to find and word them: [questions.md](questions.md).
2. **No plan yet, nothing open** (or the answers are in). Invoke the `nightshift:plan`
   skill with the Skill tool: it writes the plan, with the spec and ticket guidance.
3. **A plan, and the user asked for changes.** Invoke `nightshift:plan` too, for a revised
   plan, then wait again.
4. **A plan the user approved** ("go", or anything that clearly means build it).
   `nightshift label building`, then build the tickets in order, in this worktree:
   - Each ticket test-first where it has logic to test ([tdd.md](tdd.md)), checked the way
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
