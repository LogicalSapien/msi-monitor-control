#!/usr/bin/env swift
//
//  hid-info.swift — MSI MD342CQP HID device enumerator
//  tools/hid-info/hid-info.swift
//
//  Enumerates all HID interfaces for VID=0x1462 PID=0x3FA4 and prints:
//    • Device path, usage page, usage, report descriptor (if readable)
//    • Whether the device sends any input reports (waits 3 s)
//    • An honest assessment of passive-capture feasibility
//
//  Run from repo root:
//      swift tools/hid-info/hid-info.swift
//
//  No dependencies beyond macOS IOKit (macOS 11+).
//  If the monitor is not connected the tool exits cleanly with a diagnostic.
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

// ─── Target device ──────────────────────────────────────────────────────────

let kVendorID:  Int = 0x1462   // MSI (Micro-Star International)
let kProductID: Int = 0x3FA4   // MD342CQP

// ─── Helpers ────────────────────────────────────────────────────────────────

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func printSeparator() {
    print(String(repeating: "─", count: 60))
}

// ─── Device matching ────────────────────────────────────────────────────────

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

let matchCriteria: [String: Any] = [
    kIOHIDVendorIDKey:  kVendorID,
    kIOHIDProductIDKey: kProductID
]
IOHIDManagerSetDeviceMatching(manager, matchCriteria as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

print("")
printSeparator()
print("MSI MD342CQP HID Device Enumerator")
print("VID: 0x\(String(kVendorID, radix: 16, uppercase: true))  PID: 0x\(String(kProductID, radix: 16, uppercase: true))")
printSeparator()

guard openResult == kIOReturnSuccess else {
    print("Could not open IOHIDManager (error: \(openResult))")
    print("Make sure the monitor is connected via USB and try again.")
    exit(1)
}

// Give IOKit a moment to enumerate
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

guard let deviceSet = IOHIDManagerCopyDevices(manager),
      let deviceArray = deviceSet as? Set<IOHIDDevice>,
      !deviceArray.isEmpty else {

    print("Device NOT found: VID=0x1462 PID=0x3FA4")
    print("")
    print("Possible causes:")
    print("  1. Monitor not connected via USB.")
    print("  2. Monitor connected via USB-C but without the USB upstream cable.")
    print("  3. Wrong VID/PID — run `system_profiler SPUSBDataType` to verify.")
    print("")
    printSeparator()
    print("VERDICT on passive HID capture")
    printSeparator()
    print("""
Even if the device were connected, passive IOHIDManager input-report listening
almost certainly cannot capture PBP/KVM toggle traffic.  Here is why:

  • The MSI MD342CQP control protocol sends OUTPUT reports from HOST → MONITOR.
    The host writes a 53-byte ASCII command; the monitor acts on it silently.
  • When you press OSD buttons on the monitor itself, the firmware changes
    state INTERNALLY — no HID report is sent to the host.  There is nothing
    to sniff from the macOS side.
  • An IOHIDManager input-report callback fires only when the DEVICE sends data
    to the HOST (IN endpoint).  For a pure output-report HID device like this
    one, that never happens during normal use.

RECOMMENDED CAPTURE METHOD: opcode probing (see tools/hid-probe/).
  Swift tools/hid-probe/hid-probe.swift

Alternatively, on Windows: run MSI Productivity Intelligence + Wireshark +
USBPcap and trigger PBP/KVM from the software — the Windows host then sends
the output report, which USBPcap can capture.
""")
    exit(0)
}

// ─── Found devices — enumerate each interface ────────────────────────────────

print("Found \(deviceArray.count) HID interface(s) for VID=0x1462 PID=0x3FA4")
print("")

var inputReportsReceived = 0

for (index, device) in deviceArray.enumerated() {
    printSeparator()
    print("Interface \(index + 1)")
    printSeparator()

    func prop(_ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    let productName   = prop(kIOHIDProductKey) as? String   ?? "(unknown)"
    let manufacturer  = prop(kIOHIDManufacturerKey) as? String ?? "(unknown)"
    let transport     = prop(kIOHIDTransportKey) as? String   ?? "(unknown)"
    let usagePage     = prop(kIOHIDPrimaryUsagePageKey) as? Int ?? -1
    let usage         = prop(kIOHIDPrimaryUsageKey) as? Int     ?? -1
    let maxInputSize  = prop(kIOHIDMaxInputReportSizeKey) as? Int  ?? 0
    let maxOutputSize = prop(kIOHIDMaxOutputReportSizeKey) as? Int ?? 0
    let maxFeatureSize = prop(kIOHIDMaxFeatureReportSizeKey) as? Int ?? 0

    print("Product:        \(productName)")
    print("Manufacturer:   \(manufacturer)")
    print("Transport:      \(transport)")
    print("Usage page:     0x\(String(usagePage, radix: 16, uppercase: true)) (\(usagePage))")
    print("Usage:          0x\(String(usage, radix: 16, uppercase: true)) (\(usage))")
    print("Max input size: \(maxInputSize) bytes")
    print("Max output size:\(maxOutputSize) bytes")
    print("Max feature sz: \(maxFeatureSize) bytes")

    // Try to read the report descriptor
    if let descriptorData = prop(kIOHIDReportDescriptorKey) as? Data {
        let bytes = [UInt8](descriptorData)
        print("Report descriptor (\(bytes.count) bytes):")
        // Print 16 bytes per line
        var offset = 0
        while offset < bytes.count {
            let slice = Array(bytes[offset..<min(offset + 16, bytes.count)])
            print("  \(String(format: "%04x", offset)): \(hexString(slice))")
            offset += 16
        }
    } else {
        print("Report descriptor: (not available via IOKit property)")
    }

    // Register input-report callback to see if the device ever sends data
    let callbackInfo = Unmanaged.passRetained(NSMutableDictionary())

    IOHIDDeviceRegisterInputReportCallback(
        device,
        UnsafeMutablePointer<UInt8>.allocate(capacity: 64),
        64,
        { context, result, sender, type, reportID, report, reportLength in
            inputReportsReceived += 1
            let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
            print("")
            print(">>> INPUT REPORT received (ID=\(reportID), len=\(reportLength))")
            print("    \(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
        },
        nil
    )

    let openDevResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    if openDevResult != kIOReturnSuccess {
        print("Could not open interface (error \(openDevResult)) — may need accessibility permissions")
    }
}

// ─── Passive listen for input reports ─────────────────────────────────────

print("")
printSeparator()
print("Passive input-report listener — waiting 3 seconds")
print("(Interact with the monitor OSD now to see if any reports arrive)")
printSeparator()
print("")

RunLoop.current.run(until: Date(timeIntervalSinceNow: 3.0))

printSeparator()
print("Listener finished.  Input reports received: \(inputReportsReceived)")
print("")

if inputReportsReceived == 0 {
    print("No input reports received — as expected for this device.")
    print("")
}

// ─── Verdict ────────────────────────────────────────────────────────────────

printSeparator()
print("VERDICT on passive HID capture")
printSeparator()
print("""
The MD342CQP uses a pure output-report protocol:
  HOST → MONITOR (set report, 53 bytes, ASCII command)

When you press the OSD buttons on the monitor, the firmware responds
INTERNALLY.  No HID report is sent back to the host.  An IOHIDManager
input-report listener therefore captures NOTHING when you toggle PBP or
KVM via the OSD.

Passive listening is ONLY useful if MSI's own desktop software is running
and sending output reports — but that software is Windows-only.

BEST CAPTURE PATHS (in order of effort):

  1. OPCODE PROBE (easiest — macOS, no extra software needed)
        swift tools/hid-probe/hid-probe.swift
     Send candidate payloads one at a time, watch the monitor react.
     Since the protocol is ASCII text with a single byte varying (the
     opcode), a small search space (~20 candidates) covers PBP and KVM.

  2. WINDOWS WIRESHARK (most reliable, needs Windows)
     Run MSI Productivity Intelligence + Wireshark + USBPcap on Windows.
     Trigger PBP/KVM from the app.  USBPcap captures the output report.
     See docs/REVERSE-ENGINEERING.md for the step-by-step guide.
""")

IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
