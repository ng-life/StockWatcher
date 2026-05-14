import SwiftUI

struct PopoverView: View {
    @ObservedObject var viewModel: StockViewModel
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var newStockCode = ""

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            Group {
                if showAddSheet {
                    addStockView
                } else if showSettings {
                    settingsView
                } else if viewModel.stocks.isEmpty {
                    indexSectionView
                } else {
                    indexSectionView
                    Divider()
                    stockListView
                }
            }

            Divider()
            footerView
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            if showSettings {
                Button(action: { showSettings = false }) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                Text("预警设置").font(.headline)
            } else if showAddSheet {
                Button(action: { showAddSheet = false; viewModel.errorMessage = nil }) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                Text("添加自选股").font(.headline)
            } else {
                Text("A股监控").font(.headline)
            }

            Spacer()

            if !showSettings && !showAddSheet {
                if viewModel.isRefreshing {
                    ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                }

                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(.plain).help("刷新").disabled(viewModel.isRefreshing)

                Button(action: { newStockCode = ""; showAddSheet = true }) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain).help("添加股票")

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape").font(.system(size: 12))
                }
                .buttonStyle(.plain).help("预警设置")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Index Section

    private var indexSectionView: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.indices) { index in
                VStack(spacing: 2) {
                    Text(index.name)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let q = index.quote {
                        Text(q.priceStr)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Text(q.changePercentStr)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(q.isUp ? .red : .green)
                    } else {
                        Text("--")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Add Stock

    private var addStockView: some View {
        VStack(spacing: 12) {
            TextField("输入股票代码，如 600519 或 sh600519", text: $newStockCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .onSubmit { doAdd() }

            Button("添加") { doAdd() }
                .buttonStyle(.borderedProminent)
                .disabled(newStockCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .frame(height: 100)
    }

    private func doAdd() {
        let code = newStockCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        viewModel.addStock(code: code)
        if viewModel.errorMessage ?? "" == "无效的股票代码" || viewModel.errorMessage ?? "" == "该股票已在列表中" {
            return
        }
        showAddSheet = false
    }

    // MARK: - Settings

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Enable toggle
                HStack {
                    Text("启用通知预警").font(.subheadline)
                    Spacer()
                    Toggle("", isOn: $viewModel.notificationsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider()

                // Daily threshold
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("日内涨幅阈值").font(.subheadline)
                        Spacer()
                        Text("≥ \(String(format: "%.1f", viewModel.dailyThresholdPercent))%")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Slider(value: $viewModel.dailyThresholdPercent, in: 0.5...10, step: 0.5)
                        .disabled(!viewModel.notificationsEnabled)
                    HStack {
                        Text("0.5%").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text("10%").font(.caption2).foregroundColor(.secondary)
                    }
                }

                // 5-min threshold
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("5分钟涨跌幅阈值").font(.subheadline)
                        Spacer()
                        Text("≥ \(String(format: "%.1f", viewModel.fiveMinThresholdPercent))%")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Slider(value: $viewModel.fiveMinThresholdPercent, in: 0.2...5, step: 0.1)
                        .disabled(!viewModel.notificationsEnabled)
                    HStack {
                        Text("0.2%").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text("5%").font(.caption2).foregroundColor(.secondary)
                    }
                }

                Text("超过阈值时将通过通知中心推送预警，每轮突破仅通知一次。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(height: 260)
    }

    // MARK: - Stock List

    private var stockListView: some View {
        List {
            ForEach(viewModel.stocks) { stock in
                StockRowView(stock: stock, viewModel: viewModel)
            }
            .onDelete(perform: viewModel.removeStocks)
        }
        .listStyle(.plain)
        .frame(minHeight: min(CGFloat(viewModel.stocks.count) * 56, 400))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32)).foregroundColor(.secondary)
            Text("暂无自选股票")
                .font(.subheadline).foregroundColor(.secondary)
            Button("添加股票") {
                newStockCode = ""; showAddSheet = true
            }
            .buttonStyle(.bordered)
        }
        .frame(height: 160)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("每\(Int(viewModel.refreshInterval))秒自动刷新")
                .font(.system(size: 10)).foregroundColor(.secondary)
            Spacer()
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 10)).foregroundColor(.red)
            }
            Text("新浪财经 / 腾讯证券")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}
