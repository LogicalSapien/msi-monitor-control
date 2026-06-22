#!/usr/bin/env swift
//
//  pbp-probe.swift — hunt the PBP (Picture-by-Picture) feature code on the MD342CQP
//  tools/kvm-probe/pbp-probe.swift
//
//  ── FINDING (2026-06-22, hardware-confirmed on MD342CQP) ──────────────────────
//  PBP/PIP turned out NOT to need a feature-code sweep: it is the *value* byte of
//  feature 0x36 0x30 (the multi-window MODE feature): 0x30=Off, 0x31=PIP,
//  0x32=PBP, 0x33=alt-PBP. Per-window source = features 0x36 0x31 (sub) and
//  0x36 0x32 (main, assumed). Use tools/kvm-probe/pbp-values.swift to set the
//  mode and pbp-source-probe.swift for the per-window source. This sweeper is
//  kept as a general feature-code discovery aid for FUTURE unknown features.
//  ─────────────────────────────────────────────────────────────────────────────
//
//  PBP is NOT a value of a known feature — it's its OWN 2-byte feature code at
//  indices [5],[6] (like Input=0x35,0x30 and KVM=0x38,0x3e). We sweep candidate
//  feature codes with value=1 ("on") and you watch for the screen to split.
//
//  Before running: set PBP OFF via the monitor's OSD, and connect TWO sources so
//  a split is visible. Then run; for each candidate it sends "<feature> = 1" and
//  waits for you to say whether PBP turned on.
//
//  USAGE (from repo root):
//      swift tools/kvm-probe/pbp-probe.swift                # interactive sweep 0x30..0x3f x 0x30..0x3f
//      swift tools/kvm-probe/pbp-probe.swift 0x39 0x30      # send ONE feature code, value=1
//
//  © 2026 LogicalSapien — MIT licence
//

import IOKit
import IOKit.hid
import Foundation

let kVendorID:  Int = 0x1462
let kProductID: Int = 0x3FA4

// WRITE command for <feature hi,lo> with the given value byte.
func cmd(featHi: UInt8, featLo: UInt8, value: UInt8) -> [UInt8] {
    var p = [UInt8](repeating: 0x00, count: 53)
    p[0]  = 0x01; p[1] = 0x35; p[2] = 0x62; p[3] = 0x30; p[4] = 0x30
    p[5]  = featHi; p[6] = featLo
    p[7]  = 0x30; p[8] = 0x30; p[9] = 0x30
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

func feat(_ b: UInt8) -> String { String(format: "0x%02x", b) }

guard let device = locateDevice() else {
    print("❌ Monitor not found (VID 0x1462 / PID 0x3FA4)."); exit(1)
}
print("MSI MD342CQP — PBP feature-code probe\n=====================================\n")

// One-shot mode: explicit feature code.
let args = CommandLine.arguments
if args.count == 3, let hi = UInt8(args[1].replacingOccurrences(of: "0x", with: ""), radix: 16),
                    let lo = UInt8(args[2].replacingOccurrences(of: "0x", with: ""), radix: 16) {
    let c = cmd(featHi: hi, featLo: lo, value: 1)
    let r = send(c, to: device)
    print("Sent feature \(feat(hi)) \(feat(lo)) = 1 → IOReturn 0x\(String(format: "%08x", UInt32(bitPattern: Int32(r))))")
    print("👀 Did PBP turn on (screen split)?")
    exit(0)
}

// Interactive sweep.
print("SETUP: set PBP OFF via the monitor's OSD, connect two sources, control on this Mac.")
print("I'll send candidate PBP feature codes with value=1 ('on'). After each, look for a")
print("split screen. Press Enter to send the next; type 'y' + Enter the moment PBP turns on.\n")

// CURATED candidate feature codes, most-likely first. Known features cluster:
// Input = 0x35,0x30 ('5','0'); KVM = 0x38,0x3e ('8','>'). PBP is probably a
// nearby 2-byte code. We try the high-probability neighbours of those, then a
// fuller fallback. Each entry is (hi, lo). ~20 sends instead of 254.
let candidates: [(UInt8, UInt8)] = [
    // Neighbours of Input/KVM and common "PBP/PIP/multi-window" style codes:
    (0x35, 0x31), (0x35, 0x32), (0x35, 0x33), (0x35, 0x3e),
    (0x38, 0x30), (0x38, 0x31), (0x38, 0x3d), (0x38, 0x3f),
    (0x39, 0x30), (0x39, 0x31), (0x3a, 0x30), (0x3a, 0x31),
    (0x36, 0x30), (0x36, 0x31), (0x37, 0x30), (0x37, 0x31),
    (0x3b, 0x30), (0x3c, 0x30), (0x3d, 0x30), (0x3e, 0x30), (0x3f, 0x30),
]

print("Trying \(candidates.count) curated PBP candidates (most-likely first).")
print("After each send, if the screen SPLITS, type 'y'. Else just Enter for the next. 'q' quits.\n")

var lastSent: (UInt8, UInt8)? = nil
outer: for (hi, lo) in candidates {
    if let (lh, ll) = lastSent {
        print("→ [previous was \(feat(lh)) \(feat(ll))] type 'y' if THAT split the screen, else Enter for next: ", terminator: "")
    } else {
        print("→ Press Enter to send first candidate \(feat(hi)) \(feat(lo)): ", terminator: "")
    }
    let line = (readLine() ?? "").lowercased()
    if line == "q" { break outer }
    if line == "y", let (lh, ll) = lastSent {
        print("\n🎯 PBP turned on at feature \(feat(lh)) \(feat(ll))! Confirm with:")
        print("   swift tools/kvm-probe/pbp-probe.swift \(feat(lh)) \(feat(ll))")
        print("   (and tell me that code — then we find the OFF + source-select values)")
        exit(0)
    }
    let c = cmd(featHi: hi, featLo: lo, value: 1)
    let r = send(c, to: device)
    if r != kIOReturnSuccess {
        print("   ⚠️ send failed 0x\(String(format: "%08x", UInt32(bitPattern: Int32(r)))) — ensure control/USB on Mac, MSI app quit.")
    } else {
        print("   sent \(feat(hi)) \(feat(lo)) = 1 — did the screen split? (answer on the NEXT prompt)")
    }
    lastSent = (hi, lo)
}
if let (lh, ll) = lastSent {
    print("\n→ Last candidate was \(feat(lh)) \(feat(ll)). Type 'y' now if IT split the screen, else Enter: ", terminator: "")
    if (readLine() ?? "").lowercased() == "y" {
        print("🎯 PBP at \(feat(lh)) \(feat(ll)) — confirm: swift tools/kvm-probe/pbp-probe.swift \(feat(lh)) \(feat(ll))")
    }
}
print("\nDone. If none split the screen, tell me — I'll widen the candidate list.")
