#!/bin/bash
# Prepare a pinned native release for the container; never execute the binary.
set -euo pipefail

VERSION="${1:?Usage: bash scripts/download-kimi.sh VERSION [arm64|x64] (e.g. 2.2.0)}"
ARCH="${2:-arm64}"
if (( $# > 2 )) || [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a stable numeric version and optional architecture." >&2
    exit 2
fi
case "$ARCH" in
    arm64|x64) ;;
    *) echo "Unsupported architecture: $ARCH (expected arm64 or x64)" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-kimi"
mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.download.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
ARCHIVE="kimi-code-linux-$ARCH.zip"
URL="https://github.com/MoonshotAI/kimi-code/releases/download/%40moonshot-ai/kimi-code%40$VERSION/$ARCHIVE"
curl --fail --location --retry 3 "$URL" --output "$STAGING_DIR/$ARCHIVE"
curl --fail --location --retry 3 "$URL.sha256" --output "$STAGING_DIR/$ARCHIVE.sha256"

# Validate the upstream digest and extract only the expected flat ZIP member.
# Python's standard library avoids requiring unzip on the build host.
python3 - "$STAGING_DIR" "$ARCHIVE" <<'PY'
import hashlib
import re
import shutil
import sys
import zipfile
from pathlib import Path

stage = Path(sys.argv[1])
archive = stage / sys.argv[2]
checksum = (stage / (archive.name + ".sha256")).read_text().strip()
match = re.fullmatch(r"([0-9a-fA-F]{64})[ \t]+\*?" + re.escape(archive.name), checksum)
if match is None:
    sys.exit("Invalid upstream checksum file")
digest = hashlib.sha256()
with archive.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != match[1].lower():
    sys.exit("Kimi Code archive SHA-256 mismatch")
with zipfile.ZipFile(archive) as package:
    if package.namelist() != ["kimi"] or package.getinfo("kimi").file_size == 0:
        sys.exit("Unexpected Kimi Code ZIP contents (expected one nonempty kimi binary)")
    with package.open("kimi") as source, (stage / "kimi").open("wb") as target:
        shutil.copyfileobj(source, target)
PY

install -m 755 "$STAGING_DIR/kimi" "$BUILD_DIR/kimi"
install -m 644 "$STAGING_DIR/$ARCHIVE" "$BUILD_DIR/$ARCHIVE"
install -m 644 "$STAGING_DIR/$ARCHIVE.sha256" "$BUILD_DIR/$ARCHIVE.sha256"
printf '%s\n' "$VERSION" > "$BUILD_DIR/version.txt"
printf 'linux-%s\n' "$ARCH" > "$BUILD_DIR/platform.txt"
(
    cd "$BUILD_DIR"
    sha256sum kimi > kimi.sha256
)
printf 'Prepared Kimi Code %s (linux-%s). Build containers/kimi.sif on the matching architecture.\n' "$VERSION" "$ARCH"
