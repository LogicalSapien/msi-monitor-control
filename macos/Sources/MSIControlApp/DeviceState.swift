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
            if let group = command.group { currentByGroup[group] = command }
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
