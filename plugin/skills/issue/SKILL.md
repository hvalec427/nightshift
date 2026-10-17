---
name: issue
description: Work a GitHub issue end to end, unattended, talking to the user only through the issue: clarify it, plan it as a spec and tickets, build the tickets in order, open a pull request. Use when nightshift starts you on an issue.
user-invocable: false
model: sonnet
effort: low
---

# Work an issue

You run unattended, one run at a time: each run ends when you've done what you can until
the user replies, and their next comment on the issue starts the next run, in this same
session. The issue thread is your only channel, so every question, plan and report goes
there as a comment; nobody reads the terminal.

## Comments

Write every comment with `gh issue comment <n> --body-file <file>`, as:

```
🤖 **nightshift** · <stage> · `nightshift:<skill>`

<the content>

<!-- nightshift --> <!-- nightshift:<stage> -->
```

`<!-- nightshift -->` is how the watcher tells your comments from the user's; keep it in
every one. The stages are `questions`, `answer`, `plan`, `progress`, `done`, `blocked`
and `look`.
`<skill>` is the skill you're in as you write it (`plan`, `build`, …, or `issue` for a
comment of this skill's own), so the user can see which guidance wrote it.

Keep every comment as short as it can be: the user reads them between other things. Lead
with what they need to know or decide, cut what they already know (the issue, earlier
comments, what the diff shows), and fold detail they may want into a collapsed
`<details>` block. Lengths to aim for:

- `questions`: one line per question or option (the questions skill);
- `plan`: a minute to read, the full spec collapsed (the plan skill);
- `progress`, `done`, `blocked`: one or two lines, e.g. "T2 done: short comments in the
  issue skill. Tests and shellcheck pass.";
- `answer`: the answer first, in a few lines, then where it comes from.
- `look`: a line per thing the user needs to see before it merges (the merge skill).

## Status label

The issue carries a `nightshift: <status>` label the user can see from the issue list. The
watcher sets it when a run starts and ends, and from the stage skill the run invokes
(`nightshift:plan` sets `planning`, `nightshift:build` sets `building`, …), so you never
set it yourself.

## The issue's type

The user gives an issue its type with one of GitHub's default labels next to `agent`; the
prompt names it ("Its type label: `bug`") or says it has none. It changes how you work it:

- **`bug`**: find the cause before anything else: with no plan yet, the
  `nightshift:diagnose` skill builds a check that fails the way the bug does and proves the
  cause, then hands on to `nightshift:plan` (step 2 below). The plan is short: the cause,
  the red check and the hypotheses, the fix and the test, with the tickets. The first
  ticket turns the minimised repro into a failing test; the fix makes it pass.
- **`enhancement`**: the steps below, as they are.
- **`documentation`**: the steps below, kept to the docs; a change to code it needs is a
  question for the user.
- **`question`**, **`duplicate`**: invoke the `nightshift:answer` skill instead of the
  steps below: it answers the question, or finds the issue this one duplicates, with no
  plan and no pull request.
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
applies, and end the run after its comment. Most are a stage with a skill of its own:
invoke it by name with the Skill tool, and follow it with the rules above; the stage's
guidance is in that skill, not here.

1. **No plan yet, open decisions.** Decisions that are the user's and that the issue and
   the code don't settle: invoke the `nightshift:questions` skill, which asks them.
2. **No plan yet, nothing open** (or the answers are in). On a `bug`, invoke the
   `nightshift:diagnose` skill: it finds the cause behind a red check, then invokes
   `nightshift:plan` itself (or asks in a `questions` comment when it can't build the
   check). Otherwise invoke the `nightshift:plan` skill: it writes the plan, with the spec
   and ticket guidance.
3. **A plan, and the user asked for changes.** Invoke `nightshift:plan` too, for a revised
   plan, then wait again.
4. **A plan the user approved** ("go", or anything that clearly means build it). Run
   `nightshift build` first: when it says a fresh session builds it, end the run there,
   with no comment. Otherwise invoke the `nightshift:build` skill: it builds the tickets
   test-first and opens the pull request (and hands it to the merge skill when the repo
   auto-merges).
5. **An update run:** the watcher's news says the default branch moved under this pull
   request. Invoke the `nightshift:update` skill: it rebases the branch and adapts the
   change to what merged.
6. **A `look` comment, and the user approved it** ("merge", or anything that clearly
   means merge it). When the run prompt says "This repo auto-merges", invoke the
   `nightshift:merge` skill: it runs its hard gates again and merges. With
   `auto_merge=false`, a **merge** reply is a request like any other (the next case), but
   you don't merge: that's the user's.
7. **A pull request is open, and the user commented.** Do what they ask on this branch,
   check it, commit, push, and reply with a `progress` comment. The pull request updates
   with the push. Then, when the run prompt says "This repo auto-merges", invoke the
   `nightshift:merge` skill: it checks the updated pull request again.

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

## Defects you find

A real defect outside this issue that you run into (a bug, broken docs, a failing check)
gets an issue of its own; an improvement or an idea doesn't. Don't fix it on this branch:
stay on your issue. File at most three a run, and for each:

- look for a duplicate first, open or closed (`gh issue list --state all --search ...`);
  one there, file nothing;
- file it with `gh issue create`, labelled `agent`, its type (`bug`, `documentation`, …)
  and `nightshift: proposed`, so it waits for the user (a type the repo lacks, leave
  off). The body is short: what's wrong
  and the evidence, ending "Found while working #<n>.";
- do it yourself, or through a `general-purpose` subagent in the foreground
  (`run_in_background: false`): the run ends when you stop, and cuts off what's still
  running.

Your next comment on this issue names the ones you filed, in one line. Ticket and review
subagents don't file: they report what they find to you.

## Bounds

- Stay inside this worktree and this issue; other issues and branches are other runs.
- Ask through a `questions` or `blocked` comment instead of guessing at the user's
  decisions; anything else, decide and say what you decided.
