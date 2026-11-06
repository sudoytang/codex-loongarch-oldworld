#!/bin/bash
# Stage the public release assets: the stripped Codex binary and its SHA256.
# Usage: CODEX_VERSION=0.167.0 CODEX_BIN=... ./scripts/package.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=versions.sh
source "$HERE/versions.sh"

CODEX_VERSION="$(normalize_codex_version "${CODEX_VERSION:?}")"
BIN="${CODEX_BIN:?set CODEX_BIN to the stripped codex executable}"
"$HERE/verify-elf.sh" "$BIN"

OUT="${OUT_DIR:-$ROOT/out}"
mkdir -p "$OUT"
NAME="codex-loongarch64-oldworld-${CODEX_VERSION}"
DEST="$OUT/$NAME"

# Drop any previous public assets (including the old friend tarball if present).
rm -f "$DEST" "$OUT/SHA256SUMS.txt" \
  "$OUT/codex-loongarch-kylin-${CODEX_VERSION}.tar.xz"
rm -rf "$OUT/codex-loongarch-kylin"

install -m 755 "$BIN" "$DEST"
( cd "$OUT" && sha256sum "$NAME" > SHA256SUMS.txt )
ls -lh "$DEST"
cat "$OUT/SHA256SUMS.txt"
echo "PACKAGE_OK $DEST"
