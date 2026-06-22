import Foundation
import MSIControl

/// Observable wrapper around `MSIDevice` so SwiftUI views can react to connection state.
final class DeviceState: ObservableObject {

    @Published var isConnected: Bool = false
    @Published var lastError: String? = nil

    /// Last successfully-sent command per mutually-exclusive group, for the "current"
    /// highlight. In-memory only (NOT persisted — a stale highlight across launches
    /// would mislead) and best-effort: it reflects what THIS app last switched, and
    /// can be out of date if the user switched via the monitor's OSD buttons. The
    /// monitor itself cannot report state (see PROTOCOL.md § no read-back).
    @Published private(set) var currentByGroup: [Command.Group: Command] = [:]

    /// PBP per-window source selections (promoted from SettingsView @State so the
    /// EdgeSwitchTracker can read them without touching UI; v0.2.3 design §4.3).
    /// Updated by SettingsView when the user changes a source dropdown.
    /// Defaults reflect what the monitor's OSD typically shows on first PBP enable.
    @Published var pbpMainSource: InputEnum = .hdmi1
    @Published var pbpSubSource: InputEnum = .hdmi1

    /// Called on the main thread after a PBP-mode command succeeds. Used to notify
    /// the EdgeSwitchTracker so it can transition between Standby and Active.
    var onPBPModeChanged: (() -> Void)?

    private let device = MSIDevice()
    private var timer: Timer?

    init() {
        updateState()
        // Poll for connection changes every 2 seconds.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateState()
        }
    }

    private func updateState() {
        // Re-scan the USB bus so the connection indicator recovers after a KVM switch
        // routes the monitor's HID away and back. Without re-scanning, isConnected
        // stays stale-false even when the device reappears (v0.2.4 hotfix).
        device.refresh()
        isConnected = device.isConnected
    }

    /// True if `command` is the last one this app successfully sent in its group.
    /// Non-monitor actions (no group) are never "current".
    func isCurrent(_ command: Command) -> Bool {
        guard let group = command.group else { return false }
        return currentByGroup[group] == command
    }

    /// Sends a command; on success records it as its group's "current" and clears
    /// the error; on failure records a human-readable error (and leaves "current"
    /// untouched — we only highlight what definitely went through).
    func send(_ command: Command) {
        let result = device.send(command)
        switch result {
        case .success:
            lastError = nil
            if let group = command.group {
                currentByGroup[group] = command
                // Notify the edge-switch tracker if a PBP mode changed successfully,
                // so it can transition between Standby and Active (v0.2.3 design §3.1).
                if group == .pbpMode { onPBPModeChanged?() }
            }
        case .failure(let error):
            apply(error, label: command.label)
        }
    }

    /// Sets a PBP/PIP window's source input. `.main` is hardware-unverified — the UI
    /// surfaces that; this just sends.
    func setPBPSource(window: PBPWindow, input: InputEnum) {
        let result = device.setPBPSource(window: window, input: input)
        if case .failure(let error) = result {
            apply(error, label: "PBP source")
        } else {
            lastError = nil
        }
    }

    private func apply(_ error: MSIError, label: String) {
        switch error {
        case .deviceNotFound:
            lastError = "Monitor not connected."
        case .payloadUnavailable:
            lastError = "Payload for \(label) is not yet known."
        case .sendFailed(let detail):
            lastError = "Send failed: \(detail)"
        }
    }
}
