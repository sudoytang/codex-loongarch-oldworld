#!/bin/sh
# Codex CLI wrapper for old-world LoongArch (Kylin V10 SP1).
#
# This build is a single binary, not a "complete local package", so the
# background app-server daemon cannot start ("this CLI has no complete local
# package ..."). The wrapper adds --no-daemon as the first top-level option:
#   codex                -> codex --no-daemon
#   codex exec "..."     -> codex --no-daemon exec "..."
#   codex resume --last  -> codex --no-daemon resume --last
# It does not add it when you already passed --no-daemon / --remote, or for
# the subcommands that need the daemon (agents, remote-control, app-server).
# Set CODEX_WRAPPER_DAEMON=1 to run the real binary with no changes.
REAL=/opt/codex-loongarch/bin/codex

if [ "${CODEX_WRAPPER_DAEMON:-0}" = 1 ]; then
    exec "$REAL" "$@"
fi

skip_next=0
sub=""
for a in "$@"; do
    case "$a" in
        --no-daemon|--remote|--remote=*) exec "$REAL" "$@" ;;
    esac
    if [ -z "$sub" ]; then
        if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
        case "$a" in
            -c|--config|-m|--model|-p|--profile|-C|--cd|-s|--sandbox|\
            -a|--ask-for-approval|-i|--image|--add-dir|--enable|--disable|\
            --local-provider|--remote-auth-token-env)
                skip_next=1 ;;
            --) sub="--" ;;
            -*) ;;
            *) sub="$a" ;;
        esac
    fi
done

case "$sub" in
    agents|remote-control|app-server) exec "$REAL" "$@" ;;
esac

exec "$REAL" --no-daemon "$@"
