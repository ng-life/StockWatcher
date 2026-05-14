# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

macOS 菜单栏 A 股监控程序，SwiftUI + AppKit 混编，macOS 14.0+，无第三方依赖。通过新浪财经/腾讯证券免费 API 获取实时行情，支持本地通知预警，点击股票可打开东方财富 K 线图窗口。

## 构建与运行

```bash
# 构建 Release 版
xcodebuild -project StockWatcher.xcodeproj -scheme StockWatcher -configuration Release -derivedDataPath ./DerivedData build

# 运行（菜单栏应用，无 Dock 图标）
open DerivedData/Build/Products/Release/StockWatcher.app

# 终止
pkill -f StockWatcher

# 构建产物清理
rm -rf DerivedData
```

## 架构

**MVVM 模式**，`StockViewModel` 是唯一的数据中枢（`@MainActor` + `ObservableObject`）。

数据流：`Combine Timer（5秒）→ refresh() → StockAPIService.fetchQuotes() → 更新 stocks → checkThresholds() → 通知`。所有视图观察 `@Published` 属性自动刷新。

**关键文件：**
- `StockWatcherApp.swift` — `@main` 入口，唯一 Scene 是 `MenuBarExtra(.window)`
- `StockViewModel.swift` — 核心业务逻辑：定时刷新、价格历史追踪、阈值通知、自选股管理、持久化、菜单栏 NSImage 渲染
- `StockAPIService.swift` — 新浪 API（主力）→ 腾讯 API（备用）fallback，GBK 编码解析
- `WebChartWindow.swift` — WKWebView 封装 + NSWindow 管理，按股票代码去重打开

## 重要约定与坑点

**颜色体系（中国股市惯例）：** 红涨绿跌，与西方相反。`StockQuote.isUp` → `.red`、`isDown` → `.green`。

**菜单栏颜色问题：** `MenuBarExtra` 的 label 会被系统转成 template image 强制覆盖颜色。解决方案：用 `statusBarImage()` 将 `NSAttributedString` 预渲染为 `NSImage`，再用 `Image(nsImage:)` 显示。新加菜单栏 UI 元素时沿用此模式。

**中文编码：** 新浪和腾讯 API 返回 GBK/GB18030 编码，通过 `CFStringEncodings.GB_18030_2000` 解码。修改 API 解析时必须保留此逻辑。

**代码规范化：** `normalizeCode(_:)` 负责将用户输入（如 `600519`、`sh600519`）统一为带 `sh`/`sz` 前缀的格式：6/5/9 开头 → `sh`，其余 → `sz`。

**通知去重：** `checkThresholds()` 用 `notifiedDailyHigh` / `notifiedFiveMinHigh` 两个 Set 做去重，价格回落到阈值以下才重置。避免每 5 秒重复推送同一条预警。

**窗口管理：** `WebChartWindowManager` 持有 `[code: NSWindow]` 字典，`isReleasedWhenClosed = false` 防止窗口关闭后被释放。`WindowDelegate` 在 `windowWillClose` 时清理引用。新窗口默认 920×680，最小 480×400。

**持久化：** 自选股列表存在 `UserDefaults` key `"tracked_stocks"`；通知阈值设置存在 `"notifications_enabled"`、`"daily_threshold"`、`"five_min_threshold"`。默认自选股：贵州茅台 (`sh600519`)、平安银行 (`sz000001`)。

**东方财富 URL 构造：** `market=1` 为沪市（sh/6xxxxx/5xxxxx/9xxxxx），`market=0` 为深市。
