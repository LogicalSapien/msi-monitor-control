#!/usr/bin/env swift
//
//  kvm-send.swift — send ONE KVM position to the MD342CQP, then exit.
//  tools/kvm-probe/kvm-send.swift
//
//  Locates the device fresh on every run (no stale handle), sends the KVM
//  feature 0x38 0x3e with byte[10] = 0x30 + <position>, and exits. Run it once
//  per value so the KVM switching USB away mid-run can't break a later send.
//
//  USAGE (from repo root), position 0..3:
//      swift tools/kvm-probe/kvm-send.swift 0     # byte[10] = 0x30
//      swift tools/kvm-probe/kvm-send.swift 2     # byte[10] = 0x32
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

let kVendorID:  Int = 0x1462
let kProductID: Int = 0x3FA4

guard CommandLine.arguments.count == 2,
      let position = UInt8(CommandLine.arguments[1]), position <= 9 else {
    print("usage: swift tools/kvm-probe/kvm-send.swift <position 0-9>")
    exit(2)
}

func kvmPayload(position: UInt8) -> [UInt8] {
    var p = [UInt8](repeating: 0x00, count: 53)
    p[0]  = 0x01; p[1] = 0x35; p[2] = 0x62; p[3] = 0x30; p[4] = 0x30
    p[5]  = 0x38; p[6] = 0x3e            // KVM feature
    p[7]  = 0x30; p[8] = 0x30; p[9] = 0x30
    p[10] = 0x30 + position              // value
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

guard let device = locateDevice() else {
    print("❌ Monitor not found (VID 0x1462 / PID 0x3FA4). Connected by USB?")
    exit(1)
}

let value = 0x30 + position
let payload = kvmPayload(position: position)

// Open-and-check, retry up to 3 times on a not-open/not-permitted handle.
var ret = kIOReturnNotOpen
for _ in 0..<3 {
    let openRet = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    if openRet != kIOReturnSuccess { ret = openRet; continue }
    var mutable = payload
    ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(payload[0]), &mutable, payload.count)
    if ret == kIOReturnSuccess { break }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
}

if ret == kIOReturnSuccess {
    print("✅ Sent KVM position \(position) (byte[10] = 0x\(String(format: "%02x", value))).")
    print("   👀 What did the monitor switch to?")
} else {
    print("⚠️  send failed: IOReturn 0x\(String(format: "%08x", UInt32(bitPattern: Int32(ret)))).")
    print("   Make sure control/USB is on THIS Mac and the MSI app is quit, then retry.")
    exit(1)
}
