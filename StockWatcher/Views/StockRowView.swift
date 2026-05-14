import SwiftUI

struct StockRowView: View {
    let stock: Stock
    @ObservedObject var viewModel: StockViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Market badge
            Text(stock.market)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(stock.code.hasPrefix("sh") ? .red : .blue)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill((stock.code.hasPrefix("sh") ? Color.red : Color.blue).opacity(0.12))
                )

            // Name & code
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(stock.shortCode)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let quote = stock.quote {
                // Price & change
                VStack(alignment: .trailing, spacing: 2) {
                    Text(quote.priceStr)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(quote.isUp ? .red : quote.isDown ? .green : .primary)

                    HStack(spacing: 4) {
                        Text(quote.changeStr)
                        Text(quote.changePercentStr)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(quote.isUp ? .red : quote.isDown ? .green : .secondary)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            WebChartWindowManager.shared.open(for: stock)
        }
        .contextMenu {
            Button("删除") {
                viewModel.removeStock(stock)
            }
        }
    }
}
