import XCTest
@testable import MSIControl

final class CommandTests: XCTestCase {

    // MARK: - All cases exist

    func testAllCommandsExist() {
        // pbpOn, pbpOff, kvmUSBC, kvmUpstream, kvmAuto, inputTypeC, inputDP
        XCTAssertEqual(Command.allCases.count, 7)
    }

    // MARK: - Known payloads (from docs/PROTOCOL.md)

    /// Input → Type-C: byte[10] = 0x33
    func testInputTypeCPayloadMatchesProtocol() {
        let expected: [UInt8] = [
            0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        XCTAssertEqual(Command.inputTypeC.payload, expected)
    }

    /// Input → DisplayPort: byte[10] = 0x32
    func testInputDPPayloadMatchesProtocol() {
        let expected: [UInt8] = [
            0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        XCTAssertEqual(Command.inputDP.payload, expected)
    }

    // MARK: - KVM payloads (from kdar/msi-monitor-ctrl, feature 0x38 0x3E)

    /// KVM → USB-C: feature 0x38 0x3E, value 0x32 (hardware-confirmed via kvm-probe).
    func testKVMUSBCPayloadMatchesProtocol() {
        let expected: [UInt8] = [
            0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x32, 0x0D,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        XCTAssertEqual(Command.kvmUSBC.payload, expected)
    }

    /// KVM → Upstream: feature 0x38 0x3E, value 0x31 (position 1).
    func testKVMUpstreamPayloadMatchesProtocol() {
        let expected: [UInt8] = [
            0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x31, 0x0D,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        XCTAssertEqual(Command.kvmUpstream.payload, expected)
    }

    // MARK: - Unknown payloads are nil (not invented)

    func testPBPOnPayloadIsNil() {
        XCTAssertNil(Command.pbpOn.payload,
                     "PBP On payload is unknown — must not ship invented bytes")
    }

    func testPBPOffPayloadIsNil() {
        XCTAssertNil(Command.pbpOff.payload,
                     "PBP Off payload is unknown — must not ship invented bytes")
    }

    /// KVM → Auto: feature 0x38 0x3E, value 0x30 (hardware-confirmed via kvm-probe;
    /// was the long-UNKNOWN value, now known).
    func testKVMAutoPayloadMatchesProtocol() {
        let expected: [UInt8] = [
            0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        XCTAssertEqual(Command.kvmAuto.payload, expected)
    }

    // MARK: - Payload length invariant for known commands

    func testKnownPayloadsAre53Bytes() {
        let knownCommands: [Command] = [.inputTypeC, .inputDP, .kvmUSBC, .kvmUpstream, .kvmAuto]
        for command in knownCommands {
            XCTAssertEqual(command.payload?.count, 53,
                           "\(command) payload must be 53 bytes (report ID + 52 data bytes)")
        }
    }

    // MARK: - isAvailable reflects payload knowledge

    func testInputTypeCIsAvailable() {
        XCTAssertTrue(Command.inputTypeC.isAvailable)
    }

    func testInputDPIsAvailable() {
        XCTAssertTrue(Command.inputDP.isAvailable)
    }

    func testKVMUSBCIsAvailable() {
        XCTAssertTrue(Command.kvmUSBC.isAvailable)
    }

    func testKVMUpstreamIsAvailable() {
        XCTAssertTrue(Command.kvmUpstream.isAvailable)
    }

    func testPBPOnIsUnavailable() {
        XCTAssertFalse(Command.pbpOn.isAvailable)
    }

    func testPBPOffIsUnavailable() {
        XCTAssertFalse(Command.pbpOff.isAvailable)
    }

    func testKVMAutoIsAvailable() {
        // KVM Auto now has a hardware-confirmed payload (byte[10]=0x30), so it is a
        // normal available command (menu item + hotkey).
        XCTAssertTrue(Command.kvmAuto.isAvailable)
    }

    // MARK: - Default hotkey key (seed for the default config)

    func testKVMAutoDefaultKeyIsA() {
        XCTAssertEqual(Command.kvmAuto.defaultKey, "A")
    }

    func testInputTypeCDefaultKeyIsC() {
        XCTAssertEqual(Command.inputTypeC.defaultKey, "C")
    }

    // MARK: - Stable actionId (config contract, SETTINGS.md §3.6)

    func testActionIdsAreStableAndUnique() {
        let ids = Command.allCases.map(\.actionId)
        XCTAssertEqual(Set(ids).count, Command.allCases.count,
                       "actionIds must be unique across all commands")
        // Exact ids are a contract with the Windows app + the JSON schema.
        XCTAssertEqual(Command.inputTypeC.actionId, "inputTypeC")
        XCTAssertEqual(Command.inputDP.actionId, "inputDP")
        XCTAssertEqual(Command.kvmUSBC.actionId, "kvmUSBC")
        XCTAssertEqual(Command.kvmUpstream.actionId, "kvmUpstream")
        XCTAssertEqual(Command.kvmAuto.actionId, "kvmAuto")
        XCTAssertEqual(Command.pbpOn.actionId, "pbpOn")
        XCTAssertEqual(Command.pbpOff.actionId, "pbpOff")
    }

    func testFromActionIdRoundTrips() {
        for command in Command.allCases {
            XCTAssertEqual(Command.from(actionId: command.actionId), command)
        }
        XCTAssertNil(Command.from(actionId: "nonexistent"))
    }
}
