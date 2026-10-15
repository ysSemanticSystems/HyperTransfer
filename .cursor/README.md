# Cursor pack

| Kind | Path | Purpose |
|---|---|---|
| Rule | [rules/hypertransfer.mdc](rules/hypertransfer.mdc) | Always on. RDMA gate, three hashes, completion record. The app does not listen. |
| Rule | [rules/invariants.mdc](rules/invariants.mdc) | Always on. Append to `docs/invariants.md` instead of a new gotcha file. |
| Rule | [rules/ui.mdc](rules/ui.mdc) | Tooltip and status-word contract for `static/`. |
| Rule | [rules/contracts.mdc](rules/contracts.mdc) | Shelf port inventory when the listen port or the service card changes. |
| Skill | [skills/capture-invariant/SKILL.md](skills/capture-invariant/SKILL.md) | Lock a non-obvious failure with a test and a catalog entry. |
| Skill | [skills/probe-fabric/SKILL.md](skills/probe-fabric/SKILL.md) | Read the fabric probe and say what is actually RDMA. |
| Agent | [agents/integrity-verifier.md](agents/integrity-verifier.md) | Check the gate, the three hashes, and the completion record. |
| Command | [commands/check.md](commands/check.md) | Run `swift run --disable-sandbox HyperTransferChecks`. |

Portfolio map, when the port or the card is in play: `../.contracts/`. Stamps are in that folder's README. Do not paste the map into AGENTS.md.
