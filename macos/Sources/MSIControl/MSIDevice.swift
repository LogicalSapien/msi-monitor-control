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

    private var manager: IOHIDManager?
    private var hidDevice: IOHIDDevice?

    /// Whether the MD342CQP is currently connected and open.
    public private(set) var isConnected: Bool = false

    // MARK: Init / deinit

    public init() {
        openDevice()
    }

    deinit {
        closeDevice()
    }

    // MARK: - HID device discovery

    private func openDevice() {
        // Release any previously held device/manager before re-opening.
        closeDevice()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [String: Any] = [
            kIOHIDVendorIDKey:  MSIDevice.vendorID,
            kIOHIDProductIDKey: MSIDevice.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // Schedule on the current run loop BEFORE copying devices. Per Apple's
        // IOHIDManager docs, `IOHIDManagerCopyDevices` can return an empty set if
        // the manager has not been scheduled, even when a matching device is
        // connected — which would make the app intermittently fail to find the
        // monitor. Scheduling makes enumeration reliable.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Open the manager so it can enumerate devices.
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            closeDevice()
            return
        }

        // Enumerate currently connected devices.
        guard let cfSet = IOHIDManagerCopyDevices(manager) else {
            return
        }

        // Bridge the CFSet to a Swift Set via NSSet and take the first element.
        // We compare CFTypeIDs rather than force-casting: `anyObject()` returns
        // `Any?`, and a force-cast (`as!`) would crash if it were ever not an
        // IOHIDDevice. The CFTypeID check is the safe CoreFoundation idiom.
        let nsSet = cfSet as NSSet
        guard let object = nsSet.anyObject() else { return }
        let candidate = object as CFTypeRef
        guard CFGetTypeID(candidate) == IOHIDDeviceGetTypeID() else { return }
        let device = unsafeDowncast(candidate as AnyObject, to: IOHIDDevice.self)

        // Open the individual device.
        let deviceOpenResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceOpenResult == kIOReturnSuccess else {
            return
        }

        hidDevice = device
        isConnected = true
    }

    /// Closes the open device and manager, releasing the kernel-side USB claim.
    private func closeDevice() {
        if let device = hidDevice {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            hidDevice = nil
        }
        if let manager = manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        isConnected = false
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

        // TODO(verify-on-hardware): report ID may be double-counted — byte[0]
        // (0x01) is passed both as the reportID argument AND as the first byte of
        // the buffer. Depending on how IOKit strips the report ID, the monitor may
        // receive it twice. This mirrors the reference implementation
        // (Phaseowner/MSI-Display-Switch) which works on the MD342CQP, so we keep
        // it as-is until confirmed via a USB HID capture on real hardware.
        // See docs/PROTOCOL.md § "Reverse-engineering notes".
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
