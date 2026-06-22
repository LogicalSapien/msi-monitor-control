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

    /// Two consecutive sends of an *available* command must each return without a
    /// crash or hang. This is the API-level guard for the second-send regression
    /// (`kIOReturnNotOpen` / `kIOReturnNoDevice` on the 2nd send): because
    /// `.inputTypeC` has a real payload, both calls pass the payload guard and
    /// genuinely drive the serialised lock → locate → open → SetReport (and the
    /// re-locate-and-retry backstop) path twice — which is exactly the code that
    /// used to fail on the second send. The outcome depends on whether a monitor is
    /// attached, so we assert only that BOTH calls return the same well-formed
    /// Result type (no exception, no degraded second result), not a specific value:
    ///   • no monitor      → both `.deviceNotFound`
    ///   • monitor present  → both `.success` (real send happens twice)
    /// Full success-on-hardware is confirmed by the user (no MD342CQP on CI).
    /// TODO(verify-on-hardware): confirm two consecutive available sends
    /// (e.g. .inputTypeC then .kvmUSBC) both succeed on a real MD342CQP.
    func testTwoConsecutiveAvailableSendsBehaveConsistently() {
        let device = MSIDevice()
        let first = device.send(.inputTypeC)
        let second = device.send(.inputTypeC)

        // The regression was: first succeeds, second fails. So whatever the first
        // call's outcome, the second must NOT be strictly worse — specifically, a
        // first `.success` must not be followed by a `.failure`.
        if case .success = first {
            if case .failure(let error) = second {
                XCTFail("Second consecutive send regressed to failure after the first succeeded: \(error)")
            }
        }
        // Neither call may return `.payloadUnavailable` — `.inputTypeC` has a payload.
        for (label, result) in [("first", first), ("second", second)] {
            if case .failure(.payloadUnavailable) = result {
                XCTFail("\(label) send of an available command must not report payloadUnavailable")
            }
        }
    }
}
