#!/bin/bash
# Download a specific official Linux ARM64 release; never execute it on the host.
set -euo pipefail
VERSION="${1:?Usage: bash scripts/download-codex.sh VERSION (e.g. 0.144.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Expected a stable numeric release version, without the rust-v prefix" >&2
    exit 2
}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REPO_ROOT/build-codex"
cd "$REPO_ROOT/build-codex"
ARCHIVE="codex-aarch64-unknown-linux-musl.tar.gz"
URL="https://github.com/openai/codex/releases/download/rust-v$VERSION/$ARCHIVE"
curl --fail --location --retry 3 "$URL" --output "$ARCHIVE"
# Extract only the expected program, not arbitrary paths from the archive.
tar -xzf "$ARCHIVE" codex-aarch64-unknown-linux-musl
install -m 755 codex-aarch64-unknown-linux-musl codex
printf '%s\n' "$VERSION" > version.txt
sha256sum codex > codex.sha256
printf 'Prepared Codex %s. Build and verify codex.sif on Roihu-GPU.\n' "$VERSION"
