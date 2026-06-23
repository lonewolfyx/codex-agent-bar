#!/usr/bin/env sh

set -eu

APP_NAME="${APP_NAME:-CodexAgentBar}"
BUNDLE_ID="${BUNDLE_ID:-com.lonewolfyx.CodexAgentBar}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_NAME}"
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/$CONFIGURATION"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"
TEMP_DMG="$DIST_DIR/$APP_NAME-temp.dmg"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Builds a macOS .app bundle from the Swift package and packages it as a DMG.

Options:
  -n, --name NAME          App name. Default: $APP_NAME
  -b, --bundle-id ID      Bundle identifier. Default: $BUNDLE_ID
  -v, --version VERSION   App version and DMG suffix. Default: $VERSION
  -o, --output PATH       DMG output path. Default: $DMG_PATH
  -h, --help              Show this help.

Environment overrides:
  APP_NAME, BUNDLE_ID, VERSION, BUILD_NUMBER, CONFIGURATION, DIST_DIR,
  DMG_VOLUME_NAME
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n|--name)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            APP_NAME="$2"
            shift 2
            ;;
        -b|--bundle-id)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            BUNDLE_ID="$2"
            shift 2
            ;;
        -v|--version)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        -o|--output)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            DMG_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

BUILD_DIR="$REPO_ROOT/.build/$CONFIGURATION"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
TEMP_DMG="$DIST_DIR/$APP_NAME-temp.dmg"
EXECUTABLE="$BUILD_DIR/$APP_NAME"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_command swift
require_command hdiutil

echo "Building $APP_NAME ($CONFIGURATION)..."
cd "$REPO_ROOT"
swift build -c "$CONFIGURATION"

if [ ! -x "$EXECUTABLE" ]; then
    echo "Expected executable not found: $EXECUTABLE" >&2
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE" "$STAGING_DIR" "$TEMP_DMG" "$DMG_PATH"
mkdir -p \
    "$APP_BUNDLE/Contents/MacOS" \
    "$APP_BUNDLE/Contents/Resources" \
    "$STAGING_DIR" \
    "$(dirname -- "$DMG_PATH")"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Preparing DMG staging directory..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

SIZE_MB="$(du -sm "$STAGING_DIR" | awk '{ print $1 + 64 }')"

echo "Creating temporary DMG..."
hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -size "${SIZE_MB}m" \
    "$TEMP_DMG" >/dev/null

echo "Compressing DMG..."
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR" "$TEMP_DMG"

echo "Created: $DMG_PATH"
