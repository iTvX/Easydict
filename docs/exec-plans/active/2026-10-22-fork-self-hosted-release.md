# Fork 自托管 Runner 自动发布

- 状态：active
- 创建日期：2026-10-22
- 负责人：Claude Code
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `Not recorded`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

## 背景

`iTvX/Easydict` 是长期维护的 fork，默认分支为 `dev`，没有 `main`、Tag 或 Release。现有
`release-easydict` 流程面向上游 `tisfeng/Easydict`：交互式 Draft/Publish、上游团队证书、
`asc` CLI、向 `main`/`dev` 推送 appcast 提交并跟进上游 Issue，不适合无人值守的 fork 发布。
App 的 Sparkle 地址、公钥和“新版本”检查也都指向上游，fork 构建无法收到自己的更新。

## 目标与范围

- 目标结果：PR 合并进 fork 的 `dev` 后，本机自托管 runner 自动构建、Developer ID 签名、
  Apple 公证与 staple，并发布带 ZIP、DMG、appcast 和校验和的 GitHub Release；fork 构建的
  App 从 fork 的 Release 获取更新。
- 允许修改路径：`.github/workflows/`、`scripts/fork-release/`、`docs/releases/`、`AGENTS.md`
  任务路由、`Easydict/App/Info*.plist` 的 Sparkle 键、`AppConstants`、`GitHubReleaseFetcher`。
- 同任务 history：`docs/histories/2026-10/2026-10-22-fork-self-hosted-release.md`
- 用户限制：证书、公证凭据和 Sparkle 私钥由 Max 在自己的终端运行脚本配置，不经 Agent 处理，
  不进入仓库或 GitHub Secrets；注册 runner、修改仓库设置、推送前需 Max 确认；只读参考
  Lotus 与 macshot，不修改它们。
- 非目标：修改上游 `release-easydict` Skill；迁移已安装上游版本的用户；beta channel 轮换。
- 验收标准：workflow 与脚本静态检查通过；App 在新配置下 Release 构建成功；凭据就绪后，
  一次真实运行产出已公证的 Release，且 `releases/latest/download/appcast.xml` 指向新版本。

## 工作计划

1. 编写 `scripts/fork-release/`：preflight、版本计算、不签名 Archive 后用专用钥匙串由内向外
   签名、两轮公证与 staple、ZIP/DMG、Sparkle 签名与公钥校验、appcast 与 Release 发布；
   以及 Max 运行的凭据配置脚本和 runner 安装脚本。
2. 新增仅在 `iTvX/Easydict` 的 `dev` push 和手动触发时运行的 workflow。
3. 把 `SUFeedURL`、`SUPublicEDKey` 和版本检查仓库改为 fork；Issue 链接保留上游。
4. 编写维护文档并接入 `AGENTS.md` 路由。
5. 凭据就绪后注册 runner、收紧 fork PR 审批策略、推送并验证首次发布。

## 风险与决策

- 公开仓库挂自托管 runner：fork PR 可修改 workflow 在本机执行代码。workflow 只响应 `push`
  和 `workflow_dispatch`，并把外部贡献者 PR 的 workflow 审批策略改为全部需审批。
- appcast 作为 Release 附件，经 `releases/latest/download/appcast.xml` 提供：不向分支推送
  提交、不与上游 `appcast.xml` 冲突，且 Release 公开前 feed 不会指向新版本。
- 版本号：构建号取工程构建号与 fork 最新 appcast 构建号的较大值加一；显示版本和 Tag 为
  `<MARKETING_VERSION>.<构建号>`，与 `GitHubReleaseFetcher` 的数值比较保持一致。版本只通过
  `xcodebuild` 参数注入，不提交工程文件。
- 签名团队变化：上游安装的 App 无法自动迁移到 fork；用户需手动安装一次并重新授予辅助功能权限。
- 沿用本机其他发布 runner 的模式：`~/actions-runners/<name>`、专用钥匙串加密码文件、runner
  私有 `.env`。专用钥匙串不在搜索列表中，Xcode 无法用它签名，因此构建关闭签名，由脚本按
  Sparkle 文档顺序签 XPC、`Updater.app`、`Autoupdate`，再签各 framework、dylib 和 App。
- Swift 包改用系统 git 拉取，避免 Xcode 内置 git 在无人值守时弹出钥匙串授权。

## 进度

- [x] 发布脚本、凭据配置脚本与 runner 安装脚本
- [x] workflow
- [x] App 更新地址与公钥
- [x] 凭据配置（专用钥匙串、复用 `lotus-notary`、Sparkle 密钥）与 preflight
- [x] 文档与路由
- [ ] runner 注册、外部 PR 审批策略、推送 `dev` 与首次发布验证

## 验证

- `bash -n`、`shellcheck`（全部脚本）、`python3 -m py_compile`、YAML 解析：通过；actionlint 仅
  提示自定义 runner 标签。
- `fork_release.py`：RFC 8032 测试向量通过；Sparkle `sign_update` 签名可被派生公钥验证，上游
  公钥被拒绝；appcast 两轮生成、重复构建号拒绝、Release 说明渲染符合预期。
- Debug `xcodebuild build`（agent DerivedData）：成功。
- 不签名的 Release `xcodebuild archive`（与脚本相同参数，scratch DerivedData，系统 git）：成功；
  App 为 `2.25.0.69 (69)`、universal、`SUFeedURL` 指向 fork，Frameworks 外仅主程序为 Mach-O。
- 按 `sign_app` 顺序 ad-hoc 签名归档 App：`codesign --verify --deep --strict` 通过，带 hardened
  runtime；Downloader.xpc 的 entitlements 签名前后一致。
- 使用 runner 私有配置运行 `fork-release.sh preflight`：通过。
- 代码审查后修复：移除失败日志 artifact（避免在公开仓库泄露本机路径，日志改留本机缓存目录）、
  checkout action 固定到提交 SHA、文档改正“失败不公开”的范围。

## 完成条件

- 静态检查与 Release 构建通过，首次真实发布验证完成或已明确记录阻塞项。
