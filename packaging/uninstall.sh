#!/bin/bash
# Remove Codex CLI installed by install.sh.  Usage: sudo ./uninstall.sh
# Your ~/.codex (config, sessions) is kept; delete it by hand if you want.
set -euo pipefail
DESTDIR="${DESTDIR:-}"
if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行:  sudo ./uninstall.sh" >&2
    exit 1
fi
if [ -f "$DESTDIR/usr/local/bin/codex" ] && grep -q 'opt/codex-loongarch' "$DESTDIR/usr/local/bin/codex"; then
    rm -f "$DESTDIR/usr/local/bin/codex"
    echo "已删除 /usr/local/bin/codex"
fi
rm -rf "$DESTDIR/opt/codex-loongarch"
echo "已删除 /opt/codex-loongarch"
echo "~/.codex 保留未动（配置和会话记录）。不需要的话: rm -rf ~/.codex"
