#!/bin/bash
# Download a specific official Linux ARM64 release; do not execute the binary on the host.
set -euo pipefail

VERSION="${1:?Usage: bash scripts/download-opencode.sh VERSION (e.g. 1.18.30)}"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] || {
    echo "Expected an OpenCode release version, with or without the v prefix" >&2
    exit 2
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-opencode"
ARCHIVE="opencode-linux-arm64.tar.gz"
URL="https://github.com/anomalyco/opencode/releases/download/v$VERSION/$ARCHIVE"

mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.download.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT

curl --fail --location --retry 3 "$URL" --output "$STAGING_DIR/$ARCHIVE"

# Extract only the expected executable, not arbitrary archive paths.
tar -xzf "$STAGING_DIR/$ARCHIVE" -C "$STAGING_DIR" opencode
test -s "$STAGING_DIR/opencode"

install -m 755 "$STAGING_DIR/opencode" "$BUILD_DIR/opencode"
mv -f "$STAGING_DIR/$ARCHIVE" "$BUILD_DIR/$ARCHIVE"
printf 'v%s\n' "$VERSION" > "$BUILD_DIR/version.txt"
(
    cd "$BUILD_DIR"
    sha256sum opencode > opencode.sha256
)

printf 'Prepared OpenCode v%s for Linux ARM64. Build and verify opencode.sif on Roihu-GPU.\n' "$VERSION"
