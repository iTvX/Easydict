# Fork 自动发布

本文说明 `iTvX/Easydict` fork 的自动发布：PR 合并进 `dev` 后，本机自托管 runner 构建、
签名、公证并发布 GitHub Release，fork 构建的 App 通过 Sparkle 从这些 Release 自动更新。
上游 `tisfeng/Easydict` 的交互式发布见 [easydict.md](easydict.md)，其 `release-easydict`
Skill 只面向上游，不用于 fork。

## 发布流程

[`fork-release.yml`](../../.github/workflows/fork-release.yml) 在 `dev` 收到 push（即 PR
合并）或手动触发时运行，只修改 `docs/`、Markdown、`.agents/` 或 `changelog/` 的提交不触发。
它在带 `easydict-release` 标签的自托管 runner 上执行
[`fork-release.sh run`](../../scripts/fork-release/fork-release.sh)：

1. Preflight：用密码文件解锁发布专用钥匙串，检查 Developer ID 身份、notarytool profile、
   Sparkle 私钥，以及 Info.plist 的 `SUFeedURL` 和 `SUPublicEDKey` 是否与 fork 和私钥一致。
2. 计算版本：构建号取工程 `CURRENT_PROJECT_VERSION` 与已发布 feed 最大构建号的较大值加一；
   显示版本和 Tag 为 `<MARKETING_VERSION>.<构建号>`，例如 `2.25.0.69`。版本只通过
   `xcodebuild` 参数注入，CI 不向仓库提交任何内容。
3. 不签名归档，再用专用钥匙串中的 Developer ID 由内向外签名：先签 Sparkle 的 XPC 服务、
   `Updater.app` 和 `Autoupdate`，再签每个内嵌 framework 与 dylib，最后带 entitlements 和
   hardened runtime 签 App；随后校验版本、Team ID、时间戳和 `get-task-allow`。
4. 公证并 staple App；用已 staple 的 App 生成 Sparkle ZIP 和 DMG，再签名、公证并 staple DMG。
5. 用 Sparkle 私钥签名 ZIP，并用 App 内的 `SUPublicEDKey` 验证签名；生成 Release 说明和
   `appcast.xml`（新条目在前，保留最近 10 个 fork 版本）。
6. 以 Draft 创建 Release 并核对全部附件后才公开，因此 feed 只会指向完整可下载的版本；最后确认
   公开 feed 已提供新构建。

App 的 `SUFeedURL` 是 `https://github.com/iTvX/Easydict/releases/latest/download/appcast.xml`，
“有新版本”检查和版本菜单使用 `AppConstants.releaseRepoName`。反馈 Issue 的链接仍指向上游。

## 凭据与 runner 环境

做法与本机其他发布 runner 一致：凭据只放在 runner 目录 `~/actions-runners/easydict` 下的
私有文件中，不写入仓库，也不放进 GitHub Secrets。runner 的私有 `.env` 提供：

| 变量 | 含义 |
| --- | --- |
| `EASYDICT_SIGNING_KEYCHAIN` | 存放 Developer ID 身份的专用钥匙串；未设置时使用登录钥匙串 |
| `EASYDICT_NOTARY_KEYCHAIN` | 存放 notarytool profile 的钥匙串；默认同签名钥匙串 |
| `EASYDICT_KEYCHAIN_PASSWORD_FILE` | 解锁签名钥匙串的密码文件，权限必须为 600 |
| `EASYDICT_NOTARY_KEYCHAIN_PASSWORD_FILE` | 解锁公证钥匙串的密码文件；默认同上 |
| `EASYDICT_NOTARY_PROFILE` | notarytool profile 名称，必填 |
| `EASYDICT_SPARKLE_KEY_FILE` | Sparkle Ed25519 私钥文件，权限必须为 600，必填 |
| `EASYDICT_TEAM_ID` | 可选；钥匙串中有多个 Developer ID 身份时指定团队 |
| `CODESIGN_VIA_LAUNCHCTL`、`NOTARY_VIA_LAUNCHCTL` | 可选；设为 `1` 时经 `launchctl asuser` 在登录会话中运行 codesign 或 notarytool |

发布钥匙串不加入钥匙串搜索列表，所以构建阶段关闭 Xcode 签名，改由脚本以 `--keychain` 指定
钥匙串签名。公证钥匙串可以与其他发布 App 共用；脚本结束时只重新锁定 Easydict 自己的签名
钥匙串，不锁定共用的公证钥匙串。

## 一次性准备

### 签名与公证凭据

由账号持有人在终端运行
[`setup-signing.sh`](../../scripts/fork-release/setup-signing.sh)。它创建或复用
`easydict-release.keychain-db` 及随机密码文件，导入 Developer ID 身份并允许 codesign 无弹窗
使用，准备公证凭据，生成 Sparkle 密钥，并把以上位置写入 runner 的 `.env`。身份可以来自
.p12 文件，或从本机已有的发布钥匙串复制：

```bash
./scripts/fork-release/setup-signing.sh --from-keychain <已有的发布钥匙串> --source-password-file <其密码文件> --profile <公证 profile>
./scripts/fork-release/setup-signing.sh --p12 <Developer ID .p12 文件>
```

从已有钥匙串复制时，若该钥匙串里已有 `--profile` 指定的 notarytool profile，就直接复用它
（不复制凭据，runner 公证时解锁那个钥匙串）；否则按 notarytool 的提示录入 Apple ID 与 App
专用密码（在 appleid.apple.com 生成）或 App Store Connect API key，保存到 Easydict 的钥匙串。Sparkle 密钥同时保存在登录钥匙串账户 `easydict-fork` 中；公钥写在私钥旁的
`.pub` 文件里，需要填入 `Easydict/App/Info.plist` 和 `Info-debug.plist` 的 `SUPublicEDKey`
并提交。请另行备份 Sparkle 私钥：丢失后，已安装的 fork 版本将无法再验证任何更新。

### Runner 与仓库设置

[`setup-runner.sh install`](../../scripts/fork-release/setup-runner.sh) 校验官方 SHA-256 后把
runner 解压到 `~/actions-runners/easydict`，注册为 `easydict-<主机名>`，并作为当前用户的
LaunchAgent 启动：

```bash
./scripts/fork-release/setup-runner.sh install
```

runner 只在该用户登录时运行，锁屏不影响；Mac 睡眠时任务会排队到唤醒。修改 `.env` 后再次运行
`install` 即可重启服务。

公开仓库挂自托管 runner 时，外部 PR 可能修改 workflow 在本机执行代码，因此要求所有外部
贡献者的 PR workflow 都经批准，且 `fork-release.yml` 不得添加 `pull_request` 或
`pull_request_target` 触发：

```bash
gh api -X PUT repos/iTvX/Easydict/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors
```

准备完成后，可在加载 runner `.env` 的环境中运行 `fork-release.sh preflight` 检查全部前提。

## 运维

- 手动发布当前 `dev`：`gh workflow run fork-release.yml --repo iTvX/Easydict --ref dev`。
- 在公开 Release 之前失败的运行不会公开任何内容；遗留的 Draft 会在下一次运行时自动删除，
  并以同一版本号重试。完整日志、公证结果和产物保留在
  `~/Library/Caches/easydict-fork-release/run`，直到下一次运行；为避免泄露本机路径，不上传为
  公开仓库的 artifact。
- runner 状态与卸载：`./scripts/fork-release/setup-runner.sh status|uninstall`。
- 构建缓存位于 `~/Library/Caches/easydict-fork-release/DerivedData`，增量归档失败时自动清空
  重试一次。Swift 包使用系统 git 拉取，避免无人值守时出现钥匙串授权弹窗。
- 上游新增 PlugIns、XPCServices、Helpers 或 LoginItems 时，签名会明确失败，需要先扩展
  `sign_app` 的签名顺序。

## 与上游同步

合并上游时保留 fork 专属差异：Info.plist 的 `SUFeedURL`、`SUPublicEDKey`，以及
`AppConstants.releaseRepoName`。上游的 `appcast.xml` 不被 fork 使用。上游提升
`CURRENT_PROJECT_VERSION` 或 `MARKETING_VERSION` 后，下一次 fork 构建号仍取两者较大值加一，
不会倒退。

从上游版本切换到 fork 版本需要手动安装一次 fork 的 DMG：两者签名团队和 Sparkle 密钥不同，
无法自动迁移，辅助功能等系统权限也需要重新授权。
