---
name: tdd
description: Test-first guidance for building a ticket as a red → green loop at the plan's testing seams. Loaded by the ticket subagent, and by the build skill for a one-ticket plan, before it builds.
user-invocable: false
model: sonnet
effort: high
---

# Test first

The red → green loop, and what makes it produce tests worth keeping: what a good test is,
where tests go, the anti-patterns and the rules of the loop. Every section applies on
every cycle: read them before the loop, and again when a test feels off. Adapted from Matt
Pocock's `tdd` skill (see `THIRD_PARTY.md` in the plugin).

## What a good test is

It verifies behaviour through a public interface, not implementation details: the code can
change entirely and the test still holds. It reads like a specification ("user can check
out with a valid cart"), uses the public API only, and has one logical assertion. See
[tests.md](tests.md) for examples and [mocking.md](mocking.md) for when to mock.

## Mocks

Only at system boundaries: external APIs, time and randomness, sometimes the database or
the file system. Never your own modules. At a boundary, prefer an interface that's easy to
fake: dependencies passed in, one function per external operation rather than one generic
fetcher. See [mocking.md](mocking.md).

## Seams: where tests go

A **seam** is the public boundary you test at: where you observe behaviour without reaching
inside. Tests live at seams, never against internals.

**Test only at the plan's seams.** The plan's testing decisions name them, and its approval
is the user's approval of them. Before the first test, write down the seams under test, from
the plan. A test that needs a seam the plan didn't name is a decision for a `blocked`
comment (a `BLOCKED:` reply, for a subagent), unless it's clearly inside one that was. Effort
then lands on the critical paths and the complex logic, not on every edge case.

## Anti-patterns

- **Implementation-coupled:** mocks internal collaborators, tests private functions, or
  verifies through a side channel (querying the database instead of using the interface).
  The tell: it breaks on a refactor that didn't change behaviour.
- **Tautological:** the assertion recomputes the expected value the way the code does
  (`expect(add(a, b)).toBe(a + b)`), so it passes by construction and can never disagree with
  the code. Expected values come from an independent source: a known literal, a worked
  example, the spec.
- **Horizontal slicing:** all the tests first, then all the code. Tests written in bulk
  verify imagined behaviour: the shape of things, not what a caller does, and they commit
  you to a test structure before you understand the implementation. Work in vertical
  slices instead: one test, one implementation, repeat; the first is a tracer bullet that
  proves one path end to end, and each next test responds to what the last taught you.

## Rules of the loop

- **Red before green.** Write the failing test first and see it fail, then only enough code
  to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the loop.** It belongs to the review stage (the
  `nightshift:review` skill), not the red → green cycle.
- **A repo without tests at that seam:** check the ticket the way the repo is checked (build,
  typecheck, lint, a scratch run, the running app), and say so in the summary or `progress`
  comment.
