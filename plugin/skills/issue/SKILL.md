---
name: issue
description: Work a GitHub issue end to end, unattended, through the issue's comments alone. Use when nightshift starts you on an issue.
user-invocable: false
model: sonnet
effort: low
---

# Work an issue

You run unattended, one run at a time. A run ends when you've done what you can until the
user replies; their next comment on the issue starts the next run, in this same session.
The issue thread is your only channel: every question, plan and report goes there as a
comment, because nobody reads the terminal.

## Comments

Write every comment with `gh issue comment <n> --body-file <file>`, as:

```
🤖 **nightshift** · <stage> · `nightshift:<skill>`

<the content>

<!-- nightshift --> <!-- nightshift:<stage> -->
```

`<!-- nightshift -->` is how the watcher tells your comments from the user's: every one
carries it. The stages are `questions`, `answer`, `plan`, `progress`, `done`,
`blocked` and `look`. `<skill>` is the skill you're in as you write it (`plan`, `build`,
…, or `issue` for a comment of this skill's own), so the user can see which guidance
wrote it.

Write for a reader between other things: **lead** with what they need to know or decide,
fold detail into a collapsed `<details>` block, and leave out what they already have (the
issue, earlier comments, what the diff shows). Lengths to aim for:

- `questions`: one line per question or option (the questions skill);
- `plan`: a minute to read, the full spec collapsed (the plan skill);
- `progress`, `blocked`: one or two lines, e.g. "Waiting for #4's PR to merge first."
  (the merge skill's `progress` opens with the report it was handed);
- `done`: the build's report, led by the pull request's link and what's in it, the review
  collapsed (the build skill; the merge skill's `done` and `look` open with it);
- `answer`: the answer first, in a few lines, then where it comes from;
- `look`: a line per thing the user needs to see before it merges (the merge skill).

Done when the comment has the header, the marker and the stage's length.

## Status label

The issue carries a `nightshift: <status>` label the user sees in the issue list. The
watcher sets it, when a run starts and ends and from the stage skill the run invokes
(`nightshift:plan` sets `planning`, `nightshift:build` sets `building`, …). Leave it to the
watcher.

## The issue's type

The user gives an issue its type with one of GitHub's default labels next to `agent`; the
prompt names it ("Its type label: `bug`") or says it has none. The type sets how you work:

- **`bug`**: cause first. With no plan yet (and not small, case 2 below), the
  `nightshift:diagnose` skill builds a check that fails the way the bug does and proves
  the cause, then hands on to `nightshift:plan` (case 3). The plan is short: the cause, the
  red check and the hypotheses, the fix and the test, with the tickets. The first ticket
  turns the minimised repro into a failing test; the fix makes it pass.
- **`enhancement`**: the steps below, as they are.
- **`documentation`**: the steps below, kept to the docs; a change to code it needs is a
  question for the user.
- **`question`**, **`duplicate`**: invoke the `nightshift:answer` skill instead of the
  steps below: it answers the question, or finds the issue this one duplicates, with no
  plan and no pull request.
- **`invalid`, `wontfix`**: the watcher doesn't run you while either is on the issue; the
  user alone adds them.

With **no type label**, pick the type from the issue and the code, add its label
(`gh issue edit <n> --add-label <type>`), and say in that run's comment which you took
and why. When the type turns out wrong (the issue, or the user's reply, says it's another
kind), swap it (`--remove-label <old> --add-label <new>`) and say why. Use the labels the
repo has (`gh label list`); when it lacks one, work the issue as that type anyway and say
the label is missing. A label the prompt says the user changed since your last run stands
as theirs. Labels other than the type and status ones are the user's.

## Where the issue stands

Read the thread first (`gh issue view <n> --comments`), take the first case below that
applies, and end the run after its comment. Most cases are a stage with a skill of its own:
invoke it by name with the Skill tool and follow it, with the rules above. The stage's
guidance lives in that skill, not here. "No plan yet" means no plan and no pull request: a
small issue (case 2) has a pull request and no plan, and its later runs take cases 6 to 8.

1. **No plan yet, open decisions.** Decisions that are the user's and that the issue and
   the code don't settle: invoke the `nightshift:questions` skill, which asks them.
2. **No plan yet, small.** A **small** issue is all of: a few lines (about 20) in one or
   two files; nothing for the user to decide (the issue already says what to do); no new
   command or option, no breaking change, and nothing security-relevant or touching CI,
   releases or installing; and, on a `bug`, a cause already plain
   from the issue and the code. When in doubt, it isn't small. Decide it on a run with
   no plan yet, and invoke the `nightshift:build` skill in this session (no
   `nightshift build` first: there's no planning conversation to leave behind). It builds
   the issue as its one ticket, with no plan and no wait for a **go**.
3. **No plan yet, nothing open** (or the answers are in). On a `bug`, invoke the
   `nightshift:diagnose` skill: it finds the cause behind a red check, then invokes
   `nightshift:plan` itself (or asks in a `questions` comment when it can't build the
   check). Otherwise invoke the `nightshift:plan` skill: it writes the plan, with the spec
   and ticket guidance.
4. **A plan, and the user asked for changes.** Invoke `nightshift:plan` too, for a revised
   plan, then wait again.
5. **A plan the user approved** ("go", or anything that clearly means build it), **or a
   plan that carried on** (its last line says it has no open choices, so no one said go).
   Run `nightshift build` first (`nightshift build --carry-on` for the carry-on): when it
   says a fresh session builds it, end the run there, with no comment. Otherwise invoke
   the `nightshift:build` skill: it builds the tickets test-first and opens the pull
   request (and hands it to the merge skill when the repo auto-merges).
6. **An update run:** the watcher's news says the default branch moved under this pull
   request. Invoke the `nightshift:update` skill: it rebases the branch and adapts the
   change to what merged.
7. **A `look` comment, and the user approved it** ("merge", or anything that clearly
   means merge it). When the run prompt says "This repo auto-merges", invoke the
   `nightshift:merge` skill: it runs its hard gates again and merges. With
   `auto_merge=false`, a **merge** reply is a request like any other (the next case), but
   you don't merge: that's the user's.
8. **A pull request is open, and the user commented.** Do what they ask on this branch,
   check it, commit and push. The pull request updates with the push. Then say what you did
   in a `progress` comment, only when the repo doesn't auto-merge. When the run prompt says
   "This repo auto-merges", post nothing and hand what it did to the `nightshift:merge`
   skill, invoked with the Skill tool: it puts that at the top of its one closing comment
   and checks the updated pull request again.
   On a small issue (case 2), a reply asking for a plan or "the full process" is a plan
   request instead: invoke `nightshift:plan`, and the build after its **go** (or its
   carry-on) works on this same branch and its pull request.

Done when the run's comment is posted, or the run ended as case 5 says.

## Overlap with other nightshift work

Other issues are worked on `nightshift/issue-<n>` branches of this same clone: the ones
still in progress are local branches, the finished ones open pull requests
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

Done when every other branch and pull request has been compared; no overlap, no lines.

## Defects you find

A real defect outside this issue that you run into (a bug, broken docs, a failing check)
gets an issue of its own; an improvement or an idea stays out. Leave the fix to that issue
and stay on yours. File at most three a run, and for each:

- look for a duplicate first, open or closed (`gh issue list --state all --search ...`);
  one there, file nothing;
- file it with `gh issue create`, labelled `agent`, its type (`bug`, `documentation`, …)
  and `nightshift: proposed`, so it waits for the user (leave off a type the repo lacks).
  The body is short: what's wrong and the evidence, ending "Found while working #<n>.";
- file it yourself, or through a `general-purpose` subagent in the foreground
  (`run_in_background: false`): a run ends when you stop, and cuts off what's still
  running.

Your next comment on this issue names the ones you filed, in one line. Ticket and review
subagents report what they find to you; you file.

## Bounds

- Work inside this worktree and this issue; other issues and branches are other runs.
- Ask through a `questions` or `blocked` comment for the user's decisions; decide anything
  else and say what you decided.
