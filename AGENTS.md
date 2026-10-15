# AGENTS.md

HyperTransfer copies a file over RDMA, then checks that the copy is the same file. Each pass reads the file twice. SHA-512 and BLAKE2b both have to match on the source before the copy, the received file, and the source again.

```bash
swift run --disable-sandbox HyperTransferChecks
/bin/sh scripts/run.sh
```

The app does not listen. A Thunderbolt IP service is not a reason to open the panes.

The always-on rule is `.cursor/rules/hypertransfer.mdc`. Regressions go in `docs/invariants.md` through the `capture-invariant` skill.
