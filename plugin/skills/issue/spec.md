# The spec

Adapted from Matt Pocock's `to-spec` skill (see `THIRD_PARTY.md` in the plugin). It goes in
the `plan` comment's collapsed block, synthesised from the issue, the answers and the code:
no further interview. Size it to the issue: a line or two under each heading, a single
line for a small change, and drop a heading that has nothing to say.

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
