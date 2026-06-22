#!/usr/bin/env swift
//
//  read-probe.swift — can the MD342CQP REPORT its current input/KVM state?
//  tools/kvm-probe/read-probe.swift
//
//  The command grammar has a READ opcode (byte[2] = 0x38 '8', vs 0x62 'b' for
//  write). This probe sends a READ command for the Input and KVM features, then
//  tries IOHIDDeviceGetReport to see if the monitor returns the current value.
//  If it does, we can show a live "currently selected" highlight in the app.
//  If it returns nothing/errors, the monitor is output-only and we can't read state.
//
//  USAGE (from repo root):
//      swift tools/kvm-probe/read-probe.swift
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

let kVendorID:  Int = 0x1462
let kProductID: Int = 0x3FA4

// READ command: byte[2] = 0x38 ('8') instead of 0x62 ('b'); value byte left 0x30.
func readCommand(featHi: UInt8, featLo: UInt8) -> [UInt8] {
    var p = [UInt8](repeating: 0x00, count: 53)
    p[0]  = 0x01; p[1] = 0x35
    p[2]  = 0x38            // '8' = READ
    p[3]  = 0x30; p[4] = 0x30
    p[5]  = featHi; p[6] = featLo
    p[7]  = 0x30; p[8] = 0x30; p[9] = 0x30
    p[10] = 0x30
    p[11] = 0x0D
    return p
}

func locateDevice() -> IOHIDDevice? {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, [
        kIOHIDVendorIDKey: kVendorID, kIOHIDProductIDKey: kProductID
    ] as CFDictionary)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
    guard let set = IOHIDManagerCopyDevices(mgr),
          let arr = set as? Set<IOHIDDevice>, let first = arr.first else { return nil }
    return first
}

// Open-and-check with a few retries — IOHIDDeviceOpen can return NotOpen
// transiently; matches the app's working send lifecycle.
func ensureOpen(_ device: IOHIDDevice) -> Bool {
    for _ in 0..<5 {
        if IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess { return true }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
    }
    return false
}

func hex(_ bytes: ArraySlice<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

guard let device = locateDevice() else {
    print("❌ Monitor not found (VID 0x1462 / PID 0x3FA4).")
    exit(1)
}
guard ensureOpen(device) else {
    print("❌ Could not open the device (kIOReturnNotOpen). Quit the MSI app + ensure USB on this Mac.")
    exit(1)
}
print("MSI MD342CQP — read-state probe\n================================\n")

// Try both report directions for each feature: send a READ output report, then
// GetReport on Input and Feature report types to see if the monitor answers.
let features: [(String, UInt8, UInt8)] = [
    ("Input (0x35 0x30)", 0x35, 0x30),
    ("KVM   (0x38 0x3e)", 0x38, 0x3e),
]

for (label, hi, lo) in features {
    print("── \(label) ──")
    var cmd = readCommand(featHi: hi, featLo: lo)
    let sendRet = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(cmd[0]), &cmd, cmd.count)
    print("  read-cmd sent: IOReturn 0x\(String(format: "%08x", UInt32(bitPattern: Int32(sendRet))))")

    // Give the monitor a moment to prepare a reply.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

    for (typeName, type) in [("Input", kIOHIDReportTypeInput), ("Feature", kIOHIDReportTypeFeature)] {
        var buf = [UInt8](repeating: 0, count: 64)
        var len = buf.count
        let getRet = IOHIDDeviceGetReport(device, type, CFIndex(0x01), &buf, &len)
        if getRet == kIOReturnSuccess {
            print("  GetReport(\(typeName)) OK, \(len) bytes: \(hex(buf[0..<min(len, 16)]))…")
        } else {
            print("  GetReport(\(typeName)) failed: IOReturn 0x\(String(format: "%08x", UInt32(bitPattern: Int32(getRet))))")
        }
    }
    print("")
}

print("Interpretation:")
print("  • If a GetReport returned bytes whose value byte (index ~10) changes when")
print("    you switch input via the OSD, we CAN read state → live highlight feature.")
print("  • If all GetReports fail / return constant junk, the monitor is output-only.")
