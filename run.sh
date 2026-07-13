#!/bin/sh
# Build, install and launch NativeLiquidChat on the connected iPhone.
# LeapSDK is arm64-only and the Mac is Intel, so the simulator can't be used — device only.
set -e

DEVICE_ID="024A4A30-2146-5D7E-8C4B-7AA13A4C4CF0"   # iPhone Dima T (2) — iPhone 14 Pro Max
BUNDLE_ID="com.dimatrubnikov.NativeLiquidChat"
SCHEME="NativeLiquidChat"

cd "$(dirname "$0")"

# `./run.sh test` runs the unit tests on the device instead of launching the app.
if [ "$1" = "test" ]; then
  echo "==> Regenerating Xcode project"
  xcodegen generate
  echo "==> Running tests on device"
  exec xcodebuild test -project NativeLiquidChat.xcodeproj -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_ID" -allowProvisioningUpdates
fi

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Building for device"
xcodebuild -project NativeLiquidChat.xcodeproj -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -configuration Debug -allowProvisioningUpdates build

APP=$(find ~/Library/Developer/Xcode/DerivedData/NativeLiquidChat-*/Build/Products/Debug-iphoneos \
  -maxdepth 1 -name "NativeLiquidChat.app" | head -1)
echo "==> Installing $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "==> Launching"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
