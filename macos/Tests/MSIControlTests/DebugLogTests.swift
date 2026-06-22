import XCTest
@testable import MSIControl

/// Tests for the debug log path + level formatting. We do NOT call `start()` (it
/// installs process-wide signal/exception handlers and opens the real app-support
/// file), only the pure, side-effect-free surface.
final class DebugLogTests: XCTestCase {

    func testDefaultURLIsVendorNestedBesideSettings() throws {
        let logURL = try DebugLog.defaultURL()
        let settingsURL = try HotkeyConfig.defaultURL()
        XCTAssertEqual(logURL.lastPathComponent, "debug.log")
        // Same directory as settings.json (…/LogicalSapien/MSIMonitorControl/).
        XCTAssertEqual(logURL.deletingLastPathComponent(),
                       settingsURL.deletingLastPathComponent())
        XCTAssertEqual(logURL.deletingLastPathComponent().lastPathComponent, "MSIMonitorControl")
        XCTAssertEqual(logURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
                       "LogicalSapien")
    }

    func testLevelRawValues() {
        // The file format depends on these strings — guard them.
        XCTAssertEqual(DebugLog.Level.info.rawValue, "INFO")
        XCTAssertEqual(DebugLog.Level.warn.rawValue, "WARN")
        XCTAssertEqual(DebugLog.Level.error.rawValue, "ERROR")
        XCTAssertEqual(DebugLog.Level.fatal.rawValue, "FATAL")
    }
}
