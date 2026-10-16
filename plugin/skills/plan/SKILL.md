---
name: plan
description: Write or revise an issue's plan, its spec and tickets, as one plan comment. Started by the issue skill when an issue has no plan and nothing is left to ask, or the user asked for changes to its plan.
user-invocable: false
---

# Plan an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The spec and ticket guidance below is adapted from Matt
Pocock's `to-spec` and `to-tickets` skills (see `THIRD_PARTY.md` in the plugin).

## The plan comment

`nightshift label planning`, then write the plan as one `plan` comment, short enough to
read in a minute:

- **On top:** what gets built, in two or three lines; the decisions the user should see;
  the tickets, one line each, in build order (`**T1: <title>.** <what it delivers>`); and
  the **overlap** (in the issue skill) with other nightshift work, if any.
- **Collapsed,** in one `<details><summary>Full spec</summary>` block: the **spec**
  (below), and each ticket's blockers and acceptance criteria (the **tickets**, below).
  All tickets are in this comment (no new issues).
- It ends with "Reply **go** to build it, or tell me what to change."

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

When the user asked for changes to a plan: the same, as a revised `plan` comment, then
wait again.

## The spec

It goes in the `plan` comment's collapsed block, synthesised from the issue, the answers
and the code: no further interview. Size it to the issue: a line or two under each
heading, a single line for a small change, and drop a heading that has nothing to say.

Before writing it, explore the code to know its current state, and use the project's own
vocabulary (a `GLOSSARY.md` if it has one) and its ADRs in the area you touch. Sketch the
**seams** you'll test at: prefer existing seams to new ones, the highest seam possible, and
as few as you can (ideally one). They go under Testing decisions, where the user approves
them with the plan.

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
- The seams under test, each with what it catches and misses
- Prior art: similar tests in the codebase
- How the change is checked beyond tests (the project's build, typecheck, lint; a
  simulator in a React Native app)

**Out of scope:** what this doesn't do.
```

No file paths or code snippets: they go stale fast. The exception is a snippet that encodes
a decision more precisely than prose can (a state machine, a schema, a type shape), trimmed
to the decision.

## The tickets

They're in the `plan` comment, numbered `T1`, `T2`, … in build order: one line each on
top, and in full (below) in its collapsed block. The user approves them with the plan.

Look for prefactoring first: make the change easy, then make the easy change. Then break
the work into **tracer bullets**:

- Each ticket cuts a narrow but complete path through every layer (schema, API, UI,
  tests): vertical, not one layer at a time.
- A finished ticket is verifiable on its own, and is its own commit.
- Each fits in one sitting; prefactoring comes first.
- Each names its **blockers**: the tickets that must be done before it can start, and only
  those.

A **wide refactor** (one mechanical change whose blast radius breaks call sites across the
codebase: a rename, a retyped shared symbol) is the exception: sequence it as
expand–contract. Expand (add the new form beside the old), migrate the call sites in
batches each its own ticket, then contract (delete the old form) once no caller remains.

```
**T1: <title>.** Blocked by: none (or T…).
What it delivers: the end-to-end behaviour it makes work, from the user's perspective.
- [ ] Acceptance criterion
- [ ] …
```

No file paths or code snippets, as in the spec.
