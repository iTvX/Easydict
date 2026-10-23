## 2026-10-22 | 任务：把维护者本机设置设为默认值

**Links:** None

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `Unknown`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

### 用户请求

维护者希望 fork 新安装时直接使用维护者本机 Easydict 2.25.0.72 的偏好设置，并随下一次 fork 发布上线。

### 变更

- 通用：`autoQueryOCRText` 改为关，`selectQueryTextWhenWindowActivate` 改为开；Google、欧路、
  苹果词典和快捷设置 4 个快捷图标（`showGoogleQuickLink`、`showEudicQuickLink`、
  `showAppleDictionaryQuickLink`、`showQuickActionButton`）默认不显示。
- 高级：`autoShowQueryIcon`（划词后自动显示查询图标）改为关；`fixedWindowPosition` 从屏幕右侧
  改为鼠标位置。
- 服务：`LocalStorage` 首次建立服务状态时，侧悬浮窗口里的 DeepL 和内置 AI 默认折叠
  （`enabledQuery = false`），有道照常自动查询；主窗口和迷你窗口不变。
- 快捷键：首次启动只设置划词翻译 ⌥D 和迷你窗口 ⌥F；输入翻译 ⌥A、截图翻译 ⌥S、静默截图 OCR ⌥⇧S
  和窗口内全部快捷键（⌘K、⌘⇧C 等）默认留空，与维护者本机一致。

### 设计意图

只对比本机 UserDefaults 中与代码默认值不同的用户偏好。服务列表与顺序、划词后自动查询、窗口类型、
朗读服务和菜单栏图标本来就与默认一致，不改；API key、窗口坐标与尺寸（按屏幕计算）、查询历史、
统计计数、缓存和界面语言（跟随系统）属于机器或个人数据，不写进代码。服务折叠和快捷键只在新安装
首次启动时生效，已有记录保持原样。修改 `Defaults` 默认值后，已有用户中没有手动改过这些开关的
也会随更新采用新值。

### 验证

- `xcodebuild test`（Debug，agent DerivedData）：构建通过，改动文件无新增警告；456 个测试中只有
  10 个失败，共 82 处，全部依赖本机环境，与本任务无关：OCRImageTests 的 60 处文字比对（在
  `fa1e2e02` 上已逐项相同）、需要各家 API key 和网络的服务翻译验证 19 处、本机 Copilot CLI 2 处、
  Apple 离线翻译结果 1 处。
- 按 `scripts/fork-release/fork-release.sh` 的参数做未签名 Release `xcodebuild archive`：
  `** ARCHIVE SUCCEEDED **`。
- `git diff --check`：通过。
- 未手动验证全新安装的首次启动：测试版会注册同样的 ⌥D / ⌥F 全局快捷键并抢占前台，会干扰维护者
  正在使用的 Easydict。改动只涉及默认值和首次建立服务状态的一处条件，属于低风险变更，未走
  `review` 技能。

### 受影响文件

- `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`
- `Easydict/Swift/Feature/Shortcut/Model/ShortcutManager+Default.swift`
- `Easydict/Swift/Service/Model/Storage/LocalStorage.swift`
- `docs/histories/2026-10/2026-10-22-ship-local-settings-as-defaults.md`

### 后续事项

- None
