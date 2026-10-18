---
name: build
description: Build an issue's approved plan ticket by ticket, test-first, then open its pull request. Started by the issue skill when the user approved the plan, or for a small issue or a sub-issue, and by the plan skill when the plan has no open choices.
user-invocable: false
model: sonnet
effort: high
---

# Build an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The ticket brief is adapted from Matt Pocock's
`implement-spec` skill (see `THIRD_PARTY.md` in the plugin).

Build the tickets in order, one at a time, in this worktree.

**A carry-on build** is one whose prompt says the plan has no open choices, so no one said
**go**. A user comment since the plan comes before anything else, and it is read before the
ticket files are written:

- one that changes the plan: invoke the `nightshift:plan` skill for a revised plan, which
  waits for **go** or carries on by its own rule; build nothing now;
- one that stops the build: one `blocked` comment saying you stopped as asked; end the run;
- anything else (a remark, a question the plan answers): build on.

**A small issue** (the issue skill's case 3, no `plan` comment): the issue and the user's
replies are the plan, and it is one ticket. Write no ticket files (skip step 1) and build
it yourself (step 2); the review, finish, report and merge are as below. The report opens
with: "Treated as small: built straight from the issue, with no plan. Reply **full
process** to get a plan instead."

**A large plan** (the plan lists sub-issues `S1`, `S2`, …) on **go** builds nothing itself:
it makes the sub-issues, each a pull request of its own, and ends. Write no ticket files,
and run no review, finish or merge: the parent gets no branch work and no pull request.

- **Create the sub-issues** in dependency order (a blocker before what it blocks), each
  with `nightshift sub-issue --title "S<k>: <title>" --body-file <file> [--after <n>]…`,
  one `--after` per blocker, with the number that blocker's command printed. Write the
  body file under `$TMPDIR` (`mktemp "${TMPDIR:-/tmp}/x.XXXXXX"`) and remove it after.
  The body stands alone, since the sub-issue builds from it: the problem and solution
  in a line each, the spec's decisions and testing decisions that sub-issue needs, then
  its tickets in full (blockers and acceptance criteria), and any reply of the user's
  after the plan that changed them. Sub-issues with no unmerged blocker start right away,
  in parallel; the watcher holds the rest as `waiting`.
- **One `progress` comment** on the parent, the run's only one: a line per sub-issue
  (`- #161 S1: <title>`, with `after #160` when blocked), and that each builds as its
  blockers merge and the parent closes after the last merge. Then end the run.

A resumed build lists what exists first (`gh api repos/<repo>/issues/<n>/sub_issues`) and
creates only the `S<k>` titles missing among the open ones, so a retry makes no duplicates.
When `nightshift sub-issue` fails after creating the issue, it closes that issue, saying
why, and drops it from the parent: run it again for that sub-issue, once. Failing again,
or failing to close it (it says so), post one `blocked` comment saying what it said, and
end the run.

**A sub-issue** (the issue skill's case 1: the parent marker in its body, no pull request
yet) is built from its body, which is the approved plan: the user approved it on the
parent. Ask nothing and wait for no **go**. Step 1 writes the body's tickets to their files
(there is no `plan` comment), and the rest is as below: the tickets, the review (by both
reviewers), the pull request, the report and the merge. The report opens with "Sub-issue of
#<parent>."

The sequence:

1. **Ticket files.** Before the first ticket, write each ticket of the latest `plan`
   comment (a sub-issue's: of its body) to `.nightshift/tickets/T<n>.md` in this worktree:
   its text, blockers and acceptance criteria, plus the spec's decisions it needs, and any
   reply of the user's after the plan that changed it. A resumed build rewrites them, since the plan may have
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
     whole test suite: that runs once, after the review, where the run prompt's whole-suite
     line says (step 3). Run them in the foreground and wait for them, however long they
     take: a run ends when you stop.
   - Commit each ticket on its own, in the repo's and the user's commit style.
   - Post no comment per ticket: the issue stays quiet until the closing comment (step 5).
     Keep what the ticket delivered and how it was checked for that report.
   - A ticket that can't be finished (a decision the plan didn't cover, a broken
     dependency) gets one `blocked` comment saying what's needed; end the run there.

   Done when every ticket has its commit.
3. **Review.** Invoke the `nightshift:review` skill with the Skill tool: one review, one fix
   pass. Done when it hands back its three lists (fixed, dismissed, open).
   Then the **full checks**, once, only under the local line, or the default line in a repo
   with no CI, and never under the nothing line: the whole test suite with the build,
   typecheck and lint, in the foreground. A failure is fixed and only what failed is run
   again, then the whole suite once more. Done when they pass on the last commit, or the
   line says they don't run. The run prompt's whole-suite line is one of:
   - the local line, "This repo runs its whole test suite locally": the full checks run;
   - the default line, "This repo leaves its whole test suite to CI": they run in a repo
     with no CI; in one with CI, CI runs the whole suite on the pull request, and the
     tickets' and the review's checks are all you run;
   - the nothing line, "nightshift runs no whole test suite": they don't run.

   Run the whole suite with the command the line names ("Run it with ..."), when it names
   one; otherwise work it out from the repo's instructions.

   A repo **has CI** when a workflow in `.github/workflows/` triggers on `pull_request`, or
   the repo's latest merged pull request lists checks (`gh pr checks <number>`), so external
   CI counts too. It matters only under the default line.
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
  the repo are for a question the file leaves open: the latest `plan` comment (a
  sub-issue's: its body) has the rest. When it's a retry after a `blocked` comment, add
  the user's answer and what the last attempt left in the worktree;
- this worktree's absolute path, and the commits so far (the tickets already committed in
  it: `git log --oneline` against the base branch shows them (the one the run prompt names with
  "This repo's pull requests merge into", else the default branch));
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
