# Architecture

HyperTransfer copies a file to another machine over RDMA, then checks that the copy is the same file. A copy starts only when a port is RDMA and active. Each measurement reads the file twice and keeps the digest only when the bytes agree. SHA-512 and BLAKE2b both have to match across the source before the copy, the received file, and the source again.

## What "zero copy" means here

An RDMA write lets the adapter move bytes between registered memory on two machines. The CPUs do not copy those bytes through a kernel socket buffer, and the transfer does not take a context switch per chunk.

The disk is a separate hop. Reading a file into registered memory, and writing that memory out to a file on the far side, are still copies unless the storage stack itself can DMA. This product does not claim GPUDirect Storage or a registered file buffer. The wire hop is the RDMA hop. The receipt's rate is that hop's bytes over that hop's time, measured around `land` and the receiver's take. The hash times are reported beside it so a fast copy is not confused with a fast disk.

## The notification problem

RDMA WRITE and READ are one-sided. The target CPU is not interrupted when the adapter finishes. The [rdma_bench](https://github.com/efficient/rdma_bench) `write-incomplete` case is sharper than that: the sender's completion can be visible while the remote CPU still reads zeros. `write-reordering` is the matching warning across operations that were not ordered.

HyperTransfer keeps one queue pair, so posts on that pair stay in order. Order on the wire is not the same as visibility to the CPU. The protocol therefore does three things, in this order, for every chunk:

1. Move the payload into the receiver's registered window.
2. Check the tail before publishing. On a one-sided write that check is a READ of 8 bytes, or of the whole short chunk. If it disagrees, the chunk is not published.
3. Publish a 160-byte completion record on its own line: magic `HTC1`, chunk index, offset, length, SHA-512, and BLAKE2b of that payload.

The receiver copies a chunk into the partial file only after that record parses and the CPU-visible bytes hash to the same digest. An empty file still posts the record. There is nothing to flush, and there is still a notification.

The record is not the file. A test locks that the payload bytes do not appear inside it.

Selective signaling, as rdma_bench describes it, is the reason the cookie is the signaled post and the payload writes do not each demand their own completion. The in-process endpoint publishes the cookie as that signal. The live Thunderbolt endpoint keeps that shape: the record is the signal, and a payload completion is not permission for the receiver to hash.

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

The probe reads `system_profiler SPThunderboltDataType -json`, `ibv_devinfo`, and, on Linux, `/sys/class/infiniband`. A port counts as RDMA only in state `4: ACTIVE`. On this Mac that state is the parenthetical number in `PORT_ACTIVE (4)`.

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
| Verbs device whose sysfs path contains `thunderbolt`, ACTIVE | Up | Yes. |
| `ibv_devinfo` link layer Thunderbolt, `PORT_ACTIVE (4)` | Up | Yes, once a queue pair exists. This is the Thunderbolt case on this Mac. |
| Same verbs port `PORT_DOWN` | Down | No. |
| `libibverbs` or `librdma` missing | Down, for the library | The library is not itself a port. |

RoCE wants a network that does not drop the RDMA class of traffic. MORI's environment check looks at PFC and DCQCN before it trusts a fabric ([ROCm/mori](https://github.com/ROCm/mori)). This window does not read those counters. A lossy RoCE path can still complete, slowly, because a reliable connection retransmits. The rate then hides the retries inside the elapsed time. The hash still checks the bytes.

iWARP is the verbs transport that maps RDMA onto TCP. Seeing TCP in the connection setup is not a reason to send the file on a plain socket.

InfiniBand is the native fabric. A down port is down.

[Open-RDMA](https://github.com/open-rdma/open-rdma) posts an 8-byte doorbell from the GPU and lets the NIC build the request, and it draws on the multipath reliable connection work. HyperTransfer is a CPU file copy on one queue pair. It does not post that doorbell and it does not claim multipath.

[rdma-core](https://github.com/linux-rdma/rdma-core) is the userspace verbs and `rdma_cm` stack a queue pair would be built on. [RDMA-Tutorial](https://github.com/jcxue/RDMA-Tutorial) is the small connected-transfer shape: register memory, exchange the address and rkey, post the write. The exchange is a few dozen bytes of connection setup. It is not a second copy of the file.

## What runs on this Mac

`scripts/run.sh` builds the Swift window and opens it. The probe reads Thunderbolt, `ibv_devinfo`, and, on Linux, `/sys/class/infiniband`. Browse stays closed until that probe reports an active RDMA port. Copy stays closed until the queue pair on that port is up. The check runner injects a scripted endpoint that can hide the cookie, hide the payload from the CPU, or corrupt the flush. That endpoint is not used by the window.

This Mac's queue pair is an unreliable connection, which is the type the Thunderbolt port accepts, and it speaks send and receive. There is no one-sided WRITE and no READ on this port. The payload send completes before the completion record is posted. Completion of that send means the peer posted a receive of the same length and the frames left this Mac. It does not mean the far CPU has the bytes, and it does not mean they arrived intact. The receiver hashes the registered bytes only after that record is visible, then waits for the sender's commit before `rename(2)`. The 64-byte queue-pair record travels on UDP 24764 bound to the Thunderbolt bridge, and that socket closes once the queue pair is up. File bytes stay on the verbs send.

Apple documents this port in [TN3205](https://developer.apple.com/documentation/technotes/tn3205-low-latency-communication-with-rdma-over-thunderbolt). The parts that decide whether a copy can start:

| What TN3205 says | What HyperTransfer does with it |
|---|---|
| `PORT_ACTIVE (4)` | The verbs row is Up. State 5 (`PORT_ACTIVE_DEFER`) and a parenthetical 40 stay Down. |
| Send and receive only. Register memory as local write. | The file moves by posted sends into a window this process registered. There is no remote write into a Mac that has not posted a receive. |
| The posted send length and the posted receive length have to be the same number of 4 KiB frames. | Every message is rounded up to a multiple of 4096. A 160-byte record and a 1-byte chunk both go out as 4096. A 4097-byte message goes out as 8192. |
| Send completion is not an acknowledgement. The connection is unreliable. | A failed completion stops the copy. The hash is the check. The copy is not retried on a socket. |
| At most 10 queue pairs, one scatter entry, messages up to 16,773,120 bytes. | One queue pair. One chunk at a time, 1 MiB, inside a registered window. |
| The sample reads GID index 1, the IPv4-mapped address. | A mapped GID is used when the port already has one. Otherwise the link-local GID is the route. The window does not ask for an address. |
| The library is `librdma`. | `libibverbs` is not on this Mac. The tools link `librdma`, which lives in the dyld shared cache rather than a file under `/usr/lib`. |
| Exchange the GID and queue-pair number out of band. The technote names a TCP socket as the usual way. | The exchange is the 64-byte `HTQ1` record on UDP 24764, then `HTGO`, then the socket closes. A shorter datagram, a longer one, and any other magic are ignored. A VPN that owns the default route can block that note. The window names the VPN. The file is not sent through it. |
| Disable the Thunderbolt bridge when the cables form a loop. | Two Macs with one cable use that bridge's link-local address to exchange the record. The file still does not use it. A loop of cables is a different topology, and the technote's bridge warning applies there. |
| Thunderbolt does not wake a sleeping Mac. | A peer that is asleep looks the same as a peer that has not opened the window. |

## The other computer

RDMA enabled on the far Mac is the port. It is not the receiver.

The Thunderbolt controller on that Mac writes an incoming send only into a receive that a process on that Mac has posted, into memory that process has registered. Nothing in macOS posts that receive for a file. `ibv_uc_pingpong` posts one for its own ping. MLX posts one for its own collective. A Thunderbolt IP service does not post one at all.

The process that posts HyperTransfer's receives, checks the completion record, and renames the file is HyperTransfer. Both computers run it. The window on the far side can be the same build. A different program would have to speak the same record, the same frame sizes, and the same commit. No such program ships with macOS.

The far window does not have to be the one that starts the copy. It has to be running, awake, and in the queue pair before **Copy file** is pressed. Until then this window says the queue pair is not up, and the file stays where it is.

SHA-512 and BLAKE2b are computed together, streamed. A pass reads the file twice, once in 1 MiB pieces and once in 64 KiB + 13 byte pieces, and compares the bytes before either digest is trusted. The second read asks the cache to step aside with `F_NOCACHE`. The partial file is synced with `F_FULLFSYNC` before it is hashed. The finished name is `rename(2)`. The bytes handed to the copy are digested too, and they have to match the first measurement.

## The note on the bridge

The 64-byte note uses the Thunderbolt bridge link-local address. A missing allowance from macOS, a failed send, and a failed bind try again every second, and the window says so. Once the peer note is in hand, the ready step is retried on that same pair. The higher queue-pair number waits briefly so the two kernels overlap inside the one-second ready wait. The pair is not destroyed for that refusal. The window reads the network services, the tunnel addresses, and who answers a ping on that bridge. A missing service, a disabled service, a down interface, and a bridge with no IPv6 link-local are each named. A VPN is named when a tunnel has an address or owns the default route, including when the verbs port is already Up. The file stays on this Mac until another Mac answers and the queue pair finishes. The note is still tried on the bridge. It is not moved onto the VPN.

The first byte of the record's pad is 1 when this build can list a folder. A pad of 0 is an older window. It can still receive a file, and this window does not copy until the destination folder is on screen. A second launch brings the existing window forward and does not open the port again.

## Browsing

The local root is the home folder. The peer root is the peer's home folder, listed over the queue pair after it is up. `..`, an absolute path, and any symlink component are refused. Symlinks are listed, including when they leave the root, and they are not opened. A folder copy skips them and says so. Names that start with a dot can be hidden in the list. The folder copy still includes them, and a hidden name still blocks a copy onto that name.

The copy lands in the peer folder on screen, under the selected name. There is no typed path. A name already in that listing stays until replace is on and the three hashes agree. A list that stopped early blocks a name the window did not show. A folder that is already there has to be opened before a copy goes into it.

View reads the first 4096 bytes of a file on this Mac and says when the file continues. That window is not a hash.

## Disk pressure

Free space on the volume being probed uses Place when at least 15 percent is free, Tight under 15 percent, and Full under 5 percent. Tight is orange. Full is red. The peer's disk is not this number.

## Security of the window

The window binds UDP 24764 on the Thunderbolt bridge for the 64-byte queue-pair record, then closes it. A request body is not a concept here. File bytes stay on the verbs send. The registered window is dropped when the copy ends. The scripted endpoint never mints one.
