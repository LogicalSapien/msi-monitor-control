import Foundation
import MSIControl

/// Observable wrapper around `MSIDevice` so SwiftUI views can react to connection state.
final class DeviceState: ObservableObject {

    @Published var isConnected: Bool = false
    @Published var lastError: String? = nil

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

    /// Sends a command and updates the last error on failure.
    func send(_ command: Command) {
        let result = device.send(command)
        switch result {
        case .success:
            lastError = nil
        case .failure(let error):
            switch error {
            case .deviceNotFound:
                lastError = "Monitor not connected."
            case .payloadUnavailable:
                lastError = "Payload for \(command.label) is not yet known."
            case .sendFailed(let detail):
                lastError = "Send failed: \(detail)"
            }
        }
    }
}
