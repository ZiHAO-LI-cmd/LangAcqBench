#!/bin/bash
# Prepare the official native CLI as a local container input. Never run agy
# or the upstream installer (which invokes agy install and edits shell setup).
set -euo pipefail

if (( $# < 1 || $# > 3 )); then
    echo "Usage: bash scripts/download-antigravity.sh VERSION [arm64|amd64] [MANIFEST_JSON]" >&2
    exit 2
fi
VERSION="$1"
ARCH="${2:-arm64}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Expected a stable numeric version." >&2; exit 2;
}
case "$ARCH" in
    arm64|amd64) ;;
    x64) ARCH=amd64 ;;
    *) echo "Unsupported architecture: $ARCH (expected arm64 or amd64)" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-antigravity"
mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.download.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT

# The official bootstrapper queries this service for the current manifest.
# An explicit version must match; never silently substitute a newer release.
if (( $# == 3 )); then
    cp -- "$3" "$STAGING_DIR/release.json"
else
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
        "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_$ARCH.json" \
        --output "$STAGING_DIR/release.json"
fi
URL="$(python3 - "$STAGING_DIR/release.json" "$VERSION" <<'PY'
import json
import re
import sys
from urllib.parse import urlsplit

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
if not isinstance(manifest, dict) or manifest.get("version") != sys.argv[2]:
    sys.exit("Manifest version differs from requested version; supply a saved manifest or review the new release.")
url = manifest.get("url")
checksum = manifest.get("sha512")
if not isinstance(checksum, str) or re.fullmatch(r"[0-9a-fA-F]{128}", checksum) is None:
    sys.exit("Invalid manifest SHA-512")
parsed = urlsplit(url) if isinstance(url, str) else None
if (parsed is None or parsed.scheme != "https" or parsed.netloc != "storage.googleapis.com"
        or not parsed.path.startswith("/antigravity-public/antigravity-cli/")
        or parsed.query or parsed.fragment):
    sys.exit("Unexpected release URL; review the official bootstrapper before changing the download helper.")
print(url)
PY
)"
curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
    "$URL" --output "$STAGING_DIR/payload"

python3 - "$STAGING_DIR" "$ARCH" <<'PY'
import hashlib
import json
import shutil
import sys
import tarfile
from pathlib import Path
from urllib.parse import urlsplit

stage = Path(sys.argv[1])
manifest = json.loads((stage / "release.json").read_text())
payload = stage / "payload"
digest = hashlib.sha512()
with payload.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != manifest["sha512"].lower():
    sys.exit("Antigravity payload SHA-512 mismatch")
binary = stage / "agy"
if urlsplit(manifest["url"]).path.endswith(".tar.gz"):
    # Copy just the flat regular member used by the official installer. Do not
    # extract paths, symlinks, or other archive contents into the filesystem.
    with tarfile.open(payload, "r:gz") as package:
        members = [member for member in package.getmembers() if member.name == "antigravity"]
        if len(members) != 1 or not members[0].isfile() or members[0].size == 0:
            sys.exit("Unexpected archive contents (expected a nonempty regular antigravity member)")
        with package.extractfile(members[0]) as source, binary.open("wb") as target:
            shutil.copyfileobj(source, target)
else:
    shutil.copyfile(payload, binary)

# Verify the platform without executing the downloaded program.
with binary.open("rb") as source:
    header = source.read(20)
machine = 183 if sys.argv[2] == "arm64" else 62
if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
        or int.from_bytes(header[18:20], "little") != machine):
    sys.exit("Release is not a matching 64-bit Linux ELF binary")
PY

install -m 755 "$STAGING_DIR/agy" "$BUILD_DIR/agy"
install -m 644 "$STAGING_DIR/release.json" "$BUILD_DIR/release.json"
install -m 644 "$STAGING_DIR/payload" "$BUILD_DIR/payload"
printf '%s\n' "$VERSION" > "$BUILD_DIR/version.txt"
printf 'linux_%s\n' "$ARCH" > "$BUILD_DIR/platform.txt"
(
    cd "$BUILD_DIR"
    sha256sum agy > agy.sha256
)
printf 'Prepared Antigravity CLI %s (linux_%s), without executing it. Build containers/antigravity.sif on the matching architecture.\n' "$VERSION" "$ARCH"
