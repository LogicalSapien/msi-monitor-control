import Foundation
import os.log
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Debug log
//
// A lightweight file logger for diagnosing the "app silently quits" bug. Writes
// timestamped structured lines to
// `~/Library/Application Support/LogicalSapien/MSIMonitorControl/debug.log`
// (the same vendor dir as settings.json), mirrors to os_log for live Console.app
// viewing, and — crucially — keeps a pre-opened file descriptor so a SIGNAL or
// uncaught-exception handler can append a final "TERMINATING" marker using only
// async-signal-safe `write(2)` before the process dies. The FILE is the durable
// record; os_log is the convenience mirror.

// MARK: Async-signal-safe crash state (file-scope, no Swift object access in-handler)
//
// A POSIX signal handler may ONLY call async-signal-safe functions. So everything
// the handler touches is a plain C-level global, set up ONCE at startup:
//   • `gCrashLogFD` — the pre-opened debug.log descriptor (raw `write`/`backtrace_
//     symbols_fd` target). No Foundation, no open() in the handler.
//   • `gCrashMarkers` — per-signal messages pre-encoded as null-terminated UTF-8
//     byte buffers at startup, so the handler does NO String work / NO malloc.
// The handler does ONLY: write(fd, buffer), backtrace_symbols_fd, signal(SIG_DFL),
// raise — all async-signal-safe.

private var gCrashLogFD: Int32 = -1

/// Pre-encoded "FATAL TERMINATING: signal <NAME>\n" buffers, keyed by signal number.
/// Stored as `[UInt8]` whose memory is stable for process lifetime (set once).
private var gCrashMarkers: [Int32: [UInt8]] = [:]

/// The signals we capture. SIGTERM included so a kill/terminate (which does NOT
/// route through `applicationWillTerminate`) is recorded — likely relevant to the
/// "app silently quits" bug.
private let gCrashSignals: [(sig: Int32, name: String)] = [
    (SIGSEGV, "SIGSEGV"), (SIGABRT, "SIGABRT"), (SIGILL, "SIGILL"),
    (SIGBUS, "SIGBUS"), (SIGTRAP, "SIGTRAP"), (SIGTERM, "SIGTERM"),
]

/// The async-signal-safe handler. Captures nothing (a C function pointer), reads
/// only the file-scope globals, and calls only async-signal-safe functions.
private func crashSignalHandler(_ sig: Int32) {
    if gCrashLogFD >= 0 {
        if let marker = gCrashMarkers[sig] {
            marker.withUnsafeBufferPointer { _ = write(gCrashLogFD, $0.baseAddress, $0.count) }
        }
        // backtrace_symbols_fd writes directly to the fd WITHOUT allocating — it is
        // the signal-safe backtrace path (plain `backtrace_symbols` allocates and is
        // NOT safe). Best-effort; addresses only (no symbolication needed here).
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
        let n = backtrace(&frames, Int32(frames.count))
        backtrace_symbols_fd(&frames, n, gCrashLogFD)
        fsync(gCrashLogFD)
    }
    // Restore the default action and re-raise so the OS still produces its crash report.
    signal(sig, SIG_DFL)
    raise(sig)
}

public final class DebugLog: @unchecked Sendable {

    public enum Level: String {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
        case fatal = "FATAL"
    }

    /// Shared instance. `start()` must be called once early in app launch.
    public static let shared = DebugLog()

    private let queue = DispatchQueue(label: "com.logicalsapien.msimonitorcontrol.debuglog")
    private let osLogger = Logger(subsystem: "com.logicalsapien.msimonitorcontrol", category: "debug")
    /// Pre-opened descriptor for async-signal-safe crash writes. -1 until started.
    private var fd: Int32 = -1
    private var fileURL: URL?
    /// Truncate the file on launch if it exceeds this (keeps the log bounded).
    private let maxBytesOnLaunch = 1_000_000   // ~1 MB

    private init() {}

    // MARK: Lifecycle

    /// The debug log file URL (vendor-nested, beside settings.json).
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask, appropriateFor: nil, create: false)
        return base
            .appendingPathComponent("LogicalSapien", isDirectory: true)
            .appendingPathComponent("MSIMonitorControl", isDirectory: true)
            .appendingPathComponent("debug.log", isDirectory: false)
    }

    /// Opens the log file (creating the dir), caps its size, writes a session-start
    /// marker, and installs the crash/termination handlers. Call once at launch.
    public func start(version: String = "dev") {
        queue.sync {
            guard fd < 0 else { return }   // already started
            do {
                let url = try Self.defaultURL()
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                // Cap size: if the existing file is large, start fresh.
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int, size > maxBytesOnLaunch {
                    try? FileManager.default.removeItem(at: url)
                }
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                // Open for append; keep the fd for the lifetime (and for the crash handler).
                fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
                fileURL = url
                // Publish the fd to the file-scope global the signal handler reads.
                gCrashLogFD = fd
            } catch {
                osLogger.error("DebugLog start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        write(.info, "──────── session start (v\(version)) ────────")
        installCrashHandlers()
    }

    // MARK: Writing

    /// Appends a structured line `<iso8601> <LEVEL> <message>` to the file and
    /// mirrors to os_log. Safe to call from any thread; serialised on `queue`.
    public func write(_ level: Level, _ message: String) {
        let line = "\(Self.timestamp()) \(level.rawValue) \(message)\n"
        queue.async { [weak self] in
            guard let self, self.fd >= 0 else { return }
            line.utf8CString.withUnsafeBufferPointer { buf in
                // -1 to drop the trailing NUL from the C string.
                _ = Foundation.write(self.fd, buf.baseAddress, buf.count - 1)
            }
        }
        switch level {
        case .info:  osLogger.log("\(message, privacy: .public)")
        case .warn:  osLogger.warning("\(message, privacy: .public)")
        case .error, .fatal: osLogger.error("\(message, privacy: .public)")
        }
    }

    public func info(_ m: String)  { write(.info, m) }
    public func warn(_ m: String)  { write(.warn, m) }
    public func error(_ m: String) { write(.error, m) }

    private static func timestamp() -> String {
        // ISO-8601 with milliseconds, local time. Avoids DateFormatter cost per line
        // by reusing a thread-safe formatter.
        isoFormatter.string(from: Date())
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: Crash / termination capture

    private func installCrashHandlers() {
        // Pre-encode the per-signal markers into stable byte buffers NOW (normal
        // context), so the signal handler does zero String work / zero malloc. The
        // buffers live in `gCrashMarkers` for the process lifetime.
        for (sig, name) in gCrashSignals where gCrashMarkers[sig] == nil {
            gCrashMarkers[sig] = Array("FATAL TERMINATING: signal \(name)\n".utf8)
        }

        // Uncaught Obj-C/Swift exceptions run in a NORMAL context (not a signal
        // context), so full String/Foundation work + a symbolicated backtrace are
        // allowed here.
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "(no reason)"
            let stack = exception.callStackSymbols.joined(separator: "\n  ")
            DebugLog.shared.writeFatalSync("TERMINATING: uncaught exception \(exception.name.rawValue): \(reason)\n  \(stack)")
        }

        // Fatal POSIX signals → the async-signal-safe file-scope `crashSignalHandler`
        // (a C function pointer that touches ONLY the pre-built globals and calls
        // only write/backtrace_symbols_fd/signal/raise). SIGTERM is included because
        // a terminate/kill does NOT route through `applicationWillTerminate`, so
        // capturing it distinguishes "killed by a signal" from "crashed" from
        // "user quit" — directly relevant to the "app silently quits" bug.
        for (sig, _) in gCrashSignals {
            signal(sig, crashSignalHandler)
        }
    }

    /// Synchronous fatal write used by the uncaught-exception handler (not in a
    /// signal context, so String work is allowed). Blocks until flushed.
    private func writeFatalSync(_ message: String) {
        queue.sync {
            guard fd >= 0 else { return }
            let line = "\(Self.timestamp()) FATAL \(message)\n"
            line.utf8CString.withUnsafeBufferPointer { buf in
                _ = Foundation.write(fd, buf.baseAddress, buf.count - 1)
            }
            fsync(fd)
        }
        osLogger.error("\(message, privacy: .public)")
    }
}
