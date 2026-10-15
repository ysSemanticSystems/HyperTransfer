import Foundation
@testable import HyperTransferCore

func withTemp(_ body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ht-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

func plainFile(_ root: URL, _ name: String, _ bytes: Data) throws -> URL {
    let url = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: url, options: .atomic)
    return url
}

func sampleDisk() -> DiskSpace {
    DiskSpace(word: "Place", tone: .place, freeBytes: 80, totalBytes: 100, detail: "room")
}

let connectedThunderbolt = """
{"SPThunderboltDataType":[
  {"_name":"thunderboltusb4_bus_2","receptacle_1_tag":{"current_speed_key":"Up to 120 Gb/s","receptacle_status_key":"receptacle_no_devices_connected"}},
  {"_name":"thunderboltusb4_bus_1","receptacle_1_tag":{"current_speed_key":"80 Gb/s","receptacle_status_key":"receptacle_connected"},
   "_items":[{"device_name_key":"Mac17,14","services_title":[
     {"_name":"service_ip","protocol_id_key":1},
     {"_name":"unknown_xd_service","protocol_id_key":64087}
   ]}]}
]}
""".data(using: .utf8)!
