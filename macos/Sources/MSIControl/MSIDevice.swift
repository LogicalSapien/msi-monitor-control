import Foundation
import IOKit.hid

// MARK: - Error type

/// Errors that can be returned when sending a command to the monitor.
public enum MSIError: Error, Equatable {
    /// No MD342CQP device was found on the USB bus.
    case deviceNotFound
    /// The HID send call returned a non-zero IOReturn code.
    case sendFailed(String)
    /// The command's payload is unknown (not yet reverse-engineered).
    case payloadUnavailable
}

// MARK: - Device

/// Manages the HID connection to an MSI MD342CQP monitor.
///
/// Uses `IOHIDManager` to match the monitor by its USB VID/PID
/// (`0x1462` / `0x3FA4` — from `docs/PROTOCOL.md`).
public final class MSIDevice {

    // MARK: Constants (from docs/PROTOCOL.md)
    private static let vendorID:  Int = 0x1462
    private static let productID: Int = 0x3FA4

    // MARK: State

    private var hidDevice: IOHIDDevice?

    /// Whether the MD342CQP is currently connected and open.
    public private(set) var isConnected: Bool = false

    // MARK: Init

    public init() {
        openDevice()
    }

    // MARK: - HID device discovery

    private func openDevice() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDVendorIDKey:  MSIDevice.vendorID,
            kIOHIDProductIDKey: MSIDevice.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // Open the manager so it can enumerate devices.
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { return }

        // Enumerate currently connected devices.
        guard let cfSet = IOHIDManagerCopyDevices(manager) else { return }

        // Bridge the CFSet to a Swift Set via NSSet.
        let nsSet = cfSet as NSSet
        guard let device = nsSet.anyObject() as! IOHIDDevice? else { return }

        // Open the individual device.
        let deviceOpenResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceOpenResult == kIOReturnSuccess else { return }

        hidDevice = device
        isConnected = true
    }

    // MARK: - Send

    /// Sends a command to the monitor.
    ///
    /// - Returns: `.success(())` on success; `.failure(.deviceNotFound)` if no
    ///   monitor is connected; `.failure(.payloadUnavailable)` if the command's
    ///   payload is not yet known; `.failure(.sendFailed(_))` on IOKit error.
    @discardableResult
    public func send(_ command: Command) -> Result<Void, MSIError> {
        guard isConnected, let device = hidDevice else {
            return .failure(.deviceNotFound)
        }

        guard let bytes = command.payload else {
            return .failure(.payloadUnavailable)
        }

        let reportID = CFIndex(bytes[0])
        let ret = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            reportID,
            bytes,
            bytes.count
        )

        if ret == kIOReturnSuccess {
            return .success(())
        } else {
            return .failure(.sendFailed("IOReturn 0x\(String(ret, radix: 16))"))
        }
    }
}
