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

# Loongnix cargo 1.63+ hardcodes [source.crates-io] replace-with =
# "crates-io-loongnix" (https://crates.loongnix.cn/crates.io-index) inside
# the cargo binary. Commenting out config.toml does nothing: there is no
# such file. That mirror can lag official crates.io (rustls 0.23.46 was
# missing) and its git index can EOF from GitHub-hosted runners.
# Default: put upstream cargo of the same version first on PATH and keep
# Loongnix rustc + old-world rust-std. Set USE_LOONGNIX_CRATES=1 to keep
# the baked-in mirror (useful on a host in China).
comment_out_registry_rewrites() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if grep -Eq 'replace-with|crates-io-loongnix|rsproxy|ustc.edu.cn' "$f"; then
      echo "==> neutralizing crate-registry rewrite in $f"
      sed -i -E 's/^([[:space:]]*replace-with[[:space:]]*=.*)/# \1/' "$f"
    fi
  done < <(find "${CARGO_HOME:-$HOME/.cargo}" "$HOME/.cargo" "$PREFIX" \
            -type f \( -name config -o -name config.toml \) 2>/dev/null)
}

if [ "${USE_LOONGNIX_CRATES:-0}" = "1" ]; then
  echo "==> USE_LOONGNIX_CRATES=1: leaving Loongnix cargo's crates.io mirror enabled"
else
  comment_out_registry_rewrites
  if [ ! -x "$PREFIX/hostbin/cargo" ] || grep -aFq 'crates-io-loongnix' "$PREFIX/hostbin/cargo"; then
    download "$OFFICIAL_CARGO_URL" "$DL/official-cargo-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz"
    echo "==> installing official cargo ${RUST_VER} (no crates-io-loongnix rewrite)"
    rm -rf "$PREFIX/official-cargo-extract"
    mkdir -p "$PREFIX/official-cargo-extract"
    tar -C "$PREFIX/official-cargo-extract" -xf "$DL/official-cargo-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz"
    official_cargo="$(find "$PREFIX/official-cargo-extract" -type f -path '*/bin/cargo' | head -1)"
    [ -n "$official_cargo" ]
    cp "$official_cargo" "$PREFIX/hostbin/cargo"
    chmod +x "$PREFIX/hostbin/cargo"
    rm -rf "$PREFIX/official-cargo-extract"
  fi
  if grep -aFq 'crates-io-loongnix' "$PREFIX/hostbin/cargo"; then
    echo "refusing to use cargo that still embeds crates-io-loongnix: $PREFIX/hostbin/cargo" >&2
    exit 1
  fi
  "$PREFIX/hostbin/cargo" --version
fi

echo "TOOLCHAINS_OK prefix=$PREFIX"
