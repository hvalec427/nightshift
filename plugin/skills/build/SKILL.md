---
name: build
description: Build an issue's approved plan, ticket by ticket and test-first, then open its pull request with the finish skill. Started by the issue skill when the user approved the plan.
user-invocable: false
---

# Build an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The test-first guidance below is adapted from Matt
Pocock's `tdd` skill (see `THIRD_PARTY.md` in the plugin).

Build the tickets in order, one at a time, in this worktree:

- Each ticket test-first where it has logic to test (**test first**, below), checked the
  way the repo is checked: with the project's build, typecheck, lint and tests, and in
  the running app the way the project's instructions say to check it. Run them in the
  foreground and wait for them, however long they take: a run ends when you stop.
- Commit each ticket on its own, in the repo's and the user's commit style, and post a
  short `progress` comment: what the ticket delivered and how it was checked.
- With two or more tickets, hand each to a **ticket subagent** (below), so a ticket's
  reads, test output and fixes don't fill the context of the next. A plan with one ticket
  you build yourself: there's no next ticket to keep clean.
- A ticket that can't be finished (a decision the plan didn't cover, a broken
  dependency): a `blocked` comment saying what's needed, and end the run.
- After the last ticket, review the change with the `nightshift:review` skill (invoke it
  with the Skill tool): one review, one fix pass.
- Then check the **overlap** (in the issue skill) again, since other work may have
  started or merged since the plan, and invoke the `nightshift:finish` skill to open the
  pull request, with the overlap lines in its body. The review's findings left open go in
  the pull request body too, as what's left open. Then a `done` comment with its link and
  what's in it, and the review: a line counting it, then each finding in a `<details>`
  block, a line each (its axis, what it found, and fixed, or dismissed and why, or left
  open):

  ```
  **Review:** <n> found: <n> fixed, <n> dismissed, <n> left open.
  ```

- Then, when the run prompt says "This repo auto-merges", invoke the `nightshift:merge`
  skill with the Skill tool: it merges the pull request, with a one-line `done` comment,
  or posts a `look` comment saying what needs the user. The watcher removes the worktree
  after this run.

## Ticket subagents

Start each with the Agent tool (`general-purpose`), without a `model`, so it runs on the
run's own model. Its brief stands on its own, since it sees nothing of this conversation:

- the ticket from the plan: its text, what blocks it and its acceptance criteria, and the
  spec's decisions it needs; when it's a retry after a `blocked` comment, the user's
  answer and what the last attempt left in the worktree;
- this worktree's absolute path, and the tickets already committed in it;
- the test-first guidance: the sections below, from **test first** on, copied in, not
  pointed to;
- how the repo is checked (as above), and the commit style;
- what it may do: build, check and commit this one ticket, in this worktree. It never
  comments on the issue, changes labels, pushes, opens a pull request or touches the other
  tickets. It files no issues: a defect it finds outside the ticket goes in its reply.
- what it returns: a short summary of what the ticket delivered and how it was checked;
  or, when it can't finish, a reply starting with `BLOCKED:`, then what's needed, what it
  finished and what it left uncommitted. It commits nothing half done.

When it returns, check the work is there: the ticket's commit on top, and the tree clean.
Then post the `progress` comment from its summary and start the next ticket. A `BLOCKED:`
reply (or no commit) gets the one `blocked` comment, from what it said, and ends the run;
the next run hands the same ticket to a new subagent.

## Test first

Build each ticket that has logic to test as a red → green loop, at the seams the plan's
testing decisions name. The plan's approval is the user's approval of those seams; a test
that needs a seam the plan didn't name is a decision for a `blocked` comment, unless it's
clearly inside one that was.

## A good test

It verifies behaviour through a public interface, not implementation details: the code
can change entirely and the test still holds. It reads like a specification ("user can
check out with a valid cart"), uses the public API only, and has one logical assertion.

Anti-patterns:

- **Implementation-coupled:** mocks internal collaborators, tests private functions, or
  verifies through a side channel (querying the database instead of using the interface).
  The tell: it breaks on a refactor that didn't change behaviour.
- **Tautological:** the expected value is recomputed the way the code computes it, so it
  passes by construction. Expected values come from an independent source: a known
  literal, a worked example, the spec.
- **Horizontal:** all the tests first, then all the code. Tests written ahead verify
  imagined behaviour.

## Mocks

Only at system boundaries: external APIs, time and randomness, sometimes the database or
the file system. Never your own modules. At a boundary, prefer an interface that's easy to
fake: dependencies passed in, one function per external operation rather than one generic
fetcher.

## The loop

- **Red before green.** Write one failing test, see it fail, then only enough code to pass
  it. No speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle; let
  each cycle inform the next.
- **Refactor after,** with the tests green, not inside the loop.
- A repo without tests at that seam: check the ticket the way the repo is checked (build,
  typecheck, lint, a scratch run, the running app), and say so in the `progress` comment.
