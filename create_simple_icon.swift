#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Create a simple gradient icon with "TX" text
func createTENEXIcon(size: Int) -> CGImage? {
    let width = size
    let height = size
    
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil,
                                 width: width,
                                 height: height,
                                 bitsPerComponent: 8,
                                 bytesPerRow: 0,
                                 space: colorSpace,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    
    // Create gradient
    let colors = [
        CGColor(red: 88/255, green: 86/255, blue: 214/255, alpha: 1.0),  // Purple
        CGColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0)   // Blue
    ] as CFArray
    
    let locations: [CGFloat] = [0.0, 1.0]
    
    guard let gradient = CGGradient(colorsSpace: colorSpace,
                                   colors: colors,
                                   locations: locations) else {
        return nil
    }
    
    // Draw gradient
    context.drawLinearGradient(gradient,
                              start: CGPoint(x: 0, y: 0),
                              end: CGPoint(x: 0, y: CGFloat(height)),
                              options: [])
    
    // Add rounded corners mask
    let cornerRadius = CGFloat(size) * 0.2237
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                     cornerWidth: cornerRadius,
                     cornerHeight: cornerRadius,
                     transform: nil)
    
    context.addPath(path)
    context.clip()
    
    // Draw text
    context.setFillColor(CGColor(white: 1.0, alpha: 1.0))
    let fontSize = CGFloat(size) * 0.4
    
    // Simple text drawing (TX)
    let text = "TX"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    
    let attributedString = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributedString.size()
    
    let textRect = CGRect(
        x: (CGFloat(width) - textSize.width) / 2,
        y: (CGFloat(height) - textSize.height) / 2 - CGFloat(size) * 0.05,
        width: textSize.width,
        height: textSize.height
    )
    
    context.saveGState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    attributedString.draw(in: textRect)
    context.restoreGState()
    
    return context.makeImage()
}

// Save image to file
func saveImage(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                           UTType.png.identifier as CFString,
                                                           1,
                                                           nil) else {
        print("Failed to create image destination")
        return
    }
    
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// Icon sizes configuration
let iconSizes: [(name: String, size: Int)] = [
    ("iphone-notification@2x", 40),
    ("iphone-notification@3x", 60),
    ("iphone-settings@2x", 58),
    ("iphone-settings@3x", 87),
    ("iphone-spotlight@2x", 80),
    ("iphone-spotlight@3x", 120),
    ("iphone-app@2x", 120),
    ("iphone-app@3x", 180),
    ("ipad-notification@1x", 20),
    ("ipad-notification@2x", 40),
    ("ipad-settings@1x", 29),
    ("ipad-settings@2x", 58),
    ("ipad-spotlight@1x", 40),
    ("ipad-spotlight@2x", 80),
    ("ipad-app@1x", 76),
    ("ipad-app@2x", 152),
    ("ipad-pro-app@2x", 167),
    ("app-store", 1024)
]

// Main execution
let iconDir = "/Users/pablofernandez/projects/TENEX-kf5rtr/tenex-ios/TENEX/Resources/Assets.xcassets/AppIcon.appiconset"

print("Generating TENEX app icons...")

for (name, size) in iconSizes {
    print("Creating \(name).png (\(size)x\(size))...")
    
    if let icon = createTENEXIcon(size: size) {
        let path = "\(iconDir)/\(name).png"
        saveImage(icon, to: path)
    } else {
        print("Failed to create \(name)")
    }
}

print("✅ All icons generated successfully!")