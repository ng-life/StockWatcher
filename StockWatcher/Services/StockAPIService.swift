import Foundation

final class StockAPIService {
    static let shared = StockAPIService()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    // MARK: - Fetch

    func fetchQuotes(for codes: [String]) async -> [String: StockQuote] {
        guard !codes.isEmpty else { return [:] }

        // Try Sina first, fallback to Tencent
        if let result = await fetchSinaQuotes(codes), !result.isEmpty {
            return result
        }
        return await fetchTencentQuotes(codes) ?? [:]
    }

    func fetchQuote(for code: String) async throws -> StockQuote {
        let quotes = await fetchQuotes(for: [code])
        guard let quote = quotes[code] else {
            throw StockAPIError.parseError("无法获取 \(code) 的行情数据")
        }
        return quote
    }

    // MARK: - Sina Finance API

    private func fetchSinaQuotes(_ codes: [String]) async -> [String: StockQuote]? {
        let list = codes.joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(list)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")

        do {
            let (data, _) = try await session.data(for: request)
            guard let text = decodeGBK(data) else { return nil }
            return parseSinaResponse(text, codes: codes)
        } catch {
            return nil
        }
    }

    private func parseSinaResponse(_ text: String, codes: [String]) -> [String: StockQuote] {
        var result: [String: StockQuote] = [:]

        for code in codes {
            let prefix = code.hasPrefix("sh") ? "hq_str_sh" : "hq_str_sz"
            let varName = "\(prefix)\(code.dropFirst(2))"
            guard let line = text.components(separatedBy: "\n").first(where: { $0.contains(varName) }) else {
                continue
            }

            // Extract content between quotes
            guard let start = line.firstIndex(of: "\""),
                  let end = line[line.index(after: start)...].firstIndex(of: "\"") else { continue }

            let content = String(line[line.index(after: start)..<end])

            result[code] = parseSinaFields(content, code: code)
        }
        return result
    }

    /// Sina fields: name, open, prev_close, current, high, low, bid, ask, volume, amount, ...
    private func parseSinaFields(_ content: String, code: String) -> StockQuote? {
        let fields = content.components(separatedBy: ",")
        guard fields.count >= 6,
              let prevClose = Double(fields[2]),
              let current = Double(fields[3]),
              let high = Double(fields[4]),
              let low = Double(fields[5]),
              prevClose > 0 else { return nil }

        let open = Double(fields[1]) ?? 0
        let volume = fields.count > 8 ? (Double(fields[8]) ?? 0) * 100 : 0.0
        let change = current - prevClose
        let changePercent = (change / prevClose) * 100

        return StockQuote(
            currentPrice: current,
            change: change,
            changePercent: changePercent,
            high: high,
            low: low,
            open: open,
            prevClose: prevClose,
            volume: volume,
            timestamp: Date()
        )
    }

    // MARK: - Tencent Securities API

    private func fetchTencentQuotes(_ codes: [String]) async -> [String: StockQuote]? {
        let list = codes.joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(list)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("https://gu.qq.com", forHTTPHeaderField: "Referer")

        do {
            let (data, _) = try await session.data(for: request)
            guard let text = decodeGBK(data) else { return nil }
            return parseTencentResponse(text, codes: codes)
        } catch {
            return nil
        }
    }

    /// Tencent fields separated by ~: market(1), name(2), code(3), current(4), prev_close(5), open(6), volume(7), ...
    private func parseTencentResponse(_ text: String, codes: [String]) -> [String: StockQuote] {
        var result: [String: StockQuote] = [:]

        for code in codes {
            let prefix = code.hasPrefix("sh") ? "v_sh" : "v_sz"
            let varName = "\(prefix)\(code.dropFirst(2))"
            guard let line = text.components(separatedBy: "\n").first(where: { $0.contains(varName) }),
                  line.contains("~") else { continue }

            let fields = line.components(separatedBy: "~")
            guard fields.count >= 6,
                  let current = Double(fields[3]),
                  let prevClose = Double(fields[4]),
                  prevClose > 0 else { continue }

            let open = Double(fields[5]) ?? 0
            let high = fields.count > 33 ? (Double(fields[33]) ?? 0) : 0.0
            let low = fields.count > 34 ? (Double(fields[34]) ?? 0) : 0.0
            let volume = fields.count > 6 ? (Double(fields[6]) ?? 0) * 100 : 0.0
            let change = current - prevClose
            let changePercent = (change / prevClose) * 100

            result[code] = StockQuote(
                currentPrice: current,
                change: change,
                changePercent: changePercent,
                high: high,
                low: low,
                open: open,
                prevClose: prevClose,
                volume: volume,
                timestamp: Date()
            )
        }
        return result
    }

    // MARK: - Index

    private let indexCodes = ["s_sh000001", "s_sz399001", "s_sh000688"]

    func fetchIndices() async -> [String: IndexQuote] {
        let list = indexCodes.joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(list)") else { return [:] }

        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")

        do {
            let (data, _) = try await session.data(for: request)
            guard let text = decodeGBK(data) else { return [:] }
            return parseIndexResponse(text)
        } catch {
            return [:]
        }
    }

    /// Sina index fields: name, current, change, changePercent, volume, amount, ...
    private func parseIndexResponse(_ text: String) -> [String: IndexQuote] {
        var result: [String: IndexQuote] = [:]

        for code in indexCodes {
            let varName = "hq_str_\(code)"
            guard let line = text.components(separatedBy: "\n").first(where: { $0.contains(varName) }),
                  let start = line.firstIndex(of: "\""),
                  let end = line[line.index(after: start)...].firstIndex(of: "\"") else { continue }

            let content = String(line[line.index(after: start)..<end])
            let fields = content.components(separatedBy: ",")
            guard fields.count >= 4,
                  let current = Double(fields[1]),
                  let change = Double(fields[2]),
                  let changePercent = Double(fields[3]) else { continue }

            result[code] = IndexQuote(
                currentPrice: current,
                change: change,
                changePercent: changePercent,
                timestamp: Date()
            )
        }
        return result
    }

    // MARK: - Helpers

    private func decodeGBK(_ data: Data) -> String? {
        let gbkEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let str = String(data: data, encoding: String.Encoding(rawValue: gbkEnc)) {
            return str
        }
        return String(data: data, encoding: .utf8)
    }
}

enum StockAPIError: Error, LocalizedError {
    case parseError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .parseError(let msg): return msg
        case .networkError(let msg): return msg
        }
    }
}
