#!/bin/bash
# Download and install the old-world LoongArch cross toolchain:
# Loongson GCC 8.3 (glibc 2.28 sysroot), Loongnix Rust 1.99.0 + rust-std,
# and Loongnix OpenSSL 1.1.1 headers/libs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=versions.sh
source "$HERE/versions.sh"

ROOT="$(cd "$HERE/.." && pwd)"
PREFIX="${TOOLCHAIN_PREFIX:-$ROOT/.cache/toolchains}"
mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"
DL="$PREFIX/dl"
mkdir -p "$DL" "$PREFIX/rust" "$PREFIX/ossl" "$PREFIX/hostbin"

download() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    echo "already have $(basename "$dest")"
    return 0
  fi
  echo "==> downloading $url"
  local tmp="${dest}.part"
  rm -f "$tmp"
  local i
  for i in 1 2 3 4 5 6; do
    if curl -fL --retry 5 --retry-all-errors --retry-delay 8 \
        --connect-timeout 30 --speed-limit 10000 --speed-time 60 \
        -o "$tmp" "$url"; then
      mv "$tmp" "$dest"
      return 0
    fi
    echo "download attempt $i failed, retrying..." >&2
    sleep $((i * 8))
  done
  echo "FAILED to download $url" >&2
  return 1
}

if [ ! -x "$PREFIX/gcc/bin/loongarch64-linux-gnu-gcc" ]; then
  download "$GCC_URL" "$DL/${GCC_NAME}.tar.xz"
  echo "==> extracting GCC toolchain"
  rm -rf "$PREFIX/gcc" "$PREFIX/${GCC_NAME}"
  tar -C "$PREFIX" -xf "$DL/${GCC_NAME}.tar.xz"
  if [ -d "$PREFIX/${GCC_NAME}" ]; then
    mv "$PREFIX/${GCC_NAME}" "$PREFIX/gcc"
  else
    # unexpected top-level name
    top="$(find "$PREFIX" -maxdepth 1 -mindepth 1 -type d ! -name dl ! -name rust ! -name ossl ! -name hostbin ! -name gcc | head -1)"
    [ -n "$top" ]
    mv "$top" "$PREFIX/gcc"
  fi
  "$PREFIX/gcc/bin/loongarch64-linux-gnu-gcc" -dumpversion
fi

if [ ! -x "$PREFIX/rust/bin/cargo" ] || [ ! -d "$PREFIX/rust/lib/rustlib/loongarch64-unknown-linux-gnu" ]; then
  download "$RUST_HOST_URL" "$DL/rust-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz"
  download "$RUST_STD_URL" "$DL/rust-std-${RUST_VER}-loongarch64-unknown-linux-gnu.tar.xz"
  echo "==> installing Rust ${RUST_VER} (host + loongarch64 std)"
  rm -rf "$PREFIX/rust" "$PREFIX/rust-extract"
  mkdir -p "$PREFIX/rust-extract"
  tar -C "$PREFIX/rust-extract" -xf "$DL/rust-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz"
  tar -C "$PREFIX/rust-extract" -xf "$DL/rust-std-${RUST_VER}-loongarch64-unknown-linux-gnu.tar.xz"
  host_dir="$(find "$PREFIX/rust-extract" -maxdepth 1 -type d -name 'rust-*-x86_64-unknown-linux-gnu' | head -1)"
  std_dir="$(find "$PREFIX/rust-extract" -maxdepth 1 -type d -name 'rust-std-*-loongarch64-unknown-linux-gnu' | head -1)"
  "$host_dir/install.sh" --prefix="$PREFIX/rust" --disable-ldconfig
  "$std_dir/install.sh" --prefix="$PREFIX/rust" --disable-ldconfig
  rm -rf "$PREFIX/rust-extract"
  "$PREFIX/rust/bin/rustc" -vV
  test -d "$PREFIX/rust/lib/rustlib/loongarch64-unknown-linux-gnu"
fi

if [ ! -e "$PREFIX/ossl/usr/include/openssl/ssl.h" ] || [ ! -e "$PREFIX/ossl/usr/lib/loongarch64-linux-gnu/libssl.so" ]; then
  download "$OSSL_DEV_URL" "$DL/libssl-dev_${OSSL_DEB_VER}_loongarch64.deb"
  download "$OSSL_LIB_URL" "$DL/libssl1.1_${OSSL_DEB_VER}_loongarch64.deb"
  echo "==> extracting OpenSSL headers and libs"
  rm -rf "$PREFIX/ossl"
  mkdir -p "$PREFIX/ossl"
  dpkg-deb -x "$DL/libssl-dev_${OSSL_DEB_VER}_loongarch64.deb" "$PREFIX/ossl"
  dpkg-deb -x "$DL/libssl1.1_${OSSL_DEB_VER}_loongarch64.deb" "$PREFIX/ossl"
  if [ -d "$PREFIX/ossl/usr/include/loongarch64-linux-gnu/openssl" ]; then
    mkdir -p "$PREFIX/ossl/usr/include/openssl"
    cp -a "$PREFIX/ossl/usr/include/loongarch64-linux-gnu/openssl/." "$PREFIX/ossl/usr/include/openssl/"
  fi
  test -e "$PREFIX/ossl/usr/include/openssl/ssl.h"
  test -e "$PREFIX/ossl/usr/lib/loongarch64-linux-gnu/libssl.so" \
    || test -e "$PREFIX/ossl/usr/lib/loongarch64-linux-gnu/libssl.so.1.1"
fi

# Host cc/c++ wrappers: Rust 1.99 defaults to -fuse-ld=lld (bundled rust-lld),
# which SIGSEGV'd on the Debian host that first produced a working binary.
# Drop those flags so host build.rs / proc-macro links use system GNU ld.bfd.
WRAP="$PREFIX/hostbin"
cat > "$WRAP/cc" << 'W'
#!/bin/bash
args=()
for a in "$@"; do
  case "$a" in
    -fuse-ld=lld|-fuse-ld=mold) ;;
    *) args+=("$a") ;;
  esac
done
exec /usr/bin/cc "${args[@]}"
W
cat > "$WRAP/c++" << 'W'
#!/bin/bash
args=()
for a in "$@"; do
  case "$a" in
    -fuse-ld=lld|-fuse-ld=mold) ;;
    *) args+=("$a") ;;
  esac
done
exec /usr/bin/c++ "${args[@]}"
W
chmod +x "$WRAP/cc" "$WRAP/c++"

# Loongnix's cargo often rewrites crates.io to crates-io-loongnix, which
# can lag official crates (CI failed on rustls 0.23.46). Use crates.io.
neutralize_registry_rewrites() {
  local f
  for f in \
      "${CARGO_HOME:-$HOME/.cargo}/config.toml" \
      "${CARGO_HOME:-$HOME/.cargo}/config" \
      "$HOME/.cargo/config.toml" \
      "$HOME/.cargo/config" \
      "$PREFIX/rust/.cargo/config.toml" \
      "$PREFIX/rust/.cargo/config"; do
    [ -f "$f" ] || continue
    if grep -Eq 'replace-with|crates-io-loongnix|rsproxy|ustc.edu.cn' "$f"; then
      echo "==> neutralizing crate-registry rewrite in $f"
      sed -i -E 's/^([[:space:]]*replace-with[[:space:]]*=.*)/# \1/' "$f"
    fi
  done
}
neutralize_registry_rewrites

echo "TOOLCHAINS_OK prefix=$PREFIX"
