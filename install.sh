#!/bin/sh
# Install the latest mikemccabe/mdv fork release.
#
#   curl -fsSL https://raw.githubusercontent.com/mikemccabe/mdv/fork/install.sh | sh
#
# Fetches the newest release zip from GitHub, checks its sha256, extracts
# the app bundle into the target directory, and clears the quarantine
# attribute (the fork's builds are ad-hoc signed, not notarized, so a
# quarantined copy would be refused by Gatekeeper). Read it first if you
# like; it only touches the install directory.
#
#   MDV_VERSION=v1.5.1-mm.2   pick a release instead of the latest
#   MDV_APP_DIR=~/Applications install somewhere other than /Applications

set -eu

REPO="mikemccabe/mdv"
APP_DIR="${MDV_APP_DIR:-/Applications}"
API="https://api.github.com/repos/$REPO/releases"

case "$(uname -s)" in Darwin) ;; *) echo "mdv is a macOS app" >&2; exit 1 ;; esac

if [ -n "${MDV_VERSION:-}" ]; then
  TAG="$MDV_VERSION"
else
  TAG=$(curl -fsSL "$API/latest" | sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p')
  [ -n "$TAG" ] || { echo "could not determine the latest release" >&2; exit 1; }
fi
ZIP="mdv-${TAG#v}-macos.zip"
URL="https://github.com/$REPO/releases/download/$TAG/$ZIP"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

echo "downloading $URL"
curl -fsSL -o "$ZIP" "$URL"
curl -fsSL -o "$ZIP.sha256" "$URL.sha256"
shasum -a 256 -c "$ZIP.sha256"

# ditto keeps the bundle's symlinks and code signature intact; unzip can
# leave a bundle that spctl reports as "sealed resource is missing".
mkdir -p "$APP_DIR"
rm -rf "$APP_DIR/mdv.app"
ditto -x -k "$ZIP" "$APP_DIR"
xattr -dr com.apple.quarantine "$APP_DIR/mdv.app" 2>/dev/null || true

# Refresh LaunchServices so the .md association picks up this copy.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$APP_DIR/mdv.app" 2>/dev/null || true

echo "installed mdv $TAG to $APP_DIR/mdv.app"
