#!/bin/bash

echo "🔍 TENEX App Store Readiness Check"
echo "=================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check function
check() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# App icons check
echo -e "\n📱 App Icons:"
ICON_DIR="TENEX/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "$ICON_DIR/app-store.png" ]; then
    ICON_COUNT=$(ls -1 "$ICON_DIR"/*.png 2>/dev/null | wc -l)
    check 0 "Found $ICON_COUNT app icons including App Store icon"
else
    check 1 "App Store icon (1024x1024) not found"
fi

# Info.plist checks
echo -e "\n📋 Info.plist Configuration:"
INFO_PLIST="TENEX/Info.plist"

# Check for required keys
grep -q "CFBundleDisplayName" "$INFO_PLIST"
check $? "Display name configured"

grep -q "LSApplicationCategoryType" "$INFO_PLIST"
check $? "App category configured"

grep -q "ITSAppUsesNonExemptEncryption" "$INFO_PLIST"
check $? "Export compliance configured"

grep -q "NSMicrophoneUsageDescription" "$INFO_PLIST"
check $? "Microphone usage description present"

grep -q "UILaunchStoryboardName" "$INFO_PLIST"
check $? "Launch screen configured"

# Bundle identifier check
echo -e "\n🆔 Bundle Identifier:"
BUNDLE_ID=$(grep -A1 "PRODUCT_BUNDLE_IDENTIFIER" TENEX/TENEX.xcodeproj/project.pbxproj | grep "com.tenex" | head -1 | sed 's/.*= //;s/;//')
if [ ! -z "$BUNDLE_ID" ]; then
    check 0 "Bundle identifier: $BUNDLE_ID"
else
    check 1 "Bundle identifier not found"
fi

# Entitlements check
echo -e "\n🔐 Entitlements:"
if [ -f "TENEX/TENEX.entitlements" ]; then
    check 0 "Entitlements file exists"
else
    check 1 "Entitlements file not found"
fi

# Launch screen check
echo -e "\n🚀 Launch Screen:"
if [ -f "TENEX/Resources/LaunchScreen.storyboard" ]; then
    check 0 "Launch screen storyboard exists"
else
    check 1 "Launch screen not found"
fi

echo -e "\n📝 Next Steps:"
echo "1. Open Xcode and verify all settings"
echo "2. Create/update provisioning profiles in Apple Developer portal"
echo "3. Archive the app: Product > Archive"
echo "4. Upload to App Store Connect"
echo "5. Add screenshots and complete metadata in App Store Connect"
echo "6. Submit for review"

echo -e "\n${YELLOW}Note:${NC} See APP_STORE_INFO.md for detailed submission guidelines"