# 移除 Firebase 与 Sentry

- 状态：completed
- 创建日期：2026-10-22
- 负责人：Claude Code
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5[1m]`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

## 背景

Fork `iTvX/Easydict` 仍沿用上游的 Firebase 项目（`easydict-7232d`）和 Sentry DSN，数据只进入上游
作者的后台，fork 维护者看不到。2026-10-22 性能审计还发现 Firebase 不受“匿名统计”开关控制、Sentry
以 `debug = true` 启动且可能启动两次，选区上报还带有前台 App、bundle ID 和浏览器 host。

## 目标与范围

- 目标结果：删除 Firebase Analytics 与 Sentry 的依赖、初始化、上报调用、配置文件、Sentry 符号上传
  脚本和“隐私”设置页；保留 `MMCrash` 写入本机日志目录的崩溃日志。
- 允许修改路径：`Easydict/`、`Easydict.xcodeproj/project.pbxproj`、
  `Easydict.xcworkspace/xcshareddata/swiftpm/Package.resolved`、`.gitignore`、`docs/`。
- 同任务 history：`docs/histories/2026-10/2026-10-22-remove-firebase-sentry.md`
- 用户限制：在独立 worktree 中开发；与启动/设置窗口、查询泄漏两个并行任务协调合并顺序，本任务先合并。
- 非目标：不改动 `MMCrash` 本地崩溃日志；不清理用户机器上残留的旧偏好值。
- 验收标准：仓库不再引用 Firebase、Sentry 或 `AnalyticsService`；Debug 构建通过；Package.resolved
  不再包含仅由这两个 SDK 引入的依赖。

## 工作计划

1. 删除 `AnalyticsService` 及其 Swift / Objective-C 调用点，只为分析存在的辅助代码一并删除。
2. 删除隐私设置页、`allowCrashLog` / `allowAnalytics` 配置及其本地化字符串。
3. 删除 `GoogleService-Info.plist`、`sentryDSN`、Sentry 符号上传 build phase 与 `.sentryclirc` 忽略项。
4. 从工程移除 `firebase-ios-sdk` 与 `sentry-cocoa`，重新解析 Package.resolved。
5. 构建验证、Review，记录 history 并归档本计划。

## 风险与决策

- 删除隐私页后 `SettingTab` 的原始值顺延；该值未持久化，只用于 `TabView` 选择。
- 只用于记录设置变更的 `Defaults` 观察者随 `logSettings` 一起删除，保留有实际副作用的观察者。
- 用户机器上旧的 `EZConfiguration_kAllowCrashLogKey` / `EZConfiguration_kAllowAnalyticsKey` 偏好值
  不再被读取，残留无害，不额外迁移。

## 进度

- [x] 删除代码、设置页与配置。
- [x] 移除依赖并重新解析。
- [x] 构建、Review、history。

## 验证

- 结果见同任务 history：
  [`2026-10-22-remove-firebase-sentry.md`](../../../histories/2026-10/2026-10-22-remove-firebase-sentry.md)。

## 完成条件

- Debug 构建通过，`git grep` 不再找到 Firebase / Sentry / `AnalyticsService` 引用。
