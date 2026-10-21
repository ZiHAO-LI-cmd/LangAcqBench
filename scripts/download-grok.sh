#!/bin/bash
# Prepare an official pinned Linux release as a container input. Never run grok
# or the upstream installer, which executes the binary and edits shell setup.
set -euo pipefail

if (( $# < 1 || $# > 3 )); then
    echo "Usage: bash scripts/download-grok.sh VERSION [arm64|amd64] [EXPECTED_SHA256]" >&2
    exit 2
fi
VERSION="$1"
ARCH="${2:-arm64}"
EXPECTED_SHA256="${3:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._]+)?$ ]] || {
    echo "Expected an explicit X.Y.Z or X.Y.Z-suffix version." >&2; exit 2;
}
case "$ARCH" in
    arm64|aarch64) ARCH=aarch64 ;;
    amd64|x64|x86_64) ARCH=x86_64 ;;
    *) echo "Unsupported architecture: $ARCH (expected arm64 or amd64)" >&2; exit 2 ;;
esac
if [[ -n "$EXPECTED_SHA256" && ! "$EXPECTED_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "EXPECTED_SHA256 must contain exactly 64 hexadecimal characters." >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-grok"
mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.download.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT

# These are the primary and fallback locations in the official bootstrapper.
# Fetch the uncompressed flat binary, without invoking any installer hooks.
ARTIFACT="grok-$VERSION-linux-$ARCH"
URL="https://x.ai/cli/$ARTIFACT"
if ! curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
    "$URL" --output "$STAGING_DIR/grok"; then
    URL="https://storage.googleapis.com/grok-build-public-artifacts/cli/$ARTIFACT"
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
        "$URL" --output "$STAGING_DIR/grok"
fi

python3 - "$STAGING_DIR/grok" "$ARCH" "$EXPECTED_SHA256" <<'PY'
import hashlib
import sys
from pathlib import Path

binary = Path(sys.argv[1])
with binary.open("rb") as source:
    header = source.read(20)
machine = 183 if sys.argv[2] == "aarch64" else 62
if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
        or int.from_bytes(header[18:20], "little") != machine):
    sys.exit("Release is not a matching 64-bit Linux ELF binary")
if sys.argv[3]:
    digest = hashlib.sha256()
    with binary.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != sys.argv[3].lower():
        sys.exit("Grok binary SHA-256 mismatch")
PY

install -m 755 "$STAGING_DIR/grok" "$BUILD_DIR/grok"
printf '%s\n' "$VERSION" > "$BUILD_DIR/version.txt"
printf 'linux-%s\n' "$ARCH" > "$BUILD_DIR/platform.txt"
printf '%s\n' "$URL" > "$BUILD_DIR/url.txt"
(
    cd "$BUILD_DIR"
    sha256sum grok > grok.sha256
)
printf 'Prepared Grok Build %s (linux-%s), without executing it.\n' "$VERSION" "$ARCH"
if [[ -z "$EXPECTED_SHA256" ]]; then
    echo "Recorded a local SHA-256 only; no upstream digest was verified." >&2
fi
