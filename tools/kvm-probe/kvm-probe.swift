#!/usr/bin/env swift
//
//  kvm-probe.swift — MSI MD342CQP KVM position mapper
//  tools/kvm-probe/kvm-probe.swift
//
//  Sends the KVM feature (0x38 0x3e) with byte[10] cycling through positions
//  0–3, one per keypress, so you can watch the monitor and record which KVM
//  source each value actually selects. The app's labels (USB-C / Upstream /
//  Auto) were assigned from an unverified reference and are shifted — this maps
//  them for real.
//
//  USAGE (from repo root):
//      swift tools/kvm-probe/kvm-probe.swift
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

let kVendorID:  Int = 0x1462
let kProductID: Int = 0x3FA4

// KVM command: 0x01 0x35 0x62 0x30 0x30 [38 3e] 0x30 0x30 0x30 [value] 0x0D, padded to 53.
// Only byte[10] (the value) changes between positions; 0x30 = position 0.
func kvmPayload(position: UInt8) -> [UInt8] {
    var p = [UInt8](repeating: 0x00, count: 53)
    p[0]  = 0x01           // report ID
    p[1]  = 0x35           // '5' prefix
    p[2]  = 0x62           // 'b' = write
    p[3]  = 0x30
    p[4]  = 0x30
    p[5]  = 0x38           // KVM feature hi
    p[6]  = 0x3e           // KVM feature lo
    p[7]  = 0x30
    p[8]  = 0x30
    p[9]  = 0x30
    p[10] = 0x30 + position // value: '0' + position
    p[11] = 0x0D           // terminator
    return p
}

// We deliberately use the IOHIDManager only for discovery, then own the
// IOHIDDevice directly — and open-and-check before every send, retrying once on
// a not-open/not-permitted result. This mirrors the app's send lifecycle, which
// is what makes its sends succeed where a naive open-once probe failed with
// kIOReturnNotOpen (0xe00002cd).

func locateDevice() -> IOHIDDevice? {
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
          let first = arr.first else { return nil }
    return first
}

func send(_ payload: [UInt8], to device: IOHIDDevice) -> IOReturn {
    // Open-and-check before the write (IOHIDDeviceOpen on an already-open device
    // is a success no-op), retry once on NotOpen/NotPermitted.
    func attempt() -> IOReturn {
        let openRet = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if openRet != kIOReturnSuccess { return openRet }
        var mutable = payload
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(payload[0]), &mutable, payload.count)
    }
    var ret = attempt()
    if ret == kIOReturnNotOpen || ret == kIOReturnNotPermitted {
        ret = attempt()
    }
    return ret
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

// ─── Run ─────────────────────────────────────────────────────────────────────

print("MSI MD342CQP — KVM position probe")
print("=================================\n")

guard let device = locateDevice() else {
    print("❌ Monitor not found (VID 0x1462 / PID 0x3FA4). Is it connected by USB?")
    exit(1)
}
print("✅ Monitor found.\n")
print("For each position I send the KVM command, then you tell me what the monitor")
print("switched to (USB-C / Upstream / Auto / no change). Press Enter to send the next.\n")

for position in UInt8(0)...UInt8(3) {
    let value = 0x30 + position
    print("→ Press Enter to send KVM position \(position) (byte[10] = 0x\(String(format: "%02x", value)))…", terminator: "")
    _ = readLine()
    let payload = kvmPayload(position: position)
    let ret = send(payload, to: device)
    if ret == kIOReturnSuccess {
        print("   Sent: \(hex(payload))")
        print("   👀 What did the monitor switch to? (note it down)\n")
    } else {
        print("   ⚠️  send failed: IOReturn 0x\(String(ret, radix: 16))\n")
    }
}

print("Done. Report back which source each position selected:")
print("  position 0 (0x30) → ?")
print("  position 1 (0x31) → ?")
print("  position 2 (0x32) → ?")
print("  position 3 (0x33) → ?")
