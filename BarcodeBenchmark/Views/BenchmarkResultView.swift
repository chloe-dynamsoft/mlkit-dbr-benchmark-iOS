import SwiftUI

struct BenchmarkResultView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Source Info
                sourceInfoSection
                
                // Time Comparison
                timeComparisonSection
                
                // Detection Count
                detectionCountSection
                
                // Video Stats (if applicable)
                if viewModel.benchmarkMode == "video" {
                    videoStatsSection
                }
                
                // Barcode Lists
                barcodeListsSection
                
                // Back Button
                backButton
            }
            .padding()
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
    
    // MARK: - Source Info Section
    private var sourceInfoSection: some View {
        HStack {
            Image(systemName: viewModel.benchmarkMode == "video" ? "video" : "photo")
                .foregroundColor(.benchmarkPurple)
            
            Text("\(viewModel.benchmarkMode == "video" ? "Video" : "Image"): \(viewModel.sourceFileName ?? "Unknown")")
                .font(.subheadline)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Time Comparison Section
    private var timeComparisonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Processing Time")
                .font(.headline)
            
            // Dynamsoft Time
            timeRow(
                title: "Dynamsoft",
                result: viewModel.dynamsoftResult,
                color: .dynamsoftBlue,
                showAverage: viewModel.benchmarkMode == "video"
            )
            
            // MLKit Time
            timeRow(
                title: "MLKit",
                result: viewModel.mlkitResult,
                color: .mlkitGreen,
                showAverage: viewModel.benchmarkMode == "video"
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func timeRow(title: String, result: BenchmarkResult?, color: Color, showAverage: Bool) -> some View {
        let timeMs = result?.totalTimeMs ?? 0
        let maxTime = max(viewModel.dynamsoftResult?.totalTimeMs ?? 1, viewModel.mlkitResult?.totalTimeMs ?? 1)
        let progress = maxTime > 0 ? Double(timeMs) / Double(maxTime) : 0
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if showAverage, let result = result {
                    Text(String(format: "%.1f ms/frame (total: %d ms)", result.avgTimePerFrame, timeMs))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(timeMs) ms")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
        }
    }
    
    // MARK: - Detection Count Section
    private var detectionCountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Barcodes Detected")
                .font(.headline)
            
            HStack(spacing: 20) {
                countCard(
                    title: "Dynamsoft",
                    count: viewModel.dynamsoftResult?.barcodes.count ?? 0,
                    color: .dynamsoftBlue
                )
                
                countCard(
                    title: "MLKit",
                    count: viewModel.mlkitResult?.barcodes.count ?? 0,
                    color: .mlkitGreen
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func countCard(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text("\(count)")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Video Stats Section
    private var videoStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Video Benchmark Metrics")
                .font(.headline)
            
            // Frames Processed
            HStack {
                Image(systemName: "film")
                    .foregroundColor(.benchmarkPurple)
                
                Text("Total Frames Processed:")
                    .font(.subheadline)
                
                Spacer()
                
                Text("\(viewModel.dynamsoftResult?.framesProcessed ?? 0)")
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            
            Divider()
            
            // Success Rate Section
            Text("Success Rate (Decodes / Frames)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                successRateCard(
                    title: "Dynamsoft",
                    result: viewModel.dynamsoftResult,
                    color: .dynamsoftBlue
                )
                
                successRateCard(
                    title: "MLKit",
                    result: viewModel.mlkitResult,
                    color: .mlkitGreen
                )
            }
            
            Divider()
            
            // Time-to-First-Read (TTFR) Section
            Text("Time-to-First-Read (TTFR)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                ttfrCard(
                    title: "Dynamsoft",
                    result: viewModel.dynamsoftResult,
                    color: .dynamsoftBlue
                )
                
                ttfrCard(
                    title: "MLKit",
                    result: viewModel.mlkitResult,
                    color: .mlkitGreen
                )
            }
            
            // CSV Export Button
            if let csvURL = viewModel.csvFileURL {
                Divider()
                csvExportSection(csvURL: csvURL)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func successRateCard(title: String, result: BenchmarkResult?, color: Color) -> some View {
        VStack(spacing: 8) {
            let successRate = result?.successRate ?? 0
            let successCount = result?.successfulDecodes ?? 0
            let totalFrames = result?.framesProcessed ?? 0
            
            Text(String(format: "%.1f%%", successRate))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            
            Text("\(successCount)/\(totalFrames)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private func ttfrCard(title: String, result: BenchmarkResult?, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(result?.ttfrFormatted ?? "N/A")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            
            if let frameIndex = result?.firstReadFrameIndex {
                Text("Frame #\(frameIndex)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No decode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private func csvExportSection(csvURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CSV Log Saved")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.benchmarkPurple)
                
                Text(csvURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                ShareLink(item: csvURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Barcode Lists Section
    private var barcodeListsSection: some View {
        VStack(spacing: 20) {
            // Dynamsoft Barcodes
            barcodeList(
                title: "Dynamsoft Results",
                barcodes: viewModel.dynamsoftResult?.barcodes ?? [],
                color: .dynamsoftBlue
            )
            
            // MLKit Barcodes
            barcodeList(
                title: "MLKit Results",
                barcodes: viewModel.mlkitResult?.barcodes ?? [],
                color: .mlkitGreen
            )
        }
    }
    
    private func barcodeList(title: String, barcodes: [BarcodeInfo], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(color)
            
            if barcodes.isEmpty {
                Text("No barcodes detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                ForEach(barcodes) { barcode in
                    barcodeRow(barcode: barcode, color: color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func barcodeRow(barcode: BarcodeInfo, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(barcode.format)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(barcode.text.count > 100 ? String(barcode.text.prefix(100)) + "..." : barcode.text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    // MARK: - Back Button
    private var backButton: some View {
        Button {
            // Clear annotations and reset state
            viewModel.annotations.removeAll()
            viewModel.sourceFileName = nil
            
            // Pop to root (home)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                if let navigationController = findNavigationController(from: rootViewController) {
                    navigationController.popToRootViewController(animated: true)
                }
            }
        } label: {
            Text("Back to Home")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.dynamsoftBlue)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }
    
    private func findNavigationController(from viewController: UIViewController) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        for child in viewController.children {
            if let found = findNavigationController(from: child) {
                return found
            }
        }
        return nil
    }
}

#Preview {
    let viewModel = MainViewModel()
    viewModel.benchmarkMode = "image"
    viewModel.sourceFileName = "test_image.jpg"
    
    let dynamsoftResult = BenchmarkResult(engineName: "Dynamsoft")
    dynamsoftResult.totalTimeMs = 150
    dynamsoftResult.framesProcessed = 1
    dynamsoftResult.barcodes = [
        BarcodeInfo(format: "QR_CODE", text: "https://example.com", decodeTimeMs: 150),
        BarcodeInfo(format: "EAN_13", text: "1234567890123", decodeTimeMs: 150)
    ]
    viewModel.dynamsoftResult = dynamsoftResult
    
    let mlkitResult = BenchmarkResult(engineName: "MLKit")
    mlkitResult.totalTimeMs = 200
    mlkitResult.framesProcessed = 1
    mlkitResult.barcodes = [
        BarcodeInfo(format: "QR_CODE", text: "https://example.com", decodeTimeMs: 200)
    ]
    viewModel.mlkitResult = mlkitResult
    
    return NavigationStack {
        BenchmarkResultView()
            .environmentObject(viewModel)
    }
}
