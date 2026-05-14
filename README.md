# StockWatcher — macOS 菜单栏 A 股监控工具

macOS 菜单栏实时股票行情监控程序，基于 SwiftUI + AppKit 混编，macOS 14.0+，零第三方依赖。通过新浪财经 / 腾讯证券免费 API 获取实时行情，支持本地通知预警。

## 功能

- **菜单栏显示** — 菜单栏直接显示第一只自选股的实时价格，红涨绿跌，一目了然
- **多股监控** — 支持添加多只 A 股，每 5 秒自动刷新行情
- **涨跌预警** — 支持日内涨跌幅和 5 分钟快速涨跌幅双重阈值通知
- **K 线图** — 点击股票即可打开东方财富 K 线图窗口，按股票代码去重
- **右键删除** — 右键股票行可快速移除自选股
- **数据持久化** — 自选股列表和通知阈值自动保存

## 截图

（待补充）

## 系统要求

- macOS 14.0+
- Xcode 15.2+（如需从源码构建）

## 安装

### 直接下载

从 [Releases](../../releases) 下载最新版 `StockWatcher.app`，拖入 `/Applications` 即可。

### 从源码构建

```bash
git clone https://github.com/lifeng/StockWatcher.git
cd StockWatcher

# 构建 Release 版
xcodebuild -project StockWatcher.xcodeproj \
  -scheme StockWatcher \
  -configuration Release \
  -derivedDataPath ./DerivedData build

# 运行
open DerivedData/Build/Products/Release/StockWatcher.app
```

## 使用说明

### 启动

首次启动需要授予通知权限。程序运行后菜单栏会显示第一只自选股的价格。

### 添加股票

1. 点击菜单栏图标，点击右上角 **+** 按钮
2. 输入股票代码（支持 `600519`、`sh600519` 等格式）
3. 按回车确认

### 查看行情

弹出面板显示所有自选股列表，包含：
- 市场标签（沪/深）
- 股票名称和代码
- 当前价格
- 涨跌额和涨跌幅（红色上涨，绿色下跌）

### 查看 K 线图

点击任意股票行，自动打开东方财富 K 线图窗口。同一只股票不会重复打开窗口。

### 设置预警

点击右上角齿轮图标进入设置：
- **日内涨跌幅预警** — 当日累计涨跌幅超过阈值时通知，默认 ±3%
- **5 分钟涨跌幅预警** — 短时间内快速涨跌超过阈值时通知，默认 ±1%

通知带有去重机制，价格回落到阈值以下后才会再次触发。

### 删除股票

右键点击股票行，选择「删除」即可移除。

## 技术说明

| 项目 | 说明 |
|------|------|
| 语言 | Swift 5.0 |
| 框架 | SwiftUI + AppKit |
| 目标系统 | macOS 14.0 |
| 依赖 | 无第三方依赖，仅链接 WebKit.framework |
| 数据源 | 新浪财经 API → 腾讯证券 API（fallback） |
| 刷新频率 | 5 秒 |

### 数据流

```
Timer（5秒） → refresh() → StockAPIService.fetchQuotes()
  → 新浪 API（hq.sinajs.cn）
  └→ 失败时回退腾讯 API（qt.gtimg.cn）
  → 更新 stocks → checkThresholds() → 触发通知
```

### API 编码

新浪和腾讯 API 均返回 **GBK/GB18030** 编码的数据，非 UTF-8。程序通过 `CFStringEncodings.GB_18030_2000` 自动解码。

### 颜色体系

遵循中国股市惯例：**红色代表上涨，绿色代表下跌**，与西方市场颜色方案相反。

### 菜单栏渲染

`MenuBarExtra` 的 label 会被系统强制转为 template image 覆盖颜色。程序通过 `NSAttributedString` 预渲染为 `NSImage` 后再显示，保留了红涨绿跌的颜色效果。

### 架构

MVVM 模式，`StockViewModel` 是核心中枢（`@MainActor` + `ObservableObject`），所有视图通过 `@Published` 属性自动刷新。

```
StockWatcherApp
├── Views/
│   ├── PopoverView.swift       主弹出面板
│   ├── StockRowView.swift       单只股票行
│   └── WebChartWindow.swift     K 线图窗口
├── ViewModels/
│   └── StockViewModel.swift     核心业务逻辑
├── Models/
│   └── StockModels.swift        数据模型
└── Services/
    ├── StockAPIService.swift    行情 API 服务
    └── NotificationManager.swift 通知管理
```

## 常见问题

**Q: 为什么有些股票查不到？**
A: 新浪 / 腾讯 API 仅覆盖沪深 A 股。代码以 6/5/9 开头为沪市，其余为深市。

**Q: 菜单栏价格颜色不显示红绿色？**
A: macOS 可能会覆盖菜单栏图片颜色，这是已知的系统行为。程序已做处理，如仍有问题请尝试重新启动应用。

**Q: 如何停止程序？**
A: 在菜单栏弹出面板点击设置齿轮旁的退出按钮，或在终端执行 `pkill -f StockWatcher`。

## License

MIT
