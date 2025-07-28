#!/bin/bash

# TENEX App Icon Generator
# This script generates all required iOS app icon sizes

ICON_DIR="/Users/pablofernandez/projects/TENEX-kf5rtr/tenex-ios/TENEX/Resources/Assets.xcassets/AppIcon.appiconset"

# Create the base 1024x1024 icon using ImageMagick
# This creates a gradient background with "TX" text
generate_base_icon() {
    convert -size 1024x1024 \
        gradient:'#5856D6-#007AFF' \
        -fill white \
        -gravity center \
        -font Helvetica-Bold \
        -pointsize 400 \
        -annotate +0-50 "TX" \
        -alpha set \
        -background none \
        -vignette 0x0 \
        /tmp/tenex_base_icon.png
    
    # Apply iOS-style rounded corners (22.37% of size)
    convert /tmp/tenex_base_icon.png \
        \( +clone -alpha extract \
        -draw 'fill black polygon 0,0 0,229 229,0 fill white circle 229,229 229,0' \
        \( +clone -flip \) -compose Multiply -composite \
        \( +clone -flop \) -compose Multiply -composite \
        \) -alpha off -compose CopyOpacity -composite \
        /tmp/tenex_icon_rounded.png
}

# Generate all required sizes
generate_all_sizes() {
    # Define all required icon sizes for iOS
    declare -A ICONS=(
        ["iphone-notification@2x.png"]="40"
        ["iphone-notification@3x.png"]="60"
        ["iphone-settings@2x.png"]="58"
        ["iphone-settings@3x.png"]="87"
        ["iphone-spotlight@2x.png"]="80"
        ["iphone-spotlight@3x.png"]="120"
        ["iphone-app@2x.png"]="120"
        ["iphone-app@3x.png"]="180"
        ["ipad-notification@1x.png"]="20"
        ["ipad-notification@2x.png"]="40"
        ["ipad-settings@1x.png"]="29"
        ["ipad-settings@2x.png"]="58"
        ["ipad-spotlight@1x.png"]="40"
        ["ipad-spotlight@2x.png"]="80"
        ["ipad-app@1x.png"]="76"
        ["ipad-app@2x.png"]="152"
        ["ipad-pro-app@2x.png"]="167"
        ["app-store.png"]="1024"
    )
    
    # Generate each size
    for filename in "${!ICONS[@]}"; do
        size="${ICONS[$filename]}"
        echo "Generating $filename (${size}x${size})"
        convert /tmp/tenex_icon_rounded.png -resize ${size}x${size} "$ICON_DIR/$filename"
    done
}

# Generate Contents.json
generate_contents_json() {
    cat > "$ICON_DIR/Contents.json" << 'EOF'
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
EOF
}

# Main execution
echo "Generating TENEX app icons..."

# Check if ImageMagick is installed
if ! command -v convert &> /dev/null; then
    echo "Error: ImageMagick is required. Install it with: brew install imagemagick"
    exit 1
fi

# Generate the base icon
echo "Creating base icon..."
generate_base_icon

# Generate all sizes
echo "Generating all icon sizes..."
generate_all_sizes

# Generate Contents.json
echo "Generating Contents.json..."
generate_contents_json

# Clean up temporary files
rm -f /tmp/tenex_base_icon.png /tmp/tenex_icon_rounded.png

echo "✅ All icons generated successfully!"
echo "Icons saved to: $ICON_DIR"