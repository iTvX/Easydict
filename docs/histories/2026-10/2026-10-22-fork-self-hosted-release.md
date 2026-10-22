## 2026-10-22 | 任务：为 fork 配置自托管 runner 自动发布

**Links:** [计划](../../exec-plans/completed/2026-10/2026-10-22-fork-self-hosted-release.md)、[Release 2.25.0.69](https://github.com/iTvX/Easydict/releases/tag/2.25.0.69)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `Not recorded`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

### 用户请求

在本机配置 GitHub Actions runner：PR 合并后自动构建、Apple 公证并发布 Release；App 的更新
跟随 fork（`iTvX/Easydict`）而不是上游。

### 变更

- 新增 `.github/workflows/fork-release.yml`：仅在 `iTvX/Easydict` 的 `dev` push 与手动触发时，
  在带 `easydict-release` 标签的自托管 runner 上运行；不响应任何 PR 事件，不上传 artifact。
- 新增 `scripts/fork-release/`：`fork-release.sh` 负责 preflight、版本计算、不签名 Archive、
  由内向外 Developer ID 签名、App 与 DMG 两轮公证和 staple、Sparkle 签名与公钥校验、appcast、
  Draft 核对后公开 Release；`fork_release.py` 提供版本、Release 说明 HTML、appcast 与 Ed25519
  校验；`setup-signing.sh` 供维护者在终端配置专用钥匙串、公证 profile 与 Sparkle 密钥；
  `setup-runner.sh` 安装、查看和卸载 runner。
- `Info.plist`、`Info-debug.plist` 的 `SUFeedURL` 改为
  `releases/latest/download/appcast.xml`，`SUPublicEDKey` 改为 fork 的 Sparkle 公钥；
  `AppConstants.releaseRepoName` 供版本检查与 Releases 链接使用，Issue 链接仍指向上游。
- 新增 `docs/releases/fork-release.md`，并在 `AGENTS.md` 任务路由中指向它。

### 设计意图

沿用本机其他发布 runner 的做法：`~/actions-runners/<name>`、专用钥匙串加密码文件、runner 私有
`.env`，凭据不进入仓库或 GitHub Secrets。公证复用本机已有的 `lotus-notary` profile，只读借用
其所在钥匙串、不锁定也不修改它。appcast 作为 Release 附件提供，CI 不向分支推送提交，也不与
上游 `appcast.xml` 冲突；显示版本 `<MARKETING_VERSION>.<构建号>` 与 `GitHubReleaseFetcher` 的数值
比较一致。仓库公开，因此只用 push 触发，并要求外部贡献者 PR 的 workflow 经批准。

### 验证

- `bash -n`、`shellcheck`、`py_compile`、YAML 解析、`git diff --check` 与相对链接检查：通过。
- `fork_release.py`：RFC 8032 测试向量、Sparkle `sign_update` 交叉验证、appcast 生成与重复构建号
  拒绝：通过。
- Debug `xcodebuild build`：成功；不签名 Release `xcodebuild archive`：成功，产物为
  `2.25.0.69 (69)` universal；按脚本顺序 ad-hoc 签名后 `codesign --verify --deep --strict` 通过。
- 使用 runner 私有配置运行 `fork-release.sh preflight`：通过（Developer ID 团队 `AW54C93V4H`、
  公证 profile、Sparkle 公私钥配对、更新地址）。
- 首次真实发布：runner `easydict-admins-mac-mini` 的 Fork Release 运行成功，发布 `2.25.0.69`；
  App 与 DMG 均获 Apple 公证并 staple。匿名下载后核对校验和、EdDSA 签名、`codesign --deep
  --strict`、`stapler validate` 与 `spctl`（Notarized Developer ID，团队 `AW54C93V4H`），公开
  feed 提供构建 69：全部通过。
- 未验证：已安装 fork 版本后的 Sparkle 自动更新，需要下一个版本发布后才能观察。

### 受影响文件

- `.github/workflows/fork-release.yml`
- `scripts/fork-release/fork-release.sh`
- `scripts/fork-release/fork_release.py`
- `scripts/fork-release/setup-signing.sh`
- `scripts/fork-release/setup-runner.sh`
- `Easydict/App/Info.plist`
- `Easydict/App/Info-debug.plist`
- `Easydict/Swift/Utility/Constants/AppConstants.swift`
- `Easydict/Swift/Utility/GitHubReleaseFetcher.swift`
- `docs/releases/fork-release.md`
- `docs/exec-plans/completed/2026-10/2026-10-22-fork-self-hosted-release.md`
- `AGENTS.md`

### 后续事项

- 已安装上游版本的设备需手动安装一次 fork 的 DMG，并重新授予辅助功能等权限。
