import Foundation

// MARK: - Registrar seam

/// Abstraction over the live global-hotkey registrar so the commit/rollback policy
/// can be unit-tested with a spy (the real implementation is the app's Carbon
/// `HotKeyManager`). `apply` registers the config's chords and returns the actionIds
/// the OS REFUSED (reserved/in-use) — the conflict authority per SETTINGS.md §3.5.
public protocol HotkeyRegistering: AnyObject {
    @discardableResult
    func apply(config: HotkeyConfig) -> [String]
}

// MARK: - Commit / rollback orchestration

/// Encapsulates the "register first, persist only on success, roll back on OS
/// rejection" policy (SETTINGS.md §3.5/§5) over a `HotkeyRegistering` so it is
/// testable without Carbon. The store wires this to the real registrar + persistence.
public enum HotkeyCommitter {

    /// The result of attempting to commit a candidate config.
    public struct Result: Equatable {
        /// The config that is now LIVE (candidate if committed, previous if rolled back).
        public let liveConfig: HotkeyConfig
        /// True if the candidate was accepted + should be persisted.
        public let committed: Bool
        /// ActionIds the OS rejected (empty when committed).
        public let rejectedActions: [String]
    }

    /// Tries `candidate` against the registrar FIRST. If the OS accepts every chord,
    /// returns `.committed` with `candidate` live. If any chord is rejected, it
    /// RE-REGISTERS `previous` (so the user keeps working hotkeys), returns
    /// `committed == false`, and the caller must NOT persist. The `persist` closure
    /// is invoked exactly once, only on success, before returning.
    @discardableResult
    public static func commit(previous: HotkeyConfig,
                              candidate: HotkeyConfig,
                              registrar: HotkeyRegistering,
                              persist: (HotkeyConfig) -> Void) -> Result {
        let rejected = registrar.apply(config: candidate)
        switch HotkeyConfig.decideCommit(previous: previous, candidate: candidate, rejectedActions: rejected) {
        case .commit(let committed):
            persist(committed)
            return Result(liveConfig: committed, committed: true, rejectedActions: [])
        case .rollback(let previous, let rejectedActions):
            // Re-register the last-known-good config so hotkeys still work.
            _ = registrar.apply(config: previous)
            return Result(liveConfig: previous, committed: false, rejectedActions: rejectedActions)
        }
    }
}
