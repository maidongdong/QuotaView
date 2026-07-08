# QuotaView 1.1.6

原生 Swift/AppKit 菜单栏应用。它直接启动本机：

```text
/Applications/Codex.app/Contents/Resources/codex app-server --listen stdio://
```

通过 JSON-RPC 调用 `account/rateLimits/read`，显示 5 小时和周额度的剩余百分比及重置时间。剩余额度按 `100 - usedPercent` 计算。

## 构建

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open outputs/CodexQuotaBar.app
```

## 安装

推荐打开 `outputs/CodexQuotaBar.dmg`，将 `CodexQuotaBar.app` 拖入“应用程序”，再从“应用程序”中启动。应用无需单独登录，直接使用本机 Codex App 的账号状态。

这是 Apple Silicon 测试版，采用 ad-hoc 签名且未进行 Apple 公证。其他电脑首次打开时，可能需要右键应用并选择“打开”，或在“系统设置 > 隐私与安全性”中允许。

构建脚本同时输出：

- `outputs/CodexQuotaBar.dmg`：推荐安装包。
- `outputs/CodexQuotaBar.zip`：备用压缩包。
- `outputs/CodexQuotaBar.app`：本机直接运行版本。

ZIP 和 DMG 内的应用均在临时目录完成签名；直接放在文件同步目录中的 `.app` 可能被系统附加 `FinderInfo` 属性。

应用常驻 macOS 顶部菜单栏，每 15 秒轮询一次，并监听 `account/rateLimits/updated`、`account/updated` 和 `account/login/completed`，在额度或账号变化后立即刷新。点击菜单栏额度可查看两行分段电量条、剩余百分比和重置时间。

弹窗底部的“设置”默认折叠。展开后可以开启或关闭“开机自动启动”。该选项默认开启，用户选择会被持久保存；从只读 DMG 直接运行时不会注册登录项，并会提示先完成安装。
