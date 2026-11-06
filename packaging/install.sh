#!/bin/bash
# Install Codex CLI (old-world loongarch64 build) for Kylin V10 SP1.
# Usage:  sudo ./install.sh
# DESTDIR=/some/root ./install.sh installs into a staging root (for testing).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DESTDIR="${DESTDIR:-}"
PREFIX_DIR="$DESTDIR/opt/codex-loongarch"
WRAPPER="$DESTDIR/usr/local/bin/codex"

if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行:  sudo ./install.sh" >&2
    exit 1
fi

if [ -z "$DESTDIR" ]; then
    arch="$(uname -m)"
    if [ "$arch" != "loongarch64" ]; then
        echo "警告: 当前架构是 $arch，这个包只适用于 loongarch64。" >&2
    fi
    if [ ! -e /lib64/ld.so.1 ]; then
        echo "警告: 没找到 /lib64/ld.so.1，这台机器可能不是旧世界(ABI1.0)系统，codex 可能无法运行。" >&2
    fi
fi

for f in bin/codex bin/codex-wrapper.sh config.toml.template; do
    [ -f "$HERE/$f" ] || { echo "缺少文件: $f" >&2; exit 1; }
done

echo "==> 安装 codex 到 /opt/codex-loongarch/bin/codex"
install -d -m 755 "$PREFIX_DIR/bin"
install -m 755 "$HERE/bin/codex" "$PREFIX_DIR/bin/codex"
install -m 644 "$HERE/config.toml.template" "$PREFIX_DIR/config.toml.template"
install -m 755 "$HERE/uninstall.sh" "$PREFIX_DIR/uninstall.sh"

echo "==> 安装启动脚本 /usr/local/bin/codex (自动加 --no-daemon)"
install -d -m 755 "$DESTDIR/usr/local/bin"
install -m 755 "$HERE/bin/codex-wrapper.sh" "$WRAPPER"

# ~/.codex/config.toml for the user who ran sudo (or TARGET_USER / current user)
user="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"
if [ -n "$DESTDIR" ]; then
    home="$DESTDIR/home/$user"
else
    home="$(getent passwd "$user" | cut -d: -f6)"
fi
if [ -z "$home" ]; then
    echo "找不到用户 $user 的家目录，跳过配置文件。" >&2
else
    cfg_dir="$home/.codex"
    cfg="$cfg_dir/config.toml"
    if [ -e "$cfg" ]; then
        echo "==> $cfg 已存在，保留不动 (模板在 /opt/codex-loongarch/config.toml.template)"
    else
        echo "==> 写入 DeepSeek 配置 $cfg"
        install -d -m 700 "$cfg_dir"
        install -m 600 "$HERE/config.toml.template" "$cfg"
        if [ -z "$DESTDIR" ] && [ "$user" != root ]; then
            grp="$(id -gn "$user")"
            chown "$user:$grp" "$cfg_dir" "$cfg"
        fi
    fi
fi

echo
echo "安装完成。"
if [ -z "$DESTDIR" ]; then
    "$WRAPPER" --version || echo "警告: codex --version 运行失败" >&2
fi
echo "下一步: 设置 DeepSeek key，然后运行 codex（见 README.txt）。"
