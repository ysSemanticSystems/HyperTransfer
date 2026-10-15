import Darwin
import Foundation

public struct NetworkService: Equatable, Sendable {
    public var name: String
    public var enabled: Bool
}

public struct InterfaceFact: Equatable, Sendable {
    public var name: String
    public var up: Bool
    public var inactive: Bool
    public var linkLocals: [String]
    public var globals: [String]
}

public struct TunnelFact: Equatable, Sendable {
    public var name: String
    public var address: String
}

public struct BridgeFacts: Equatable, Sendable {
    public var probeFailed: Bool
    public var serviceLines: [String]
    public var bridgeUp: Bool
    public var linkLocal: String?
    public var tunnels: [TunnelFact]
    public var defaultRoute: String?
    public var responders: [String]
    public var selfAddress: String?
    public var replyProbeFailed: Bool
}

public struct BridgeDiagnosis: Equatable, Sendable {
    public var word: String
    public var tone: StatusTone
    public var sentence: String
    public var vpnNames: [String]
    public var peerSeen: Bool
    public var bridgeReady: Bool
}

public func parseNetworkServices(_ text: String) -> [NetworkService] {
    var services: [NetworkService] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw).trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("An asterisk") { continue }
        let disabled = line.hasPrefix("*")
        let name = line.drop { $0 == "*" || $0 == " " }.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { continue }
        services.append(NetworkService(name: name, enabled: !disabled))
    }
    return services
}

public func isVpnServiceName(_ name: String) -> Bool {
    let folded = name.lowercased()
    let keys = [
        "vpn", "tailscale", "wireguard", "proton", "mullvad", "nordvpn", "expressvpn",
        "cloudflare", "warp", "zerotier", "openvpn", "tunnelblick", "viscosity",
        "private internet", "windscribe", "ivpn",
    ]
    return keys.contains { folded.contains($0) }
}

public func isTunnelInterface(_ name: String) -> Bool {
    name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")
}

public func parseIfconfig(_ text: String) -> [InterfaceFact] {
    var facts: [InterfaceFact] = []
    var current: InterfaceFact?
    func flush() {
        if let current { facts.append(current) }
    }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !line.hasPrefix("\t"), !line.hasPrefix(" "), let colon = trimmed.firstIndex(of: ":"),
           trimmed.contains("flags=") {
            flush()
            let name = String(trimmed[..<colon])
            let flags = trimmed
            current = InterfaceFact(
                name: name,
                up: flags.contains("UP"),
                inactive: false,
                linkLocals: [],
                globals: []
            )
            continue
        }
        guard current != nil else { continue }
        if trimmed.hasPrefix("status:") {
            current?.inactive = trimmed.contains("inactive")
        } else if trimmed.hasPrefix("inet6 ") {
            let address = trimmed.dropFirst("inet6 ".count).split(separator: " ").first.map(String.init) ?? ""
            let bare = address.split(separator: "%").first.map(String.init) ?? address
            if bare.lowercased().hasPrefix("fe80:") {
                current?.linkLocals.append(bare)
            } else if isGlobalIPv6(bare) {
                current?.globals.append(bare)
            }
        } else if trimmed.hasPrefix("inet ") {
            let address = trimmed.dropFirst("inet ".count).split(separator: " ").first.map(String.init) ?? ""
            if isGlobalIPv4(address) {
                current?.globals.append(address)
            }
        }
    }
    flush()
    return facts
}

public func parseDefaultRoute(_ text: String) -> String? {
    for raw in text.split(separator: "\n") {
        let line = String(raw).trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("interface:") else { continue }
        let name = line.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
    return nil
}

public func parsePingResponders(_ text: String) -> [String] {
    var found: [String] = []
    for raw in text.split(separator: "\n") {
        let line = String(raw)
        guard let range = line.range(of: "from ") else { continue }
        var host = line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "," }
        if let zone = host.firstIndex(of: "%") {
            host = host[..<zone]
        }
        let address = String(host)
        if address.isEmpty || found.contains(address) { continue }
        found.append(address)
    }
    return found
}

public func diagnoseBridge(_ facts: BridgeFacts) -> BridgeDiagnosis {
    if facts.probeFailed {
        return BridgeDiagnosis(
            word: "Down", tone: .down,
            sentence: "The Thunderbolt bridge probe did not finish. The queue-pair note is not assumed to have a path.",
            vpnNames: [], peerSeen: false, bridgeReady: false
        )
    }
    let services = parseNetworkServices(facts.serviceLines.joined(separator: "\n"))
    let bridgeService = services.first { $0.name == "Thunderbolt Bridge" }
    let vpnNames = vpnDisplayNames(services: services, tunnels: facts.tunnels)
    let route = facts.defaultRoute.flatMap { isTunnelInterface($0) ? $0 : nil }
    var names = vpnNames
    if names.isEmpty, let route { names = [route] }
    func named(_ sentence: String) -> String {
        guard !names.isEmpty else { return sentence }
        return "\(areUp(names)). \(sentence)"
    }
    if bridgeService == nil {
        return closed(
            word: "Down", tone: .down,
            sentence: named("Thunderbolt Bridge is not a network service. The 64-byte queue-pair note has nowhere to go, and the file stays on this Mac."),
            vpnNames: names
        )
    }
    if bridgeService?.enabled != true {
        return closed(
            word: "Down", tone: .down,
            sentence: named("Thunderbolt Bridge is disabled. The 64-byte queue-pair note stays on this Mac, and the file stays with it."),
            vpnNames: names
        )
    }
    if !facts.bridgeUp {
        return closed(
            word: "Down", tone: .down,
            sentence: named("The Thunderbolt bridge interface is down. The queue-pair note cannot leave this Mac."),
            vpnNames: names
        )
    }
    if facts.linkLocal == nil || facts.linkLocal?.isEmpty == true {
        return closed(
            word: "Down", tone: .down,
            sentence: named("The Thunderbolt bridge has no IPv6 link-local address. The queue-pair note cannot be sent."),
            vpnNames: names
        )
    }
    let others = facts.responders.filter { !sameLinkLocal($0, facts.selfAddress) }
    if facts.replyProbeFailed {
        let lead = names.isEmpty ? "" : "\(areUp(names)). "
        return BridgeDiagnosis(
            word: "Unreachable", tone: .unreachable,
            sentence: "\(lead)The Thunderbolt bridge reply probe did not finish. Another Mac is not assumed. The queue-pair note is still tried on the bridge.",
            vpnNames: names, peerSeen: false, bridgeReady: true
        )
    }
    if others.isEmpty {
        if !names.isEmpty, let route {
            return BridgeDiagnosis(
                word: "Unreachable", tone: .unreachable,
                sentence: "\(vpnLead(names, route: route)). No other Mac answered on the Thunderbolt bridge. The VPN can block the 64-byte queue-pair note. The file is not sent through the VPN.",
                vpnNames: names, peerSeen: false, bridgeReady: true
            )
        }
        if !names.isEmpty {
            return BridgeDiagnosis(
                word: "Unreachable", tone: .unreachable,
                sentence: "\(areUp(names)). No other Mac answered on the Thunderbolt bridge. A VPN can block the 64-byte queue-pair note while the verbs port stays up. The file stays on this Mac.",
                vpnNames: names, peerSeen: false, bridgeReady: true
            )
        }
        return BridgeDiagnosis(
            word: "Unreachable", tone: .unreachable,
            sentence: "No other Mac answered on the Thunderbolt bridge. The 64-byte queue-pair note is still being sent. The file stays on this Mac until a peer window answers.",
            vpnNames: [], peerSeen: false, bridgeReady: true
        )
    }
    if !names.isEmpty {
        return BridgeDiagnosis(
            word: "Reachable", tone: .reachable,
            sentence: "\(areUp(names)). Another Mac answered on the Thunderbolt bridge, so the queue-pair note is using that bridge and not the VPN.",
            vpnNames: names, peerSeen: true, bridgeReady: true
        )
    }
    return BridgeDiagnosis(
        word: "Up", tone: .up,
        sentence: "Another Mac answered on the Thunderbolt bridge. Waiting for its HyperTransfer window to finish the queue pair.",
        vpnNames: [], peerSeen: true, bridgeReady: true
    )
}

public enum ExchangeStep: Equatable {
    case connected
    case waiting
    case retry(String)
    case reopen(String)
}

public func introductionRetry(_ detail: String) -> String {
    if detail.contains("tried again every second") { return detail }
    let reason = detail.isEmpty ? "The queue-pair note did not land." : detail
    return "\(reason) The queue-pair note is tried again every second."
}

public func exchangeStep(rc: Int32, detail: String) -> ExchangeStep {
    if rc == 0 { return .connected }
    if rc == 1 { return .waiting }
    let sentence = introductionRetry(detail)
    if rc < 0 { return .reopen(sentence) }
    return .retry(sentence)
}

public func phaseOnScreen(phase: String, diagnosis: BridgeDiagnosis?) -> String {
    if phase.hasPrefix("Queue pair is up") || phase.hasPrefix("Copying") || phase.hasPrefix("Received") {
        return phase
    }
    if phase.contains("tried again") || phase.contains("will not open it again") { return phase }
    let failure = phase.contains("could not") || phase.contains("did not") || phase.contains("no link-local")
        || phase.contains("stopped") || phase.contains("was not")
    if failure { return phase }
    if let diagnosis { return diagnosis.sentence }
    return phase
}

public func probeBridge() -> BridgeDiagnosis {
    guard let services = runTool("/usr/sbin/networksetup", ["-listallnetworkservices"]),
          let interfacesText = runTool("/sbin/ifconfig", ["-a"]) else {
        return diagnoseBridge(BridgeFacts(
            probeFailed: true, serviceLines: [], bridgeUp: false, linkLocal: nil, tunnels: [],
            defaultRoute: nil, responders: [], selfAddress: nil, replyProbeFailed: true
        ))
    }
    let interfaces = parseIfconfig(interfacesText)
    let bridge = interfaces.first { $0.name == "bridge0" }
    let bridgeUp = bridge?.up == true && bridge?.inactive != true
    let linkLocal = bridge?.linkLocals.first
    let tunnels = interfaces.filter { isTunnelInterface($0.name) && !$0.globals.isEmpty }.map {
        TunnelFact(name: $0.name, address: $0.globals[0])
    }
    let route = runTool("/sbin/route", ["-n", "get", "default"]).flatMap(parseDefaultRoute)
    var responders: [String] = []
    var replyFailed = false
    if bridgeUp, linkLocal != nil {
        if let ping = runTool("/sbin/ping6", ["-c", "1", "-W", "500", "ff02::1%bridge0"]) {
            responders = parsePingResponders(ping)
        } else {
            replyFailed = true
        }
    }
    return diagnoseBridge(BridgeFacts(
        probeFailed: false,
        serviceLines: services.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
        bridgeUp: bridgeUp,
        linkLocal: linkLocal,
        tunnels: tunnels,
        defaultRoute: route,
        responders: responders,
        selfAddress: linkLocal,
        replyProbeFailed: replyFailed
    ))
}

public func tunnels(from interfaces: [InterfaceFact]) -> [TunnelFact] {
    interfaces.filter { isTunnelInterface($0.name) && !$0.globals.isEmpty }.map {
        TunnelFact(name: $0.name, address: $0.globals[0])
    }
}

private func vpnDisplayNames(services: [NetworkService], tunnels: [TunnelFact]) -> [String] {
    guard !tunnels.isEmpty else { return [] }
    let named = services.filter { $0.enabled && isVpnServiceName($0.name) }.map(\.name)
    if !named.isEmpty { return named }
    return tunnels.map(\.name)
}

private func areUp(_ names: [String]) -> String {
    if names.count == 1 { return "\(names[0]) is up" }
    if names.count == 2 { return "\(names[0]) and \(names[1]) are up" }
    let head = names.dropLast().joined(separator: ", ")
    return "\(head), and \(names.last ?? "") are up"
}

private func vpnLead(_ names: [String], route: String) -> String {
    if names.count == 1, names[0] == route {
        return "\(names[0]) is up and owns the default route"
    }
    return "\(areUp(names)) and \(route) owns the default route"
}

private func closed(word: String, tone: StatusTone, sentence: String, vpnNames: [String]) -> BridgeDiagnosis {
    BridgeDiagnosis(word: word, tone: tone, sentence: sentence, vpnNames: vpnNames, peerSeen: false, bridgeReady: false)
}

private func sameLinkLocal(_ lhs: String, _ rhs: String?) -> Bool {
    guard let rhs else { return false }
    func bare(_ value: String) -> String {
        value.split(separator: "%").first.map { $0.lowercased() } ?? value.lowercased()
    }
    return bare(lhs) == bare(rhs)
}

private func isGlobalIPv4(_ address: String) -> Bool {
    !address.isEmpty && !address.hasPrefix("169.254.") && !address.hasPrefix("127.")
}

private func isGlobalIPv6(_ address: String) -> Bool {
    let lower = address.lowercased()
    return !lower.isEmpty && !lower.hasPrefix("fe80:") && lower != "::1"
}

private func readBounded(_ path: String, arguments: [String] = [], seconds: Double = 5) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    do {
        try process.run()
    } catch {
        return nil
    }
    if done.wait(timeout: .now() + seconds) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if data.isEmpty && process.terminationStatus != 0 { return nil }
    return String(decoding: data, as: UTF8.self)
}

private func runTool(_ path: String, _ args: [String]) -> String? {
    readBounded(path, arguments: args)
}
