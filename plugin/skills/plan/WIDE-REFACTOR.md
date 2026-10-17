# A wide refactor

A **wide refactor** is one mechanical change (rename a column, retype a shared symbol)
whose **blast radius** fans across the codebase, so a single edit breaks thousands of call
sites at once and no vertical slice lands green. Sequence it as **expand–contract**:

1. **Expand:** add the new form beside the old, so nothing breaks.
2. **Migrate** the call sites in batches sized by blast radius (per package, per
   directory), each batch its own ticket blocked by the expand. CI stays green from batch
   to batch because the old form still exists.
3. **Contract:** delete the old form once no caller remains, in a ticket blocked by every
   migrate batch.

When even the batches can't stay green alone, keep the sequence and end it with an
integrate-and-verify ticket blocked by all of them: green is promised only there, and the
tickets before it say so.
