---
name: plan
description: Write or revise an issue's plan, a spec and tickets in one plan comment. Started by the issue skill for an issue with no plan and nothing left to ask, or when the user asked to change its plan.
user-invocable: false
model: opus
effort: high
---

# Plan an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The spec and ticket guidance is adapted from Matt
Pocock's `to-spec` and `to-tickets` skills (see `THIRD_PARTY.md` in the plugin).

Synthesise the issue, the answers and the code into one `plan` comment. The build runs in a
fresh session that sees the issue and this comment, not this conversation, so the plan
holds everything the build needs: the answers, the decisions, the constraints you found.
Synthesise from what you have; the interview was the questions skill's.

1. **Explore.** Read the code to know its current state. Use the project's own vocabulary
   (`.nightshift/CONTEXT.md`, if it has one) and respect its ADRs in the area you touch.
   On a `bug`, read [BUG.md](BUG.md) now: it shapes the comment, the spec and the tickets.
   Done when you can say where the change lands.
2. **Choose the seams.** A **seam** is the public boundary a test observes behaviour at.
   Prefer an existing seam to a new one and the highest seam you can; the fewer, the
   better, and one is ideal. They go under Testing decisions, where the user approves them
   with the plan. Done when each behaviour the change adds has a seam to be tested at.
3. **Write the spec** ([below](#the-spec)). Done when each heading says something or is
   dropped.
4. **Cut the tickets** ([below](#the-tickets)). Done when every ticket is verifiable on its
   own and its blockers are named.
5. **Check for open choices** ([below](#open-choices)). Done when you can name each open
   choice, or say there is none.
6. **Write the comment** ([below](#the-plan-comment)), then end the run as it says: wait
   for the user, or carry on. Done when the comment is posted.

The plan fits the issue's size (the issue skill's Size section). A **small** one is a single
ticket, **medium** is as described here, and a **large** one adds the sub-issues
([below](#a-large-plan)). A reply that switches the size gets a revised plan for the new one.

A revised plan, after the user asked for changes, is the same: a new `plan` comment with
their changes in it, then wait again, or carry on when it has no open choice. A bug's plan,
from the diagnose skill, is the same too.

## Open choices

An **open choice** is a decision in the plan that the issue and the user's answers don't
settle, and that the user might make differently. Answering a question with an assumption
counts. A choice with one sensible answer doesn't: where the code goes, naming that follows
the code's conventions, test seams that follow prior art. A revised plan that only applies
the changes the user asked for makes no choice of its own.

With any open choice, the plan stops for **go** and names those choices under "Decisions to
look at". With none, it carries on: the comment says so, and the run builds without waiting.
When unsure, it's open. A **large** plan has no carry-on: it always stops for **go**. On a
project board (the run prompt says "This repo works from a project board") no plan carries
on: it always stops, and the user approves it with **go** or by moving the card to In
progress.

## The spec

Size it to the issue: a line or two under each heading, a single line for a small change,
and no heading that has nothing to say.

```
## Spec

**Problem.** The problem the user faces, from the user's perspective.

**Solution.** The solution, from the user's perspective.

**User stories**
1. As a <actor>, I want <feature>, so that <benefit>
…   (numbered; extensive for a feature, a handful for a small change)

**Implementation decisions**
- The modules built or changed, and the interfaces of those that change
- Architectural decisions, schema changes, API contracts, specific interactions
- What you settled yourself, and why

**Testing decisions**
- What a good test is here: external behaviour, never implementation details
- The seams under test, each with what it catches and misses
- Prior art: similar tests in the codebase
- How the change is checked beyond tests (the project's build, typecheck, lint; the
  running app, the way the project's instructions say)

**Out of scope:** what this doesn't do.
```

Describe modules and interfaces in prose: paths and snippets go stale fast. The exception
is a snippet that encodes a decision more precisely than prose can (a state machine, a
schema, a type shape), trimmed to the decision.

## The tickets

Numbered `T1`, `T2`, … in build order. The user approves them with the plan, and on **go**
they become the build's ticket files, named by `T<n>`, so keep the titles short and
unique.

**Prefactor** first: make the change easy, then make the easy change. Then cut
**tracer bullets**:

- Each ticket cuts a narrow but complete path through every layer (schema, API, UI,
  tests): vertical, one slice of the feature across all of them.
- A finished ticket is demoable or verifiable on its own, and is its own commit.
- Each fits one fresh context window.
- Each names its **blockers**: the tickets that must be done before it can start, and only
  those.

A **wide refactor** (one mechanical change that breaks call sites across the codebase: a
rename, a retyped shared symbol) cannot be a tracer bullet: sequence it as in
[WIDE-REFACTOR.md](WIDE-REFACTOR.md).

```
**T1: <title>.** Blocked by: none (or T…).
What it delivers: the end-to-end behaviour it makes work, from the user's perspective.
- [ ] Acceptance criterion
- [ ] …
```

Tickets follow the spec's rule on paths and snippets.

## A large plan

The spec is as above. The tickets, cut as above, are then grouped into **sub-issues**
numbered `S1`, `S2`, …: each a few tickets that merge as one pull request, so a review
stays small and a wrong assumption costs one sub-issue. Each sub-issue names the
sub-issues it's **blocked by**, and only those: the ones whose merged code it needs.
Sub-issues with no blocker build at once, in parallel, so group by what must merge first,
not by area alone. List them in dependency order (a blocker before what it blocks): the
build creates them in that order, and a blocker's number is known only once it exists.

```
**S1: <title>.** Blocked by: none (or S…). Tickets: T1, T2.
**S2: <title>.** Blocked by: S1. Tickets: T3.
```

A ticket's blockers stay within its sub-issue or point at an earlier sub-issue's. A large
plan never carries on: its last line is always the **go** one. Done when every ticket is
in one sub-issue and each sub-issue's blockers are earlier in the list.

## The plan comment

Short enough to read in a minute. The tickets live in this comment; on **go**, the build
writes them to ticket files, so you write no issues (a large plan's sub-issues are the
build's to create).

- **On top:** what gets built, in two or three lines; the decisions the user should see;
  the tickets, one line each, in build order (`**T1: <title>.** <what it delivers>`), a
  large plan's grouped under their sub-issues (`**S1: <title>.** Blocked by: none.`); and
  the **overlap** (in the issue skill) with other nightshift work, if any.
- **Collapsed,** in one `<details><summary>Full spec</summary>` block: the spec, then each
  ticket's blockers and acceptance criteria.
- **Last line,** with an open choice, and always for a large plan: "Reply **go** to build
  it, or tell me what to change." With none: "No open choices, so I'm building it now:
  comment to stop or change it." On a board: "Reply **go** or move the card to In progress
  to build it, or tell me what to change."

```
**What changes:** <two or three lines>.

**Tickets**
- **T1: <title>.** <what it delivers>
- **T2: <title>.** <what it delivers>

<details><summary>Full spec</summary>

<the spec, then each ticket's blockers and criteria>
</details>

Reply **go** to build it, or tell me what to change.
```

With no open choice the last line is the carry-on one instead (on a board, never). Post
the comment, then run `nightshift build --carry-on`. When it says a fresh session builds
it, end the run there, with no comment; otherwise invoke the `nightshift:build` skill with
the Skill tool and build here. Done when the comment is posted and the run ended or went on
to build, as it said.
