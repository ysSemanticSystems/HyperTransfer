import Foundation

public struct PortReport: Equatable, Sendable {
    public var name: String
    public var transport: String
    public var state: String
    public var rdma: Bool
    public var word: String
    public var tone: StatusTone
    public var detail: String

    public init(
        name: String,
        transport: String,
        state: String,
        rdma: Bool,
        word: String,
        tone: StatusTone,
        detail: String
    ) {
        self.name = name
        self.transport = transport
        self.state = state
        self.rdma = rdma
        self.word = word
        self.tone = tone
        self.detail = detail
    }
}

public struct DiskSpace: Equatable, Sendable {
    public var word: String
    public var tone: StatusTone
    public var freeBytes: Int64?
    public var totalBytes: Int64?
    public var detail: String
}

public struct FabricReport: Equatable, Sendable {
    public var rdmaActive: Bool
    public var rdmaWord: String
    public var rdmaTone: StatusTone
    public var summary: String
    public var ports: [PortReport]
    public var disk: DiskSpace
    public var verbsLibrary: String?
}

private let iwarpDrivers: Set<String> = ["siw", "iw_cxgb4", "cxgb4", "cxgb3", "nes"]
private let roceDrivers: Set<String> = [
    "mlx4", "mlx4_core", "mlx5", "mlx5_core", "bnxt_re", "qedr", "hns", "hns_roce",
    "ocrdma", "rdma_rxe", "rxe", "irdma", "ionic", "ionic_rdma", "mana",
]
private let efaDrivers: Set<String> = ["efa"]

public func portIsActive(_ state: String) -> Bool {
    let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let colon = trimmed.firstIndex(of: ":") else {
        return trimmed == "4"
    }
    let head = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
    return head == "4"
}

public func diskStatus(freeBytes: Int64, totalBytes: Int64) -> (String, StatusTone) {
    if totalBytes <= 0 { return ("Place", .place) }
    if freeBytes * 20 < totalBytes { return ("Full", .down) }
    if freeBytes * 20 < totalBytes * 3 { return ("Tight", .unreachable) }
    return ("Place", .place)
}

public func diskSpace(at url: URL) -> DiskSpace {
    do {
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ])
        guard let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else {
            return DiskSpace(
                word: "Place",
                tone: .place,
                freeBytes: nil,
                totalBytes: nil,
                detail: "Free space could not be read. A copy can still fail when the disk that fills is the peer."
            )
        }
        let word = diskStatus(freeBytes: Int64(free), totalBytes: Int64(total))
        let detail = diskDetail(word: word.0, free: Int64(free), total: Int64(total))
        return DiskSpace(word: word.0, tone: word.1, freeBytes: Int64(free), totalBytes: Int64(total), detail: detail)
    } catch {
        return DiskSpace(
            word: "Place",
            tone: .place,
            freeBytes: nil,
            totalBytes: nil,
            detail: "Free space could not be read. A copy can still fail when the disk that fills is the peer."
        )
    }
}

public func classifyVerbsPort(
    name: String,
    linkLayer: String,
    state: String,
    driver: String,
    sysfsPath: String
) -> PortReport {
    let active = portIsActive(state)
    let layer = linkLayer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let driverName = driver.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let thunderbolt = sysfsPath.lowercased().contains("thunderbolt")
    let transport: String
    if layer.contains("infiniband") {
        transport = "infiniband"
    } else if thunderbolt {
        transport = "thunderbolt"
    } else if efaDrivers.contains(driverName) {
        transport = "efa"
    } else if iwarpDrivers.contains(driverName) {
        transport = "iwarp"
    } else if roceDrivers.contains(driverName) {
        transport = "roce"
    } else if layer.contains("ethernet") {
        transport = "ethernet-rdma"
    } else {
        transport = "unknown"
    }
    let word: String
    let tone: StatusTone
    let rdma: Bool
    if active && transport != "unknown" {
        word = "Up"
        tone = .up
        rdma = true
    } else {
        word = "Down"
        tone = .down
        rdma = false
    }
    return PortReport(
        name: name,
        transport: transport,
        state: active ? "active" : "down",
        rdma: rdma,
        word: word,
        tone: tone,
        detail: verbsDetail(name: name, transport: transport, driver: driverName, state: state.trimmingCharacters(in: .whitespacesAndNewlines), active: active)
    )
}

public func readLinuxSysfs(at sysfs: URL) -> [PortReport] {
    let base = sysfs.appendingPathComponent("class/infiniband", isDirectory: true)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir), isDir.boolValue else {
        return []
    }
    let devices = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
    var ports: [PortReport] = []
    for device in devices.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        var deviceIsDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: device.path, isDirectory: &deviceIsDir), deviceIsDir.boolValue else {
            continue
        }
        let driver = driverName(device)
        let portRoot = device.appendingPathComponent("ports", isDirectory: true)
        guard let portDirs = try? FileManager.default.contentsOfDirectory(at: portRoot, includingPropertiesForKeys: nil) else {
            continue
        }
        for portDir in portDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let state = readText(portDir.appendingPathComponent("state"))
            let layer = readText(portDir.appendingPathComponent("link_layer"))
            ports.append(classifyVerbsPort(
                name: "\(device.lastPathComponent)/\(portDir.lastPathComponent)",
                linkLayer: layer,
                state: state,
                driver: driver,
                sysfsPath: device.path
            ))
        }
    }
    return ports
}

public func parseThunderbolt(_ data: Data) -> [PortReport] {
    guard let json = try? JSONSerialization.jsonObject(with: data) else {
        return [failedProbe("The Thunderbolt probe was not JSON. Nothing is treated as RDMA.")]
    }
    guard let root = json as? [String: Any] else {
        return [failedProbe("The Thunderbolt probe had an unexpected shape. Nothing is treated as RDMA.")]
    }
    guard let buses = root["SPThunderboltDataType"] as? [Any] else {
        return [failedProbe("The Thunderbolt report was not a list. Nothing in it is treated as RDMA.")]
    }
    return buses.compactMap { $0 as? [String: Any] }.flatMap(busPorts)
}

public func verbsPort(library: String?) -> PortReport {
    if let library {
        return PortReport(
            name: "libibverbs",
            transport: "verbs",
            state: "present",
            rdma: false,
            word: "Place",
            tone: .place,
            detail: "The verbs library is at \(library). A port still has to be ACTIVE before a copy starts."
        )
    }
    return PortReport(
        name: "libibverbs",
        transport: "verbs",
        state: "absent",
        rdma: false,
        word: "Down",
        tone: .down,
        detail: "The verbs library is not installed. InfiniBand, RoCE, and iWARP need it."
    )
}

public func findVerbsLibrary() -> String? {
    let candidates = [
        "/usr/lib/libibverbs.so.1",
        "/usr/lib64/libibverbs.so.1",
        "/opt/homebrew/lib/libibverbs.dylib",
        "/usr/local/lib/libibverbs.dylib",
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0) }
}

public func buildReport(ports: [PortReport], verbsLibrary: String?, disk: DiskSpace) -> FabricReport {
    let active = ports.filter { $0.rdma && $0.state == "active" }
    if !active.isEmpty {
        let names = active.map(\.name).joined(separator: ", ")
        return FabricReport(
            rdmaActive: true,
            rdmaWord: "Up",
            rdmaTone: .up,
            summary: "RDMA is up on \(names).",
            ports: ports,
            disk: disk,
            verbsLibrary: verbsLibrary
        )
    }
    let link = ports.contains { $0.transport == "thunderbolt" && $0.state == "link-up" }
    if link {
        return FabricReport(
            rdmaActive: false,
            rdmaWord: "Unreachable",
            rdmaTone: .unreachable,
            summary: "Thunderbolt is connected. RDMA is unreachable, so the file panes stay closed.",
            ports: ports,
            disk: disk,
            verbsLibrary: verbsLibrary
        )
    }
    return FabricReport(
        rdmaActive: false,
        rdmaWord: "Down",
        rdmaTone: .down,
        summary: "No RDMA port is active. The file panes stay closed.",
        ports: ports,
        disk: disk,
        verbsLibrary: verbsLibrary
    )
}

public func probeMachine(sysfs: URL? = nil, home: URL? = nil) -> FabricReport {
    var ports = probeThunderbolt()
    let root = sysfs ?? URL(fileURLWithPath: "/sys", isDirectory: true)
    if FileManager.default.fileExists(atPath: root.path) {
        ports.append(contentsOf: readLinuxSysfs(at: root))
    }
    let library = findVerbsLibrary()
    ports.append(verbsPort(library: library))
    let disk = diskSpace(at: home ?? FileManager.default.homeDirectoryForCurrentUser)
    return buildReport(ports: ports, verbsLibrary: library, disk: disk)
}

private func verbsDetail(name: String, transport: String, driver: String, state: String, active: Bool) -> String {
    let driverBit = driver.isEmpty ? " The driver name could not be read." : " Driver \(driver)."
    switch transport {
    case "infiniband":
        if active { return "InfiniBand port \(name) is ACTIVE.\(driverBit)" }
        return "InfiniBand port \(name) is \(state.isEmpty ? "not ACTIVE" : state).\(driverBit) A subnet manager or a cable may be missing."
    case "roce":
        if active {
            return "RoCE port \(name) is ACTIVE.\(driverBit) A lossy Ethernet path can still retransmit and hide that cost in the copy time."
        }
        return "RoCE port \(name) is \(state.isEmpty ? "not ACTIVE" : state).\(driverBit)"
    case "iwarp":
        if active { return "iWARP port \(name) is ACTIVE.\(driverBit) The connection rides TCP. The file writes are RDMA." }
        return "iWARP port \(name) is \(state.isEmpty ? "not ACTIVE" : state).\(driverBit)"
    case "efa":
        if active { return "EFA port \(name) is ACTIVE.\(driverBit) This is RDMA and it is not labeled RoCE." }
        return "EFA port \(name) is \(state.isEmpty ? "not ACTIVE" : state).\(driverBit)"
    case "thunderbolt":
        if active { return "Thunderbolt RDMA port \(name) is ACTIVE.\(driverBit)" }
        return "A Thunderbolt verbs port \(name) is present and not ACTIVE.\(driverBit)"
    case "ethernet-rdma":
        let named = active ? "ACTIVE" : (state.isEmpty ? "not ACTIVE" : state)
        return "Ethernet RDMA port \(name) is \(named).\(driverBit) It is not labeled RoCE or iWARP because the driver name did not say which."
    default:
        return "Port \(name) is not a transport this window will copy on.\(driverBit)"
    }
}

private func busPorts(_ bus: [String: Any]) -> [PortReport] {
    let name = (bus["_name"] as? String) ?? "thunderbolt"
    let tag = (bus["receptacle_1_tag"] as? [String: Any]) ?? [:]
    let status = (tag["receptacle_status_key"] as? String) ?? ""
    let speed = (tag["current_speed_key"] as? String) ?? ""
    let connected = status == "receptacle_connected"
    let items = (bus["_items"] as? [Any]) ?? []
    var deviceName = ""
    var services: [[String: Any]] = []
    for item in items {
        guard let item = item as? [String: Any] else { continue }
        if let named = item["device_name_key"] as? String, !named.isEmpty {
            deviceName = named
        }
        if let titled = item["services_title"] as? [Any] {
            services.append(contentsOf: titled.compactMap { $0 as? [String: Any] })
        }
    }
    if !connected {
        let speedBit = speed.isEmpty ? "" : " Reported ceiling \(speed)."
        return [PortReport(
            name: name,
            transport: "thunderbolt",
            state: "down",
            rdma: false,
            word: "Down",
            tone: .down,
            detail: "No device is connected on \(name).\(speedBit)"
        )]
    }
    let peer = deviceName.isEmpty ? "a connected device" : deviceName
    let speedBit = speed.isEmpty ? "" : " at \(speed)"
    var ports = [PortReport(
        name: name,
        transport: "thunderbolt",
        state: "link-up",
        rdma: false,
        word: "Up",
        tone: .up,
        detail: "\(peer) is connected\(speedBit). The cable is up. RDMA is decided by the services on it."
    )]
    if services.isEmpty {
        ports.append(PortReport(
            name: "\(name) services",
            transport: "thunderbolt-unknown",
            state: "unrecognized",
            rdma: false,
            word: "Unreachable",
            tone: .unreachable,
            detail: "A device is connected and no service was reported. RDMA is unreachable on this cable."
        ))
        return ports
    }
    ports.append(contentsOf: services.map { servicePort(busName: name, service: $0) })
    return ports
}

private func servicePort(busName: String, service: [String: Any]) -> PortReport {
    let serviceName = (service["_name"] as? String) ?? "service"
    let protocolID = service["protocol_id_key"].map { "\($0)" } ?? "unknown"
    if serviceName == "service_ip" {
        return PortReport(
            name: "\(busName) IP",
            transport: "thunderbolt-ip",
            state: "link-up",
            rdma: false,
            word: "Unreachable",
            tone: .unreachable,
            detail: "Protocol \(protocolID) is Internet Protocol. RDMA is unreachable on this service. A copy here would move through the kernel."
        )
    }
    return PortReport(
        name: "\(busName) \(serviceName)",
        transport: "thunderbolt-unknown",
        state: "unrecognized",
        rdma: false,
        word: "Unreachable",
        tone: .unreachable,
        detail: "Protocol \(protocolID) (\(serviceName)) is not InfiniBand, RoCE, or iWARP. It is left unused."
    )
}

private func probeThunderbolt() -> [PortReport] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPThunderboltDataType", "-json"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return [failedProbe("The Thunderbolt probe did not finish (\(error)). Nothing is treated as RDMA.")]
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if process.terminationStatus != 0 || data.isEmpty {
        return [failedProbe("The Thunderbolt probe returned nothing. Nothing is treated as RDMA.")]
    }
    return parseThunderbolt(data)
}

private func failedProbe(_ detail: String) -> PortReport {
    PortReport(
        name: "thunderbolt",
        transport: "thunderbolt",
        state: "probe-failed",
        rdma: false,
        word: "Down",
        tone: .down,
        detail: detail
    )
}

private func driverName(_ device: URL) -> String {
    let link = device.appendingPathComponent("device/driver")
    let destination = (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) ?? ""
    return URL(fileURLWithPath: destination).lastPathComponent
}

private func readText(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

private func diskDetail(word: String, free: Int64, total: Int64) -> String {
    let freeText = formatBytes(free)
    let totalText = formatBytes(total)
    switch word {
    case "Full":
        return "\(freeText) free of \(totalText) on this volume. Under 5 percent free."
    case "Tight":
        return "\(freeText) free of \(totalText) on this volume. Under 15 percent free."
    default:
        return "\(freeText) free of \(totalText) on this volume."
    }
}

private func formatBytes(_ size: Int64) -> String {
    let gib = Int64(1024 * 1024 * 1024)
    let mib = Int64(1024 * 1024)
    if size >= gib {
        return String(format: "%.1f GiB", Double(size) / Double(gib))
    }
    if size >= mib {
        return String(format: "%.1f MiB", Double(size) / Double(mib))
    }
    return "\(size) B"
}
