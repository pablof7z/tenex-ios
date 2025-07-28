#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Create a simple gradient icon
func createBasicIcon(size: Int) -> CGImage? {
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
    
    // Create gradient background
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
    
    // Draw simple white circle in center as placeholder
    let centerX = CGFloat(width) / 2
    let centerY = CGFloat(height) / 2
    let radius = CGFloat(size) * 0.3
    
    context.setFillColor(CGColor(gray: 1.0, alpha: 0.9))
    context.fillEllipse(in: CGRect(x: centerX - radius, 
                                   y: centerY - radius, 
                                   width: radius * 2, 
                                   height: radius * 2))
    
    // Add inner circle for depth
    let innerRadius = radius * 0.7
    context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
    context.fillEllipse(in: CGRect(x: centerX - innerRadius, 
                                   y: centerY - innerRadius, 
                                   width: innerRadius * 2, 
                                   height: innerRadius * 2))
    
    return context.makeImage()
}

// Save image to file
func saveImage(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                           UTType.png.identifier as CFString,
                                                           1,
                                                           nil) else {
        print("Failed to create image destination for \(path)")
        return false
    }
    
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
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

var successCount = 0
for (name, size) in iconSizes {
    print("Creating \(name).png (\(size)x\(size))...")
    
    if let icon = createBasicIcon(size: size) {
        let path = "\(iconDir)/\(name).png"
        if saveImage(icon, to: path) {
            successCount += 1
        } else {
            print("Failed to save \(name)")
        }
    } else {
        print("Failed to create \(name)")
    }
}

// Update Contents.json
let contentsJson = """
{
  "images" : [
    {
      "filename" : "iphone-notification@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "iphone-notification@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "filename" : "iphone-settings@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "iphone-settings@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "iphone-spotlight@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "iphone-spotlight@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "filename" : "iphone-app@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "iphone-app@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "ipad-notification@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20"
    },
    {
      "filename" : "ipad-notification@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "ipad-settings@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29"
    },
    {
      "filename" : "ipad-settings@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "ipad-spotlight@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "40x40"
    },
    {
      "filename" : "ipad-spotlight@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "ipad-app@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76"
    },
    {
      "filename" : "ipad-app@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76"
    },
    {
      "filename" : "ipad-pro-app@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "83.5x83.5"
    },
    {
      "filename" : "app-store.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

do {
    let contentsPath = "\(iconDir)/Contents.json"
    try contentsJson.write(toFile: contentsPath, atomically: true, encoding: .utf8)
    print("✅ Contents.json updated")
} catch {
    print("Failed to write Contents.json: \(error)")
}

print("\n✅ Generated \(successCount)/\(iconSizes.count) icons successfully!")
print("Icons saved to: \(iconDir)")