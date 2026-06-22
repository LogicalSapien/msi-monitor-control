#!/usr/bin/env swift
//
//  hid-probe.swift — MSI MD342CQP HID feature/opcode prober
//  tools/hid-probe/hid-probe.swift
//
//  Sends candidate HID output reports to the monitor and lets you observe
//  whether the monitor reacts.  This is the practical method for discovering
//  PBP and KVM payloads on a device that emits no input reports.
//
//  COMMAND GRAMMAR (from the kdar/msi-monitor-ctrl reference, src/device.rs)
//  ────────────────────────────────────────────────────────────────────────
//  The MD342CQP protocol is an ASCII command of fixed shape:
//
//    Index  Byte        Meaning
//      0    0x01        Report ID
//      1    0x35 ('5')  Fixed prefix
//      2    RW          0x62 ('b') = WRITE, 0x38 ('8') = READ
//      3    0x30 ('0')  Fixed
//      4    0x30 ('0')  Fixed
//      5    FEAT_HI     Feature code, high byte  ── the FEATURE selector
//      6    FEAT_LO     Feature code, low byte   ──   (2 ASCII bytes)
//      7    0x30 ('0')  Fixed
//      8    0x30 ('0')  Fixed
//      9    0x30 ('0')  Fixed
//     10    0x30+value  Value byte: 0x30 + position (e.g. 0x31='1', 0x32='2')
//     11    0x0D ('\r') Terminator
//     12..  0x00        Zero padding to 53 bytes
//
//  KNOWN FEATURE CODES (FEAT_HI, FEAT_LO at indices 5,6):
//      Input  = 0x35, 0x30   ('5','0')   value: 0=HDMI1 1=HDMI2 2=DP 3=Type-C
//      KVM    = 0x38, 0x3e   ('8','>')   (confirmed in kdar reference)
//      PBP    = UNKNOWN       ← what we are hunting for
//
//  KEY INSIGHT: PBP is almost certainly ANOTHER 2-byte FEATURE code at
//  indices 5,6 — NOT a different value byte at index 10.  Sweeping the value
//  byte alone will never find PBP.  Use the FEATURE sweep (--sweep-feature
//  or interactive menu option "f") instead.
//
//  SAFETY
//  ──────
//  The worst case is "nothing happens" — monitors ignore reports they don't
//  understand.  This tool sends one report at a time; in interactive mode each
//  send requires a keypress.  Every payload matches the known 53-byte grammar.
//
//  USAGE (run from repo root)
//  ──────────────────────────
//      # Interactive menu (recommended)
//      swift tools/hid-probe/hid-probe.swift
//
//      # Send one known/explicit command (value sweep within a feature)
//      swift tools/hid-probe/hid-probe.swift --feature 0x35 0x30 --value 3   # Input → Type-C
//      swift tools/hid-probe/hid-probe.swift --feature 0x38 0x3e --value 1   # KVM position 1
//
//      # Semi-automatic FEATURE sweep — the realistic way to find PBP
//      swift tools/hid-probe/hid-probe.swift --sweep-feature 0x30 0x3f       # sweep both [5],[6] over 0x30..0x3f
//      swift tools/hid-probe/hid-probe.swift --sweep-feature 0x30 0x3f --delay 2.5
//
//      # Legacy value-byte sweep within the Input feature (rarely useful now)
//      swift tools/hid-probe/hid-probe.swift --sweep-value 0x30 0x39
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

// ─── Device constants ───────────────────────────────────────────────────────

let kVendorID:  Int = 0x1462
let kProductID: Int = 0x3FA4
let kPayloadLength: Int = 53

// Read/write opcodes at index 2
let kRWWrite: UInt8 = 0x62   // 'b'
let kRWRead:  UInt8 = 0x38   // '8'

// ─── Known features (for reference + baseline testing) ─────────────────────

struct Feature {
    let hi: UInt8
    let lo: UInt8
    let label: String
}

let knownFeatures: [Feature] = [
    Feature(hi: 0x35, lo: 0x30, label: "Input  (known) — value 0=HDMI1 1=HDMI2 2=DP 3=Type-C"),
    Feature(hi: 0x38, lo: 0x3e, label: "KVM    (known) — value selects KVM source"),
]

// ─── Payload builder ─────────────────────────────────────────────────────────

/// Build a 53-byte report for a given feature pair and value position.
/// - rw: kRWWrite (default) or kRWRead.
/// - featHi/featLo: the 2-byte feature selector at indices 5,6.
/// - value: position; byte at index 10 = 0x30 + value.
func buildPayload(rw: UInt8 = kRWWrite, featHi: UInt8, featLo: UInt8, value: UInt8) -> [UInt8] {
    var p = [UInt8](repeating: 0x00, count: kPayloadLength)
    p[0]  = 0x01            // report ID
    p[1]  = 0x35            // '5'
    p[2]  = rw              // 'b' write or '8' read
    p[3]  = 0x30            // '0'
    p[4]  = 0x30            // '0'
    p[5]  = featHi          // feature high byte
    p[6]  = featLo          // feature low byte
    p[7]  = 0x30            // '0'
    p[8]  = 0x30            // '0'
    p[9]  = 0x30            // '0'
    p[10] = 0x30 &+ value   // value position
    p[11] = 0x0D            // '\r'
    // p[12..52] = 0x00
    return p
}

// ─── HID transport ───────────────────────────────────────────────────────────

func openDevice() -> IOHIDDevice? {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, [
        kIOHIDVendorIDKey:  kVendorID,
        kIOHIDProductIDKey: kProductID
    ] as CFDictionary)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }

    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

    guard let set = IOHIDManagerCopyDevices(mgr),
          let arr = set as? Set<IOHIDDevice>,
          let first = arr.first else {
        return nil
    }
    IOHIDDeviceOpen(first, IOOptionBits(kIOHIDOptionsTypeNone))
    return first
}

func sendPayload(_ payload: [UInt8], to device: IOHIDDevice) -> IOReturn {
    var mutable = payload
    return IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        CFIndex(payload[0]),
        &mutable,
        payload.count
    )
}

// ─── Formatting helpers ──────────────────────────────────────────────────────

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func asciiChar(_ b: UInt8) -> String {
    (b >= 0x20 && b < 0x7F) ? "'\(Character(UnicodeScalar(b)))'" : "0x\(String(format: "%02x", b))"
}

func printSeparator() { print(String(repeating: "─", count: 64)) }

func describePayload(_ p: [UInt8]) {
    let rwLabel = p[2] == kRWWrite ? "WRITE" : (p[2] == kRWRead ? "READ" : "0x\(String(format: "%02x", p[2]))")
    print("  RW:      \(rwLabel)")
    print("  Feature: 0x\(String(format: "%02x", p[5])) 0x\(String(format: "%02x", p[6]))  (\(asciiChar(p[5])),\(asciiChar(p[6])))")
    print("  Value:   0x\(String(format: "%02x", p[10]))  (position \(Int(p[10]) - 0x30))")
    print("  Payload: \(hexString(Array(p[0..<12]))) [..zeros..]")
}

// ─── CLI parsing ─────────────────────────────────────────────────────────────

func parseByteArg(_ s: String) -> UInt8? {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("0x") || t.hasPrefix("0X") { return UInt8(t.dropFirst(2), radix: 16) }
    return UInt8(t)
}

enum Mode {
    case interactive
    case single(featHi: UInt8, featLo: UInt8, value: UInt8)
    case sweepFeature(from: UInt8, to: UInt8, value: UInt8, delay: Double)
    case sweepValue(from: UInt8, to: UInt8, featHi: UInt8, featLo: UInt8)
}

func printHelp() {
    print("""
hid-probe — MSI MD342CQP HID feature / opcode prober

GRAMMAR (kdar reference)
    [01 35 RW 30 30 FEAT_HI FEAT_LO 30 30 30 (30+value) 0d] padded to 53 bytes
    RW: write=0x62 read=0x38   Feature: 2 bytes at indices 5,6   Value: index 10
    Known features:  Input=0x35,0x30   KVM=0x38,0x3e   PBP=UNKNOWN (hunt for it)

USAGE
    swift tools/hid-probe/hid-probe.swift [OPTIONS]

OPTIONS
    --feature <hi> <lo> --value <n>   Send one explicit command and exit
    --sweep-feature <from> <to>       Sweep feature pair [5],[6] over from..to
                                       (each byte; value fixed, default 1 = "on")
        [--value <n>]                  value position to use during the sweep
        [--delay <s>]                  delay between sends in semi-auto sweep
    --sweep-value <from> <to>         Sweep value byte within a feature
        [--feature <hi> <lo>]          feature to hold (default Input 0x35 0x30)
    --help                            Show this help

EXAMPLES
    # Confirm baseline — Input → Type-C (known-good, monitor should switch):
    swift tools/hid-probe/hid-probe.swift --feature 0x35 0x30 --value 3

    # Confirm KVM (known feature):
    swift tools/hid-probe/hid-probe.swift --feature 0x38 0x3e --value 1

    # HUNT FOR PBP — sweep the feature pair, value=1 ("on"), 2.5 s apart:
    swift tools/hid-probe/hid-probe.swift --sweep-feature 0x30 0x3f --delay 2.5

INTERPRETATION
    After each send, watch the monitor for ~2 s and note what changed:
      • Input switched          → an Input-related feature
      • PBP turned on/off       → PBP feature FOUND — record it!
      • KVM switched            → KVM feature
      • Nothing                 → not a recognised feature (safe, expected)
    Record any confirmed feature pair + payload and paste into docs/PROTOCOL.md.
""")
}

// Defaults
var mode: Mode = .interactive

let cli = Array(CommandLine.arguments.dropFirst())
var i = 0

// Scratch values gathered across flags
var optFeatHi: UInt8? = nil
var optFeatLo: UInt8? = nil
var optValue:  UInt8  = 1
var optDelay:  Double = 2.0
var sweepFeatureRange: (UInt8, UInt8)? = nil
var sweepValueRange:   (UInt8, UInt8)? = nil

while i < cli.count {
    let arg = cli[i]
    switch arg {
    case "--help", "-h":
        printHelp(); exit(0)
    case "--feature":
        guard i + 2 < cli.count,
              let hi = parseByteArg(cli[i+1]),
              let lo = parseByteArg(cli[i+2]) else {
            print("Error: --feature requires two byte values (e.g. --feature 0x35 0x30)."); exit(1)
        }
        optFeatHi = hi; optFeatLo = lo; i += 2
    case "--value":
        guard i + 1 < cli.count, let v = parseByteArg(cli[i+1]) else {
            print("Error: --value requires a number (e.g. --value 1)."); exit(1)
        }
        optValue = v; i += 1
    case "--delay":
        guard i + 1 < cli.count, let d = Double(cli[i+1]) else {
            print("Error: --delay requires seconds (e.g. --delay 2.5)."); exit(1)
        }
        optDelay = d; i += 1
    case "--sweep-feature":
        guard i + 2 < cli.count,
              let from = parseByteArg(cli[i+1]),
              let to   = parseByteArg(cli[i+2]) else {
            print("Error: --sweep-feature requires two byte bounds (e.g. 0x30 0x3f)."); exit(1)
        }
        sweepFeatureRange = (from, to); i += 2
    case "--sweep-value":
        guard i + 2 < cli.count,
              let from = parseByteArg(cli[i+1]),
              let to   = parseByteArg(cli[i+2]) else {
            print("Error: --sweep-value requires two byte bounds (e.g. 0x30 0x39)."); exit(1)
        }
        sweepValueRange = (from, to); i += 2
    default:
        print("Unknown argument: \(arg).  Run with --help for usage."); exit(1)
    }
    i += 1
}

// Resolve mode from gathered flags
if let (from, to) = sweepFeatureRange {
    mode = .sweepFeature(from: from, to: to, value: optValue, delay: optDelay)
} else if let (from, to) = sweepValueRange {
    mode = .sweepValue(from: from, to: to,
                       featHi: optFeatHi ?? 0x35, featLo: optFeatLo ?? 0x30)
} else if let hi = optFeatHi, let lo = optFeatLo {
    mode = .single(featHi: hi, featLo: lo, value: optValue)
}

// ─── Open device ──────────────────────────────────────────────────────────

print("")
printSeparator()
print("MSI MD342CQP HID Feature / Opcode Prober")
printSeparator()
print("VID: 0x1462  PID: 0x3FA4")
print("Grammar: [01 35 RW 30 30 FEAT_HI FEAT_LO 30 30 30 (30+value) 0d]")
print("Known features: Input=0x35,0x30  KVM=0x38,0x3e  PBP=UNKNOWN")
print("")
print("⚠  Safety: worst case for an unknown command is 'nothing happens'.")
print("   Only well-formed 53-byte reports are sent, one at a time.")
print("")

print("Opening device...", terminator: " "); fflush(stdout)
guard let device = openDevice() else {
    print("FAILED")
    print("")
    print("Device not found: VID=0x1462 PID=0x3FA4")
    print("Connect the monitor via its USB upstream cable and try again.")
    exit(1)
}
print("OK")
print("")

// ─── Probe primitive ───────────────────────────────────────────────────────

@discardableResult
func probe(featHi: UInt8, featLo: UInt8, value: UInt8, label: String? = nil, rw: UInt8 = kRWWrite) -> Bool {
    let payload = buildPayload(rw: rw, featHi: featHi, featLo: featLo, value: value)
    printSeparator()
    if let label = label { print("Action: \(label)") }
    describePayload(payload)
    print("")
    print("Sending...", terminator: " "); fflush(stdout)
    let result = sendPayload(payload, to: device)
    if result == kIOReturnSuccess {
        print("OK")
        return true
    } else {
        print("FAILED (IOReturn: \(result))")
        return false
    }
}

@discardableResult
func waitForEnter(_ prompt: String = "Press Enter to continue...") -> String {
    print(prompt, terminator: ""); fflush(stdout)
    return readLine(strippingNewline: true) ?? ""
}

// ─── Interactive menu ──────────────────────────────────────────────────────

func interactiveMenu() {
    while true {
        printSeparator()
        print("Choose an action (or 'q' to quit):")
        print("")
        print("  KNOWN FEATURES (use these to confirm sends reach the monitor):")
        for (idx, f) in knownFeatures.enumerated() {
            print(String(format: "   %d) %@", idx + 1, f.label))
        }
        print("")
        print("  DISCOVERY:")
        print("   f) PBP discovery — guided feature sweep (RECOMMENDED for PBP)")
        print("   c) Custom single command (enter feature pair + value)")
        print("   q) Quit")
        print("")
        print("Choice: ", terminator: ""); fflush(stdout)

        guard let raw = readLine(strippingNewline: true) else { break }
        let line = raw.trimmingCharacters(in: .whitespaces).lowercased()

        if line == "q" { break }

        if line == "f" {
            pbpDiscoveryFlow()
            continue
        }

        if line == "c" {
            print("Feature HI byte (e.g. 0x35): ", terminator: ""); fflush(stdout)
            guard let hiS = readLine(), let hi = parseByteArg(hiS) else { print("Invalid."); continue }
            print("Feature LO byte (e.g. 0x30): ", terminator: ""); fflush(stdout)
            guard let loS = readLine(), let lo = parseByteArg(loS) else { print("Invalid."); continue }
            print("Value position (e.g. 1): ", terminator: ""); fflush(stdout)
            guard let vS = readLine(), let v = parseByteArg(vS) else { print("Invalid."); continue }
            probe(featHi: hi, featLo: lo, value: v)
            waitForEnter()
            continue
        }

        if let choice = Int(line), choice >= 1, choice <= knownFeatures.count {
            let f = knownFeatures[choice - 1]
            print("Value position (e.g. 0,1,2,3): ", terminator: ""); fflush(stdout)
            let vS = readLine() ?? "1"
            let v = parseByteArg(vS) ?? 1
            probe(featHi: f.hi, featLo: f.lo, value: v, label: f.label)
            waitForEnter()
            continue
        }

        print("Invalid choice.")
    }
}

// ─── Guided PBP discovery flow ─────────────────────────────────────────────

func pbpDiscoveryFlow() {
    printSeparator()
    print("PBP DISCOVERY — guided feature sweep")
    printSeparator()
    print("""
PBP is an UNKNOWN 2-byte feature code at indices [5],[6].  We hold the value
byte fixed (1 = "on") and sweep the feature pair across an ASCII-hex range,
watching for PBP to switch on.

BEFORE YOU START:
  1. On the monitor OSD, set PBP / PIP to OFF.  This is your baseline.
  2. Make sure two sources are connected so PBP turning on is visible.

We send one candidate at a time.  After each, watch the screen:
  • If the picture splits / a second source appears → PBP just turned ON.
    Note the feature pair shown, then answer 'y' at the prompt.
  • Otherwise press Enter to try the next candidate.
""")
    print("")
    print("Feature byte range to sweep.  From [Enter for 0x30]: ", terminator: ""); fflush(stdout)
    let from = parseByteArg(readLine() ?? "") ?? 0x30
    print("To [Enter for 0x3f]: ", terminator: ""); fflush(stdout)
    let to = parseByteArg(readLine() ?? "") ?? 0x3f
    print("Value position to send (1 = 'on') [Enter for 1]: ", terminator: ""); fflush(stdout)
    let value = parseByteArg(readLine() ?? "") ?? 1
    print("")

    let lo = min(from, to), hi = max(from, to)
    let span = Int(hi - lo + 1)
    print("Sweeping feature [5],[6] over 0x\(String(format: "%02x", lo))..0x\(String(format: "%02x", hi)), value=\(value).")
    print("(Up to \(span * span) candidate pairs, known features skipped. Type 'q' to stop.)")
    print("")

    outer: for fh in lo...hi {
        for fl in lo...hi {
            // Skip known features so a real Input/KVM switch isn't mistaken for PBP
            if (fh == 0x35 && fl == 0x30) || (fh == 0x38 && fl == 0x3e) { continue }
            probe(featHi: fh, featLo: fl, value: value, label: "PBP candidate")
            print("")
            let resp = waitForEnter("Did PBP turn ON? [y = found / Enter = next / q = stop]: ")
                .trimmingCharacters(in: .whitespaces).lowercased()
            if resp == "q" { print("Sweep stopped."); break outer }
            if resp == "y" { confirmPbpFound(featHi: fh, featLo: fl); break outer }
        }
    }
    print("")
    print("PBP discovery finished.")
}

func confirmPbpFound(featHi: UInt8, featLo: UInt8) {
    printSeparator()
    print("PBP FEATURE CANDIDATE CONFIRMED")
    printSeparator()
    let onPayload  = buildPayload(featHi: featHi, featLo: featLo, value: 1) // 0x31 = on
    let offPayload = buildPayload(featHi: featHi, featLo: featLo, value: 0) // 0x30 = off
    print("Feature pair: 0x\(String(format: "%02x", featHi)) 0x\(String(format: "%02x", featLo))")
    print("")
    print("PBP On (value 1) payload:")
    print("  \(hexString(onPayload))")
    print("")
    print("Now testing PBP OFF (value 0) — watch the monitor return to single picture.")
    waitForEnter("Press Enter to send PBP OFF...")
    probe(featHi: featHi, featLo: featLo, value: 0, label: "PBP OFF (value 0)")
    print("")
    let resp = waitForEnter("Did PBP turn OFF? [y/n]: ").trimmingCharacters(in: .whitespaces).lowercased()
    print("")
    printSeparator()
    print("RECORD THESE IN docs/PROTOCOL.md:")
    printSeparator()
    print("PBP On  = \(hexString(onPayload))")
    if resp == "y" {
        print("PBP Off = \(hexString(offPayload))")
    } else {
        print("PBP Off = (value 0 did not turn it off — try other value positions, e.g.:")
        print("           swift tools/hid-probe/hid-probe.swift --feature 0x\(String(format: "%02x", featHi)) 0x\(String(format: "%02x", featLo)) --value 2 )")
    }
    print("")
}

// ─── Semi-automatic feature sweep (non-interactive) ───────────────────────

func sweepFeatureSemiAuto(from: UInt8, to: UInt8, value: UInt8, delay: Double) {
    let lo = min(from, to), hi = max(from, to)
    print("Semi-automatic FEATURE sweep: [5],[6] over 0x\(String(format: "%02x", lo))..0x\(String(format: "%02x", hi)), value=\(value), delay=\(delay)s")
    print("Watch the monitor.  Note any feature pair that causes a visible change.")
    print("(Press Ctrl-C to stop.)")
    print("")
    for fh in lo...hi {
        for fl in lo...hi {
            if (fh == 0x35 && fl == 0x30) || (fh == 0x38 && fl == 0x3e) {
                print("(skipping known feature 0x\(String(format: "%02x", fh)) 0x\(String(format: "%02x", fl)))")
                continue
            }
            probe(featHi: fh, featLo: fl, value: value,
                  label: "candidate 0x\(String(format: "%02x", fh)) 0x\(String(format: "%02x", fl))")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: delay))
        }
    }
    print("")
    print("Sweep complete.  Re-run any feature that caused a change in interactive mode")
    print("to capture both on/off values.")
}

// ─── Dispatch ─────────────────────────────────────────────────────────────

switch mode {
case .interactive:
    interactiveMenu()
case .single(let hi, let lo, let v):
    let label = knownFeatures.first(where: { $0.hi == hi && $0.lo == lo })?.label
    probe(featHi: hi, featLo: lo, value: v, label: label)
    print("")
case .sweepFeature(let from, let to, let value, let delay):
    sweepFeatureSemiAuto(from: from, to: to, value: value, delay: delay)
case .sweepValue(let from, let to, let hi, let lo):
    let l = min(from, to), h = max(from, to)
    print("Value-byte sweep within feature 0x\(String(format: "%02x", hi)) 0x\(String(format: "%02x", lo)): 0x\(String(format: "%02x", l))..0x\(String(format: "%02x", h))")
    print("(Note: PBP is a FEATURE, not a value — this mode rarely finds it.)")
    print("")
    for raw in l...h {
        let value = raw >= 0x30 ? raw - 0x30 : raw   // accept a raw byte or a position
        probe(featHi: hi, featLo: lo, value: value)
        let resp = waitForEnter("Reaction? [Enter = next / q = stop]: ").trimmingCharacters(in: .whitespaces).lowercased()
        if resp == "q" { print("Stopped."); break }
    }
}

printSeparator()
print("Done.  Paste any confirmed payload bytes into docs/PROTOCOL.md.")
print("")
