#!/bin/bash
# Fail unless the binary is old-world LoongArch: interpreter /lib64/ld.so.1
# and no GLIBC symbol newer than 2.28.
set -euo pipefail
BIN="${1:?usage: verify-elf.sh path/to/codex}"
if [ ! -f "$BIN" ]; then
  echo "missing file: $BIN" >&2
  exit 1
fi

if ! readelf -h "$BIN" | grep -q 'LoongArch'; then
  echo "FAIL: not a LoongArch ELF" >&2
  readelf -h "$BIN" >&2 || true
  exit 1
fi

interp="$(readelf -l "$BIN" | sed -n 's/.*\[Requesting program interpreter: \(.*\)\]/\1/p')"
if [ "$interp" != "/lib64/ld.so.1" ]; then
  echo "FAIL: interpreter is '${interp:-<none>}', expected /lib64/ld.so.1 (old-world ABI 1.0)" >&2
  readelf -l "$BIN" | grep -A2 INTERP >&2 || true
  exit 1
fi

mapfile -t vers < <(readelf -W -s "$BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sed 's/^GLIBC_//' | sort -Vu)
if [ "${#vers[@]}" -eq 0 ]; then
  echo "FAIL: no GLIBC symbols found (unexpected for this build)" >&2
  exit 1
fi
max="${vers[-1]}"
echo "GLIBC symbols: ${vers[*]}"
echo "max GLIBC_${max}"
if [ "$(printf '%s\n' "$max" "2.28" | sort -V | tail -1)" != "2.28" ]; then
  echo "FAIL: max GLIBC_${max} is newer than 2.28" >&2
  exit 1
fi
echo "VERIFY_OK interpreter=/lib64/ld.so.1 max_glibc=2.28"
