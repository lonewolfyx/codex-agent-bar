#!/usr/bin/env sh

set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_ENV_FILE="${VERSION_ENV_FILE:-$REPO_ROOT/version.env}"

APP_NAME="${APP_NAME:-AgentBar}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
APPCAST_PATH="${APPCAST_PATH:-$REPO_ROOT/appcast.xml}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-generate_appcast}"

VERSION="1.0.0"
BUILD_NUMBER="1"
if [ -f "$VERSION_ENV_FILE" ]; then
    . "$VERSION_ENV_FILE"
fi

RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"
DMG_PATH="${DMG_PATH:-$DIST_DIR/$APP_NAME-$VERSION.dmg}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/lonewolfyx/codex-agent-bar/releases/download/$RELEASE_TAG/}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Generates appcast.xml for the current DMG using Sparkle's generate_appcast tool.

Options:
  -d, --dmg PATH              DMG to publish. Default: $DMG_PATH
  -o, --output PATH           Appcast output path. Default: $APPCAST_PATH
  -t, --tag TAG               GitHub release tag. Default: $RELEASE_TAG
  -u, --download-url URL      Download URL prefix. Default: $DOWNLOAD_URL_PREFIX
  -h, --help                  Show this help.

Environment overrides:
  APP_NAME, DIST_DIR, VERSION_ENV_FILE, DMG_PATH, APPCAST_PATH,
  RELEASE_TAG, DOWNLOAD_URL_PREFIX, SPARKLE_GENERATE_APPCAST
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -d|--dmg)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            DMG_PATH="$2"
            shift 2
            ;;
        -o|--output)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            APPCAST_PATH="$2"
            shift 2
            ;;
        -t|--tag)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            RELEASE_TAG="$2"
            DOWNLOAD_URL_PREFIX="https://github.com/lonewolfyx/codex-agent-bar/releases/download/$RELEASE_TAG/"
            shift 2
            ;;
        -u|--download-url)
            if [ "$#" -lt 2 ]; then
                echo "Missing value for $1" >&2
                exit 1
            fi
            DOWNLOAD_URL_PREFIX="$2"
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

if [ ! -f "$DMG_PATH" ]; then
    echo "Expected DMG not found: $DMG_PATH" >&2
    exit 1
fi

if ! command -v "$SPARKLE_GENERATE_APPCAST" >/dev/null 2>&1; then
    CANDIDATE="$(
        find "$REPO_ROOT/.build" -name generate_appcast -type f 2>/dev/null \
            | head -n 1
    )"
    if [ -n "$CANDIDATE" ]; then
        SPARKLE_GENERATE_APPCAST="$CANDIDATE"
    else
        echo "Missing Sparkle generate_appcast tool." >&2
        echo "Install Sparkle tools or set SPARKLE_GENERATE_APPCAST=/path/to/generate_appcast." >&2
        exit 1
    fi
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/AgentBar-appcast.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

cp "$DMG_PATH" "$WORK_DIR/"

"$SPARKLE_GENERATE_APPCAST" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    "$WORK_DIR"

if [ ! -f "$WORK_DIR/appcast.xml" ]; then
    echo "generate_appcast did not create appcast.xml" >&2
    exit 1
fi

mkdir -p "$(dirname -- "$APPCAST_PATH")"
cp "$WORK_DIR/appcast.xml" "$APPCAST_PATH"

echo "Updated: $APPCAST_PATH"
