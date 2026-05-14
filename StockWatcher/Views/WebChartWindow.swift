import SwiftUI
import WebKit

// MARK: - SwiftUI WKWebView Wrapper

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - URL Builder

extension Stock {
    var eastMoneyURL: URL {
        let rawCode = shortCode
        // market: 1=SH, 0=SZ
        let market: String = {
            if code.hasPrefix("sh") { return "1" }
            if code.hasPrefix("sz") { return "0" }
            // 6xxxxx, 5xxxxx, 9xxxxx -> Shanghai (1), else Shenzhen (0)
            if rawCode.hasPrefix("6") || rawCode.hasPrefix("5") || rawCode.hasPrefix("9") {
                return "1"
            }
            return "0"
        }()
        return URL(string: "https://quote.eastmoney.com/basic/h5chart-iframe.html?code=\(rawCode)&market=\(market)&type=r")!
    }
}

// MARK: - Window Manager

final class WebChartWindowManager {
    static let shared = WebChartWindowManager()
    private var windows: [String: NSWindow] = [:]

    private init() {}

    func open(for stock: Stock) {
        // Bring existing window to front if already open
        if let existing = windows[stock.code], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let title = "\(stock.name) (\(stock.shortCode))"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false

        let webView = WebView(url: stock.eastMoneyURL)

        // Host in a minimal SwiftUI shell with close support
        let hostingView = NSHostingView(rootView: WebChartContentView(webView: webView, title: title))

        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        windows[stock.code] = window

        // Clean up ref when window closes
        window.delegate = WindowDelegate { [weak self] in
            self?.windows.removeValue(forKey: stock.code)
        }
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

// MARK: - Content View for the Chart Window

private struct WebChartContentView: View {
    let webView: WebView
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            webView
                .edgesIgnoringSafeArea(.all)
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}
