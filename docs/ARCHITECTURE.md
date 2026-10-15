# Architecture

HyperTransfer copies a file to another machine over RDMA, then checks that the copy is the same file. A copy starts only when a port is RDMA and active. Each measurement reads the file twice and keeps the digest only when the bytes agree. SHA-512 and BLAKE2b both have to match across the source before the copy, the received file, and the source again.

## What "zero copy" means here

An RDMA write lets the adapter move bytes between registered memory on two machines. The CPUs do not copy those bytes through a kernel socket buffer, and the transfer does not take a context switch per chunk.

The disk is a separate hop. Reading a file into registered memory, and writing that memory out to a file on the far side, are still copies unless the storage stack itself can DMA. This product does not claim GPUDirect Storage or a registered file buffer. The wire hop is the RDMA hop. The receipt's rate is that hop's bytes over that hop's time, measured around `land` and the receiver's take. The hash times are reported beside it so a fast copy is not confused with a fast disk.

## The notification problem

RDMA WRITE and READ are one-sided. The target CPU is not interrupted when the adapter finishes. The [rdma_bench](https://github.com/efficient/rdma_bench) `write-incomplete` case is sharper than that: the sender's completion can be visible while the remote CPU still reads zeros. `write-reordering` is the matching warning across operations that were not ordered.

HyperTransfer uses one reliable connection, so posts on that connection stay in order. Order on the wire is not the same as visibility to the CPU. The protocol therefore does three things, in this order, for every chunk:

1. WRITE the payload into the receiver's registered window.
2. READ the tail back (8 bytes, or the whole short chunk). If it disagrees, the chunk is not published.
3. WRITE a 160-byte completion record on its own line: magic `HTC1`, chunk index, offset, length, SHA-512, and BLAKE2b of that payload.

The receiver copies a chunk into the partial file only after that record parses and the CPU-visible bytes hash to the same digest. An empty file still posts the record. There is nothing to flush, and there is still a notification.

The record is not the file. A test locks that the payload bytes do not appear inside it.

Selective signaling, as rdma_bench describes it, is the reason the cookie is the signaled post and the payload writes do not each demand their own completion. The in-process endpoint publishes the cookie as that signal. A future verbs endpoint has to keep that shape: signal the record, and do not treat a payload completion as permission for the receiver to hash.

## The two digests

SHA-512 and BLAKE2b-512, streamed, of the data fork. They are different constructions. A collision has to satisfy both on the same bytes.

Each pass reads the file twice before either digest is kept. One read is 1 MiB at a time. The other is 64 KiB + 13 bytes at a time, with the cache asked to step aside. The bytes are compared. If they differ, there is no digest and the file is not renamed.

1. Hash the source before any byte is posted.
2. Copy.
3. Hash the partial file on the destination after it has been synced (`F_FULLFSYNC` on this Mac, otherwise `fsync`).
4. Hash the source again. This read asks the cache to step aside (`F_NOCACHE` here, `posix_fadvise(DONTNEED)` where that exists).

The second source read exists because the file can change, or a disk can return bad bytes, between the first hash and the read that filled the window. Comparing only the first hash to the destination would bless a copy of bytes the source no longer has. Comparing only the destination to the source as it is now would bless a copy of a file that changed under the transfer.

| Before | Received | Source again | What the receipt says |
|---|---|---|---|
| A | A | A | Match. The partial is renamed onto the finished name. |
| A | A | B | The source changed. The received file matches the earlier bytes. The finished name is not written. |
| A | B | B | The source changed during the copy. The received file matches the source as it is now, not the hash taken before the transfer. |
| A | C | B | The source changed, and the received file matches neither reading. |
| A | B | A | The source stayed the same. The received file does not. |
| lengths differ | | | Lengths are named. No digest equality is claimed. |

A file that already sits at the destination is left there unless replace is on, and replace itself waits for the rename. The previous bytes stay until `os.replace` of the partial. If that rename fails, the word is Down even though the three digests matched, and the partial remains.

If the source inode changes and the bytes do not, the receipt still says Match and names the inode change.

Sparse files are read as their logical bytes, holes included as zeros. The digest is of that logical file. The hole is not preserved as a hole.

## Attributes that are not the data fork

Extended attribute names, and a non-empty resource fork (`..namedfork/rsrc`), are listed and not transferred. When the three data-fork digests match, the bytes are still renamed into place. The word on that receipt is **Data fork**, not Match.

`com.apple.provenance` is the exception this Mac forces onto a new file and puts back if it is removed. It is named on the receipt and it does not take the word Match, because treating every local file as a partial copy would make that word meaningless. Any other attribute still does.

## Transports

The probe reads `system_profiler SPThunderboltDataType -json` and, on Linux, `/sys/class/infiniband`. A port counts as RDMA only in state `4: ACTIVE`.

| What the probe sees | Word | Copy |
|---|---|---|
| Thunderbolt receptacle connected | Up, for the cable | No |
| Thunderbolt service `service_ip` (protocol 1) | Unreachable | No. This is Internet Protocol. |
| Any other Thunderbolt protocol, including 64087 | Unreachable | No. It is not InfiniBand, RoCE, or iWARP. |
| InfiniBand link, not ACTIVE | Down | No. A subnet manager or a cable is the usual cause. |
| RoCE driver and Ethernet link, ACTIVE | Up | Yes, once a peer queue pair exists. |
| iWARP driver (`siw` and the cxgb/nes set), ACTIVE | Up | Yes. The connection rides TCP. The file writes are RDMA. |
| EFA, ACTIVE | Up | Yes. The label stays EFA, not RoCE. |
| Ethernet link, driver name missing, ACTIVE | Up | Yes, labeled ethernet-rdma, not RoCE and not iWARP. |
| Verbs device whose sysfs path contains `thunderbolt`, ACTIVE | Up | Yes. This is the only Thunderbolt case that is RDMA. |
| `libibverbs` missing | Down, for the library | The library is not itself a port. |

RoCE wants a network that does not drop the RDMA class of traffic. MORI's environment check looks at PFC and DCQCN before it trusts a fabric ([ROCm/mori](https://github.com/ROCm/mori)). This window does not read those counters. A lossy RoCE path can still complete, slowly, because a reliable connection retransmits. The rate then hides the retries inside the elapsed time. The hash still checks the bytes.

iWARP is the verbs transport that maps RDMA onto TCP. Seeing TCP in the connection setup is not a reason to send the file on a plain socket.

InfiniBand is the native fabric. A down port is down.

[Open-RDMA](https://github.com/open-rdma/open-rdma) posts an 8-byte doorbell from the GPU and lets the NIC build the request, and it draws on the multipath reliable connection work. HyperTransfer is a CPU file copy on one reliable connection. It does not post that doorbell and it does not claim multipath.

[rdma-core](https://github.com/linux-rdma/rdma-core) is the userspace verbs and `rdma_cm` stack a queue pair would be built on. [RDMA-Tutorial](https://github.com/jcxue/RDMA-Tutorial) is the small connected-transfer shape: register memory, exchange the address and rkey, post the write. The exchange is a few dozen bytes of connection setup. It is not a second copy of the file.

## What runs on this Mac

`scripts/run.sh` builds the Swift window and opens it. The probe reads Thunderbolt and, on Linux, `/sys/class/infiniband`. Browse and copy stay closed until that probe reports an active RDMA port, and copy stays closed after that until a queue pair exists. The check runner injects a scripted endpoint that can hide the cookie, hide the payload from the CPU, or corrupt the flush. That endpoint is not used by the window.

The queue-pair post path, through libibverbs, is not built. This Mac has no verbs library, and the live Thunderbolt service is Internet Protocol plus an unrecognized protocol. Building a TCP copy and calling it RDMA would break the gate. The next endpoint implements `land`, `cpuCookie`, and `cpuPayload` with real posts, and it registers only the window it needs.

SHA-512 and BLAKE2b are computed together, streamed. A pass reads the file twice, once in 1 MiB pieces and once in 64 KiB + 13 byte pieces, and compares the bytes before either digest is trusted. The second read asks the cache to step aside with `F_NOCACHE`. The partial file is synced with `F_FULLFSYNC` before it is hashed. The finished name is `rename(2)`. The bytes handed to the copy are digested too, and they have to match the first measurement.

## Browsing

The local root is the home folder. The peer root is the peer's exported folder. `..`, an absolute path, and any symlink component are refused. Symlinks are listed, including when they leave the root, and they are not opened. A folder copy skips them and says so. Names that start with a dot can be hidden in the list. The folder copy still includes them.

View reads the first 4096 bytes and says when the file continues. That window is not a hash.

## Disk pressure

Free space on the volume being probed uses Place when at least 15 percent is free, Tight under 15 percent, and Full under 5 percent. Tight is orange. Full is red. The peer's disk is not this number.

## Security of the window

The app does not listen. A request body is not a concept here. The rkey of a real window would be a capability for that window only, dropped when the copy ends. The scripted endpoint never mints one.
