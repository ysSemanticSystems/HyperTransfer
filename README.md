# HyperTransfer

HyperTransfer copies a file to another machine over RDMA, then checks that the copy is the same file.

The received file keeps its real name only when every measurement agrees.

## Check

Each measurement reads the file twice. One read uses 1 MiB pieces. The other uses 64 KiB + 13 byte pieces and asks the cache to step aside. The bytes are compared before a digest is trusted. Two reads that disagree stop the copy.

Each agreed read is digested with SHA-512 and with BLAKE2b. Both have to match. A collision has to land in both families at once.

1. Measure the source before anything is sent.
2. Copy the file. The bytes handed to the copy are digested too, and they have to match that first measurement.
3. Measure the file that arrived, twice.
4. Measure the source again, twice.

| Before | Received | Source again | Result |
| --- | --- | --- | --- |
| A | A | A | The file is renamed into place. |
| A | A | B | The source changed. The received file matches the earlier bytes. It is not renamed. |
| A | B | B | The source changed during the copy. The received file matches the source as it is now. It is not renamed. |
| A | B | A | The source stayed the same. The received file does not. It is not renamed. |

## Fabric

A copy starts only when a port is RDMA and active.

| Link | What HyperTransfer does |
| --- | --- |
| RoCE, InfiniBand, iWARP, or EFA, port active | The file can be copied once a queue pair exists. |
| Thunderbolt verbs port `PORT_ACTIVE (4)` | The file can be copied once the other Mac is running HyperTransfer and the queue pair is up. |
| Thunderbolt carrying ordinary IP | The cable can be up. The file is not copied. |
| Unrecognized Thunderbolt protocol | Left unused. |

## Both computers

The other Mac needs RDMA enabled, and it needs this app running. The Thunderbolt port accepts a send only when the far side has posted a receive of the same size. HyperTransfer is the program that posts that receive, checks the completion record, and renames the file. A Mac with RDMA on, and this app closed, has nowhere for the file to land.

## Further reading

| Document | What it covers |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How a one-sided RDMA write is treated as finished, and what the receipt is claiming. |
| [docs/invariants.md](docs/invariants.md) | Failures that have a check so they cannot slip back in. |

## Commands

Open the app:

```bash
/bin/sh scripts/run.sh
```

Run the checks:

```bash
swift run --disable-sandbox HyperTransferChecks
```
