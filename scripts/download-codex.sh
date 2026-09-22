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
# Stage both components before replacing the installed pair.
STAGING_DIR="$(mktemp -d "$REPO_ROOT/build-codex/.download.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
for PROGRAM in codex codex-code-mode-host; do
    MEMBER="$PROGRAM-aarch64-unknown-linux-musl"
    ARCHIVE="$MEMBER.tar.gz"
    URL="https://github.com/openai/codex/releases/download/rust-v$VERSION/$ARCHIVE"
    curl --fail --location --retry 3 "$URL" --output "$STAGING_DIR/$ARCHIVE"
    # Extract only the expected program, not arbitrary paths from the archive.
    tar -xzf "$STAGING_DIR/$ARCHIVE" -C "$STAGING_DIR" "$MEMBER"
    test -s "$STAGING_DIR/$MEMBER"
done
for PROGRAM in codex codex-code-mode-host; do
    MEMBER="$PROGRAM-aarch64-unknown-linux-musl"
    install -m 755 "$STAGING_DIR/$MEMBER" "$PROGRAM"
    mv -f "$STAGING_DIR/$MEMBER.tar.gz" "$MEMBER.tar.gz"
done
printf '%s\n' "$VERSION" > version.txt
sha256sum codex codex-code-mode-host > codex.sha256
printf 'Prepared Codex %s and its code-mode host. Build and verify codex.sif on Roihu-GPU.\n' "$VERSION"
