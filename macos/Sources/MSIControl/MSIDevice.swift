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
/// ## Open lifecycle — why the IOHIDManager is discovery-only
///
/// Earlier versions kept an `IOHIDManager` open for the lifetime of the device and
/// relied on it to hold the device's open claim. The manager is scheduled on a run
/// loop, and in a SwiftUI `MenuBarExtra` app it was created during early app
/// initialisation on whatever run-loop/thread context happened to be current then —
/// not the continuously-serviced run loop that menu actions later fire on. When the
/// manager's scheduling run loop was not being serviced, the kernel let the device
/// handle drop back to *not open*, so the SECOND `SetReport` returned
/// `kIOReturnNotOpen` (`0x10000003`) even though the first send had succeeded. This
/// reproduced reliably on real hardware: one input switch worked, the next failed.
///
/// The fix is to stop tying the open lifecycle to the manager at all. We use the
/// manager ONLY to enumerate (match VID/PID and copy the device set), then close
/// and unschedule it immediately. We own the located `IOHIDDevice` directly,
/// open it ourselves at send time, and CHECK the open return before every
/// `SetReport`. A standalone script that opens the device and sends in the same
/// context works every time — this brings the app to that same footing. As a
/// backstop, ANY failed send triggers exactly one full re-enumeration and retry,
/// which also recovers from a handle invalidated by unplug/replug
/// (`kIOReturnNoDevice`), not just a dropped open claim.
public final class MSIDevice {

    // MARK: Constants (from docs/PROTOCOL.md)
    private static let vendorID:  Int = 0x1462
    private static let productID: Int = 0x3FA4

    // MARK: State

    /// The located device handle that we own and open directly. The IOHIDManager
    /// is NOT retained here — it is created, used for enumeration, then closed
    /// inside `locateDevice()`, so nothing depends on its run-loop scheduling.
    private var hidDevice: IOHIDDevice?

    /// Serialises the locate-and-send block in `send` so two threads cannot both
    /// run `locateDevice()` and leak a handle (a TOCTOU race on `hidDevice`).
    private let lock = NSLock()

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

    /// Locates the matching device using a *transient* IOHIDManager, then closes
    /// the manager so nothing depends on its run-loop scheduling. The located
    /// `IOHIDDevice` is retained in `hidDevice` and opened on demand by `send`.
    /// Safe to call repeatedly.
    @discardableResult
    private func locateDevice() -> Bool {
        // Release any previously held device before re-locating.
        closeDevice()

        // Create a manager solely for enumeration. It is closed before this method
        // returns — we deliberately do NOT keep it as long-lived state, because
        // tying the device's open claim to a manager scheduled on a (possibly dead)
        // run loop is exactly what caused the second-send `kIOReturnNotOpen` bug.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDVendorIDKey:  MSIDevice.vendorID,
            kIOHIDProductIDKey: MSIDevice.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // Schedule on the current run loop BEFORE copying devices. Per Apple's
        // IOHIDManager docs, `IOHIDManagerCopyDevices` can return an empty set if
        // the manager has not been scheduled, even when a matching device is
        // connected. Scheduling makes enumeration reliable. We unschedule + close
        // the manager via `defer` so it never outlives this method.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
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

        // Retain the device handle. The manager (closed by `defer`) does not keep
        // it alive — `hidDevice` does, via ARC's bridge of the CFType.
        hidDevice = device
        if !isConnected { DebugLog.shared.info("device located (MD342CQP)") }
        isConnected = true
        // Open state is established at send time (`attemptSend` → `ensureDeviceOpen`),
        // so the open and the SetReport always happen in the same call context.
        return true
    }

    /// Ensures the located device handle is open. Returns the open IOReturn.
    /// Calling `IOHIDDeviceOpen` on an already-open device is a no-op that returns
    /// success, so this is safe to call before every send.
    private func ensureDeviceOpen() -> IOReturn {
        guard let device = hidDevice else { return kIOReturnNoDevice }
        return IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Closes the open device, releasing the kernel-side USB claim. The IOHIDManager
    /// is transient (closed inside `locateDevice`), so there is nothing else to
    /// tear down here.
    private func closeDevice() {
        if let device = hidDevice {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            hidDevice = nil
        }
        isConnected = false
    }

    // MARK: - Send

    /// Sends a command to the monitor as a HID output report.
    ///
    /// Resilient to a stale OR invalidated device handle: if the handle is not
    /// currently located, the device is re-located first; if the first attempt
    /// fails for ANY reason (e.g. `kIOReturnNotOpen` from a dropped open claim, or
    /// `kIOReturnNoDevice` after an unplug/replug invalidated the handle), discovery
    /// is re-run and the send is retried exactly once. If re-discovery finds no
    /// monitor, the handle is dropped and `.deviceNotFound` is returned — the app
    /// recovers on the next call without needing a restart.
    ///
    /// - Returns: `.success(())` on success; `.failure(.deviceNotFound)` if no
    ///   monitor is connected (or it disappeared and re-discovery found nothing);
    ///   `.failure(.payloadUnavailable)` if the command's payload is not yet known;
    ///   `.failure(.sendFailed(_))` on a persistent IOKit error (both the first
    ///   attempt and the single re-locate-and-retry failed).
    @discardableResult
    public func send(_ command: Command) -> Result<Void, MSIError> {
        guard let bytes = command.payload else {
            DebugLog.shared.warn("send(\(command.actionId)): payload unavailable — not sent")
            return .failure(.payloadUnavailable)
        }

        // Serialise the whole locate-and-send sequence: the `hidDevice == nil`
        // check followed by `locateDevice()` is a TOCTOU window — without the lock
        // two concurrent callers could both locate/open and leak a handle.
        lock.lock()
        defer { lock.unlock() }

        // Locate the device if we do not currently hold a reference.
        if hidDevice == nil {
            locateDevice()
        }
        guard hidDevice != nil else {
            DebugLog.shared.warn("send(\(command.actionId)): device not found")
            return .failure(.deviceNotFound)
        }

        // First attempt.
        let ret = attemptSend(bytes)
        if ret == kIOReturnSuccess {
            DebugLog.shared.info("send(\(command.actionId)): OK")
            return .success(())
        }
        DebugLog.shared.warn("send(\(command.actionId)): first attempt failed IOReturn 0x\(String(ret, radix: 16)) — re-locating + retrying once")

        // Backstop: ANY first-attempt failure triggers exactly one re-locate-and-
        // retry. We deliberately do NOT filter on specific IOReturn codes — a fresh
        // re-enumeration is the correct recovery for the whole failure class:
        //   • kIOReturnNotOpen     — the open claim was dropped (run-loop staleness)
        //   • kIOReturnNotPermitted — a transient permission lapse
        //   • kIOReturnNoDevice    — the handle was invalidated (unplug/replug)
        // `locateDevice()` first calls `closeDevice()`, which sets `hidDevice = nil`
        // and `isConnected = false`; so if re-discovery finds nothing those stay
        // cleared and we return `.deviceNotFound` (no stale state, no leak — the
        // lock guards the whole sequence). Otherwise `attemptSend` opens the fresh
        // handle and SetReports in the same call context.
        locateDevice()
        guard hidDevice != nil else {
            DebugLog.shared.warn("send(\(command.actionId)): re-locate found no device — deviceNotFound")
            return .failure(.deviceNotFound)
        }
        let retryRet = attemptSend(bytes)
        if retryRet == kIOReturnSuccess {
            DebugLog.shared.info("send(\(command.actionId)): OK after retry")
            return .success(())
        }

        DebugLog.shared.error("send(\(command.actionId)): FAILED after retry — IOReturn 0x\(String(retryRet, radix: 16))")
        return .failure(.sendFailed("IOReturn 0x\(String(retryRet, radix: 16))"))
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
