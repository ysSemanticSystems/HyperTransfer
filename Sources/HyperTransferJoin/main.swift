import Foundation
import HyperTransferVerbs

if ht_claim_single() != 0 {
    fputs("HyperTransfer is already open.\n", stderr)
    exit(1)
}
let device = CommandLine.arguments.dropFirst().first ?? "rdma_en3"
let seconds = Double(CommandLine.arguments.dropFirst(2).first ?? "") ?? 20
guard let session = device.withCString({ ht_open($0) }) else {
    fputs("open \(device): \(String(cString: ht_last_error(nil)))\n", stderr)
    exit(1)
}
defer { ht_close(session) }
let deadline = Date().addingTimeInterval(seconds)
fputs("joining \(device) for \(Int(seconds))s\n", stderr)
while Date() < deadline {
    let rc = ht_exchange(session, 1000)
    let err = String(cString: ht_last_error(session))
    print("rc=\(rc) \(err)")
    fflush(stdout)
    if rc == 0 {
        print("queue pair is up")
        exit(0)
    }
}
fputs("queue pair did not come up\n", stderr)
exit(2)
