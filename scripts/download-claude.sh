#!/bin/bash
# Install a pinned official Claude Code build into build-claude without using
# the current user's Claude installation or credentials.
set -euo pipefail

VERSION="${1:?Usage: bash scripts/download-claude.sh VERSION (e.g. 2.1.89)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Expected a stable numeric Claude Code version" >&2
    exit 2
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-claude"
mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.download.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT

# Run the official installer with a temporary home so it cannot change the
# user's installation or authenticate against the user's Claude account.
curl --fail --location --retry 3 \
    https://claude.ai/install.sh --output "$STAGING_DIR/install.sh"
mkdir -p "$STAGING_DIR/home"
HOME="$STAGING_DIR/home" bash "$STAGING_DIR/install.sh" "$VERSION"

LAUNCHER="$STAGING_DIR/home/.local/bin/claude"
test -x "$LAUNCHER"
CLAUDE_BIN="$(readlink -f "$LAUNCHER")"
test -s "$CLAUDE_BIN"

install -m 755 "$CLAUDE_BIN" "$BUILD_DIR/claude"
install -m 644 "$STAGING_DIR/install.sh" "$BUILD_DIR/install.sh"
printf '%s\n' "$VERSION" > "$BUILD_DIR/version.txt"
(
    cd "$BUILD_DIR"
    sha256sum claude install.sh > claude.sha256
)

printf 'Prepared Claude Code %s for the target Linux architecture. Build and verify claude.sif on Roihu-GPU.\n' "$VERSION"
