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

1. **Ticket files.** Before the first ticket, write each ticket of the latest `plan`
   comment to `.nightshift/tickets/T<n>.md` in this worktree: its text, blockers and
   acceptance criteria, plus the spec's decisions it needs, and any reply of the user's
   after the plan that changed it. A resumed build rewrites them, since the plan may have
   been revised. The plan comment stays the source; the files are a working copy, never
   committed (the CLI keeps `.nightshift/tickets/` out of git) and gone with the
   worktree. Done when every ticket of the latest plan has its file.
2. **Each ticket,** in order. With two or more tickets, hand each to a **ticket subagent**
   ([below](#ticket-subagents)), so a ticket's reads, test output and fixes don't fill the
   context of the next. A plan with one ticket you build yourself, after invoking the
   `nightshift:tdd` skill with the Skill tool: there's no next ticket to keep clean.
   - Test-first where the ticket has logic to test, by the `nightshift:tdd` skill, and
     checked the way the repo is checked: the project's build, typecheck and lint, the
     tests for what the ticket touched (its own and the existing ones that cover the code
     it changed), and the running app the way the project's instructions say. Not the
     whole test suite: that runs once, after the review. Run them in the foreground and
     wait for them, however long they take: a run ends when you stop.
   - Commit each ticket on its own, in the repo's and the user's commit style.
   - Post no comment per ticket: the issue stays quiet until the closing comment (step 5).
     Keep what the ticket delivered and how it was checked for that report.
   - A ticket that can't be finished (a decision the plan didn't cover, a broken
     dependency) gets one `blocked` comment saying what's needed; end the run there.

   Done when every ticket has its commit.
3. **Review.** Invoke the `nightshift:review` skill with the Skill tool: one review, one fix
   pass. Done when it hands back its three lists (fixed, dismissed, open).
   Then the **full checks**, once: the whole test suite with the build, typecheck and lint,
   in the foreground. A failure is fixed and only what failed is run again, then the whole
   suite once more. Done when they pass on the last commit.
4. **Finish.** Check the **overlap** (in the issue skill) again, since other work may have
   started or merged since the plan, then invoke the `nightshift:finish` skill to open the
   pull request, handing it the overlap lines for the body. The review's findings left
   open go in the pull request body too, as what's left open. Done when you have the pull
   request's URL.
5. **Report.** The pull request's link and what's in it, and the review: a line counting
   it, then each finding in a `<details>` block, a line each (its axis, what it found, and
   fixed, or dismissed and why, or left open):

   ```
   **Review:** <n> found: <n> fixed, <n> dismissed, <n> left open.
   ```

   Post it as the `done` comment, the run's one closing comment, only when the repo doesn't
   auto-merge. With auto-merge (the run prompt says "This repo auto-merges") you post
   nothing here: step 6 hands the report on.
6. **Merge.** When the run prompt says "This repo auto-merges", hand the
   report from step 5, as it stands, to the `nightshift:merge` skill, invoked with the
   Skill tool: it puts it at the top of its one closing comment, then merges the
   pull request (`done`), or posts a `look` comment saying what needs the user. The watcher
   removes the worktree after this run.

## Ticket subagents

Start each with the Agent tool (`nightshift:ticket`), without a `model`, so it runs on the
model its agent sets; the agent loads the `nightshift:tdd` skill itself. Its brief sees
nothing of this conversation, so it works by pointers: say where to read, and leave what
the subagent can read itself unpasted.

- the ticket's ID (T2, say) and where its text lives: the file
  `.nightshift/tickets/T<n>.md` in the worktree. The ticket, its blockers, its acceptance
  criteria and the spec's decisions it needs are there, not pasted. The issue number and
  the repo are for a question the file leaves open: the latest `plan` comment has the
  rest. When it's a retry after a `blocked` comment, add the user's answer and what the
  last attempt left in the worktree;
- this worktree's absolute path, and the commits so far (the tickets already committed in
  it: `git log --oneline` against the default branch shows them);
- for the second ticket on, the replies of the earlier tickets: what each delivered and what
  it flagged, a short list from the summaries the subagents returned in this build, not
  their logs. A ticket is then not caught by what an earlier one already ran into;
- how the repo is checked (as above), and the commit style;
- what it may do: build, check and commit this one ticket, in this worktree. Everything
  else is yours: it never comments on the issue, changes labels, pushes, opens a pull
  request or touches the other tickets. It files no issues: a defect it finds outside the
  ticket goes in its reply;
- what it returns: a short summary of what the ticket delivered and how it was checked;
  or, when it can't finish, a reply starting with `BLOCKED:`, then what's needed, what it
  finished and what it left uncommitted. It commits only finished work.

When it returns, check the work is there: the ticket's commit on top, and the tree clean.
Then start the next ticket; its summary goes in the report, not in a comment. A `BLOCKED:`
reply (or no commit) gets the one `blocked` comment, from what it said, and ends the run;
the next run hands the same ticket to a new subagent.
