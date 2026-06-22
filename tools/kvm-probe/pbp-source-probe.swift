#!/usr/bin/env swift
//
//  pbp-source-probe.swift — find the PBP/PIP per-window SOURCE-select feature(s)
//  tools/kvm-probe/pbp-source-probe.swift
//
//  Mode feature is 0x36 0x30 (value: 0=off, 1=PIP, 2/3=PBP). The per-window
//  source (which input feeds the left/main window vs the right/sub window) is
//  almost certainly a NEARBY feature. This probes candidate source features by
//  cycling their value 0..4 (likely the input enum: 0=HDMI1 1=HDMI2 2=DP 3=Type-C)
//  so you can watch which window's source changes.
//
//  PRE: put the monitor in PBP first (so two windows are visible):
//      swift tools/kvm-probe/pbp-values.swift 0x36 0x30     # then send value 2 (PBP)
//
//  USAGE: probe ONE candidate source-feature, cycling its value 0..4:
//      swift tools/kvm-probe/pbp-source-probe.swift 0x36 0x31
//      swift tools/kvm-probe/pbp-source-probe.swift 0x36 0x32
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

let kVendorID: Int = 0x1462
let kProductID: Int = 0x3FA4

guard CommandLine.arguments.count == 3,
      let featHi = UInt8(CommandLine.arguments[1].replacingOccurrences(of: "0x", with: ""), radix: 16),
      let featLo = UInt8(CommandLine.arguments[2].replacingOccurrences(of: "0x", with: ""), radix: 16) else {
    print("usage: swift tools/kvm-probe/pbp-source-probe.swift <featHi> <featLo>   e.g. 0x36 0x31")
    exit(2)
}

func cmd(value: UInt8) -> [UInt8] {
    var p = [UInt8](repeating: 0x00, count: 53)
    p[0] = 0x01; p[1] = 0x35; p[2] = 0x62; p[3] = 0x30; p[4] = 0x30
    p[5] = featHi; p[6] = featLo
    p[7] = 0x30; p[8] = 0x30; p[9] = 0x30
    p[10] = 0x30 + value
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

func send(_ payload: [UInt8], to device: IOHIDDevice) -> IOReturn {
    func attempt() -> IOReturn {
        let o = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if o != kIOReturnSuccess { return o }
        var m = payload
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(payload[0]), &m, payload.count)
    }
    var r = attempt()
    if r == kIOReturnNotOpen || r == kIOReturnNotPermitted { r = attempt() }
    return r
}

guard let device = locateDevice() else { print("❌ Monitor not found."); exit(1) }

let f = String(format: "0x%02x 0x%02x", featHi, featLo)
print("MSI MD342CQP — PBP source-feature probe: \(f)\n")
print("Make sure the monitor is in PBP/PIP first (two windows visible).")
print("I cycle this feature's value 0..4. Watch which WINDOW's source changes (and to what).")
print("Input enum is usually 0=HDMI1 1=HDMI2 2=DP 3=Type-C.\n")

for value in UInt8(0)...UInt8(4) {
    print("→ Press Enter to send \(f) = \(value)…", terminator: "")
    _ = readLine()
    let r = send(cmd(value: value), to: device)
    if r == kIOReturnSuccess {
        print("   sent. 👀 Which window changed source, and to which input?\n")
    } else {
        print("   ⚠️ send failed 0x\(String(format: "%08x", UInt32(bitPattern: Int32(r)))).\n")
    }
}

print("Report: for \(f), did value 0..4 change the LEFT/main window, the RIGHT/sub window,")
print("or nothing? And which input each value selected (HDMI1/HDMI2/DP/Type-C)?")
