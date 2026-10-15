---
name: capture-invariant
description: >
  Capture a must-not-regress HyperTransfer failure into docs/invariants.md
  and lock it with a unit test. Use when a bug is non-obvious, when a
  transport or hash edge case would have to be re-taught, or when the user
  says a behavior must not regress.
---

# Capture invariant

One catalog: [docs/invariants.md](../../../docs/invariants.md). Do not add a parallel gotcha file.

## When

- The failure is not obvious from the function name
- A transport was mislabeled, a one-sided write was trusted too early, or a hash was compared short of three reads
- The user said this must not regress

## Steps

1. Add or extend a test under `tests/` that fails if the bug returns. Name it for the failure.
2. Pick `INV-<AREA>-NNN`. AREA is `RDMA`, `INTEGRITY`, `FABRIC`, `HTTP`, or `UI`.
3. Append a catalog entry: status active, failure, lock, ops or `—`, paths, added date.
4. Run:

```bash
swift run --disable-sandbox HyperTransferChecks
```

5. Tell the user the id and the test name.

## Do not

- Add an always-on rule for one bug
- Lock an entry to a test that does not exist
- Retire an id. Set `status: retired` and keep the heading.
