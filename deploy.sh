#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Get app name
APP_NAME="TENEX"

echo -e "${YELLOW}📦 Building ${APP_NAME} for TestFlight...${NC}"

# Check if ExportOptions plist exists
if [ ! -f "ExportOptions-TestFlight.plist" ]; then
    echo -e "${RED}❌ ExportOptions-TestFlight.plist not found${NC}"
    echo -e "${YELLOW}Please create this file with your provisioning profile settings${NC}"
    exit 1
fi

# Clean build folder
echo -e "${YELLOW}🧹 Cleaning build folder...${NC}"
rm -rf build/

# Archive the app
echo -e "${YELLOW}📦 Archiving ${APP_NAME}...${NC}"
xcodebuild archive \
    -project "${APP_NAME}/${APP_NAME}.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "build/${APP_NAME}.xcarchive" \
    -destination "generic/platform=iOS" \
    | xcbeautify

# Export the archive
echo -e "${YELLOW}📤 Exporting archive...${NC}"
xcodebuild -exportArchive \
    -archivePath "build/${APP_NAME}.xcarchive" \
    -exportPath "build" \
    -exportOptionsPlist "ExportOptions-TestFlight.plist" \
    | xcbeautify

# Upload to App Store Connect
echo -e "${YELLOW}🚀 Uploading to App Store Connect...${NC}"
xcrun altool --upload-app \
    -f "build/${APP_NAME}.ipa" \
    -t ios \
    --apiKey "$APP_STORE_API_KEY" \
    --apiIssuer "$APP_STORE_API_ISSUER"

echo -e "${GREEN}✅ ${APP_NAME} uploaded to TestFlight successfully!${NC}"