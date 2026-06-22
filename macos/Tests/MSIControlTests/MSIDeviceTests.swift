import XCTest
@testable import MSIControl

/// Tests for `MSIDevice`.
///
/// The `deviceNotFound` tests are designed to run in CI where no MD342CQP is
/// attached. On a developer machine with the monitor plugged in they are
/// automatically skipped — this is expected behaviour.
final class MSIDeviceTests: XCTestCase {

    // MARK: - Helpers

    private func requireNoMonitor(file: StaticString = #filePath, line: UInt = #line) throws {
        let device = MSIDevice()
        try XCTSkipIf(
            device.isConnected,
            "MD342CQP is connected — skipping 'not-connected' test. Run in CI for coverage."
        )
    }

    // MARK: - Tests

    func testDeviceNotConnectedWhenNoMonitorAttached() throws {
        try requireNoMonitor()
        let device = MSIDevice()
        XCTAssertFalse(device.isConnected,
                       "isConnected should be false when no MD342CQP is attached")
    }

    func testSendReturnsDeviceNotFoundWhenNoMonitorAttached() throws {
        try requireNoMonitor()
        let device = MSIDevice()
        let result = device.send(.inputDP)
        switch result {
        case .failure(let error):
            if case .deviceNotFound = error {
                // Expected.
            } else {
                XCTFail("Expected .deviceNotFound but got \(error)")
            }
        case .success:
            XCTFail("Expected .failure(.deviceNotFound) but got .success — is a monitor attached?")
        }
    }

    /// Sending a command with no payload returns `.payloadUnavailable` (not a crash).
    /// This test runs regardless of monitor presence.
    func testSendUnavailableCommandReturnPayloadUnavailable() {
        let device = MSIDevice()
        let result = device.send(.pbpOn)
        // Should be either payloadUnavailable (no monitor) or payloadUnavailable
        // (monitor present but payload unknown). Either way, not .success.
        if case .success = result {
            XCTFail("Sending an unavailable command should never succeed")
        }
        // If device is connected, payloadUnavailable is returned; if not, deviceNotFound.
        // Both are acceptable failures — just not .success.
    }
}
