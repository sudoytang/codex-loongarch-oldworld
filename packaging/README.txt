Codex CLI 龙芯版（旧世界 LoongArch / 银河麒麟 V10 SP1）
==========================================================

这是什么
--------
OpenAI Codex CLI __CODEX_VERSION__，专门为旧世界 LoongArch（ABI1.0、glibc 2.28）
交叉编译的版本，适用于龙芯 3A6000 + 银河麒麟桌面 V10 SP1。
已预配好 DeepSeek 作为模型服务（关闭了沙箱、开启了 AI 自动审查，见第 3 节），只需要填自己的 DeepSeek API key。

包里的文件
----------
  install.sh             安装脚本（用 sudo 运行）
  uninstall.sh           卸载脚本
  bin/codex              Codex 程序本体（约 317MB）
  bin/codex-wrapper.sh   启动脚本，装好后就是 codex 命令
  config.toml.template   DeepSeek 配置模板（不含 key）

1. 安装
-------
  tar -xJf codex-loongarch-kylin.tar.xz
  cd codex-loongarch-kylin
  sudo ./install.sh

安装脚本会：
  - 把程序放到 /opt/codex-loongarch/bin/codex
  - 装一个 /usr/local/bin/codex 启动命令
  - 如果 ~/.codex/config.toml 还不存在，就写入 DeepSeek 配置
    （已有的配置不会被覆盖）
最后会打印 codex-cli __CODEX_VERSION__，说明程序能正常运行。

2. 设置 DeepSeek API key
------------------------
到 https://platform.deepseek.com 申请 key，然后：

  echo 'export DEEPSEEK_API_KEY=sk-你的key' >> ~/.bashrc
  source ~/.bashrc

key 只存在你自己的 ~/.bashrc 里，配置文件里没有。

3. 使用
-------
  cd 你的项目目录
  codex                              进入交互界面
  codex "帮我看看这个项目是做什么的"    带着问题直接开始
  codex exec "say hi in one word"    非交互，跑完就退出
  codex resume                       继续之前的会话
  codex --version                    查看版本

关于 --no-daemon：这个版本是单独一个程序，没法启动 Codex 的后台服务，
直接运行会报 "this CLI has no complete local package"。
/usr/local/bin/codex 这个启动命令会自动加上 --no-daemon，平时直接敲 codex
就行，不用管它。需要原样调用时可以用 /opt/codex-loongarch/bin/codex。
codex agents、codex remote-control 依赖后台服务，这个版本用不了。

关于沙箱和审查：Codex 在 Linux 上默认用 bubblewrap(bwrap) 做沙箱，麒麟 V10
没有 bwrap，沙箱启动不了。所以 config.toml 里关掉了沙箱，改用 AI 自动审查：
  sandbox_mode = "danger-full-access"
  approval_policy = "on-request"
  approvals_reviewer = "auto_review"
普通命令直接执行；Codex 判定为危险的命令（比如 rm -rf 这类）会交给一个 AI
审查员决定放不放行，不会来问你。命令拥有你这个用户的全部权限，请只在你信任的
项目目录里使用。
想每条命令都先过 AI 审查：把 approval_policy 改成 "untrusted"（更慢、更费 token）。
完全不要审查：删掉 approvals_reviewer 那行，approval_policy 改成 "never"
（这时危险命令会被直接拒绝）。

切换模型：编辑 ~/.codex/config.toml，把 model 改成 "deepseek-v4-pro"。

4. 卸载
-------
  sudo ./uninstall.sh
（或 sudo /opt/codex-loongarch/uninstall.sh）
~/.codex 里的配置和会话记录会保留，不需要的话 rm -rf ~/.codex。
