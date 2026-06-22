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
/// (`0x1462` / `0x3FA4` — from `docs/PROTOCOL.md`) and sends commands as HID
/// output reports via `IOHIDDeviceSetReport`.
///
/// ## Why `send` re-opens on demand
///
/// The device handle's open state is maintained by the IOHIDManager, which is
/// scheduled on a run loop. In a SwiftUI `MenuBarExtra` app the device is created
/// during early app initialisation, on whatever run-loop/thread context happens to
/// be current then — which is not guaranteed to be the same, continuously-serviced
/// run loop that menu actions later fire on. When that scheduling run loop is not
/// being serviced, the kernel can let the device handle drop back to *not open*,
/// so a later `SetReport` returns `kIOReturnNotOpen` (`0x10000003`) even though an
/// earlier send succeeded. This was observed on real hardware: input switching
/// worked once, then a subsequent KVM send failed with `NotOpen`.
///
/// The robust fix is to treat the handle as potentially stale and (re)open it at
/// send time, retrying once on a `NotOpen`/`NotPermitted` result. A standalone
/// script that opens the device and immediately sends in the same context works
/// reliably — this brings the app to the same footing for every send.
public final class MSIDevice {

    // MARK: Constants (from docs/PROTOCOL.md)
    private static let vendorID:  Int = 0x1462
    private static let productID: Int = 0x3FA4

    // MARK: State

    private var manager: IOHIDManager?
    private var hidDevice: IOHIDDevice?

    /// Whether a matching MD342CQP device has been located. (Open state is
    /// (re)established lazily at send time — see `send`.)
    public private(set) var isConnected: Bool = false

    // MARK: Init / deinit

    public init() {
        locateDevice()
    }

    deinit {
        closeDevice()
    }

    // MARK: - HID device discovery

    /// Locates the matching device (creating + opening the manager and finding the
    /// device reference) but does NOT assume the device stays open — `send` opens
    /// it on demand. Safe to call repeatedly.
    @discardableResult
    private func locateDevice() -> Bool {
        // Release any previously held device/manager before re-locating.
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
        // connected. Scheduling makes enumeration reliable.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            closeDevice()
            return false
        }

        guard let cfSet = IOHIDManagerCopyDevices(manager) else {
            return false
        }

        // Bridge the CFSet to a Swift Set via NSSet and take the first element.
        // We compare CFTypeIDs rather than force-casting: `anyObject()` returns
        // `Any?`, and a force-cast (`as!`) would crash if it were ever not an
        // IOHIDDevice. The CFTypeID check is the safe CoreFoundation idiom.
        let nsSet = cfSet as NSSet
        guard let object = nsSet.anyObject() else { return false }
        let candidate = object as CFTypeRef
        guard CFGetTypeID(candidate) == IOHIDDeviceGetTypeID() else { return false }
        let device = unsafeDowncast(candidate as AnyObject, to: IOHIDDevice.self)

        hidDevice = device
        isConnected = true

        // Open eagerly too — the common case (run loop still alive) then needs no
        // reopen. If the handle later goes stale, `send` reopens it.
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        return true
    }

    /// Ensures the located device handle is open. Returns the open IOReturn.
    /// Calling `IOHIDDeviceOpen` on an already-open device is a no-op that returns
    /// success, so this is safe to call before every send.
    private func ensureDeviceOpen() -> IOReturn {
        guard let device = hidDevice else { return kIOReturnNoDevice }
        return IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
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

    /// Sends a command to the monitor as a HID output report.
    ///
    /// Resilient to a stale device handle: if the handle is not currently located,
    /// the device is re-located first; if `IOHIDDeviceSetReport` returns
    /// `kIOReturnNotOpen`/`kIOReturnNotPermitted`, the device is re-located and the
    /// send is retried exactly once before reporting failure.
    ///
    /// - Returns: `.success(())` on success; `.failure(.deviceNotFound)` if no
    ///   monitor is connected; `.failure(.payloadUnavailable)` if the command's
    ///   payload is not yet known; `.failure(.sendFailed(_))` on IOKit error.
    @discardableResult
    public func send(_ command: Command) -> Result<Void, MSIError> {
        guard let bytes = command.payload else {
            return .failure(.payloadUnavailable)
        }

        // Locate the device if we do not currently hold a reference.
        if hidDevice == nil {
            locateDevice()
        }
        guard hidDevice != nil else {
            return .failure(.deviceNotFound)
        }

        // First attempt.
        var ret = attemptSend(bytes)
        if ret == kIOReturnSuccess {
            return .success(())
        }

        // If the handle was not open (or permission lapsed), re-locate the device
        // — which re-opens it — and retry exactly once. This recovers from the
        // run-loop-scheduling staleness described in the type doc.
        if ret == kIOReturnNotOpen || ret == kIOReturnNotPermitted {
            locateDevice()
            guard hidDevice != nil else {
                return .failure(.deviceNotFound)
            }
            ret = attemptSend(bytes)
            if ret == kIOReturnSuccess {
                return .success(())
            }
        }

        return .failure(.sendFailed("IOReturn 0x\(String(ret, radix: 16))"))
    }

    /// Ensures the device is open and performs a single `SetReport`. Returns the
    /// IOReturn from `SetReport` (or from `IOHIDDeviceOpen` if opening failed).
    private func attemptSend(_ bytes: [UInt8]) -> IOReturn {
        let openRet = ensureDeviceOpen()
        // If opening failed for a reason other than "already open", surface it so
        // the caller's retry logic can react (e.g. NotOpen → re-locate).
        if openRet != kIOReturnSuccess {
            return openRet
        }
        guard let device = hidDevice else { return kIOReturnNoDevice }

        // TODO(verify-on-hardware): report ID may be double-counted — byte[0]
        // (0x01) is passed both as the reportID argument AND as the first byte of
        // the buffer. This mirrors the reference implementation
        // (Phaseowner/MSI-Display-Switch) which works on the MD342CQP, so we keep
        // it as-is until confirmed via a USB HID capture on real hardware.
        // See docs/PROTOCOL.md § "Reverse-engineering notes".
        let reportID = CFIndex(bytes[0])
        return IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            reportID,
            bytes,
            bytes.count
        )
    }
}
