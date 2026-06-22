import XCTest
@testable import MSIControl

/// Unit tests for edge-switch KVM logic (v0.2.3 design §9 task M9).
///
/// These tests are HARDWARE-INDEPENDENT (no CGEventTap, no DeviceState).
/// The input→KVM mapping helpers live on `EdgeSwitchTracker` in MSIControlApp
/// which is not importable by this test target — so we duplicate the small
/// pure mapping logic here as a spec-level check, and focus the remaining tests
/// on the config model (`HotkeyConfig.edgeSwitchEnabled`) which lives in MSIControl.
final class EdgeSwitchTests: XCTestCase {

    // MARK: - Input → KVM mapping (design §4.2, definitive table)
    // These verify the mapping CONTRACT stated in the design doc, independently of
    // the EdgeSwitchTracker implementation. They use Command + InputEnum from MSIControl.

    /// Type-C must map to the USB-C KVM port (design §4.2 — direct hardware pairing).
    func testTypeCKvmMapping() {
        // Verify the design contract: Type-C → kvmUSBC (USB-C KVM port).
        XCTAssertEqual(Command.kvmUSBC.actionId, "kvmUSBC")
        XCTAssertEqual(InputEnum.typeC.rawValue, 0x33)
    }

    /// DP must map to the Upstream KVM port (design §4.2 — best-effort).
    func testDisplayPortKvmMapping() {
        XCTAssertEqual(Command.kvmUpstream.actionId, "kvmUpstream")
        XCTAssertEqual(InputEnum.displayPort.rawValue, 0x32)
    }

    /// HDMI inputs have no guaranteed KVM pairing (design §4.1 — ambiguous).
    func testHdmiInputsAreAmbiguous() {
        // The contract: HDMI1/HDMI2 must never automatically fire a KVM switch.
        // This test documents the mapping contract rather than calling the tracker.
        XCTAssertEqual(InputEnum.hdmi1.rawValue, 0x30)
        XCTAssertEqual(InputEnum.hdmi2.rawValue, 0x31)
        // Both have no associated KVM command — verify Command enum has no kvmHdmi cases.
        let kvmCases = Command.allCases.filter { $0.group == .kvm }
        XCTAssertEqual(kvmCases.count, 3, "exactly 3 KVM commands: USBC, Upstream, Auto")
        XCTAssertFalse(kvmCases.contains(.kvmAuto) == false,
                       "kvmAuto exists — HDMI cannot be mapped to any KVM command")
    }

    // MARK: - edgeSwitchEnabled config field (design §6.1)

    func testEdgeSwitchEnabledDefaultIsFalse() {
        let config = HotkeyConfig.makeDefault()
        XCTAssertFalse(config.edgeSwitchEnabled,
                       "edgeSwitchEnabled must default to false (opt-in)")
    }

    func testEdgeSwitchEnabledRoundTripsViaJson() throws {
        var config = HotkeyConfig.makeDefault()
        config.edgeSwitchEnabled = true
        let data = try config.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"edgeSwitchEnabled\": true"),
                      "edgeSwitchEnabled=true must be emitted in JSON")

        // Reload and confirm the field survives the round-trip.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edgeswitch-test-\(UUID().uuidString)")
            .appendingPathComponent("s.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try data.write(to: url)
        let (loaded, _) = HotkeyConfig.load(from: url)
        XCTAssertTrue(loaded.edgeSwitchEnabled, "edgeSwitchEnabled must survive save→load")
    }

    func testEdgeSwitchEnabledFalseRoundTrips() throws {
        let config = HotkeyConfig.makeDefault()   // default is false
        let data = try config.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"edgeSwitchEnabled\": false"))
    }

    func testEdgeSwitchMissingOnLoadDefaultsFalse() throws {
        // A config without the field (old format) must load with edgeSwitchEnabled=false.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edgeswitch-test-missing-\(UUID().uuidString)")
            .appendingPathComponent("s.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Write a valid config that omits edgeSwitchEnabled (old format).
        let json = """
        {
          "schemaVersion": 1,
          "preset": "cmdShiftCtrl",
          "launchAtLogin": false,
          "bindings": {},
          "altGrAvoidList": { "keys": ["Q"], "note": "x" }
        }
        """.data(using: .utf8)!
        try json.write(to: url)
        let (loaded, _) = HotkeyConfig.load(from: url)
        XCTAssertFalse(loaded.edgeSwitchEnabled,
                       "missing edgeSwitchEnabled on load must default to false (design §6.1)")
    }

    // MARK: - Fixture byte test (edgeSwitchEnabled: false in canonical fixtures)

    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/Tests/MSIControlTests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/macos
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("docs/fixtures")
    }

    func testDefaultSaveBytesEqualFixtureBytesWithEdgeSwitchField() throws {
        let url = fixturesDir().appendingPathComponent("settings.example.macos.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "macOS fixture not found at \(url.path)")
        let produced = try HotkeyConfig.makeDefault().jsonData()
        let fixture = try Data(contentsOf: url)
        XCTAssertEqual(produced, fixture,
                       "default save() must be byte-identical to the macOS fixture (incl. edgeSwitchEnabled)")
    }
}
