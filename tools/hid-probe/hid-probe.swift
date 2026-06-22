#!/usr/bin/env swift
//
//  hid-probe.swift — MSI MD342CQP HID opcode prober
//  tools/hid-probe/hid-probe.swift
//
//  Sends a single candidate HID output report to the monitor and lets you
//  observe whether the monitor reacts.  This is the practical method for
//  discovering PBP and KVM payloads on a device that emits no input reports.
//
//  BACKGROUND
//  ──────────
//  The MD342CQP protocol is ASCII text over HID output reports:
//
//    Byte[0]  = 0x01  (report ID)
//    Bytes[1..11] = ASCII command string, always of the form "5b005030003X\r"
//      where X is the opcode character (one ASCII byte)
//    Bytes[12..52] = 0x00 padding
//
//  For input switching, the known opcodes are:
//    '0' (0x30) → HDMI 1     '1' (0x31) → HDMI 2
//    '2' (0x32) → DisplayPort '3' (0x33) → Type-C
//
//  PBP and KVM almost certainly follow the same structure but with different
//  opcode characters.  This tool probes them.
//
//  SAFETY
//  ──────
//  The worst case is "nothing happens" — monitors ignore reports they don't
//  understand.  This tool sends only one report at a time, after you confirm.
//  Known-good opcodes (input-switch 0x30–0x33) are labelled so you can verify
//  them as a baseline before probing unknowns.
//
//  USAGE
//  ─────
//      # Interactive mode — shows a menu and prompts before each send
//      swift tools/hid-probe/hid-probe.swift
//
//      # Send a specific known opcode (non-interactive)
//      swift tools/hid-probe/hid-probe.swift --opcode 0x33
//
//      # Send a raw byte value
//      swift tools/hid-probe/hid-probe.swift --opcode 51        # decimal
//
//      # Probe a range of opcodes interactively (useful for sweep)
//      swift tools/hid-probe/hid-probe.swift --sweep 0x34 0x50
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

// ─── Device constants ───────────────────────────────────────────────────────

let kVendorID:  Int = 0x1462
let kProductID: Int = 0x3FA4

// ─── Known opcodes (for reference + baseline testing) ─────────────────────

struct KnownOpcode {
    let byte: UInt8
    let label: String
}

let knownOpcodes: [KnownOpcode] = [
    KnownOpcode(byte: 0x30, label: "Input → HDMI 1     (known-good)"),
    KnownOpcode(byte: 0x31, label: "Input → HDMI 2     (known-good)"),
    KnownOpcode(byte: 0x32, label: "Input → DisplayPort (known-good)"),
    KnownOpcode(byte: 0x33, label: "Input → Type-C     (known-good)"),
    // Candidates for PBP and KVM.  These are educated guesses based on the
    // ASCII-sequential pattern; none are confirmed.  Observe the monitor.
    KnownOpcode(byte: 0x34, label: "? candidate — observe monitor"),
    KnownOpcode(byte: 0x35, label: "? candidate — observe monitor"),
    KnownOpcode(byte: 0x36, label: "? candidate — observe monitor"),
    KnownOpcode(byte: 0x37, label: "? candidate — observe monitor"),
    KnownOpcode(byte: 0x38, label: "? candidate — observe monitor"),
    KnownOpcode(byte: 0x39, label: "? candidate — observe monitor"),
    KnownOpcode(byte: 0x41, label: "? candidate (ASCII 'A') — observe monitor"),
    KnownOpcode(byte: 0x42, label: "? candidate (ASCII 'B') — observe monitor"),
    KnownOpcode(byte: 0x43, label: "? candidate (ASCII 'C') — observe monitor"),
    KnownOpcode(byte: 0x44, label: "? candidate (ASCII 'D') — observe monitor"),
    KnownOpcode(byte: 0x45, label: "? candidate (ASCII 'E') — observe monitor"),
    KnownOpcode(byte: 0x46, label: "? candidate (ASCII 'F') — observe monitor"),
    KnownOpcode(byte: 0x47, label: "? candidate (ASCII 'G') — observe monitor"),
    KnownOpcode(byte: 0x48, label: "? candidate (ASCII 'H') — observe monitor"),
]

// ─── Payload builder ─────────────────────────────────────────────────────────
//
//  Known-good payload structure (from PROTOCOL.md / Phaseowner reference):
//
//  Offset  Byte   Notes
//  0       0x01   Report ID
//  1       0x35   ASCII '5'
//  2       0x62   ASCII 'b'       — wait, let me check the reference exactly
//
//  From PROTOCOL.md, Input→Type-C (opcode byte at index 10):
//    0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D, 0x00...
//
//  Decoding the ASCII bytes[1..11]:
//    0x35 = '5'   0x62 = 'b'   0x30 = '0'   0x30 = '0'
//    0x35 = '5'   0x30 = '0'   0x30 = '0'   0x30 = '0'
//    0x30 = '0'   0x33 = '3' ← opcode   0x0D = '\r'
//
//  Full ASCII: "5b00500030\r"  Wait — counting: indices 1-11 inclusive = 11 bytes
//    byte[1]=0x35='5'  byte[2]=0x62='b'  byte[3]=0x30='0'  byte[4]=0x30='0'
//    byte[5]=0x35='5'  byte[6]=0x30='0'  byte[7]=0x30='0'  byte[8]=0x30='0'
//    byte[9]=0x30='0'  byte[10]=0x33='3' byte[11]=0x0D=\r
//
//  So the command string is: "5b005000003\r"  where '3' = Type-C
//  For DP (0x32):            "5b005000002\r"
//
//  The opcode byte is at index 10.  We substitute the candidate there.

let kPayloadLength: Int = 53

func buildPayload(opcode: UInt8) -> [UInt8] {
    // Template from PROTOCOL.md (Type-C = opcode 0x33):
    //   01 35 62 30 30 35 30 30 30 30 33 0D 00 00 ... (53 bytes)
    var payload: [UInt8] = Array(repeating: 0x00, count: kPayloadLength)
    payload[0]  = 0x01  // report ID
    payload[1]  = 0x35  // '5'
    payload[2]  = 0x62  // 'b'
    payload[3]  = 0x30  // '0'
    payload[4]  = 0x30  // '0'
    payload[5]  = 0x35  // '5'
    payload[6]  = 0x30  // '0'
    payload[7]  = 0x30  // '0'
    payload[8]  = 0x30  // '0'
    payload[9]  = 0x30  // '0'
    payload[10] = opcode // ← the byte we are probing
    payload[11] = 0x0D  // '\r'
    // bytes[12..52] remain 0x00
    return payload
}

// ─── HID send ────────────────────────────────────────────────────────────────

func openDevice() -> IOHIDDevice? {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, [
        kIOHIDVendorIDKey:  kVendorID,
        kIOHIDProductIDKey: kProductID
    ] as CFDictionary)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else { return nil }

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
    var mutablePayload = payload
    return IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        CFIndex(payload[0]),
        &mutablePayload,
        payload.count
    )
}

// ─── Formatting helpers ──────────────────────────────────────────────────────

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func printSeparator() { print(String(repeating: "─", count: 60)) }

func printPayloadSummary(_ payload: [UInt8], opcode: UInt8) {
    let opcodeAscii = opcode >= 0x20 && opcode < 0x7F
        ? " (ASCII '\(String(bytes: [opcode], encoding: .ascii) ?? "?")')"
        : ""
    print("  Opcode: 0x\(String(format: "%02x", opcode))\(opcodeAscii)")
    print("  Payload (\(payload.count) bytes):")
    print("    \(hexString(Array(payload[0..<12]))) [..zeros..]")
}

// ─── CLI argument parsing ────────────────────────────────────────────────────

enum Mode {
    case interactive
    case singleOpcode(UInt8)
    case sweep(UInt8, UInt8)
}

func parseByteArg(_ s: String) -> UInt8? {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
        return UInt8(trimmed.dropFirst(2), radix: 16)
    }
    return UInt8(trimmed)
}

var mode: Mode = .interactive

let cliArgs = Array(CommandLine.arguments.dropFirst())
var idx = 0
while idx < cliArgs.count {
    let arg = cliArgs[idx]
    switch arg {
    case "--help", "-h":
        print("""
hid-probe — MSI MD342CQP HID opcode prober

USAGE
    swift tools/hid-probe/hid-probe.swift [OPTIONS]

OPTIONS
    --opcode <byte>         Send one specific opcode (hex or decimal)
    --sweep <from> <to>     Probe each opcode in the range interactively
    --help                  Show this help

EXAMPLES
    swift tools/hid-probe/hid-probe.swift
        Interactive menu — choose from known + candidate opcodes

    swift tools/hid-probe/hid-probe.swift --opcode 0x33
        Send opcode 0x33 (Type-C input) — use as baseline confirmation

    swift tools/hid-probe/hid-probe.swift --sweep 0x34 0x45
        Walk opcodes 0x34–0x45, one at a time, pausing to let you observe

INTERPRETATION
    Watch the monitor after each send.  Record what changes (if anything):
      • Monitor switches input → likely an input-switch opcode variant
      • PBP mode activates/deactivates → PBP opcode found
      • KVM switches → KVM opcode found
      • Nothing → opcode not recognised (safe, expected for most candidates)

    Once you identify a payload, paste the bytes to the project lead and
    they will record them in docs/PROTOCOL.md.
""")
        exit(0)
    case "--opcode":
        idx += 1
        guard idx < cliArgs.count, let b = parseByteArg(cliArgs[idx]) else {
            print("Error: --opcode requires a byte value (e.g. 0x33 or 51).")
            exit(1)
        }
        mode = .singleOpcode(b)
    case "--sweep":
        idx += 1
        guard idx + 1 < cliArgs.count,
              let from = parseByteArg(cliArgs[idx]),
              let to   = parseByteArg(cliArgs[idx + 1]) else {
            print("Error: --sweep requires two byte values (e.g. --sweep 0x34 0x50).")
            exit(1)
        }
        idx += 1
        mode = .sweep(from, to)
    default:
        print("Unknown argument: \(arg).  Run with --help for usage.")
        exit(1)
    }
    idx += 1
}

// ─── Main ────────────────────────────────────────────────────────────────────

print("")
printSeparator()
print("MSI MD342CQP HID Opcode Prober")
printSeparator()
print("VID: 0x1462  PID: 0x3FA4")
print("")
print("⚠  Safety note: worst case for an unknown opcode is 'nothing happens'.")
print("   This tool only sends reports matching the known payload structure.")
print("")

// Open device
print("Opening device...", terminator: " ")
fflush(stdout)

guard let device = openDevice() else {
    print("FAILED")
    print("")
    print("Device not found: VID=0x1462 PID=0x3FA4")
    print("Make sure the monitor is connected via USB upstream cable and try again.")
    exit(1)
}
print("OK")
print("")

// ─── Single opcode mode ───────────────────────────────────────────────────

func probeSingle(opcode: UInt8, label: String? = nil) {
    let payload = buildPayload(opcode: opcode)
    printSeparator()
    if let label = label {
        print("Action: \(label)")
    }
    printPayloadSummary(payload, opcode: opcode)
    print("")
    print("Sending...", terminator: " ")
    fflush(stdout)
    let result = sendPayload(payload, to: device)
    if result == kIOReturnSuccess {
        print("OK")
        print("→ Observe the monitor now.  Did it react? (Y/N/note)")
    } else {
        print("FAILED (IOReturn: \(result))")
    }
}

// ─── Interactive mode ─────────────────────────────────────────────────────

func interactiveMenu() {
    while true {
        printSeparator()
        print("Choose an opcode to probe (or 'q' to quit):")
        print("")
        for (i, op) in knownOpcodes.enumerated() {
            print(String(format: "  %2d) 0x%02x  %@", i + 1, op.byte, op.label))
        }
        print("   c) Enter a custom opcode (hex or decimal)")
        print("   q) Quit")
        print("")
        print("Choice: ", terminator: "")
        fflush(stdout)

        guard let line = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces) else { break }

        if line.lowercased() == "q" { break }

        if line.lowercased() == "c" {
            print("Enter opcode (e.g. 0x34 or 52): ", terminator: "")
            fflush(stdout)
            guard let customLine = readLine(strippingNewline: true),
                  let opcode = parseByteArg(customLine) else {
                print("Invalid input.")
                continue
            }
            probeSingle(opcode: opcode)
        } else if let choice = Int(line), choice >= 1, choice <= knownOpcodes.count {
            let op = knownOpcodes[choice - 1]
            probeSingle(opcode: op.byte, label: op.label)
        } else {
            print("Invalid choice.")
            continue
        }

        print("")
        print("Press Enter to continue...", terminator: "")
        fflush(stdout)
        _ = readLine()
    }
}

// ─── Sweep mode ───────────────────────────────────────────────────────────

func sweepRange(from: UInt8, to: UInt8) {
    let range = from <= to ? Array(from...to) : Array(to...from).reversed()
    print("Sweep: 0x\(String(format: "%02x", from)) → 0x\(String(format: "%02x", to))  (\(range.count) opcodes)")
    print("")

    for opcode in range {
        let label = knownOpcodes.first(where: { $0.byte == opcode })?.label
        probeSingle(opcode: opcode, label: label)
        print("")
        print("Did the monitor react? Record what happened, then press Enter to continue")
        print("(or type 'q' + Enter to stop the sweep): ", terminator: "")
        fflush(stdout)
        let resp = readLine(strippingNewline: true) ?? ""
        if resp.trimmingCharacters(in: .whitespaces).lowercased() == "q" {
            print("Sweep stopped.")
            break
        }
    }
}

// ─── Dispatch ─────────────────────────────────────────────────────────────

switch mode {
case .interactive:
    interactiveMenu()
case .singleOpcode(let opcode):
    let label = knownOpcodes.first(where: { $0.byte == opcode })?.label
    probeSingle(opcode: opcode, label: label)
    print("")
case .sweep(let from, let to):
    sweepRange(from: from, to: to)
}

printSeparator()
print("Done.  Paste any confirmed payload bytes into docs/PROTOCOL.md.")
print("")
