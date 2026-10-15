---
name: probe-fabric
description: >
  Read HyperTransfer's fabric probe and say which ports are RDMA. Use when
  the window is closed, when a Thunderbolt cable is up, or when deciding
  whether a copy is allowed to start.
---

# Probe the fabric

## Run

Open the HyperTransfer window, or:

```bash
swift run --disable-sandbox HyperTransferChecks
```

The live probe is `probeMachine()` in `Sources/HyperTransferCore/Fabric.swift`. The window calls it on Refresh.

## How to read it

- `rdmaActive` is the gate. False means browse and copy stay closed.
- A Thunderbolt row with word Up is the cable. The IP row beside it is Unreachable. Protocol 1 is Internet Protocol. An unrecognized protocol, including 64087, stays unused.
- InfiniBand, RoCE, iWARP, and EFA count only when the number before the colon is 4.
- A missing driver name on Ethernet is `ethernet-rdma`, not RoCE and not iWARP.
- EFA is not relabeled RoCE.
- `libibverbs` absent means this Mac cannot post a queue pair. Do not open a socket path instead.

## After the probe

If `rdmaActive` is false, say which row is Up and which row is Unreachable or Down. Stop there. Do not propose a socket copy of the file.
