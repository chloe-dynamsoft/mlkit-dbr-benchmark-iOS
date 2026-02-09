import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var showingExportSheet = false
    @State private var exportURLs: [URL] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Session History Section
                if !viewModel.historyStore.sessions.isEmpty {
                    sessionHistorySection
                }
                
                // Benchmark Section
                benchmarkSection
                
                // Camera Scanners Section
                cameraScannersSection
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Barcode Benchmark")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingExportSheet) {
            if !exportURLs.isEmpty {
                ActivityViewControllerWrapper(activityItems: exportURLs)
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.dynamsoftBlue)
            
            Text("Compare barcode scanning performance")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }
    
    // MARK: - Session History Section
    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session History")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    viewModel.historyStore.clearHistory()
                }) {
                    Text("Clear")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.historyStore.sessions.count) sessions recorded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // List recent sessions
                ForEach(viewModel.historyStore.sessions.suffix(3).reversed()) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.videoName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(session.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            exportSingleSession(session)
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.benchmarkPurple)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if viewModel.historyStore.sessions.count > 3 {
                    Text("+ \(viewModel.historyStore.sessions.count - 3) more sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                Button(action: {
                    exportAllSessions()
                }) {
                    Label("Export All Sessions", systemImage: "folder.badge.gear")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.benchmarkPurple)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func exportSingleSession(_ session: BenchmarkSession) {
        // Create temp file for single session
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateStr = dateFormatter.string(from: session.date)
        let filename = "benchmark_\(session.videoName)_\(dateStr).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try session.csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURLs = [fileURL]
            showingExportSheet = true
        } catch {
            print("Failed to export session: \(error)")
        }
    }
    
    private func exportAllSessions() {
        var urls: [URL] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        
        for session in viewModel.historyStore.sessions {
            let dateStr = dateFormatter.string(from: session.date)
            let sanitizedName = session.videoName.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")
            let filename = "benchmark_\(sanitizedName)_\(dateStr).csv"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            
            do {
                try session.csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                urls.append(fileURL)
            } catch {
                print("Failed to write session \(session.videoName): \(error)")
            }
        }
        
        if !urls.isEmpty {
            exportURLs = urls
            showingExportSheet = true
        }
    }
    
    // MARK: - Benchmark Section
    private var benchmarkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Benchmarks")
                .font(.title2)
                .fontWeight(.bold)
            
            // Image and Video Benchmark Row
            HStack(spacing: 16) {
                NavigationLink(destination: ImageBenchmarkView()) {
                    BenchmarkCard(
                        title: "Image",
                        subtitle: "Benchmark",
                        icon: "photo",
                        color: .benchmarkPurple
                    )
                }
                
                NavigationLink(destination: VideoBenchmarkView()) {
                    BenchmarkCard(
                        title: "Video",
                        subtitle: "Frame-by-Frame",
                        icon: "video",
                        color: .benchmarkPurple
                    )
                }
            }
            
            // Video Stream Benchmark Row
            HStack(spacing: 16) {
                NavigationLink(destination: VideoStreamBenchmarkView()) {
                    BenchmarkCard(
                        title: "Video Stream",
                        subtitle: "Native Processing",
                        icon: "video.bubble.left",
                        color: .benchmarkPurple
                    )
                }
                
                // Empty placeholder for symmetry
                Color.clear
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Camera Scanners Section
    private var cameraScannersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera Scanners")
                .font(.title2)
                .fontWeight(.bold)
            
            // Resolution Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Camera Resolution")
                    .font(.headline)
                
                Picker("Resolution", selection: $viewModel.resolutionIndex) {
                    Text("720P").tag(0)
                    Text("1080P").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Camera Scanners Row
            HStack(spacing: 16) {
                NavigationLink(destination: DynamsoftScannerView()) {
                    BenchmarkCard(
                        title: "Dynamsoft",
                        subtitle: "Camera",
                        icon: "camera.viewfinder",
                        color: .dynamsoftBlue
                    )
                }
                
                NavigationLink(destination: MLKitScannerView()) {
                    BenchmarkCard(
                        title: "MLKit",
                        subtitle: "Camera",
                        icon: "camera.viewfinder",
                        color: .mlkitGreen
                    )
                }
            }
        }
    }
    

}

// MARK: - Benchmark Card Component
struct BenchmarkCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(MainViewModel())
    }
}

// MARK: - Activity View Controller Wrapper for Share Sheet
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
