# 降低启动内存与常驻开销

- 状态：completed
- 创建日期：2026-10-22
- 负责人：Max Yu
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `Not recorded`
- **Environment:** `macOS 27.0.1 / Xcode 27.0 (27A266a)`

## 背景

2026-10-22 的性能调查（同版本 Release 构建对照测量）发现：启动时的窗口补丁用
`objc_copyClassList` 实例化进程内全部类，常驻 +12.5 MB；每次启动都跑 Vision OCR 预热，
常驻 +8.5 MB、启动峰值 +77 MB；打开一次设置后关闭，常驻 +36 MB 且不回落。另有划词、
OCR 截图和若干常驻小项的额外开销。查询结果视图泄漏和 Firebase/Sentry 移除由其他任务负责。

## 目标与范围

- 目标结果：去掉上述启动开销，处理报告中其余低风险条目；设置窗口能释放则释放。
- 允许修改路径：`Easydict/` 下与上述条目相关的源码；本 plan 与同任务 history。
- 同任务 history：`docs/histories/2026-10/2026-10-22-reduce-startup-memory-and-overhead.md`
- 用户限制：在独立 worktree 和分支上完成；不改查询结果视图（`EZWordResultView.m` 等）、
  `EZWindowManager.m` 和统计相关代码；合并顺序为 Firebase 移除、本任务、泄漏修复。
- 非目标：查询泄漏、Firebase/Sentry 移除、LLM 流式输出的增量渲染（需改 `EZWordResultView.m`）。
- 验收标准：Debug 与 Release 构建通过；相关现有测试不新增失败；隔离测试版实测启动常驻下降。

## 工作计划

1. 窗口补丁只按镜像扫描 AppKit、SwiftUI、QuickLookUI、ImageKit，不再实例化全部类。
2. OCR 预热在当前系统版本成功一次、且编译缓存仍在时跳过。
3. 设置窗口关闭时卸载标签页内容，实测后决定是否保留。
4. 划词：去掉每次划词取浏览器 URL 的 AppleScript（只供统计使用）；语言检测只取前缀。
5. OCR：裁剪后的截图拷贝为独立位图；诊断 PNG 只在 DEBUG 写盘。
6. 其余常驻小项：音频缓存、查询历史、密钥缓存、Vapor 延迟初始化、WebView swizzle、
   Google JSContext、MDict 缓存、苹果词典样式表、窗口拖动写盘。
7. 构建、测试、隔离测试版实测、独立 Review 并修复有效 finding。

## 风险与决策

- 窗口补丁按镜像扫描：在 macOS 27 上加载全部相关框架后，全量扫描只命中这四个框架中的
  五个类；其他框架将来新增的重写不再覆盖，代价是失去一次 GPU 优化，不影响功能。
- OCR 预热：同时检查标记和 e5rt 的按系统构建号缓存目录；目录布局变化时退回每次启动预热。
- 设置窗口：与原版同条件对照后撤回。SwiftUI 的类型元数据和缓存无法释放，释放的对象又因
  malloc 碎片不归还系统，重新打开要重建，反复开关后占用反而比原版高。
- AX 全局超时：撤回。超时后的读取失败没有回退路径，较慢应用（如首次请求辅助功能树的
  Electron 应用）会从“慢但成功”变成取词失败。
- 浏览器“优先使用 AppleScript”是用户设置，保留其取词行为，只去掉取 URL 的那次。
- 不改强制复制的触发条件和多击延迟：属于取词兼容性调优，回归风险高于收益。
- 查询历史与窗口位置改为延迟写盘，待写期间关闭 sudden termination，退出时同步写完。

## 进度

- [x] 窗口补丁
- [x] OCR 预热
- [x] 设置窗口（实测后撤回）
- [x] 划词与 OCR
- [x] 其余小项
- [x] 构建、测试、实测与 Review

## 验证

- 见同任务 history。

## 完成条件

- 构建与相关测试通过，实测数据记录到 history，Review 无未处理的有效 finding。
