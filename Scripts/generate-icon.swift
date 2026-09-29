#!/usr/bin/env swift

// Generiert das HotSync App-Icon im klassischen Stil:
// Zwei verschlungene Pfeile (rot + blau) in einem Kreis

import AppKit
import Foundation

// MARK: - Icon zeichnen

func drawHotSyncIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let padding = size * 0.08
    let center = CGPoint(x: size / 2, y: size / 2)
    let outerRadius = (size / 2) - padding
    let circleLineWidth = size * 0.07
    let arrowWidth = size * 0.12
    let arrowHeadLength = size * 0.18
    let arrowHeadWidth = size * 0.22

    // Hintergrund: Weißer Kreis mit Schatten
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: CGColor(gray: 0, alpha: 0.3))
    context.setFillColor(CGColor.white)
    context.addEllipse(in: CGRect(x: padding, y: padding, width: outerRadius * 2, height: outerRadius * 2))
    context.fillPath()
    context.restoreGState()

    // Innerer Kreis-Ring (grauer Rand)
    let ringRadius = outerRadius - circleLineWidth / 2
    context.setStrokeColor(CGColor(gray: 0.85, alpha: 1.0))
    context.setLineWidth(circleLineWidth * 0.3)
    context.addEllipse(in: CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))
    context.strokePath()

    // --- Roter Pfeil (oben-links → unten-rechts, Kurve nach links-unten) ---
    drawRedArrow(context: context, center: center, radius: outerRadius, size: size,
                 arrowWidth: arrowWidth, headLength: arrowHeadLength, headWidth: arrowHeadWidth)

    // --- Blauer Pfeil (unten-rechts → oben-links, Kurve nach rechts-oben) ---
    drawBlueArrow(context: context, center: center, radius: outerRadius, size: size,
                  arrowWidth: arrowWidth, headLength: arrowHeadLength, headWidth: arrowHeadWidth)

    image.unlockFocus()
    return image
}

func drawRedArrow(context: CGContext, center: CGPoint, radius: CGFloat, size: CGFloat,
                  arrowWidth: CGFloat, headLength: CGFloat, headWidth: CGFloat) {
    context.saveGState()

    // Roter Pfeil: von oben (12 Uhr) im Bogen nach links-unten, Pfeilspitze zeigt nach unten-links
    let red = CGColor(red: 0.75, green: 0.05, blue: 0.1, alpha: 1.0)
    let darkRed = CGColor(red: 0.6, green: 0.02, blue: 0.08, alpha: 1.0)

    // Pfeilschaft als Arc
    let arrowRadius = radius * 0.52
    let startAngle: CGFloat = .pi * 0.55   // ca. 100° (oben-links)
    let endAngle: CGFloat = .pi * 1.85     // ca. 333° (unten-rechts area)

    // Schaft (breiter Bogen)
    let path = CGMutablePath()

    // Äußerer Bogen
    let outerR = arrowRadius + arrowWidth / 2
    let innerR = arrowRadius - arrowWidth / 2

    // Bogen zeichnen (Schaft)
    path.addArc(center: center, radius: outerR, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    path.addArc(center: center, radius: innerR, startAngle: endAngle, endAngle: startAngle, clockwise: false)
    path.closeSubpath()

    context.setFillColor(red)
    context.addPath(path)
    context.fillPath()

    // Pfeilspitze am Start-Ende (zeigt nach oben-links)
    let tipAngle = startAngle
    let tipX = center.x + arrowRadius * cos(tipAngle)
    let tipY = center.y + arrowRadius * sin(tipAngle)

    // Richtung der Pfeilspitze (tangential zum Kreis, in Pfeilrichtung)
    let tangentAngle = tipAngle + .pi / 2  // perpendicular, pointing in arrow direction

    let tipDirX = cos(tangentAngle)
    let tipDirY = sin(tangentAngle)
    let perpX = -tipDirY
    let perpY = tipDirX

    let arrowTip = CGMutablePath()
    // Spitze
    arrowTip.move(to: CGPoint(
        x: tipX + tipDirX * headLength,
        y: tipY + tipDirY * headLength
    ))
    // Linke Seite
    arrowTip.addLine(to: CGPoint(
        x: tipX - perpX * headWidth / 2,
        y: tipY - perpY * headWidth / 2
    ))
    // Rechte Seite
    arrowTip.addLine(to: CGPoint(
        x: tipX + perpX * headWidth / 2,
        y: tipY + perpY * headWidth / 2
    ))
    arrowTip.closeSubpath()

    context.setFillColor(darkRed)
    context.addPath(arrowTip)
    context.fillPath()

    // Nochmal mit dem helleren Rot überlagern für Gradient-Effekt
    context.setFillColor(red)
    context.addPath(arrowTip)
    context.fillPath()

    context.restoreGState()
}

func drawBlueArrow(context: CGContext, center: CGPoint, radius: CGFloat, size: CGFloat,
                   arrowWidth: CGFloat, headLength: CGFloat, headWidth: CGFloat) {
    context.saveGState()

    let blue = CGColor(red: 0.15, green: 0.12, blue: 0.65, alpha: 1.0)

    let arrowRadius = radius * 0.52
    let startAngle: CGFloat = .pi * 1.55   // ca. 280° (unten-rechts)
    let endAngle: CGFloat = .pi * 0.85     // ca. 153° (oben-links area)

    // Schaft
    let outerR = arrowRadius + arrowWidth / 2
    let innerR = arrowRadius - arrowWidth / 2

    let path = CGMutablePath()
    path.addArc(center: center, radius: outerR, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    path.addArc(center: center, radius: innerR, startAngle: endAngle, endAngle: startAngle, clockwise: false)
    path.closeSubpath()

    context.setFillColor(blue)
    context.addPath(path)
    context.fillPath()

    // Pfeilspitze
    let tipAngle = startAngle
    let tipX = center.x + arrowRadius * cos(tipAngle)
    let tipY = center.y + arrowRadius * sin(tipAngle)

    let tangentAngle = tipAngle + .pi / 2
    let tipDirX = cos(tangentAngle)
    let tipDirY = sin(tangentAngle)
    let perpX = -tipDirY
    let perpY = tipDirX

    let arrowTip = CGMutablePath()
    arrowTip.move(to: CGPoint(
        x: tipX + tipDirX * headLength,
        y: tipY + tipDirY * headLength
    ))
    arrowTip.addLine(to: CGPoint(
        x: tipX - perpX * headWidth / 2,
        y: tipY - perpY * headWidth / 2
    ))
    arrowTip.addLine(to: CGPoint(
        x: tipX + perpX * headWidth / 2,
        y: tipY + perpY * headWidth / 2
    ))
    arrowTip.closeSubpath()

    context.setFillColor(blue)
    context.addPath(arrowTip)
    context.fillPath()

    context.restoreGState()
}

// MARK: - PNG Export

func savePNG(_ image: NSImage, to path: String, size: Int) {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1.0)
    resized.unlockFocus()

    guard let tiffData = resized.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Fehler beim Speichern: \(path)")
        return
    }

    try! pngData.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

let projectDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let iconsetDir = "\(projectDir)/HotSync.iconset"

// Iconset-Ordner erstellen
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// Icon in hoher Auflösung zeichnen
let masterIcon = drawHotSyncIcon(size: 1024)

// Alle erforderlichen Größen für .icns
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

print("Generiere HotSync-Icon...")
for (name, px) in sizes {
    let path = "\(iconsetDir)/\(name).png"
    savePNG(masterIcon, to: path, size: px)
    print("  \(name).png (\(px)x\(px))")
}

print("Erstelle .icns...")

// iconutil aufrufen
let icnsPath = "\(projectDir)/Resources/AppIcon.icns"
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Icon erstellt: \(icnsPath)")
    // Cleanup
    try? FileManager.default.removeItem(atPath: iconsetDir)
} else {
    print("FEHLER: iconutil fehlgeschlagen (Exit \(process.terminationStatus))")
}
