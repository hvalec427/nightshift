---
name: build
description: Build an issue's approved plan, ticket by ticket and test-first, then open its pull request with the finish skill. Started by the issue skill when the user approved the plan.
user-invocable: false
model: sonnet
effort: high
---

# Build an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The ticket brief below is adapted from Matt Pocock's
`implement-spec` skill (see `THIRD_PARTY.md` in the plugin).

Build the tickets in order, one at a time, in this worktree:

- Before the first ticket, give each ticket a sub-issue of the issue (**Sub-issues**,
  below): it is where the ticket's text lives, for you, the subagent and the user.
- Each ticket test-first where it has logic to test (by the `nightshift:tdd` skill), checked
  the way the repo is checked: with the project's build, typecheck, lint and tests, and in
  the running app the way the project's instructions say to check it. Run them in the
  foreground and wait for them, however long they take: a run ends when you stop.
- Commit each ticket on its own, in the repo's and the user's commit style, and post a
  short `progress` comment: what the ticket delivered and how it was checked.
- With two or more tickets, hand each to a **ticket subagent** (below), so a ticket's
  reads, test output and fixes don't fill the context of the next. A plan with one ticket
  you build yourself, after invoking the `nightshift:tdd` skill with the Skill tool: there's
  no next ticket to keep clean.
- A ticket that can't be finished (a decision the plan didn't cover, a broken
  dependency): a `blocked` comment saying what's needed, and end the run.
- After the last ticket, review the change with the `nightshift:review` skill (invoke it
  with the Skill tool): one review, one fix pass.
- Then check the **overlap** (in the issue skill) again, since other work may have
  started or merged since the plan, and invoke the `nightshift:finish` skill to open the
  pull request, with the overlap lines and the sub-issue numbers (it closes them) in its
  body. The review's findings left open go in the pull request body too, as what's left
  open. Then a `done` comment with its link and
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

## Sub-issues

Make one sub-issue per ticket, with `gh issue create --parent <issue> --title … --body …`
where gh supports `--parent` (`gh issue create --help` lists it), so the user can follow
the build in GitHub's UI.

- **Title** it `T1: <ticket title>`, so it can be found again. **Body:** the ticket's text,
  its blockers and acceptance criteria as the plan has them, and `Part of #<issue>`.
- **No `agent` label,** and no other: the watcher works issues labelled `agent`, and a
  sub-issue is not one to work.
- **Without `--parent`,** create the issue, then attach it through the REST API:
  `gh api repos/{owner}/{repo}/issues/<issue>/sub_issues -f sub_issue_id=<id>`. The id is
  the new issue's `id` field (`gh api repos/{owner}/{repo}/issues/<n> --jq .id`), not its
  number.
- **Reuse before creating.** A resumed or fresh build reuses the sub-issues already under
  the issue, found by title: `gh issue view <issue> --json subIssues`, or `gh api
  repos/{owner}/{repo}/issues/<issue>/sub_issues`. It creates only the tickets with none,
  so no ticket gets two.
- A change the user's reply made to a ticket goes in its sub-issue's body too, so the
  sub-issue and the plan agree.

Done when `gh issue view <issue> --json subIssues` lists one sub-issue per ticket. Keep
each one's number for its brief and for the pull request body.

## Ticket subagents

Start each with the Agent tool (`nightshift:ticket`), without a `model`, so it runs on the
model its agent sets; the agent loads the `nightshift:tdd` skill itself. Its brief sees
nothing of this conversation, so it works by pointers: it says where to read, and doesn't
paste what the subagent can read itself.

- the ticket's ID (T2, say), its sub-issue (the number, where the ticket's text lives), and
  where the plan comment is: the issue number and the repo, and that it reads its
  sub-issue and the latest `plan` comment (`<!-- nightshift:plan -->`) with `gh`, plus any
  reply of the user's after it that changed it. The ticket, its blockers, its acceptance
  criteria and the spec's decisions are there, not pasted. When it's a retry after a
  `blocked` comment, the user's answer and what the last attempt left in the
  worktree;
- this worktree's absolute path, and the commits so far (the tickets already committed in
  it: `git log --oneline` against the default branch shows them);
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
