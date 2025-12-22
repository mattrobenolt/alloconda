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

if ! command -v zig >/dev/null 2>&1; then
    ZIG_VERSION=${ZIG_VERSION:-0.15.2}
    ZIG_ARCHIVE="zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
    ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_ARCHIVE}"
    curl -sSL "$ZIG_URL" -o "$TMPDIR/$ZIG_ARCHIVE"
    tar -xf "$TMPDIR/$ZIG_ARCHIVE" -C "$TMPDIR"
    export PATH="$TMPDIR/zig-linux-x86_64-${ZIG_VERSION}:$PATH"
fi

curl -sSL "$URL" -o "$TMPDIR/$ARCHIVE"
tar -xzf "$TMPDIR/$ARCHIVE" -C "$TMPDIR"

mkdir -p "$HOME/.local/bin"
mv "$TMPDIR/mdbook" "$HOME/.local/bin/"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uvx >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

PBS_CACHE_DIR="${ALLOCONDA_PBS_CACHE:-$HOME/.cache/alloconda/pbs}"
FETCH_OUTPUT=$(uvx alloconda python fetch --version 3.14 --pbs-target x86_64-unknown-linux-gnu --cache-dir "$PBS_CACHE_DIR")
INCLUDE_DIR=$(echo "$FETCH_OUTPUT" | sed -n 's/.* -> //p; s/.* at //p' | tail -n 1)
if [[ -z "$INCLUDE_DIR" ]]; then
    echo "Failed to resolve Python include directory for Zig docs" >&2
    exit 1
fi

zig build docs -Dpython-include="$INCLUDE_DIR" -p docs

mdbook build
