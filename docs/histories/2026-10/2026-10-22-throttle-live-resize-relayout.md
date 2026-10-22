## 2026-10-22 | 任务：拖动调整查询窗口宽度时限制结果重排频率

**Links:** 无

### 执行上下文

- **Agent Name:** `Unknown`
- **Model:** `Unknown`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

### 用户请求

性能调查列出的问题需要全部修复。其中一项是：拖动窗口边缘调整宽度时，每一帧都会整表
重载查询结果。该项由启动项优化任务移交，单独提交。

### 变更

- `EZBaseQueryViewController` 把按宽度重排结果的逻辑提取为 `-relayoutResultsForCurrentWidth`。
- 窗口处于 live resize 时，`resizeWindowBlock` 改为合并重排：每 0.1 秒最多一次。
- 监听 `NSWindowDidEndLiveResizeNotification`，拖动结束时先作废已记录的布局宽度，再按最终宽度强制重排一次。
- 窗口高度更新只在没有待执行重排时记录当前宽度，避免把尚未重排的宽度误记为已布局。
- 非拖动引起的宽度变化（例如窗口动画结束后的检查）仍然立即重排，与原来一致。

### 设计意图

整表重载会重建每个结果视图、重新测量文本，并重算词典 iframe 高度。拖动时 `windowDidResize`
每帧都会触发，主线程的重排工作因此随帧率线性增长。限频之后，拖动过程中内容仍会约每 0.1 秒
跟随宽度重排一次。拖动期间，流式输出或词典高度回调可能先触发窗口高度更新，后者原本会把尚未重排的
宽度记为已布局，导致后续重排被跳过。因此高度更新在有待执行重排时不再记录宽度，拖动结束时也会强制
按最终宽度重排一次，最终布局与原来一致。窗口的 frame 持久化在 `EZLayoutManager` 中，
不在本任务范围内。

### 验证

- `xcodebuild build`（Debug，agent DerivedData）：`** BUILD SUCCEEDED **`，改动文件没有新增警告。
- `git diff --check`：通过。
- Review（`review` 技能，静态审查）：发现 1 个 P2，已修复。拖动期间高度更新会提前记录宽度，可能让
  最终重排被跳过。修复后其余检查项无问题：标记位竞态、与高度动画的交互、非拖动路径不变、观察者
  注销和 block 弱引用。
- 未手动验证：真实拖动窗口边缘时的重排效果。测试环境不能占用前台交互，live resize 只能由
  用户拖动触发。

### 受影响文件

- `Easydict/objc/ViewController/Window/BaseQueryWindow/EZBaseQueryViewController.m`

### 后续事项

- None
