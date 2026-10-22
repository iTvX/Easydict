## 2026-10-22 | 任务：移除 Firebase 与 Sentry

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-22-remove-firebase-sentry.md)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5[1m]`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

### 用户请求

Fork 没有自己的 Firebase / Sentry 项目，沿用的是上游作者的 key；按维护者要求整体删除统计与崩溃上报，
只保留本机崩溃日志，同时删除对应的设置开关和依赖。

### 变更

- 删除 `AnalyticsService`（Firebase Analytics + Sentry）以及 Swift / Objective-C 中全部上报调用，
  包括选区事件里采集的前台 App、bundle ID 和浏览器 host。
- 删除“隐私”设置页、`allowCrashLog` / `allowAnalytics` 配置和 7 个只属于该页的本地化 key；
  `MyConfiguration` 中只为上报设置变更而存在的 22 个 `Defaults` 观察者和 setter 一并删除。
- 删除 `GoogleService-Info.plist`、加密的 `sentryDSN`、Release 的 Sentry 符号上传 build phase、
  `.sentryclirc` 忽略项，以及只服务于上报的 `EZEnumTypes` / `DeviceSystemInfo` 辅助方法。
- 工程移除 `firebase-ios-sdk` 与 `sentry-cocoa`；重新解析后 Package.resolved 少了 14 个只由二者
  引入的包，其余 pin 不变。
- `MMCrash` 本机崩溃日志保持不变；替换文本按钮的本地日志改为不依赖统计辅助方法。

### 设计意图

Fork 维护者看不到上游后台的数据，保留 SDK 只会让用户数据发往第三方并带来启动和常驻开销；
Firebase 还不受原开关控制。整体删除比修开关更符合隐私与维护目标。删除隐私页后 `SettingTab`
原始值顺延，该值只用于 `TabView` 选择，不持久化。用户机器上的旧偏好值不再读取，残留无害。

### 验证

- `xcodebuild -resolvePackageDependencies -scmProvider system`（checkout 专属 Agent DerivedData）：
  成功，Package.resolved 只删除 14 个 pin。
- `xcodebuild build -workspace Easydict.xcworkspace -scheme Easydict`（Debug）：通过。
- 按 `scripts/fork-release/fork-release.sh` 的参数做未签名 Release `xcodebuild archive`：通过；
  产物不再包含 Firebase / Sentry 符号或 `GoogleService-Info.plist`，主二进制比当前安装的
  2.25.0.69 小约 5.5 MB。
- `git diff --check`、`jq -e .`（`Localizable.xcstrings`、`Package.resolved`）、`plutil -lint`
  （`project.pbxproj`、`EncryptedSecretKeys.plist`）：通过。
- Review：检查完整 diff、调用链、测试 target、文档与致谢来源；无有效 finding。
- 未运行：`xcodebuild test`（测试未引用被删除的 API，本次不改变可测试行为）；手动未打开设置窗口 UI。

### 受影响文件

- `.gitignore`
- `Easydict.xcodeproj/project.pbxproj`
- `Easydict.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `Easydict/App/EasydictApp.swift`
- `Easydict/App/GoogleService-Info.plist`
- `Easydict/App/Localizable.xcstrings`
- `Easydict/Swift/Feature/Configuration/`
- `Easydict/Swift/Feature/DefaultAPIKeys/EncryptedSecretKeys.plist`
- `Easydict/Swift/Service/Model/Storage/LocalStorage.swift`
- `Easydict/Swift/Utility/DeviceInfo/DeviceSystemInfo.swift`
- `Easydict/Swift/Utility/Logging/AnalyticsService.swift`
- `Easydict/Swift/View/SettingView/`
- `Easydict/objc/Service/Model/EZEnumTypes.h`
- `Easydict/objc/Service/Model/EZEnumTypes.m`
- `Easydict/objc/ViewController/`
- `docs/exec-plans/completed/2026-10/2026-10-22-remove-firebase-sentry.md`
- `docs/histories/2026-10/2026-10-22-remove-firebase-sentry.md`

### 后续事项

- `EventMonitor.frontmostApplication` 与 `browserTabURLString` 已无读取方，由并行的启动/设置任务清理。
