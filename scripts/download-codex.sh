#!/bin/bash
# Download a complete official Linux ARM64 package; never execute it on the host.
set -euo pipefail
VERSION="${1:?Usage: bash scripts/download-codex.sh VERSION (e.g. 0.167.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Expected a stable numeric release version, without the rust-v prefix" >&2
    exit 2
}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REPO_ROOT/build-codex"
cd "$REPO_ROOT/build-codex"
# Validate the entire package before replacing the previous build input.
STAGING_DIR="$(mktemp -d "$REPO_ROOT/build-codex/.download.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
ARCHIVE="codex-package-aarch64-unknown-linux-musl.tar.gz"
CHECKSUMS="codex-package_SHA256SUMS"
BASE_URL="https://github.com/openai/codex/releases/download/rust-v$VERSION"
for ASSET in "$ARCHIVE" "$CHECKSUMS"; do
    curl --fail --location --retry 3 "$BASE_URL/$ASSET" --output "$STAGING_DIR/$ASSET"
done
(
    cd "$STAGING_DIR"
    awk -v asset="$ARCHIVE" '$2 == asset {print; found=1} END {if (!found) exit 1}' \
        "$CHECKSUMS" > archive.sha256
    sha256sum -c archive.sha256
    mkdir package
    tar -xzf "$ARCHIVE" -C package
    python3 "$REPO_ROOT/scripts/check-codex-package.py" package "$VERSION"
    find package -type f -exec sha256sum {} + | LC_ALL=C sort -k2 > package.sha256
)
rm -rf -- "$REPO_ROOT/build-codex/package"
mv "$STAGING_DIR/package" package
mv "$STAGING_DIR/package.sha256" package.sha256
mv "$STAGING_DIR/archive.sha256" codex-package.archive.sha256
mv "$STAGING_DIR/$ARCHIVE" "$ARCHIVE"
mv "$STAGING_DIR/$CHECKSUMS" "$CHECKSUMS"
printf '%s\n' "$VERSION" > version.txt
printf 'Prepared complete Codex %s package. Build and verify codex.sif on Roihu-GPU.\n' "$VERSION"
