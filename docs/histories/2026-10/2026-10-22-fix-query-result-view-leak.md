## 2026-10-22 | 任务：修复每次查询泄漏结果视图的问题

**Links:** 无

### 执行上下文

- **Agent Name:** `Unknown`
- **Model:** `Unknown`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

### 用户请求

性能调查发现每次查询后内存持续增长。用户要求追查原因，直到完全修复。

### 变更

- `EZWordResultView` 两个发音按钮的 `playAudioBlock` 改为弱引用 `self`：
  - 音标发音按钮复用 `-refreshWithResult:` 中已有的 `mm_weakify(self)`。
  - 底部工具栏方法在方法开头统一声明一次 `mm_weakify(self)`，并移除 Markdown 切换按钮分支里
    重复声明的那一处。
- `-refreshWithResult:` 移除旧子视图前，先把直接子视图中 `NSTextView` 的 `delegate` 置空。

### 设计意图

用 Release 对照构建驱动查询，并配合 `heap`、`leaks --traceTree` 和临时的 retain/release 跟踪
定位到两个原因：

1. **发音按钮 block 强引用结果视图。** 按钮是结果视图的子视图，二者构成引用环。表格每次刷新
   都会换新的结果单元格，旧的 `EZWordResultView` 连同 service 和整棵子视图树都无法释放。
2. **`NSTextView` 释放时会 autorelease 它的 delegate。** 旧的结果标签可能在 `__CFRunLoopDoBlocks`
   这类没有局部自动释放池的延迟工作中才被释放。AppKit 只在处理 NSEvent 时才排空主线程的自动
   释放池，而 Easydict 的查询多由快捷键、URL Scheme、定时器和异步回调触发，所以结果视图会一直
   留到用户下一次与窗口交互。刷新前把 delegate 置空，autorelease 就发生在当前调用栈内，不会
   再滞留。

另外试过在表格刷新入口包一层 `@autoreleasepool`，对第 2 个原因无效：autorelease 发生在
AppKit 的延迟工作中，不经过这些入口。因此没有保留这项改动。也没有采用给主 RunLoop
加全局自动释放池观察者的方案，因为它会改变整个 AppKit 的自动释放语义，风险过大。

### 验证

- `xcodebuild build`（Release、arm64、ad-hoc 签名，独立 DerivedData）：`** BUILD SUCCEEDED **`。
- `xcodebuild build`（Debug，agent DerivedData）：`** BUILD SUCCEEDED **`，改动文件没有新增警告。
- 对照实测：同一 commit 分别构建修复前和修复后的版本，使用独立 bundle id 和默认服务
  （有道、DeepL、内置 AI），通过 `easydict://query` 连续查询 12 次：

  | 版本 | 常驻内存 | 残留 `EZWordResultView` |
  |---|---|---|
  | 修复前 | 74.0 → 102.1 MB，线性增长约 2.3 MB/次 | 42 个 |
  | 修复后 | 72.4 → 80.6 MB，第 4 次后基本持平 | 3 个（即正在显示的 3 个） |

- 修复后第 4 到第 12 次查询之间，堆只增加 0.34 MB，对象数量反而减少。
- 只做发音 block 修复时，每次查询仍残留约 1.2 个结果视图；加上 delegate 置空后归零。
  另外，人为向 App 发送 NSEvent 后残留同样归零，这印证了第 2 个原因。
- Review（`review` 技能，静态审查）：无 finding。
  - `EZWordResultView` 唯一实现的 delegate 方法是 `-textView:doCommandBySelector:`（Esc 关闭
    窗口）。新建标签仍会设置 delegate，所以该行为不受影响。
  - 设置了 delegate 的标签都是直接子视图。
  - 弱引用的发音 block 只会在按钮仍可点击时调用，此时 `self` 必然存活。
- 未手动验证：Esc 关闭窗口、发音播放和 Markdown 切换的实际点击（测试环境不能占用前台交互）。

### 受影响文件

- `Easydict/objc/ViewController/View/WordResultView/EZWordResultView.m`

### 后续事项

- 修复后每次查询仍有少量 AppKit 内部的 `NSKeyValueDependency` 等对象增长（约 1 KB/次），来源
  不在 Easydict 代码中，暂不处理。
