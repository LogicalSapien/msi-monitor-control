import XCTest
@testable import MSIControl

final class CommandTests: XCTestCase {

    // MARK: - All cases exist

    func testAllCommandsExist() {
        // 10 monitor commands + showLauncher (UI action) = 11.
        XCTAssertEqual(Command.allCases.count, 11)
    }

    // MARK: - showLauncher (UI action, not a HID command)

    func testShowLauncherIsNonMonitorAction() {
        XCTAssertFalse(Command.showLauncher.isMonitorCommand)
        XCTAssertNil(Command.showLauncher.payload, "showLauncher sends no HID report")
        XCTAssertTrue(Command.showLauncher.isAvailable, "UI action is always available")
        XCTAssertNil(Command.showLauncher.group, "no monitor-state group")
        XCTAssertEqual(Command.showLauncher.defaultKey, "Space")
        XCTAssertEqual(Command.showLauncher.actionId, "showLauncher")
    }

    func testAllOtherCommandsAreMonitorCommands() {
        for c in Command.allCases where c != .showLauncher {
            XCTAssertTrue(c.isMonitorCommand, "\(c) should be a monitor command")
        }
    }

    /// Input → HDMI 1: feature 0x35 0x30, value 0x30 (hardware-confirmed v0.2.2).
    func testInputHDMI1PayloadMatchesProtocol() {
        XCTAssertEqual(Command.inputHDMI1.payload,
                       Command.makePayload(featHi: 0x35, featLo: 0x30, value: 0x30))
        XCTAssertEqual(Command.inputHDMI1.payload?[10], 0x30)
    }

    /// Input → HDMI 2: feature 0x35 0x30, value 0x31.
    func testInputHDMI2PayloadMatchesProtocol() {
        XCTAssertEqual(Command.inputHDMI2.payload?[10], 0x31)
        XCTAssertEqual(Command.inputHDMI2.payload?[5], 0x35)
        XCTAssertEqual(Command.inputHDMI2.payload?[6], 0x30)
    }

    // MARK: - PBP/PIP mode payloads (feature 0x36 0x30, hardware-confirmed v0.2.2)

    func testPBPModePayloadsMatchProtocol() {
        // Off=0x30, PIP=0x31, PBP=0x32; all feature 0x36 0x30.
        XCTAssertEqual(Command.pbpOff.payload, Command.makePayload(featHi: 0x36, featLo: 0x30, value: 0x30))
        XCTAssertEqual(Command.pbpPIP.payload, Command.makePayload(featHi: 0x36, featLo: 0x30, value: 0x31))
        XCTAssertEqual(Command.pbpOn.payload,  Command.makePayload(featHi: 0x36, featLo: 0x30, value: 0x32))
        for c in [Command.pbpOff, .pbpPIP, .pbpOn] {
            XCTAssertEqual(c.payload?[5], 0x36)
            XCTAssertEqual(c.payload?[6], 0x30)
        }
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

    // (As of v0.2.2 there are no nil-payload / unknown commands — PBP modes are
    // hardware-confirmed, tested above in testPBPModePayloadsMatchProtocol.)

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

    func testMonitorPayloadsAre53Bytes() {
        // Every MONITOR command has a hardware-confirmed 53-byte payload
        // (showLauncher is a UI action with no payload — excluded).
        for command in Command.allCases where command.isMonitorCommand {
            XCTAssertEqual(command.payload?.count, 53,
                           "\(command) payload must be 53 bytes (report ID + 52 data bytes)")
        }
    }

    // MARK: - Availability (every command is available in v0.2.2)

    func testAllCommandsAreAvailable() {
        for command in Command.allCases {
            XCTAssertTrue(command.isAvailable, "\(command) should be available in v0.2.2")
        }
    }

    // MARK: - Default hotkey key (seed for the default config)

    func testInputDefaultKeys() {
        XCTAssertEqual(Command.inputHDMI1.defaultKey, "H")
        XCTAssertEqual(Command.inputHDMI2.defaultKey, "J")
        XCTAssertEqual(Command.inputTypeC.defaultKey, "C")
        XCTAssertEqual(Command.inputDP.defaultKey, "D")
    }

    func testKVMDefaultKeys() {
        XCTAssertEqual(Command.kvmUSBC.defaultKey, "K")
        XCTAssertEqual(Command.kvmUpstream.defaultKey, "U")
        XCTAssertEqual(Command.kvmAuto.defaultKey, "A")
    }

    func testPBPModeDefaultKeys() {
        // PBP/PIP modes ship WITH default chords (O/I/P) as of the v0.2.2 final call.
        XCTAssertEqual(Command.pbpOff.defaultKey, "O")
        XCTAssertEqual(Command.pbpPIP.defaultKey, "I")
        XCTAssertEqual(Command.pbpOn.defaultKey, "P")
    }

    // MARK: - Mutually-exclusive groups (for "current" tracking)

    func testCommandGroups() {
        for c in [Command.inputHDMI1, .inputHDMI2, .inputTypeC, .inputDP] {
            XCTAssertEqual(c.group, .input)
        }
        for c in [Command.kvmUSBC, .kvmUpstream, .kvmAuto] {
            XCTAssertEqual(c.group, .kvm)
        }
        for c in [Command.pbpOff, .pbpPIP, .pbpOn] {
            XCTAssertEqual(c.group, .pbpMode)
        }
    }

    // MARK: - Stable actionId (config contract, SETTINGS.md §3.6)

    func testActionIdsAreStableAndUnique() {
        let ids = Command.allCases.map(\.actionId)
        XCTAssertEqual(Set(ids).count, Command.allCases.count,
                       "actionIds must be unique across all commands")
        // Exact ids are a contract with the Windows app + the JSON schema.
        XCTAssertEqual(Command.inputHDMI1.actionId, "inputHDMI1")
        XCTAssertEqual(Command.inputHDMI2.actionId, "inputHDMI2")
        XCTAssertEqual(Command.inputTypeC.actionId, "inputTypeC")
        XCTAssertEqual(Command.inputDP.actionId, "inputDP")
        XCTAssertEqual(Command.kvmUSBC.actionId, "kvmUSBC")
        XCTAssertEqual(Command.kvmUpstream.actionId, "kvmUpstream")
        XCTAssertEqual(Command.kvmAuto.actionId, "kvmAuto")
        XCTAssertEqual(Command.pbpOff.actionId, "pbpOff")
        XCTAssertEqual(Command.pbpPIP.actionId, "pbpPIP")
        XCTAssertEqual(Command.pbpOn.actionId, "pbpOn")
        XCTAssertEqual(Command.showLauncher.actionId, "showLauncher")
    }

    /// The canonical serialisation order is a cross-app contract (SETTINGS.md §3.6).
    func testCanonicalActionOrder() {
        XCTAssertEqual(HotkeyConfig.canonicalActionOrder, [
            "inputHDMI1", "inputHDMI2", "inputTypeC", "inputDP",
            "kvmUSBC", "kvmUpstream", "kvmAuto",
            "pbpOff", "pbpPIP", "pbpOn",
            "showLauncher",
        ])
        // Every canonical id resolves to a real command, and vice versa.
        XCTAssertEqual(Set(HotkeyConfig.canonicalActionOrder),
                       Set(Command.allCases.map(\.actionId)))
    }

    func testFromActionIdRoundTrips() {
        for command in Command.allCases {
            XCTAssertEqual(Command.from(actionId: command.actionId), command)
        }
        XCTAssertNil(Command.from(actionId: "nonexistent"))
    }

    // MARK: - PBP source-select bytes (PROTOCOL.md § PBP)

    func testInputEnumRawValues() {
        XCTAssertEqual(InputEnum.hdmi1.rawValue, 0x30)
        XCTAssertEqual(InputEnum.hdmi2.rawValue, 0x31)
        XCTAssertEqual(InputEnum.displayPort.rawValue, 0x32)
        XCTAssertEqual(InputEnum.typeC.rawValue, 0x33)
    }

    func testPBPSourceFeatures() {
        // Sub = 0x36 0x31 (confirmed); Main = 0x36 0x32 (assumed, unverified).
        XCTAssertEqual(PBPWindow.sub.feature.hi, 0x36)
        XCTAssertEqual(PBPWindow.sub.feature.lo, 0x31)
        XCTAssertTrue(PBPWindow.sub.isVerified)
        XCTAssertEqual(PBPWindow.main.feature.hi, 0x36)
        XCTAssertEqual(PBPWindow.main.feature.lo, 0x32)
        XCTAssertFalse(PBPWindow.main.isVerified, "main-window source is assumed, not hardware-verified")
    }

    func testPBPSourcePayloadLayout() {
        // Sub-window source = HDMI2: feature 0x36 0x31, value 0x31.
        let p = Command.makePayload(featHi: PBPWindow.sub.feature.hi,
                                    featLo: PBPWindow.sub.feature.lo,
                                    value: InputEnum.hdmi2.rawValue)
        XCTAssertEqual(p.count, 53)
        XCTAssertEqual(p[5], 0x36)
        XCTAssertEqual(p[6], 0x31)
        XCTAssertEqual(p[10], 0x31)
        XCTAssertEqual(p[0], 0x01)   // report ID
        XCTAssertEqual(p[11], 0x0D)  // terminator
    }
}
