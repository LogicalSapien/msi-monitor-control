import CoreGraphics
import AppKit
@preconcurrency import MSIControl

// MARK: - Input Monitoring permission helpers

/// Permission states for CGEventTap / Input Monitoring (macOS 10.15+).
public enum InputMonitoringStatus: Equatable, Sendable {
    /// The process has Input Monitoring permission.
    case granted
    /// The OS denied the tap (CGEventTapCreate returned nil).
    case denied
    /// Status not yet checked (pre-toggle-on).
    case unknown

    public var statusText: String {
        switch self {
        case .granted: return "Granted ✓ — edge-switch KVM can be enabled."
        case .denied:  return "Denied — grant permission in System Settings, then re-enable the toggle."
        case .unknown: return "Not checked yet (enable the toggle to request access)."
        }
    }
}

/// Probes whether Input Monitoring is granted by attempting to create a
/// listen-only tap with a throwaway mask.  Creates and immediately invalidates
/// the CFMachPort — no events are consumed and no port is leaked.
func probeInputMonitoringPermission() -> InputMonitoringStatus {
    let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
    let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
        userInfo: nil
    )
    guard let tap else { return .denied }
    CFMachPortInvalidate(tap)   // release the Mach port immediately; no leak
    return .granted
}

// MARK: - EdgeSwitchTracker

/// Tracks the cursor position and fires a KVM switch when it crosses the centre
/// divider of the MSI MD342CQP in PBP mode.
///
/// **Threading model — main run loop only.**
/// The CGEventTap's `CFRunLoopSource` is added to `CFRunLoopGetMain()` with
/// `.commonModes`, so every callback fires on the main thread.  No background
/// thread is involved.  All state is therefore main-thread-only — no locks needed.
///
/// **State machine (design §3):**
///
/// | `isEnabled` | PBP mode (last sent) | Effective state |
/// |:-----------:|:-------------------:|:----------------:|
/// | false        | any                  | Idle — no tap installed |
/// | true         | Off / PIP            | Standby — tap installed, callback exits immediately |
/// | true         | PBP (`pbpOn`)        | Active — divider comparison runs |
///
/// **Hysteresis (design §5):** ±48 px dead zone + 800 ms dwell.
final class EdgeSwitchTracker {

    // MARK: - Configuration constants

    /// Dead-zone half-width in points around the divider (design §5.1).
    static let deadZone: CGFloat = 48
    /// Minimum time between consecutive KVM switches (design §5.2).
    static let dwellSeconds: Double = 0.8
    /// Target display native resolution (points × backing scale = pixels).
    private static let targetWidth:  CGFloat = 3440
    private static let targetHeight: CGFloat = 1440

    // MARK: - Dependencies (all main-thread)

    private let onKvmSwitch: (Command) -> Void
    private weak var deviceState: DeviceState?

    // MARK: - Main-thread-only state (no locking required)

    private var isEnabled:    Bool    = false
    private var msiFrame:     CGRect  = .zero
    private var dividerX:     CGFloat = 0

    // MARK: - Tap infrastructure (main-thread-only)

    private var tapPort:       CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Hysteresis state (main-thread-only — callback on main run loop)

    private enum Side { case left, right, unknown }
    private var currentSide:    Side             = .unknown
    private var lastSwitchTime: CFAbsoluteTime   = 0

    // MARK: - Init / deinit

    init(deviceState: DeviceState, onKvmSwitch: @escaping (Command) -> Void) {
        self.deviceState = deviceState
        self.onKvmSwitch = onKvmSwitch
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeTap()
    }

    // MARK: - Public API (main thread)

    func setEnabled(_ enabled: Bool) {
        assert(Thread.isMainThread)
        guard enabled != isEnabled else { return }
        if enabled {
            scanDisplays()
            installTap()
            // isEnabled is set to true only inside installTap() on success.
            // If tapCreate fails (permission denied), isEnabled stays false.
        } else {
            removeTap()
            isEnabled = false
        }
    }

    /// Call after a successful PBP-mode send or PBP-source change so the tracker
    /// reflects the current mode and source selection.
    func notifyPBPModeChanged() {
        assert(Thread.isMainThread)
        guard isEnabled else { return }
        let mode = deviceState?.currentByGroup[.pbpMode]
        DebugLog.shared.info(
            "edge-switch: PBP mode → \(mode?.actionId ?? "nil"); tracker \(mode == .pbpOn ? "Active" : "Standby")"
        )
    }

    // MARK: - Display scanning (main thread)

    @objc private func screensDidChange() { scanDisplays() }

    private func scanDisplays() {
        assert(Thread.isMainThread)
        for screen in NSScreen.screens {
            let f  = screen.frame
            let pw = f.width  * screen.backingScaleFactor
            let ph = f.height * screen.backingScaleFactor
            if Int(pw.rounded()) == Int(Self.targetWidth) &&
               Int(ph.rounded()) == Int(Self.targetHeight) {
                msiFrame = f
                dividerX = f.origin.x + f.width / 2
                DebugLog.shared.info("edge-switch: MSI display found — frame \(f), dividerX \(dividerX)")
                return
            }
        }
        msiFrame = .zero
        dividerX = 0
        DebugLog.shared.info("edge-switch: no 3440×1440 display found — tracker inactive (design §2.1)")
    }

    // MARK: - Tap install / remove (main thread)

    private func installTap() {
        assert(Thread.isMainThread)
        guard tapPort == nil else { return }   // idempotent

        let mask    = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap:              .cgSessionEventTap,
            place:            .headInsertEventTap,
            options:          .listenOnly,
            eventsOfInterest: mask,
            callback:         edgeSwitchTapCallback,
            userInfo:         selfPtr
        ) else {
            DebugLog.shared.warn("edge-switch: CGEventTapCreate failed — Input Monitoring not granted")
            // isEnabled stays false; setEnabled() will not flip it.
            return
        }

        let src = CFMachPortCreateRunLoopSource(nil, port, 0)
        // Add to the MAIN run loop — callback fires on the main thread.
        // No background thread; no cross-thread races; no retain cycles.
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tapPort       = port
        runLoopSource = src
        isEnabled     = true   // only set here, after confirmed success
        DebugLog.shared.info("edge-switch: tap installed on main run loop")
    }

    private func removeTap() {
        // Idempotent — safe to call from deinit even if never installed.
        assert(Thread.isMainThread)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let port = tapPort {
            CFMachPortInvalidate(port)
            tapPort = nil
        }
        currentSide    = .unknown
        lastSwitchTime = 0
        DebugLog.shared.info("edge-switch: tap removed")
    }

    // MARK: - Tap event handler (main thread — callback on main run loop)

    func handleTapEvent(type: CGEventType, event: CGEvent) {
        assert(Thread.isMainThread)

        // macOS sends tapDisabledByTimeout / tapDisabledByUserInput when the tap
        // falls behind.  Re-enable rather than tearing it down.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tapPort {
                CGEvent.tapEnable(tap: port, enable: true)
                DebugLog.shared.info("edge-switch: tap re-enabled after OS timeout/user-input disable")
            }
            return
        }

        // Fast-exit: disabled or display not identified.
        guard isEnabled, msiFrame != .zero else { return }

        let cursorPos = event.location   // global screen coordinates (points)
        guard msiFrame.contains(cursorPos) else { return }

        let dead = EdgeSwitchTracker.deadZone
        let newSide: Side
        if cursorPos.x < dividerX - dead {
            newSide = .left
        } else if cursorPos.x > dividerX + dead {
            newSide = .right
        } else {
            return   // inside dead zone
        }

        guard newSide != currentSide else { return }

        // Dwell suppression (design §5.2).
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSwitchTime >= EdgeSwitchTracker.dwellSeconds else { return }

        // Determine KVM command from the source in the target window.
        // DeviceState access is safe — we're on the main thread.
        let targetSource: InputEnum
        switch newSide {
        case .left:    targetSource = deviceState?.pbpMainSource ?? .hdmi1
        case .right:   targetSource = deviceState?.pbpSubSource  ?? .hdmi1
        case .unknown: return
        }
        guard let kvmCommand = EdgeSwitchTracker.kvmCommand(for: targetSource) else { return }

        // Double-guard: PBP mode must still be active.
        guard deviceState?.currentByGroup[.pbpMode] == .pbpOn else { return }

        currentSide    = newSide
        lastSwitchTime = now

        DebugLog.shared.info(
            "edge-switch: cursor crossed to \(newSide == .left ? "left" : "right") → \(kvmCommand.actionId)"
        )
        onKvmSwitch(kvmCommand)   // already on main thread — direct call, no dispatch needed
    }

    // MARK: - KVM mapping (static, no state)

    /// Input → KVM mapping table (design §4.2, definitive).
    static func kvmCommand(for input: InputEnum) -> Command? {
        switch input {
        case .typeC:         return .kvmUSBC      // Type-C → USB-C KVM port
        case .displayPort:   return .kvmUpstream  // DP → Upstream KVM (best-effort)
        case .hdmi1, .hdmi2: return nil            // HDMI — ambiguous, no auto-switch
        }
    }
}

// MARK: - CGEventTap free function callback

/// Free C-compatible callback.  Hands off to `EdgeSwitchTracker.handleTapEvent`.
///
/// The source is added to the MAIN run loop, so this fires on the main thread.
/// Return `passUnretained(event)` — listen-only tap; we must not retain the event.
private let edgeSwitchTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tracker = Unmanaged<EdgeSwitchTracker>.fromOpaque(userInfo).takeUnretainedValue()
    tracker.handleTapEvent(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
