#!/bin/bash
# Shared version helpers and pinned public toolchain URLs.
# Sourced by other scripts; not executed on its own.

# Loongnix / Loongson public downloads (old-world ABI 1.0, glibc 2.28).
: "${RUST_VER:=1.99.0}"
: "${RUST_DATE:=2026-10-09}"
: "${GCC_NAME:=loongson-gnu-toolchain-8.3-x86_64-loongarch64-linux-gnu-rc1.6}"
: "${OSSL_DEB_VER:=1.1.1d-0+lnd.13}"

RUST_HOST_URL="${RUST_HOST_URL:-https://rust-lang.loongnix.cn/dist/${RUST_VER}/${RUST_DATE}/rust-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz}"
RUST_STD_URL="${RUST_STD_URL:-https://rust-lang.loongnix.cn/dist/${RUST_VER}/${RUST_DATE}/rust-std-${RUST_VER}-loongarch64-unknown-linux-gnu.tar.xz}"
GCC_URL="${GCC_URL:-https://ftp.loongnix.cn/toolchain/gcc/release/loongarch/gcc8/${GCC_NAME}.tar.xz}"
OSSL_DEV_URL="${OSSL_DEV_URL:-https://pkg.loongnix.cn/loongnix/pool/main/o/openssl/libssl-dev_${OSSL_DEB_VER}_loongarch64.deb}"
OSSL_LIB_URL="${OSSL_LIB_URL:-https://pkg.loongnix.cn/loongnix/pool/main/o/openssl/libssl1.1_${OSSL_DEB_VER}_loongarch64.deb}"

normalize_codex_version() {
  local raw="${1:?version required}"
  raw="${raw#rust-}"
  raw="${raw#v}"
  if ! [[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unsupported Codex version '$1' (expected 0.167.0, v0.167.0, or rust-v0.167.0)" >&2
    return 1
  fi
  echo "$raw"
}
