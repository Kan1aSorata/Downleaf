#!/bin/zsh

set -euo pipefail

REQUESTED_CONFIGURATION="${1:-debug}"
ROOT_DIR="${0:A:h:h}"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode-app-derived"
APP_DIR="$ROOT_DIR/Downleaf.app"
STAGING_APP_DIR="$ROOT_DIR/.build/Downleaf.staging.app"
LEGACY_APP_DIR="$ROOT_DIR/.build/Downleaf.app"

case "${REQUESTED_CONFIGURATION:l}" in
  debug)
    CONFIGURATION="Debug"
    ;;
  release)
    CONFIGURATION="Release"
    ;;
  *)
    print -u2 -- "Unsupported configuration: $REQUESTED_CONFIGURATION"
    exit 2
    ;;
esac

cd "$ROOT_DIR"

xcodebuild \
  -project "$ROOT_DIR/Downleaf.xcodeproj" \
  -scheme Downleaf \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

PRODUCT_APP_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/Downleaf.app"
test -d "$PRODUCT_APP_DIR"

rm -rf "$STAGING_APP_DIR"
/usr/bin/ditto "$PRODUCT_APP_DIR" "$STAGING_APP_DIR"
rm -rf "$APP_DIR"
mv "$STAGING_APP_DIR" "$APP_DIR"
rm -rf "$LEGACY_APP_DIR"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R -trusted "$APP_DIR"

print -r -- "$APP_DIR"
