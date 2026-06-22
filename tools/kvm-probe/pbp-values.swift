#!/usr/bin/env swift
//
//  pbp-values.swift — map the PBP/PIP feature (candidate 0x36 0x30) value bytes
//  tools/kvm-probe/pbp-values.swift
//
//  The sweep suggested feature 0x36 0x30 controls PIP/PBP. This sends that
//  feature with value 0,1,2,3,4 one per keypress so we learn: 0=off?, 1=on/mode,
//  etc. It sends value 0 (OFF) FIRST to restore a normal screen.
//
//  USAGE (from repo root):
//      swift tools/kvm-probe/pbp-values.swift            # default feature 0x36 0x30
//      swift tools/kvm-probe/pbp-values.swift 0x36 0x31  # try a different feature
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

let kVendorID: Int = 0x1462
let kProductID: Int = 0x3FA4

var featHi: UInt8 = 0x36
var featLo: UInt8 = 0x30
if CommandLine.arguments.count == 3,
   let hi = UInt8(CommandLine.arguments[1].replacingOccurrences(of: "0x", with: ""), radix: 16),
   let lo = UInt8(CommandLine.arguments[2].replacingOccurrences(of: "0x", with: ""), radix: 16) {
    featHi = hi; featLo = lo
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
print("MSI MD342CQP — PBP value mapper for feature \(f)\n")
print("Sending value 0 (likely OFF) first to restore your screen, then 1..4.\n")

for value in UInt8(0)...UInt8(4) {
    print("→ Press Enter to send \(f) = \(value) (byte[10]=0x\(String(format: "%02x", 0x30 + value)))…", terminator: "")
    _ = readLine()
    let r = send(cmd(value: value), to: device)
    if r == kIOReturnSuccess {
        print("   sent. 👀 What's on screen now? (normal / PIP / PBP split / black / no change)\n")
    } else {
        print("   ⚠️ send failed 0x\(String(format: "%08x", UInt32(bitPattern: Int32(r)))) — control/USB on Mac, app quit.\n")
    }
}

print("Report what each value did:")
print("  \(f) = 0 → ?   1 → ?   2 → ?   3 → ?   4 → ?")
print("(We want: which value = PBP OFF, which = PBP/PIP ON, and any extra modes.)")
