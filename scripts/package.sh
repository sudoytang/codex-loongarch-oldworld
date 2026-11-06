#!/bin/bash
# Assemble the friend-style install tarball around a built codex binary.
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
STAGE="$OUT/codex-loongarch-kylin"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin"

install -m 755 "$BIN" "$STAGE/bin/codex"
install -m 755 "$ROOT/packaging/bin/codex-wrapper.sh" "$STAGE/bin/codex-wrapper.sh"
install -m 755 "$ROOT/packaging/install.sh" "$STAGE/install.sh"
install -m 755 "$ROOT/packaging/uninstall.sh" "$STAGE/uninstall.sh"

sed "s/__CODEX_VERSION__/${CODEX_VERSION}/g" \
  "$ROOT/packaging/README.txt" > "$STAGE/README.txt"
sed "s/__CODEX_VERSION__/${CODEX_VERSION}/g" \
  "$ROOT/packaging/config.toml.template" > "$STAGE/config.toml.template"

TAR="$OUT/codex-loongarch-kylin-${CODEX_VERSION}.tar.xz"
tar -C "$OUT" -cJf "$TAR" codex-loongarch-kylin
( cd "$OUT" && sha256sum "$(basename "$TAR")" > SHA256SUMS.txt )
ls -lh "$TAR"
cat "$OUT/SHA256SUMS.txt"
echo "PACKAGE_OK $TAR"
