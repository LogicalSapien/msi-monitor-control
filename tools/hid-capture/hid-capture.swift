#!/usr/bin/env swift
//
//  hid-capture.swift — MSI MD342CQP HID traffic listener
//  tools/hid-capture/hid-capture.swift
//
//  PURPOSE AND HONEST CAVEATS
//  ──────────────────────────
//  This tool registers an IOHIDManager input-report callback on every HID
//  interface the MD342CQP exposes, then listens for `--duration` seconds
//  (default 30 s).
//
//  IMPORTANT: The MD342CQP control protocol is OUTPUT-only from the host side.
//  The host sends 53-byte ASCII commands to the monitor; the monitor does not
//  normally send any input reports back.  Pressing OSD buttons on the monitor
//  causes internal firmware state changes — no HID report flows to the host.
//
//  Therefore this tool will almost certainly capture NOTHING when you press
//  OSD buttons.  It is included for completeness and to verify that assertion
//  on your hardware.  If the monitor does, unexpectedly, send input reports
//  (e.g. a button-pressed notification), they will appear here.
//
//  For actually discovering unknown payloads, use hid-probe instead:
//      swift tools/hid-probe/hid-probe.swift --help
//
//  USAGE
//  ─────
//      swift tools/hid-capture/hid-capture.swift [--duration <seconds>]
//
//  EXAMPLES
//      swift tools/hid-capture/hid-capture.swift
//      swift tools/hid-capture/hid-capture.swift --duration 60
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

// ─── CLI arguments ──────────────────────────────────────────────────────────

var listenDuration: Double = 30.0

let args = CommandLine.arguments.dropFirst()
var it = args.makeIterator()
while let arg = it.next() {
    switch arg {
    case "--duration", "-d":
        if let val = it.next(), let d = Double(val) {
            listenDuration = d
        } else {
            print("Error: --duration requires a numeric value in seconds.")
            exit(1)
        }
    case "--help", "-h":
        print("""
hid-capture — MSI MD342CQP HID input-report listener

USAGE
    swift tools/hid-capture/hid-capture.swift [OPTIONS]

OPTIONS
    --duration <s>   Listen for this many seconds (default: 30)
    --help           Show this help

CAVEATS
    This tool listens for INPUT reports from the monitor (device → host).
    The MD342CQP almost certainly sends NONE during normal use — the protocol
    is output-only (host → device).  Run hid-probe to send candidate payloads.
""")
        exit(0)
    default:
        print("Unknown argument: \(arg).  Run with --help for usage.")
        exit(1)
    }
}

// ─── Constants ──────────────────────────────────────────────────────────────

let kVendorID:  Int = 0x1462
let kProductID: Int = 0x3FA4

// ─── Helpers ────────────────────────────────────────────────────────────────

func printSeparator() { print(String(repeating: "─", count: 60)) }

func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

// ─── Setup ──────────────────────────────────────────────────────────────────

print("")
printSeparator()
print("MSI MD342CQP HID Capture")
printSeparator()
print("VID: 0x1462  PID: 0x3FA4  Duration: \(Int(listenDuration)) s")
print("")
print("NOTE: This monitors INPUT reports (device → host).  The MD342CQP")
print("      protocol is OUTPUT-only, so expect 0 reports from OSD presses.")
print("      For payload discovery, use hid-probe instead.")
print("")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey:  kVendorID,
    kIOHIDProductIDKey: kProductID
] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print("Error: could not open IOHIDManager (\(openResult))")
    exit(1)
}

// Brief enumeration wait
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

guard let deviceSet = IOHIDManagerCopyDevices(manager),
      let deviceArray = deviceSet as? Set<IOHIDDevice>,
      !deviceArray.isEmpty else {
    print("Device not found: VID=0x1462 PID=0x3FA4")
    print("Connect the monitor via USB and try again.")
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    exit(0)
}

// ─── Per-interface buffer + callback ─────────────────────────────────────

// We keep a buffer per device so the closure pointer stays valid
var reportBuffers: [Data] = []
var totalReports = 0

printSeparator()
print("Opening \(deviceArray.count) HID interface(s)")
printSeparator()

for (i, device) in deviceArray.enumerated() {
    let maxInput = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64
    let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
    let usage     = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
    let maxOutput = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) ?? 0

    print("Interface \(i + 1): usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) maxIn=\(maxInput) maxOut=\(maxOutput)")

    // Allocate buffer (kept alive as a local var, then stored)
    var buffer = Data(count: max(maxInput, 1))
    reportBuffers.append(buffer)

    let devOpenResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    if devOpenResult != kIOReturnSuccess {
        print("  Could not open (error \(devOpenResult)). Skipping.")
        continue
    }

    // Capture index for the closure
    let idx = i

    buffer.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
        guard let base = ptr.baseAddress else { return }
        let typedPtr = base.assumingMemoryBound(to: UInt8.self)

        IOHIDDeviceRegisterInputReportCallback(
            device,
            typedPtr,
            maxInput,
            { _, result, _, type, reportID, report, reportLength in
                totalReports += 1
                let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
                let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("[\(timestamp())] REPORT #\(totalReports) — interface \(idx + 1)  ID=\(reportID)  len=\(reportLength)")
                print("  hex: \(hex)")
                if let ascii = String(bytes: bytes.filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii), !ascii.isEmpty {
                    print("  ascii: \"\(ascii)\"")
                }
                print("")
            },
            nil
        )
    }
}

// ─── Listen ─────────────────────────────────────────────────────────────────

print("")
print("Listening for \(Int(listenDuration)) seconds.  Interact with the monitor OSD now.")
print("(Press Ctrl-C to stop early.)")
print("")

RunLoop.current.run(until: Date(timeIntervalSinceNow: listenDuration))

// ─── Summary ─────────────────────────────────────────────────────────────────

printSeparator()
print("Capture complete.  Input reports received: \(totalReports)")
print("")

if totalReports == 0 {
    print("As expected for the MD342CQP: zero input reports during OSD interaction.")
    print("The OSD operates entirely within the monitor firmware — no HID traffic")
    print("flows from the monitor to the host when you press OSD buttons.")
    print("")
    print("Next step: use hid-probe to discover PBP/KVM payloads by opcode probing.")
    print("  swift tools/hid-probe/hid-probe.swift --help")
} else {
    print("Unexpected input reports received!  Copy the hex bytes above and")
    print("paste them into docs/PROTOCOL.md under the relevant action.")
}
print("")

IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
