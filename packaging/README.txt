Codex CLI for LoongArch (old-world / Kylin Desktop V10 SP1)
==========================================================

What this is
------------
OpenAI Codex CLI __CODEX_VERSION__, cross-compiled for old-world LoongArch
(ABI 1.0, glibc 2.28). It is meant for Loongson 3A6000 systems running
Kylin Desktop V10 SP1.
DeepSeek is preconfigured as the model provider (sandbox disabled, AI
auto-review enabled; see section 3). You only need to add your own
DeepSeek API key.

Files in this package
---------------------
  install.sh             installer (run with sudo)
  uninstall.sh           uninstaller
  bin/codex              the Codex binary (about 317MB)
  bin/codex-wrapper.sh   launcher; this becomes the `codex` command
  config.toml.template   DeepSeek config template (no API key)

1. Install
----------
  tar -xJf codex-loongarch-kylin.tar.xz
  cd codex-loongarch-kylin
  sudo ./install.sh

The installer will:
  - place the binary at /opt/codex-loongarch/bin/codex
  - install a /usr/local/bin/codex launcher
  - write the DeepSeek config to ~/.codex/config.toml if that file
    does not already exist (an existing config is left untouched)
It then prints `codex-cli __CODEX_VERSION__`, which means the binary runs.

2. Set your DeepSeek API key
----------------------------
Create a key at https://platform.deepseek.com, then:

  echo 'export DEEPSEEK_API_KEY=sk-your-key' >> ~/.bashrc
  source ~/.bashrc

The key lives only in your own ~/.bashrc; it is not stored in the
config file.

3. Usage
--------
  cd your-project-directory
  codex                              enter the interactive UI
  codex "what does this project do?" start with a question
  codex exec "say hi in one word"    non-interactive; exits when done
  codex resume                       continue a previous session
  codex --version                    print the version

About --no-daemon: this build is a single binary and cannot start Codex's
background app-server. Running the raw binary reports "this CLI has no
complete local package". The /usr/local/bin/codex launcher adds
--no-daemon for you, so you can just type `codex`. To invoke the binary
unchanged, use /opt/codex-loongarch/bin/codex.
`codex agents` and `codex remote-control` need the background service and
are not available in this build.

About sandbox and review: on Linux, Codex sandboxes with bubblewrap
(bwrap). Kylin V10 has no bwrap, so the sandbox cannot start. The packaged
config.toml therefore turns the sandbox off and uses AI auto-review:

  sandbox_mode = "danger-full-access"
  approval_policy = "on-request"
  approvals_reviewer = "auto_review"

Ordinary commands run directly. Commands Codex flags as dangerous
(for example `rm -rf`) are sent to an AI reviewer that approves or
denies them instead of asking you. Commands run with your full user
permissions; only use this in project directories you trust.
To send every command through the AI reviewer first, set
approval_policy = "untrusted" (slower, more tokens).
To disable review entirely, delete the approvals_reviewer line and set
approval_policy = "never" (dangerous commands are then refused).

To switch models, edit ~/.codex/config.toml and set model to
"deepseek-v4-pro".

4. Uninstall
------------
  sudo ./uninstall.sh
(or sudo /opt/codex-loongarch/uninstall.sh)
Config and session history under ~/.codex are kept. Remove them with
rm -rf ~/.codex if you no longer need them.
