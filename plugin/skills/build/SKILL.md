---
name: build
description: Build an issue's approved plan ticket by ticket, test-first, then open its pull request. Started by the issue skill when the user approved the plan.
user-invocable: false
model: sonnet
effort: high
---

# Build an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The ticket brief is adapted from Matt Pocock's
`implement-spec` skill (see `THIRD_PARTY.md` in the plugin).

Build the tickets in order, one at a time, in this worktree. The sequence:

1. **Sub-issues.** Before the first ticket, give each ticket a sub-issue of the issue, by
   [SUB-ISSUES.md](SUB-ISSUES.md): it is where the ticket's text lives, for you, the
   subagent and the user. Done when the issue lists one sub-issue per ticket
   (`gh issue view <issue> --json subIssues`, or `gh api` on its `sub_issues`).
2. **Each ticket,** in order. With two or more tickets, hand each to a **ticket subagent**
   ([below](#ticket-subagents)), so a ticket's reads, test output and fixes don't fill the
   context of the next. A plan with one ticket you build yourself, after invoking the
   `nightshift:tdd` skill with the Skill tool: there's no next ticket to keep clean.
   - Test-first where the ticket has logic to test, by the `nightshift:tdd` skill, and
     checked the way the repo is checked: the project's build, typecheck, lint and tests,
     and the running app the way the project's instructions say. Run them in the
     foreground and wait for them, however long they take: a run ends when you stop.
   - Commit each ticket on its own, in the repo's and the user's commit style.
   - Post a short `progress` comment: what the ticket delivered and how it was checked.
   - A ticket that can't be finished (a decision the plan didn't cover, a broken
     dependency) gets one `blocked` comment saying what's needed; end the run there.

   Done when every ticket has its commit and its `progress` comment.
3. **Review.** Invoke the `nightshift:review` skill with the Skill tool: one review, one fix
   pass. Done when it hands back its three lists (fixed, dismissed, open).
4. **Finish.** Check the **overlap** (in the issue skill) again, since other work may have
   started or merged since the plan, then invoke the `nightshift:finish` skill to open the
   pull request, handing it the overlap lines and the sub-issue numbers (it closes them)
   for the body. The review's findings left open go in the pull request body too, as
   what's left open. Done when you have the pull request's URL.
5. **Report.** A `done` comment with the pull request's link and what's in it, and the
   review: a line counting it, then each finding in a `<details>` block, a line each (its
   axis, what it found, and fixed, or dismissed and why, or left open):

   ```
   **Review:** <n> found: <n> fixed, <n> dismissed, <n> left open.
   ```

6. **Merge.** When the run prompt says "This repo auto-merges", invoke the
   `nightshift:merge` skill with the Skill tool: it merges the pull request, with a
   one-line `done` comment, or posts a `look` comment saying what needs the user. The
   watcher removes the worktree after this run.

## Ticket subagents

Start each with the Agent tool (`nightshift:ticket`), without a `model`, so it runs on the
model its agent sets; the agent loads the `nightshift:tdd` skill itself. Its brief sees
nothing of this conversation, so it works by pointers: say where to read, and leave what
the subagent can read itself unpasted.

- the ticket's ID (T2, say), its sub-issue (the number, where the ticket's text lives), and
  where the plan comment is: the issue number and the repo, and that it reads its
  sub-issue and the latest `plan` comment (`<!-- nightshift:plan -->`) with `gh`, plus any
  reply of the user's after it that changed it. The ticket, its blockers, its acceptance
  criteria and the spec's decisions are there, not pasted. When it's a retry after a
  `blocked` comment, add the user's answer and what the last attempt left in the
  worktree;
- this worktree's absolute path, and the commits so far (the tickets already committed in
  it: `git log --oneline` against the default branch shows them);
- how the repo is checked (as above), and the commit style;
- what it may do: build, check and commit this one ticket, in this worktree. Everything
  else is yours: it never comments on the issue, changes labels, pushes, opens a pull
  request or touches the other tickets. It files no issues: a defect it finds outside the
  ticket goes in its reply;
- what it returns: a short summary of what the ticket delivered and how it was checked;
  or, when it can't finish, a reply starting with `BLOCKED:`, then what's needed, what it
  finished and what it left uncommitted. It commits only finished work.

When it returns, check the work is there: the ticket's commit on top, and the tree clean.
Then post the `progress` comment from its summary and start the next ticket. A `BLOCKED:`
reply (or no commit) gets the one `blocked` comment, from what it said, and ends the run;
the next run hands the same ticket to a new subagent.
