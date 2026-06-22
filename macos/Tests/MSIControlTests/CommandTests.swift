import XCTest
@testable import MSIControl

final class CommandTests: XCTestCase {

    // MARK: - All six cases exist

    func testAllSixCommandsExist() {
        XCTAssertEqual(Command.allCases.count, 6)
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

    // MARK: - Unknown payloads are nil (not invented)

    func testPBPOnPayloadIsNil() {
        XCTAssertNil(Command.pbpOn.payload,
                     "PBP On payload is unknown — must not ship invented bytes")
    }

    func testPBPOffPayloadIsNil() {
        XCTAssertNil(Command.pbpOff.payload,
                     "PBP Off payload is unknown — must not ship invented bytes")
    }

    func testKVMUSBCPayloadIsNil() {
        XCTAssertNil(Command.kvmUSBC.payload,
                     "KVM USB-C payload is unknown — must not ship invented bytes")
    }

    func testKVMUpstreamPayloadIsNil() {
        XCTAssertNil(Command.kvmUpstream.payload,
                     "KVM Upstream payload is unknown — must not ship invented bytes")
    }

    // MARK: - Payload length invariant for known commands

    func testKnownPayloadsAre53Bytes() {
        let knownCommands: [Command] = [.inputTypeC, .inputDP]
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

    func testPBPOnIsUnavailable() {
        XCTAssertFalse(Command.pbpOn.isAvailable)
    }

    func testKVMUSBCIsUnavailable() {
        XCTAssertFalse(Command.kvmUSBC.isAvailable)
    }
}
