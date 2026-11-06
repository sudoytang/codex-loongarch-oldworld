# Codex for old-world LoongArch

Cross-compile [OpenAI Codex](https://github.com/openai/codex) (`codex-rs` / `codex-cli`) for **old-world** LoongArch64 machines: ABI 1.0, dynamic linker `/lib64/ld.so.1`, **glibc ≤ 2.28**. That is the userspace on Loongson 3A6000 systems running **Kylin Desktop V10 SP1** (kernel 5.4).

GitHub Actions builds a friend-style install tarball and publishes a Release whenever you ask, and a scheduled workflow follows upstream **stable** Codex releases (not alphas / prereleases).

A working binary was first produced by cross-compiling Codex **0.163.0** on an x86_64 Debian host with the toolchains and workarounds below. This repository turns that recipe into scripts you can rerun.

## Install a release

Download `codex-loongarch-kylin-<version>.tar.xz` from [Releases](https://github.com/sudoytang/codex-loongarch-oldworld/releases):

```bash
tar -xJf codex-loongarch-kylin-<version>.tar.xz
cd codex-loongarch-kylin
sudo ./install.sh
```

`install.sh` puts the binary in `/opt/codex-loongarch/bin/codex` and a wrapper at `/usr/local/bin/codex`. The wrapper adds `--no-daemon` because this is a single binary, not Codex's "complete local package" (no background app-server). The tarball README (Chinese) covers DeepSeek configuration via `DEEPSEEK_API_KEY`, why the sandbox is off on Kylin (no `bwrap`), and uninstall.

No API keys are stored in this repository or in the packaged `config.toml` template.

## Trigger a build

In the Actions tab, run **Build old-world LoongArch Codex** and pass a version:

- `0.167.0`
- `v0.167.0`
- `rust-v0.167.0`

All three fetch upstream tag `rust-v0.167.0` and publish GitHub Release `v0.167.0`.

Or:

```bash
gh workflow run build.yml -f version=0.167.0
```

## How the workflows work

- [`build.yml`](.github/workflows/build.yml) — `workflow_dispatch` only. Installs the old-world toolchains, checks out `openai/codex` at `rust-v*`, cross-compiles `codex-cli`, verifies the ELF, packs `install.sh` / `uninstall.sh` / `codex-wrapper.sh` / README / config template, then creates or updates the matching Release. Cargo's crate registry and git db are cached; the toolchain tarballs are cached separately.
- [`watch-upstream.yml`](.github/workflows/watch-upstream.yml) — daily cron (06:30 Asia/Shanghai) plus manual dispatch. Reads the latest **non-prerelease**, non-alpha `rust-vX.Y.Z` release on `openai/codex`. If this repo has no `vX.Y.Z` (or `rust-vX.Y.Z`) Release yet, it dispatches `build.yml`.

A large upstream bump can break the build (new C dependencies, a Rust version Loongnix does not ship, and so on). Failures show up as failed Actions runs; they do not silently skip.

## Toolchains (public downloads)

Nothing proprietary is committed here. CI fetches:

| Piece | URL |
| --- | --- |
| Loongson GNU toolchain 8.3 (GCC 8.3.0, binutils 2.31.1, **glibc 2.28** sysroot) | https://ftp.loongnix.cn/toolchain/gcc/release/loongarch/gcc8/loongson-gnu-toolchain-8.3-x86_64-loongarch64-linux-gnu-rc1.6.tar.xz |
| Loongnix Rust 1.99.0 host (`x86_64-unknown-linux-gnu`) | https://rust-lang.loongnix.cn/dist/1.99.0/2026-10-09/rust-1.99.0-x86_64-unknown-linux-gnu.tar.xz |
| matching `rust-std` for `loongarch64-unknown-linux-gnu` (old-world) | https://rust-lang.loongnix.cn/dist/1.99.0/2026-10-09/rust-std-1.99.0-loongarch64-unknown-linux-gnu.tar.xz |
| OpenSSL 1.1.1d headers + `libssl1.1` (Loongnix) | `libssl-dev` / `libssl1.1` `1.1.1d-0+lnd.13` from https://pkg.loongnix.cn/loongnix/pool/main/o/openssl/ |

Official `rustup` `loongarch64-unknown-linux-gnu` std is the **new-world** ABI (interpreter `/lib64/ld-linux-loongarch-lp64d.so.1`). That binary will not run on Kylin V10 SP1, so this project uses Loongnix's Rust and the Loongson GCC 8.3 sysroot instead.

Upstream `rust-toolchain.toml` is deleted before the build. Codex may request 1.95.x (or another patch); Loongnix's available compiler is **1.99.0**, which is what compiled 0.163.0 successfully.

## Build workarounds

These are encoded in `scripts/build.sh` and `scripts/fetch-toolchains.sh`:

1. **Host `rust-lld` SIGSEGV.** Cross compilation still builds host `build.rs` and proc-macros. Rust 1.99 passes `-fuse-ld=lld`, and the bundled `rust-lld` segfaulted on the original Debian host. A small `cc`/`c++` wrapper drops `-fuse-ld=lld`/`mold` so host links use system `ld.bfd`.
2. **`relocation truncated to fit` (aws-lc-sys → `memcpy`).** The release binary is too large for the default LoongArch code model. Loongson GCC 8.3 accepts `tiny` / `normal` / `large` / `extreme` (not `medium`). The build sets `-mcmodel=large` on target C/C++ flags and `-C code-model=large` on `RUSTFLAGS`. After changing the model, rebuild `ring` / `aws-lc-sys`; a relink alone is not enough.
3. **Resource use.** LTO is off, `codegen-units = 16`, `debug = 0`, cargo incremental off, `-j2`. The successful Debian run needed several gigabytes of RAM plus swap.

Verification (`scripts/verify-elf.sh`) requires:

- ELF machine `LoongArch`
- interpreter `/lib64/ld.so.1`
- every `GLIBC_*` symbol ≤ `2.28`

## Local build

On an x86_64 Linux machine with `build-essential`, `cmake`, `perl`, `curl`, `git`, and `dpkg-deb`:

```bash
export CODEX_VERSION=0.167.0
./scripts/fetch-toolchains.sh
./scripts/build.sh
CODEX_BIN=work/target/loongarch64-unknown-linux-gnu/release/codex ./scripts/package.sh
```

## Credits

- [OpenAI Codex](https://github.com/openai/codex) is the upstream project. Redistribute and use build artifacts under Codex's own license (Apache-2.0 / MIT in the upstream tree). This repository only contains build and packaging scripts (MIT).
- Cross compilers and the old-world `rust-std` come from [Loongnix / Loongson](https://www.loongnix.cn/).
- The packaging wrapper, DeepSeek-oriented config template, and CI scripts were written from a successful 0.163.0 cross-build, with assistance from Grok Bot.

## What this does not do

- It does not produce a "complete local package" (`codex-code-mode-host`, bundled `rg` / `bwrap`, and so on). Features that need the background daemon (`codex agents`, remote control) are unavailable.
- It does not enable Codex's Linux sandbox on Kylin: there is no `bwrap`. The packaged config uses `sandbox_mode = "danger-full-access"` and optional AI auto-review instead.
- It does not follow alpha tags. Those ship too often for a multi-hour cross compile.
