#!/usr/bin/env bash
set -euo pipefail

MD_BOOK_VERSION=${MD_BOOK_VERSION:-0.4.52}
ARCHIVE="mdbook-v${MD_BOOK_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
URL="https://github.com/rust-lang/mdBook/releases/download/v${MD_BOOK_VERSION}/${ARCHIVE}"

TMPDIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

curl -sSL "$URL" -o "$TMPDIR/$ARCHIVE"
tar -xzf "$TMPDIR/$ARCHIVE" -C "$TMPDIR"

mkdir -p "$HOME/.local/bin"
mv "$TMPDIR/mdbook" "$HOME/.local/bin/"
export PATH="$HOME/.local/bin:$PATH"

mdbook build
