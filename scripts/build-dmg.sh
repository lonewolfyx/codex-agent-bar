#!/usr/bin/env sh

set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_ENV_FILE="${VERSION_ENV_FILE:-$REPO_ROOT/version.env}"

APP_NAME="${APP_NAME:-CodexAgentBar}"
BUNDLE_ID="${BUNDLE_ID:-com.lonewolfyx.CodexAgentBar}"
CONFIGURATION="${CONFIGURATION:-release}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_NAME}"

ENV_VERSION_WAS_SET=0
ENV_BUILD_NUMBER_WAS_SET=0
if [ "${VERSION+x}" = x ]; then
    ENV_VERSION="$VERSION"
    ENV_VERSION_WAS_SET=1
fi
if [ "${BUILD_NUMBER+x}" = x ]; then
    ENV_BUILD_NUMBER="$BUILD_NUMBER"
    ENV_BUILD_NUMBER_WAS_SET=1
fi

VERSION="1.0.0"
BUILD_NUMBER="1"
if [ -f "$VERSION_ENV_FILE" ]; then
    . "$VERSION_ENV_FILE"
fi
if [ "$ENV_VERSION_WAS_SET" -eq 1 ]; then
    VERSION="$ENV_VERSION"
fi
if [ "$ENV_BUILD_NUMBER_WAS_SET" -eq 1 ]; then
    BUILD_NUMBER="$ENV_BUILD_NUMBER"
fi

BUILD_DIR="$REPO_ROOT/.build/$CONFIGURATION"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"
TEMP_DMG="$DIST_DIR/$APP_NAME-temp.dmg"
ASSETS_DIR="$REPO_ROOT/Assets"
ICON_SOURCE="$ASSETS_DIR/app-icon.png"
MENU_BAR_ICON_SOURCE="$ASSETS_DIR/app-icon-light.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
APP_ICON="$DIST_DIR/AppIcon.icns"
OUTPUT_WAS_SET=0

usage() {
    DEFAULT_DMG_PATH="$DMG_PATH"
    if [ "$OUTPUT_WAS_SET" -eq 0 ]; then
        DEFAULT_DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
    fi

    cat <<EOF
Usage: $(basename "$0") [options]

Builds a macOS .app bundle from the Swift package and packages it as a DMG.

Options:
  -n, --name NAME          App name. Default: $APP_NAME
  -b, --bundle-id ID      Bundle identifier. Default: $BUNDLE_ID
  -v, --version VERSION   App version and DMG suffix. Default: $VERSION
  -o, --output PATH       DMG output path. Default: $DEFAULT_DMG_PATH
  -h, --help              Show this help.

Environment overrides:
  APP_NAME, BUNDLE_ID, VERSION, BUILD_NUMBER, CONFIGURATION, DIST_DIR,
  DMG_VOLUME_NAME, VERSION_ENV_FILE

Version file:
  $VERSION_ENV_FILE
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
            OUTPUT_WAS_SET=1
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
if [ "$OUTPUT_WAS_SET" -eq 0 ]; then
    DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_command swift
require_command hdiutil
require_command sips
require_command iconutil

if [ ! -f "$ICON_SOURCE" ]; then
    echo "Expected app icon not found: $ICON_SOURCE" >&2
    exit 1
fi

if [ ! -f "$MENU_BAR_ICON_SOURCE" ]; then
    echo "Expected menu bar icon not found: $MENU_BAR_ICON_SOURCE" >&2
    exit 1
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
cd "$REPO_ROOT"
swift build -c "$CONFIGURATION"

if [ ! -x "$EXECUTABLE" ]; then
    echo "Expected executable not found: $EXECUTABLE" >&2
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE" "$STAGING_DIR" "$TEMP_DMG" "$DMG_PATH" "$ICONSET_DIR" "$APP_ICON"
mkdir -p \
    "$APP_BUNDLE/Contents/MacOS" \
    "$APP_BUNDLE/Contents/Resources" \
    "$STAGING_DIR" \
    "$(dirname -- "$DMG_PATH")"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Preparing app icon..."
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON"
cp "$APP_ICON" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
cp "$MENU_BAR_ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/MenuBarIcon.png"
if [ -f "$VERSION_ENV_FILE" ]; then
    cp "$VERSION_ENV_FILE" "$APP_BUNDLE/Contents/Resources/version.env"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

rm -rf "$STAGING_DIR" "$TEMP_DMG" "$ICONSET_DIR" "$APP_ICON"

echo "Created: $DMG_PATH"
