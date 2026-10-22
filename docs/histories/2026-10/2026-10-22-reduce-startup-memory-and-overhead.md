## 2026-10-22 | 任务：降低启动内存与常驻开销

**Links:** [计划](../../exec-plans/completed/2026-10/2026-10-22-reduce-startup-memory-and-overhead.md)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `Not recorded`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

### 用户请求

按 2026-10-22 性能调查报告全部修复。本任务负责启动项、设置窗口和报告中除查询泄漏与
Firebase/Sentry 移除之外的条目，在独立 worktree 上完成，推送后开 PR 并合并发布。

### 变更

- 启动：
  - `_cornerMask` 窗口补丁不再用 `objc_copyClassList` 实例化全部类，改为只读取 AppKit、
    SwiftUI 镜像中名称像窗口的类，以及 QuickLookUI、ImageKit 的全部类；命中与原扫描相同。
  - Vision OCR 预热在当前系统版本成功一次、且 e5rt 按系统构建号的编译缓存仍在时跳过。
  - `VaporServer` 的环境检测和日志初始化推迟到服务第一次启动。
  - `SecretKeyManager.keyValues` 只读取并解密一次。
  - 已无调用方的 `EZWebViewTranslator` 不再在启动时 swizzle `WKWebView`。
- 划词与 OCR：
  - 删除每次浏览器划词都运行的取标签页 URL AppleScript，它只供已删除的统计事件使用；
    同时删除统计删除后无人读取、却在每个监听事件里更新的 `EventMonitor.frontmostApplication`。
  - 决定是否显示划词图标时，只用前 1000 个字符检测语言。
  - 截图裁剪后拷贝为独立位图，不再连带保留整块屏幕的截图；诊断 PNG 只在 DEBUG 写盘。
- 常驻小项：
  - 查询历史与收藏缓存在内存中，后台合并写入 Defaults，退出时同步写完。
  - 窗口位置拖动或缩放时最多每 0.5 秒写一次 Defaults，退出时写完。
  - 两处延迟写入在待写期间关闭 sudden termination。
  - 发音音频查找改为直接检查三种扩展名；缓存超过 100 MB 时在后台按最近使用删到 80 MB。
  - 所有 Google 服务实例共用一个 `JSContext`；更新 TKK 时同时清空签名脚本缓存的旧值。
  - MDict 单词典 data URI 缓存从 32 MB 降到 8 MB，停用词典时释放其读取器和缓存。
  - 苹果词典同一词典文档中，与前一个样式表完全相同的样式表清空内容。

### 设计意图

只去掉不影响功能的重复工作，保留用户可见行为：窗口补丁仍覆盖所有已知重写类，OCR 预热
在系统更新或缓存被清理后照常运行，浏览器“优先使用 AppleScript”设置保持原样。

以下报告条目实测或评估后没有改：

- 设置窗口关闭时卸载标签页：与原版同条件对照，SwiftUI 类型元数据与缓存不释放，释放的
  对象因 malloc 碎片不归还系统，重新打开还要重建，两次开关后占用比原版高，已撤回。
- 全局 AX 超时：超时后的读取失败没有回退路径，较慢应用会从“慢但成功”变成取词失败。
- 强制复制触发条件、多击延迟：取词兼容性调优，回归风险高于收益。
- LLM 流式增量渲染：需改 `EZWordResultView.m`，由查询泄漏任务负责该文件；`<think>`
  正则实测 2 万字约 2.7 ms，不是瓶颈。

### 验证

- Debug `xcodebuild build` 通过，变更文件无新增警告。
- `xcodebuild test`（AppleDictionaryTests、MDictReaderTests、UtilityFunctionsTests、
  AppleLanguageDetectorTests、OCRQRCodeTests、OCRImageTests）：前五个 suite 通过；
  OCRImageTests 的 60 处文字比对失败在未修改的 `fa1e2e02` 上逐项相同，与本任务无关。
- Release 隔离测试版（独立 bundle id、默认配置、同一台机器）：
  - 启动后常驻 31 MB、峰值 31–32 MB；调查报告中同一提交为 52.5 MB、峰值 121 MB。
  - 热启动到 `didFinishLaunching` 153–188 ms；报告中为 246 ms。
  - 首次启动预热照常运行并写入标记；之后启动跳过；移走 e5rt 缓存目录后再次预热。
  - 窗口补丁日志仍命中 `_NSTextFinderOverlayWindow` 与 `SwiftUISuggestionsWindow`；独立
    进程加载 Quartz、QuickLookUI 后，新扫描与全量扫描同样命中五个类，耗时约 3–8 ms、
    +1–1.4 MB，全量扫描为 13–29 ms、+12–22 MB。
- 设置窗口对照（与原版同条件，打开、关闭、再打开、再关闭）：原版打开后 +35 MB，之后
  持平；卸载内容的版本释放约 12 MB 存活对象，但占用不回落，两轮后比原版多约 10 MB，撤回。
- Google 签名：独立脚本确认只改 `window.TKK` 时签名不变，清空 `yr` 后使用新 TKK。
- `git diff --check` 通过。
- 两路独立 Review 无 P0–P2；P3 已修复：补回 QuickLookUI/ImageKit 覆盖、Google TKK 缓存、
  OCR 缓存缺失时重新预热、延迟写盘期间关闭 sudden termination；AX 超时与设置窗口改动撤回。

### 受影响文件

- `Easydict/objc/Utility/EZWindowPatch/EZWindowPatch.m`
- `Easydict/Swift/Service/Apple/AppleOCREngine/AppleOCREngine+WarmUp.swift`、`AppleOCREngine.swift`
- `Easydict/Swift/Feature/HTTPServer/Vapor/VaporServer.swift`
- `Easydict/Swift/Feature/DefaultAPIKeys/APIKey.swift`
- `Easydict/objc/Service/WebViewTranslator/EZURLSchemeHandler.m`
- `Easydict/Swift/Utility/EventMonitor/`、`Easydict/Swift/Utility/AppleScript/AppleScriptTask+Browser.swift`
- `Easydict/Swift/Feature/Screenshot/Screenshot/NSScreen+Extention.swift`
- `Easydict/Swift/View/SettingView/Tabs/Model/QueryRecordManager.swift`、
  `Easydict/Swift/Feature/Configuration/Configuration+UserData.swift`
- `Easydict/objc/ViewController/Window/WindowManager/EZLayoutManager.m`
- `Easydict/objc/Service/AudioPlayer/EZAudioPlayer.m`
- `Easydict/Swift/Service/Google/GoogleService.swift`、`GoogleService+Translate.swift`
- `Easydict/Swift/Service/Dictionary/MDict/MDictDictionary.swift`、`MDictManager.swift`
- `Easydict/Swift/Service/Dictionary/AppleDictionary/AppleDictionary.swift`
- 本任务 plan 与 history。

### 后续事项

- 查询结果窗口实时缩放时每帧重载表格（`EZBaseQueryViewController.m` 的 `resizeWindowBlock`），
  属于查询泄漏任务负责的文件，可在其合并后改为缩放结束时执行一次。
