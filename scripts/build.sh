#!/bin/bash
# Cross-compile openai/codex (codex-cli) for old-world LoongArch.
# Usage: CODEX_VERSION=0.167.0 ./scripts/build.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=versions.sh
source "$HERE/versions.sh"

CODEX_VERSION="$(normalize_codex_version "${CODEX_VERSION:?set CODEX_VERSION, e.g. 0.167.0}")"
CODEX_TAG="rust-v${CODEX_VERSION}"
JOBS="${JOBS:-2}"
SRC="${CODEX_SRC:-$ROOT/work/codex/codex-rs}"
PREFIX="${TOOLCHAIN_PREFIX:-$ROOT/.cache/toolchains}"

if [ ! -x "$PREFIX/rust/bin/cargo" ] || [ ! -x "$PREFIX/gcc/bin/loongarch64-linux-gnu-gcc" ]; then
  "$HERE/fetch-toolchains.sh"
fi
PREFIX="$(cd "$PREFIX" && pwd)"

if [ ! -d "$SRC" ]; then
  echo "==> fetching openai/codex $CODEX_TAG"
  mkdir -p "$ROOT/work"
  if [ -d "$ROOT/work/codex/.git" ]; then
    git -C "$ROOT/work/codex" fetch --depth 1 origin "refs/tags/${CODEX_TAG}:refs/tags/${CODEX_TAG}" || \
      git -C "$ROOT/work/codex" fetch --depth 1 origin tag "$CODEX_TAG"
    git -C "$ROOT/work/codex" checkout -f "tags/${CODEX_TAG}"
  else
    rm -rf "$ROOT/work/codex"
    git clone --depth 1 --branch "$CODEX_TAG" https://github.com/openai/codex.git "$ROOT/work/codex"
  fi
  SRC="$ROOT/work/codex/codex-rs"
fi

# Do not let rustup download a different channel. Loongnix ships 1.99.0;
# upstream rust-toolchain.toml may ask for another patch (historically 1.95.x
# or 1.99.1). 1.99.0 is what produced a working old-world binary.
rm -f "$SRC/rust-toolchain.toml" "$SRC/rust-toolchain" \
      "$ROOT/work/codex/rust-toolchain.toml" "$ROOT/work/codex/rust-toolchain"

export PATH="$PREFIX/hostbin:$PREFIX/rust/bin:$PREFIX/gcc/bin:$PATH"
export CC="$PREFIX/hostbin/cc"
export CXX="$PREFIX/hostbin/c++"
# Make sure a rustup wrapper (if any) cannot hijack cargo/rustc.
unset RUSTUP_TOOLCHAIN || true
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

export CARGO_TARGET_LOONGARCH64_UNKNOWN_LINUX_GNU_LINKER=loongarch64-linux-gnu-gcc
export CC_loongarch64_unknown_linux_gnu=loongarch64-linux-gnu-gcc
export CXX_loongarch64_unknown_linux_gnu=loongarch64-linux-gnu-g++
export AR_loongarch64_unknown_linux_gnu=loongarch64-linux-gnu-ar

# Large binary: default LoongArch code model truncates PC-relative relocs
# (seen as "relocation truncated to fit" against memcpy inside aws-lc-sys).
# Loongson gcc 8.3 accepts tiny/normal/large/extreme, not "medium".
export CFLAGS_loongarch64_unknown_linux_gnu="${CFLAGS_loongarch64_unknown_linux_gnu:--mcmodel=large -O2}"
export CXXFLAGS_loongarch64_unknown_linux_gnu="${CXXFLAGS_loongarch64_unknown_linux_gnu:--mcmodel=large -O2}"
export RUSTFLAGS="${RUSTFLAGS:-} -C code-model=large -C link-arg=-Wl,--no-keep-memory"

export OPENSSL_DIR="$PREFIX/ossl/usr"
export OPENSSL_LIB_DIR="$PREFIX/ossl/usr/lib/loongarch64-linux-gnu"
export OPENSSL_INCLUDE_DIR="$PREFIX/ossl/usr/include"
export PKG_CONFIG_ALLOW_CROSS=1

export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
export CARGO_PROFILE_RELEASE_DEBUG=0
export CARGO_INCREMENTAL=0
export CARGO_TERM_COLOR="${CARGO_TERM_COLOR:-always}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/work/target}"
export CARGO_NET_GIT_FETCH_WITH_CLI="${CARGO_NET_GIT_FETCH_WITH_CLI:-true}"

cd "$SRC"
# See fetch-toolchains.sh: drop Loongnix crates.io replacement if cargo
# created or inherited one after install.
for f in "${CARGO_HOME:-$HOME/.cargo}/config.toml" "${CARGO_HOME:-$HOME/.cargo}/config"; do
  if [ -f "$f" ] && grep -Eq 'replace-with|crates-io-loongnix' "$f"; then
    echo "==> neutralizing crate-registry rewrite in $f"
    sed -i -E 's/^([[:space:]]*replace-with[[:space:]]*=.*)/# \1/' "$f"
  fi
done
export CARGO_REGISTRIES_CRATES_IO_PROTOCOL="${CARGO_REGISTRIES_CRATES_IO_PROTOCOL:-sparse}"

# Project-level override in case cargo was built with a default mirror.
mkdir -p "$SRC/.cargo"
if ! grep -q 'source.upstream-crates-io' "$SRC/.cargo/config.toml" 2>/dev/null; then
  cat >> "$SRC/.cargo/config.toml" << 'CARGOCFG'

# Added by codex-loongarch-oldworld CI to use official crates.io.
[source.crates-io]
replace-with = "upstream-crates-io"

[source.upstream-crates-io]
registry = "sparse+https://index.crates.io/"
CARGOCFG
fi

echo "==> rustc $(rustc --version)  cargo $(cargo --version)"
echo "==> building $CODEX_TAG with -j${JOBS}"
date -u
time cargo build --release -p codex-cli --bin codex \
  --target loongarch64-unknown-linux-gnu -j "$JOBS"

BIN="$CARGO_TARGET_DIR/loongarch64-unknown-linux-gnu/release/codex"
test -x "$BIN"
loongarch64-linux-gnu-strip "$BIN" || true
"$HERE/verify-elf.sh" "$BIN"
ls -lh "$BIN"
echo "BUILD_OK $BIN"
