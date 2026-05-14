import Foundation
import Combine
import SwiftUI

@MainActor
final class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var isRefreshing = false
    @Published var errorMessage: String?

    // Notification thresholds (persisted)
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notifications_enabled") }
    }
    @Published var dailyThresholdPercent: Double {
        didSet { UserDefaults.standard.set(dailyThresholdPercent, forKey: "daily_threshold") }
    }
    @Published var fiveMinThresholdPercent: Double {
        didSet { UserDefaults.standard.set(fiveMinThresholdPercent, forKey: "five_min_threshold") }
    }

    private let userDefaultsKey = "tracked_stocks"
    private let apiService = StockAPIService.shared
    private var refreshTimer: AnyCancellable?
    let refreshInterval: TimeInterval = 5

    // Price history for 5-min change calculation: [code: [(timestamp, price)]]
    private var priceHistory: [String: [(Date, Double)]] = [:]

    // Dedup: prevent repeated notifications for the same breach
    private var notifiedDailyHigh: Set<String> = []
    private var notifiedFiveMinHigh: Set<String> = []

    /// Text shown in menu bar
    var statusBarText: String {
        guard let first = stocks.first, let quote = first.quote else {
            return "📈 --"
        }
        let arrow = quote.isUp ? "↑" : "↓"
        // Truncate name to 4 chars max for menu bar space
        let displayName = first.name.count > 4 ? String(first.name.prefix(4)) : first.name
        return "\(displayName) \(quote.priceStr) \(arrow)\(quote.changePercentStr)"
    }

    func statusBarImage() -> NSImage {
        let text = statusBarText
        let color: NSColor = {
            guard let first = stocks.first, let quote = first.quote else { return .labelColor }
            return quote.isUp ? .systemRed : .systemGreen
        }()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let image = NSImage(size: size)
        image.lockFocus()
        (text as NSString).draw(at: .zero, withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    init() {
        let defaults = UserDefaults.standard
        self.notificationsEnabled = defaults.object(forKey: "notifications_enabled") as? Bool ?? true
        self.dailyThresholdPercent = defaults.object(forKey: "daily_threshold") as? Double ?? 3.0
        self.fiveMinThresholdPercent = defaults.object(forKey: "five_min_threshold") as? Double ?? 1.0

        loadStocks()
        startTimer()
        Task { await refresh() }
    }

    // MARK: - Timer

    func startTimer() {
        refreshTimer?.cancel()
        refreshTimer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
    }

    func stopTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Data

    func refresh() async {
        guard !stocks.isEmpty else { return }
        isRefreshing = true
        errorMessage = nil

        let codes = stocks.map(\.code)
        let quotes = await apiService.fetchQuotes(for: codes)

        let now = Date()
        for i in stocks.indices {
            let code = stocks[i].code
            if let q = quotes[code] {
                stocks[i].quote = q

                // Update price history
                priceHistory[code, default: []].append((now, q.currentPrice))
                // Prune > 10 min old
                priceHistory[code] = priceHistory[code]?.filter { now.timeIntervalSince($0.0) < 600 }
            }
        }

        if quotes.isEmpty {
            errorMessage = "数据获取失败，请检查网络"
        }

        isRefreshing = false

        // Check thresholds & notify
        checkThresholds()
    }

    // MARK: - Stock Management

    func addStock(code: String, name: String? = nil) {
        let normalized = normalizeCode(code)
        guard !normalized.isEmpty else {
            errorMessage = "无效的股票代码"
            return
        }
        guard !stocks.contains(where: { $0.code == normalized }) else {
            errorMessage = "该股票已在列表中"
            return
        }

        let stock = Stock(code: normalized, name: name ?? normalized, quote: nil)
        stocks.append(stock)
        saveStocks()

        Task {
            await refresh()
            if name == nil, let idx = stocks.firstIndex(where: { $0.code == normalized }) {
                await updateStockName(at: idx)
            }
        }
    }

    func removeStock(_ stock: Stock) {
        stocks.removeAll { $0.code == stock.code }
        priceHistory.removeValue(forKey: stock.code)
        notifiedDailyHigh.remove(stock.code)
        notifiedFiveMinHigh.remove(stock.code)
        saveStocks()
    }

    func removeStocks(at offsets: IndexSet) {
        for i in offsets {
            let code = stocks[i].code
            priceHistory.removeValue(forKey: code)
            notifiedDailyHigh.remove(code)
            notifiedFiveMinHigh.remove(code)
        }
        stocks.remove(atOffsets: offsets)
        saveStocks()
    }

    // MARK: - Thresholds & Notifications

    private func checkThresholds() {
        guard notificationsEnabled else { return }

        for stock in stocks {
            guard let quote = stock.quote else { continue }

            // Daily change check
            let dailyAbs = abs(quote.changePercent)
            if dailyAbs >= dailyThresholdPercent {
                if !notifiedDailyHigh.contains(stock.code) {
                    let direction = quote.isUp ? "上涨" : "下跌"
                    NotificationManager.shared.send(
                        "\(stock.name) 日内\(direction)预警",
                        body: "当前 \(quote.priceStr)，日内\(direction) \(quote.changePercentStr)"
                    )
                    notifiedDailyHigh.insert(stock.code)
                }
            } else {
                notifiedDailyHigh.remove(stock.code)
            }

            // 5-minute change check
            if let fiveMinChange = calculateFiveMinChange(for: stock.code) {
                let fiveMinAbs = abs(fiveMinChange)
                if fiveMinAbs >= fiveMinThresholdPercent {
                    if !notifiedFiveMinHigh.contains(stock.code) {
                        let direction = fiveMinChange >= 0 ? "拉升" : "下挫"
                        NotificationManager.shared.send(
                            "\(stock.name) 5分钟\(direction)预警",
                            body: "当前 \(quote.priceStr)，5分钟\(direction) \(String(format: "%.2f", fiveMinAbs))%"
                        )
                        notifiedFiveMinHigh.insert(stock.code)
                    }
                } else {
                    notifiedFiveMinHigh.remove(stock.code)
                }
            }
        }
    }

    private func calculateFiveMinChange(for code: String) -> Double? {
        guard let history = priceHistory[code], history.count >= 2 else { return nil }
        let now = Date()
        // Find the oldest entry within a 5-minute window
        let fiveMinAgo = now.addingTimeInterval(-300)
        let inWindow = history.filter { $0.0 >= fiveMinAgo }
        guard inWindow.count >= 2,
              let oldestPrice = inWindow.first?.1,
              let newestPrice = inWindow.last?.1,
              oldestPrice > 0 else { return nil }

        return ((newestPrice - oldestPrice) / oldestPrice) * 100
    }

    // MARK: - Persistence

    private func saveStocks() {
        guard let data = try? JSONEncoder().encode(stocks.map { PersistedStock(code: $0.code, name: $0.name) }) else {
            return
        }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadStocks() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let persisted = try? JSONDecoder().decode([PersistedStock].self, from: data) else {
            stocks = [
                Stock(code: "sh600519", name: "贵州茅台", quote: nil),
                Stock(code: "sz000001", name: "平安银行", quote: nil),
            ]
            saveStocks()
            return
        }
        stocks = persisted.map { Stock(code: $0.code, name: $0.name, quote: nil) }
    }

    // MARK: - Helpers

    private func normalizeCode(_ raw: String) -> String {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if code.hasPrefix("sh") || code.hasPrefix("sz") {
            return code
        }
        if code.count == 6, code.allSatisfy(\.isNumber) {
            if code.hasPrefix("6") || code.hasPrefix("5") || code.hasPrefix("9") {
                return "sh\(code)"
            } else {
                return "sz\(code)"
            }
        }
        return code
    }

    private func updateStockName(at index: Int) async {
        let code = stocks[index].code
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(code)") else { return }
        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let gbkEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            guard let text = String(data: data, encoding: String.Encoding(rawValue: gbkEnc))
                    ?? String(data: data, encoding: .utf8),
                  let start = text.firstIndex(of: "\""),
                  let end = text[text.index(after: start)...].firstIndex(of: "\"") else { return }

            let content = String(text[text.index(after: start)..<end])
            let name = content.components(separatedBy: ",").first ?? ""
            if !name.isEmpty {
                stocks[index].name = name
                saveStocks()
            }
        } catch {}
    }

    private struct PersistedStock: Codable {
        let code: String
        let name: String
    }
}
