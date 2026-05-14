import Foundation

struct Stock: Identifiable, Codable, Equatable, Hashable {
    let code: String
    var name: String
    var quote: StockQuote?

    var id: String { code }

    /// "sh600519" -> "600519"
    var shortCode: String {
        code.hasPrefix("sh") || code.hasPrefix("sz")
            ? String(code.dropFirst(2))
            : code
    }

    var market: String {
        if code.hasPrefix("sh") { return "沪" }
        if code.hasPrefix("sz") { return "深" }
        return ""
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
}

struct StockQuote: Codable, Equatable {
    let currentPrice: Double
    let change: Double
    let changePercent: Double
    let high: Double
    let low: Double
    let open: Double
    let prevClose: Double
    let volume: Double
    let timestamp: Date

    var isUp: Bool { change >= 0 }
    var isDown: Bool { change < 0 }

    /// Formatted price string
    var priceStr: String { String(format: "%.2f", currentPrice) }

    /// e.g. "+1.23%" or "-0.45%"
    var changePercentStr: String {
        String(format: "%@%.2f%%", change >= 0 ? "+" : "", changePercent)
    }

    /// e.g. "+1.23" or "-0.45"
    var changeStr: String {
        String(format: "%@%.2f", change >= 0 ? "+" : "", change)
    }
}
