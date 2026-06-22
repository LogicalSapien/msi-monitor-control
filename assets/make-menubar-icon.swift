#!/usr/bin/env swift
//
// make-menubar-icon.swift — regenerate the menu-bar template icon PDF.
//
// Draws the monochrome "monitor + switch-arrows" motif (mirroring
// assets/menubar-icon.svg) into a vector PDF, sized 18×18pt. The PDF is solid
// black on a transparent background so the app can load it as a TEMPLATE image
// (NSImage.isTemplate = true) and let macOS tint it for light/dark menu bars.
//
// Usage (macOS, no Xcode required), from anywhere — paths are resolved relative
// to this script's own location, NOT the current working directory:
//   swift assets/make-menubar-icon.swift
// Writes: assets/menubar-icon.pdf  AND copies it to the SwiftPM resource dir
//         macos/Sources/MSIControlApp/Resources/menubar-icon.pdf (kept in sync).
//
import AppKit

let size: CGFloat = 18                     // menu-bar point size
let scale: CGFloat = size / 36.0           // SVG authored in a 36×36 space
var mediaBox = CGRect(x: 0, y: 0, width: size, height: size)

// Resolve paths from this script's location (…/assets/make-menubar-icon.swift)
// so regeneration is CWD-independent. assetsDir = …/assets, repoRoot = its parent.
let scriptURL = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
let assetsDir = scriptURL.deletingLastPathComponent()
let repoRoot  = assetsDir.deletingLastPathComponent()
let outURL = assetsDir.appendingPathComponent("menubar-icon.pdf")
let resourceURL = repoRoot
    .appendingPathComponent("macos/Sources/MSIControlApp/Resources/menubar-icon.pdf")

guard let ctx = CGContext(outURL as CFURL, mediaBox: &mediaBox, nil) else {
    FileHandle.standardError.write(Data("error: could not create PDF context\n".utf8))
    exit(1)
}

ctx.beginPDFPage(nil)

// Flip into a top-left origin so the coordinates match the SVG (y grows downward),
// then scale the 36×36 design space down to the 18pt page.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: scale, y: -scale)

ctx.setStrokeColor(NSColor.black.cgColor)
ctx.setFillColor(NSColor.black.cgColor)
ctx.setLineWidth(2)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Monitor bezel (rounded-rect outline).
let bezel = CGPath(roundedRect: CGRect(x: 4.5, y: 6, width: 27, height: 17),
                   cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
ctx.addPath(bezel)
ctx.strokePath()

// Stand neck + base (filled).
ctx.fill(CGRect(x: 16.5, y: 23, width: 3, height: 3.5))
let base = CGPath(roundedRect: CGRect(x: 11, y: 26.5, width: 14, height: 2.4),
                  cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)
ctx.addPath(base)
ctx.fillPath()

// Top arc (left→right) + right-pointing arrowhead.
let topArc = CGMutablePath()
topArc.move(to: CGPoint(x: 11, y: 16))
topArc.addCurve(to: CGPoint(x: 25, y: 16),
                control1: CGPoint(x: 11, y: 11.5),
                control2: CGPoint(x: 25, y: 11.5))
ctx.addPath(topArc)
ctx.strokePath()
ctx.beginPath()
ctx.move(to: CGPoint(x: 25, y: 17.5))
ctx.addLine(to: CGPoint(x: 22, y: 12.5))
ctx.addLine(to: CGPoint(x: 28, y: 12.5))
ctx.closePath()
ctx.fillPath()

// Bottom arc (right→left) + left-pointing arrowhead.
let bottomArc = CGMutablePath()
bottomArc.move(to: CGPoint(x: 25, y: 13))
bottomArc.addCurve(to: CGPoint(x: 11, y: 13),
                   control1: CGPoint(x: 25, y: 17.5),
                   control2: CGPoint(x: 11, y: 17.5))
ctx.addPath(bottomArc)
ctx.strokePath()
ctx.beginPath()
ctx.move(to: CGPoint(x: 11, y: 11.5))
ctx.addLine(to: CGPoint(x: 14, y: 16.5))
ctx.addLine(to: CGPoint(x: 8, y: 16.5))
ctx.closePath()
ctx.fillPath()

ctx.endPDFPage()
ctx.closePDF()

print("Wrote \(outURL.path)")

// Keep the SwiftPM resource copy in sync so the app bundles the freshly generated
// icon (the package resource is loaded via Bundle.module / Contents/Resources).
do {
    let fm = FileManager.default
    try fm.createDirectory(at: resourceURL.deletingLastPathComponent(),
                           withIntermediateDirectories: true)
    if fm.fileExists(atPath: resourceURL.path) {
        try fm.removeItem(at: resourceURL)
    }
    try fm.copyItem(at: outURL, to: resourceURL)
    print("Copied to \(resourceURL.path)")
} catch {
    FileHandle.standardError.write(Data("error: could not copy to resource dir: \(error)\n".utf8))
    exit(1)
}
