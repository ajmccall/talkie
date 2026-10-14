#!/bin/bash
# Generates Resources/Talkie.icns. Uses Resources/icon-1024.png if present;
# otherwise draws a simple one (a microphone on a rounded gradient square).
set -euo pipefail
cd "$(dirname "$0")/.."
PNG=Resources/icon-1024.png
if [ ! -f "$PNG" ]; then
  echo "Drawing $PNG"
  swift - "$PNG" <<'SWIFT'
import AppKit
let out = CommandLine.arguments[1]
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
// macOS icon grid: the rounded square is ~80% of the canvas.
let inset = size * 0.1
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.86, alpha: 1),
                          ending: NSColor(calibratedRed: 0.14, green: 0.11, blue: 0.40, alpha: 1))!
gradient.draw(in: path, angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let symbolSize = symbol.size
let scale = (rect.width * 0.5) / max(symbolSize.width, symbolSize.height)
let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
let origin = NSPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)
NSColor.white.set()
let tinted = NSImage(size: drawSize, flipped: false) { r in
    symbol.draw(in: r)
    NSColor.white.set()
    r.fill(using: .sourceAtop)
    return true
}
tinted.draw(in: NSRect(origin: origin, size: drawSize))
image.unlockFocus()
let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
SWIFT
fi
set=build/Talkie.iconset
rm -rf "$set"; mkdir -p "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$PNG" --out "$set/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$PNG" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/Talkie.icns
echo "Wrote Resources/Talkie.icns"
