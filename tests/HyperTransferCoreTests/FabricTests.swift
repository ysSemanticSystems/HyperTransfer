import Foundation
@testable import HyperTransferCore

final class FabricTests {
    func testDiskPressureWords() {
        XCTAssertEqual(diskStatus(freeBytes: 4, totalBytes: 100).0, "Full")
        XCTAssertEqual(diskStatus(freeBytes: 4, totalBytes: 100).1, .down)
        XCTAssertEqual(diskStatus(freeBytes: 5, totalBytes: 100).0, "Tight")
        XCTAssertEqual(diskStatus(freeBytes: 14, totalBytes: 100).0, "Tight")
        XCTAssertEqual(diskStatus(freeBytes: 14, totalBytes: 100).1, .unreachable)
        XCTAssertEqual(diskStatus(freeBytes: 15, totalBytes: 100).0, "Place")
        XCTAssertEqual(diskStatus(freeBytes: 15, totalBytes: 100).1, .place)
        XCTAssertEqual(diskStatus(freeBytes: 0, totalBytes: 0).0, "Place")
    }

    func testDiskStatusUsesIntegerBounds() {
        XCTAssertEqual(diskStatus(freeBytes: 1, totalBytes: 20).0, "Tight")
        XCTAssertEqual(diskStatus(freeBytes: 1, totalBytes: 21).0, "Full")
    }

    func testDiskSpaceNamesThisVolume() throws {
        try withTemp { root in
            let report = diskSpace(at: root)
            XCTAssertNotNil(report.freeBytes)
            XCTAssertTrue(report.detail.contains("this volume"))
            XCTAssertTrue(["Place", "Tight", "Full"].contains(report.word))
        }
    }

    func testThunderboltIPIsNotRDMA() {
        let ports = parseThunderbolt(connectedThunderbolt)
        let ip = ports.first { $0.transport == "thunderbolt-ip" }
        XCTAssertEqual(ip?.rdma, false)
        XCTAssertEqual(ip?.word, "Unreachable")
        XCTAssertEqual(ip?.tone, .unreachable)
        let cable = ports.first { $0.name == "thunderboltusb4_bus_1" }
        XCTAssertEqual(cable?.word, "Up")
        XCTAssertEqual(cable?.rdma, false)
        let report = buildReport(ports: ports, verbsLibrary: nil, disk: sampleDisk())
        XCTAssertFalse(report.rdmaActive)
        XCTAssertEqual(report.rdmaWord, "Unreachable")
    }

    func testUnknownThunderboltProtocolIsNotRDMA() {
        let ports = parseThunderbolt(connectedThunderbolt)
        let unknown = ports.first { $0.transport == "thunderbolt-unknown" }
        XCTAssertEqual(unknown?.rdma, false)
        XCTAssertTrue(unknown?.detail.contains("64087") == true)
        XCTAssertTrue(unknown?.detail.contains("not InfiniBand, RoCE, or iWARP") == true)
    }

    func testEmptyThunderboltBusIsDown() {
        let ports = parseThunderbolt(connectedThunderbolt)
        let empty = ports.first { $0.name == "thunderboltusb4_bus_2" }
        XCTAssertEqual(empty?.state, "down")
        XCTAssertEqual(empty?.rdma, false)
        XCTAssertEqual(empty?.word, "Down")
    }

    func testMalformedThunderboltJSONFailsClosed() {
        let ports = parseThunderbolt(Data("not-json".utf8))
        XCTAssertEqual(ports.count, 1)
        XCTAssertFalse(ports[0].rdma)
        XCTAssertEqual(ports[0].word, "Down")
    }

    func testRoCEActiveIsUp() {
        let port = classifyVerbsPort(name: "mlx5_0/1", linkLayer: "Ethernet\n", state: "4: ACTIVE\n", driver: "mlx5_core", sysfsPath: "/sys/class/infiniband/mlx5_0")
        XCTAssertEqual(port.transport, "roce")
        XCTAssertTrue(port.rdma)
        XCTAssertEqual(port.word, "Up")
        XCTAssertTrue(port.detail.lowercased().contains("retransmit"))
    }

    func testStateFortyIsNotActive() {
        XCTAssertFalse(portIsActive("40: ACTIVE"))
        XCTAssertTrue(portIsActive("4: ACTIVE"))
        XCTAssertTrue(portIsActive("4:ACTIVE"))
        XCTAssertFalse(portIsActive("5: ACTIVE_DEFER"))
        let port = classifyVerbsPort(name: "mlx5_0/1", linkLayer: "Ethernet", state: "5: ACTIVE_DEFER", driver: "mlx5_core", sysfsPath: "/sys/class/infiniband/mlx5_0")
        XCTAssertFalse(port.rdma)
        XCTAssertEqual(port.word, "Down")
    }

    func testIWARPActiveIsUp() {
        let port = classifyVerbsPort(name: "siw0/1", linkLayer: "Ethernet", state: "4: ACTIVE", driver: "SIW", sysfsPath: "/sys/class/infiniband/siw0")
        XCTAssertEqual(port.transport, "iwarp")
        XCTAssertTrue(port.rdma)
        XCTAssertTrue(port.detail.contains("TCP"))
    }

    func testInfiniBandDownIsNotActive() {
        let port = classifyVerbsPort(name: "mlx5_0/1", linkLayer: "InfiniBand", state: "1: DOWN", driver: "mlx5_core", sysfsPath: "/sys/class/infiniband/mlx5_0")
        XCTAssertEqual(port.transport, "infiniband")
        XCTAssertFalse(port.rdma)
        XCTAssertEqual(port.word, "Down")
        XCTAssertTrue(port.detail.contains("subnet manager"))
    }

    func testEFAIsRDMAAndNotCalledRoCE() {
        let port = classifyVerbsPort(name: "efa0/1", linkLayer: "Ethernet", state: "4: ACTIVE", driver: "efa", sysfsPath: "/sys/class/infiniband/efa0")
        XCTAssertEqual(port.transport, "efa")
        XCTAssertNotEqual(port.transport, "roce")
        XCTAssertTrue(port.rdma)
    }

    func testUnreadableEthernetDriverIsNotLabeledRoCE() {
        let port = classifyVerbsPort(name: "mystery0/1", linkLayer: "Ethernet", state: "4: ACTIVE", driver: "", sysfsPath: "/sys/class/infiniband/mystery0")
        XCTAssertEqual(port.transport, "ethernet-rdma")
        XCTAssertTrue(port.rdma)
        XCTAssertTrue(port.detail.contains("not labeled RoCE or iWARP"))
    }

    func testThunderboltSysfsActiveIsRDMA() {
        let port = classifyVerbsPort(name: "tb0/1", linkLayer: "Ethernet", state: "4: ACTIVE", driver: "mlx5_core", sysfsPath: "/sys/devices/thunderbolt/tb0")
        XCTAssertEqual(port.transport, "thunderbolt")
        XCTAssertTrue(port.rdma)
        XCTAssertEqual(port.word, "Up")
    }

    func testActiveRoCEStaysUpBesideThunderboltIP() {
        let roce = classifyVerbsPort(name: "mlx5_0/1", linkLayer: "Ethernet", state: "4: ACTIVE", driver: "mlx5_core", sysfsPath: "/sys/class/infiniband/mlx5_0")
        let ports = parseThunderbolt(connectedThunderbolt) + [roce]
        let report = buildReport(ports: ports, verbsLibrary: "/usr/lib/libibverbs.so.1", disk: sampleDisk())
        XCTAssertTrue(report.rdmaActive)
        XCTAssertEqual(report.rdmaWord, "Up")
        let ip = report.ports.first { $0.transport == "thunderbolt-ip" }
        XCTAssertEqual(ip?.rdma, false)
    }

    func testSysfsReadsAnActiveRoCEPort() throws {
        try withTemp { root in
            let port = root.appendingPathComponent("class/infiniband/mlx5_0/ports/1", isDirectory: true)
            try FileManager.default.createDirectory(at: port, withIntermediateDirectories: true)
            try "4: ACTIVE\n".write(to: port.appendingPathComponent("state"), atomically: true, encoding: .utf8)
            try "Ethernet\n".write(to: port.appendingPathComponent("link_layer"), atomically: true, encoding: .utf8)
            let driver = root.appendingPathComponent("drivers/mlx5_core", isDirectory: true)
            try FileManager.default.createDirectory(at: driver, withIntermediateDirectories: true)
            let device = root.appendingPathComponent("class/infiniband/mlx5_0/device", isDirectory: true)
            try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: device.appendingPathComponent("driver"), withDestinationURL: driver)
            let found = readLinuxSysfs(at: root)
            XCTAssertEqual(found.count, 1)
            XCTAssertEqual(found[0].transport, "roce")
            XCTAssertTrue(found[0].rdma)
        }
    }

    func testAppleThunderboltActiveIsRDMA() {
        let ports = parseIbvDevinfo(appleDevinfo)
        let active = ports.first { $0.name == "rdma_en3/1" }
        XCTAssertEqual(active?.transport, "thunderbolt")
        XCTAssertEqual(active?.word, "Up")
        XCTAssertEqual(active?.state, "active")
        XCTAssertEqual(active?.rdma, true)
        XCTAssertTrue(active?.detail.contains("ACTIVE") == true)
    }

    func testAppleThunderboltDownIsNotRDMA() {
        let ports = parseIbvDevinfo(appleDevinfo)
        let down = ports.first { $0.name == "rdma_en2/1" }
        XCTAssertEqual(down?.word, "Down")
        XCTAssertEqual(down?.rdma, false)
        XCTAssertEqual(down?.state, "down")
    }

    func testActiveDeferIsNotActive() {
        let ports = parseIbvDevinfo("hca_id: rdma_en9\ntransport: Thunderbolt (100)\nport: 1\nstate: PORT_ACTIVE_DEFER (5)\nlink_layer: Thunderbolt\n")
        XCTAssertEqual(ports.count, 1)
        XCTAssertFalse(ports[0].rdma)
        XCTAssertEqual(ports[0].word, "Down")
        XCTAssertEqual(verbsStateCode("PORT_ACTIVE_DEFER (5)"), 5)
    }

    func testParentheticalStateFortyIsNotActive() {
        let ports = parseIbvDevinfo("hca_id: rdma_en9\ntransport: Thunderbolt (100)\nport: 1\nstate: PORT_ACTIVE (40)\nlink_layer: Thunderbolt\n")
        XCTAssertEqual(ports.count, 1)
        XCTAssertFalse(ports[0].rdma)
        XCTAssertEqual(ports[0].word, "Down")
        XCTAssertNil(verbsStateCode("PORT_ACTIVE (40)").flatMap { $0 == 4 ? 4 : nil })
        XCTAssertEqual(verbsStateCode("PORT_ACTIVE (4)"), 4)
        XCTAssertEqual(verbsStateCode("4: ACTIVE"), 4)
        XCTAssertEqual(verbsStateCode("40: ACTIVE"), 40)
    }

    func testThunderboltIPStaysClosedBesideActiveVerbs() {
        var ports = parseThunderbolt(connectedThunderbolt) + parseIbvDevinfo(appleDevinfo)
        ports.append(verbsPort(library: "librdma"))
        let report = buildReport(ports: ports, verbsLibrary: "librdma", disk: sampleDisk())
        XCTAssertTrue(report.rdmaActive)
        XCTAssertEqual(report.rdmaWord, "Up")
        let ip = report.ports.first { $0.transport == "thunderbolt-ip" }
        XCTAssertEqual(ip?.rdma, false)
        XCTAssertEqual(ip?.word, "Unreachable")
        let unknown = report.ports.first { $0.transport == "thunderbolt-unknown" }
        XCTAssertEqual(unknown?.rdma, false)
        let library = report.ports.first { $0.name == "librdma" }
        XCTAssertEqual(library?.word, "Place")
        XCTAssertEqual(library?.rdma, false)
    }

    func testThisMacProbeSeesActiveThunderboltVerbs() {
        let report = probeMachine()
        XCTAssertTrue(report.rdmaActive)
        XCTAssertEqual(report.rdmaWord, "Up")
        XCTAssertNotNil(report.ports.first { $0.rdma && $0.state == "active" && $0.transport == "thunderbolt" })
        for port in report.ports where port.transport == "thunderbolt-ip" {
            XCTAssertFalse(port.rdma)
            XCTAssertEqual(port.word, "Unreachable")
        }
        for port in report.ports where port.transport == "thunderbolt-unknown" {
            XCTAssertFalse(port.rdma)
        }
        let library = report.ports.first { $0.name == "librdma" }
        XCTAssertEqual(library?.word, "Place")
        XCTAssertEqual(library?.rdma, false)
    }

    func testVerbsDeviceOpensOnThisMac() {
        let report = probeMachine()
        let device = activeVerbsDevice(report)
        XCTAssertNotNil(device)
        XCTAssertTrue(verbsQueuePairOpens(device: device ?? ""))
    }
}

private let appleDevinfo = """
hca_id:	rdma_en2
	transport:			Thunderbolt (100)
		port:	1
			state:			PORT_DOWN (1)
			link_layer:		Thunderbolt
hca_id:	rdma_en3
	transport:			Thunderbolt (100)
		port:	1
			state:			PORT_ACTIVE (4)
			link_layer:		Thunderbolt
"""
