import SwiftUI

/// Displays the video stream benchmark results with a Summary Header (Global Tally)
/// followed by the barcode lists and CSV export.
struct BenchmarkResultViewWithHeader: View {
    @EnvironmentObject var viewModel: MainViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary Header (Global Tally - the authoritative metrics)
                if let logger = viewModel.csvLogger {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.title2)
                            .bold()
                        
                        let summaryLines = logger.getSummaryHeader()
                        ForEach(Array(summaryLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        if !viewModel.annotations.isEmpty {
                            Text("Top 3 Annotation Values:")
                                .font(.headline)
                            
                            let top3 = Array(viewModel.annotations.prefix(3))
                            ForEach(top3, id: \.value) { annotation in
                                Text("• \(annotation.value)")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Source Info
                sourceInfoSection
                
                // CSV Export Button
                if let csvURL = viewModel.csvFileURL {
                    csvExportSection(csvURL: csvURL)
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
            Image(systemName: "video")
                .foregroundColor(.benchmarkPurple)
            
            Text("Video: \(viewModel.sourceFileName ?? "Unknown")")
                .font(.subheadline)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - CSV Export Section
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
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Barcode Lists Section
    private var barcodeListsSection: some View {
        VStack(spacing: 20) {
            barcodeList(
                title: "Dynamsoft Results",
                barcodes: viewModel.dynamsoftResult?.barcodes ?? [],
                color: .dynamsoftBlue
            )
            
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
            viewModel.csvLogger = nil
            viewModel.csvFileURL = nil
            
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
