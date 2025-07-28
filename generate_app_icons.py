#!/usr/bin/env python3

import os
from PIL import Image, ImageDraw, ImageFont
import json

def create_tenex_icon(size):
    """Create a simple TENEX app icon with gradient background and text"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Create gradient background (purple to blue)
    for y in range(size):
        r = int(88 + (50 * y / size))  # Purple to blue gradient
        g = int(86 + (100 * y / size))
        b = int(214 - (50 * y / size))
        draw.rectangle([(0, y), (size, y+1)], fill=(r, g, b, 255))
    
    # Add rounded corners
    corner_radius = int(size * 0.2237)  # iOS standard corner radius ratio
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([(0, 0), (size, size)], corner_radius, fill=255)
    
    # Apply mask for rounded corners
    output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    output.paste(img, (0, 0))
    output.putalpha(mask)
    
    # Draw "TX" text in white
    text = "TX"
    # Try to use a system font, fallback to default if not available
    try:
        font_size = int(size * 0.4)
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except:
        font = ImageFont.load_default()
    
    # Get text bounding box for centering
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    x = (size - text_width) // 2
    y = (size - text_height) // 2 - int(size * 0.05)  # Slightly offset up
    
    # Draw text with slight shadow
    shadow_offset = max(1, int(size * 0.01))
    draw.text((x + shadow_offset, y + shadow_offset), text, font=font, fill=(0, 0, 0, 100))
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 255))
    
    return output

def generate_all_icons():
    """Generate all required iOS app icon sizes"""
    # iOS App Icon sizes needed for App Store
    icon_sizes = {
        # iPhone Notification
        "iphone-notification@2x": (40, "20pt"),
        "iphone-notification@3x": (60, "20pt"),
        
        # iPhone Settings
        "iphone-settings@2x": (58, "29pt"),
        "iphone-settings@3x": (87, "29pt"),
        
        # iPhone Spotlight
        "iphone-spotlight@2x": (80, "40pt"),
        "iphone-spotlight@3x": (120, "40pt"),
        
        # iPhone App
        "iphone-app@2x": (120, "60pt"),
        "iphone-app@3x": (180, "60pt"),
        
        # iPad Notification
        "ipad-notification@1x": (20, "20pt"),
        "ipad-notification@2x": (40, "20pt"),
        
        # iPad Settings
        "ipad-settings@1x": (29, "29pt"),
        "ipad-settings@2x": (58, "29pt"),
        
        # iPad Spotlight
        "ipad-spotlight@1x": (40, "40pt"),
        "ipad-spotlight@2x": (80, "40pt"),
        
        # iPad App
        "ipad-app@1x": (76, "76pt"),
        "ipad-app@2x": (152, "76pt"),
        
        # iPad Pro App
        "ipad-pro-app@2x": (167, "83.5pt"),
        
        # App Store
        "app-store": (1024, "1024pt")
    }
    
    # Create icons directory
    icon_dir = "/Users/pablofernandez/projects/TENEX-kf5rtr/tenex-ios/TENEX/Resources/Assets.xcassets/AppIcon.appiconset"
    
    # Contents.json for the AppIcon set
    contents = {
        "images": [],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    
    # Generate each icon size
    for filename, (size, scale_info) in icon_sizes.items():
        print(f"Generating {filename}.png ({size}x{size})")
        icon = create_tenex_icon(size)
        icon_path = os.path.join(icon_dir, f"{filename}.png")
        icon.save(icon_path, "PNG")
        
        # Determine idiom and scale
        if "iphone" in filename:
            idiom = "iphone"
        elif "ipad" in filename:
            idiom = "ipad"
        else:
            idiom = "ios-marketing"
        
        if "@3x" in filename:
            scale = "3x"
        elif "@2x" in filename:
            scale = "2x"
        else:
            scale = "1x"
        
        # Extract point size
        pt_size = scale_info.replace("pt", "")
        
        # Add to contents.json
        image_entry = {
            "filename": f"{filename}.png",
            "idiom": idiom,
            "scale": scale,
            "size": f"{pt_size}x{pt_size}"
        }
        
        contents["images"].append(image_entry)
    
    # Special case for App Store icon
    contents["images"].append({
        "filename": "app-store.png",
        "idiom": "ios-marketing",
        "scale": "1x",
        "size": "1024x1024"
    })
    
    # Write Contents.json
    contents_path = os.path.join(icon_dir, "Contents.json")
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    
    print(f"\nAll icons generated successfully!")
    print(f"Icons saved to: {icon_dir}")
    print(f"Contents.json updated")

if __name__ == "__main__":
    # Check if PIL is installed
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Error: Pillow library is required. Install it with: pip install Pillow")
        exit(1)
    
    generate_all_icons()