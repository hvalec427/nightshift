# The tickets

Adapted from Matt Pocock's `to-tickets` skill (see `THIRD_PARTY.md` in the plugin). They're
in the `plan` comment, numbered `T1`, `T2`, … in build order, all in that comment (no new
issues): one line each on top, and in full (below) in its collapsed block. The user approves them with the plan.

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
