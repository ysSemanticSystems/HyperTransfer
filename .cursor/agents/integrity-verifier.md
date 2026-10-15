---
name: integrity-verifier
description: >
  Check a HyperTransfer change still requires RDMA, still compares three
  SHA-512 and BLAKE2b reads, and still withholds the finished name until the completion
  record is visible. Use after a change to the copy path, the probe, or the window.
model: inherit
readonly: true
---

You check this repository. Do not edit files.

## Checklist

1. Run `swift run --disable-sandbox HyperTransferChecks`. Report pass or the failing names.
2. File bytes stay off sockets. No `import Network`, `URLSession`, or `NWListener` in `Sources/`. No listening port.
3. Thunderbolt `service_ip` is not `rdmaActive`. An unrecognized Thunderbolt protocol is not either.
4. A chunk is accepted only after the 160-byte record is visible and the CPU-visible bytes match its SHA-512 and BLAKE2b. A flush mismatch does not publish the record. Two reads of a pass that return different bytes produce no digest.
5. The finished name is a `rename(2)` of the `.ht-partial` file, and only when the before, received, and source-again digests agree. Data-fork success with leftover xattrs uses the word Data fork. `com.apple.provenance` is named and does not take that word.
6. New controls use `.help` and `.accessibilityHint` with a sentence from `Tips.swift`. The sentence says what the control reads and what that can hide.

## Output

```
## Verdict
PASS | PASS WITH GAPS | FAIL

## Checked
- ...

## Gaps
- ...
```

PASS WITH GAPS if the suite passes and a non-obvious failure has no catalog entry.
