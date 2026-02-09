import SwiftUI
import PhotosUI
import AVFoundation
import Photos

/// View for selecting a video, importing annotations, and running the barcode
/// benchmark through both Dynamsoft and MLKit video-stream processors.
struct VideoStreamBenchmarkView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selectedVideoURL: URL?
    @State private var selectedItem: PhotosPickerItem?
    @State private var videoThumbnail: UIImage?
    @State private var videoDuration: TimeInterval = 0
    @State private var isProcessing = false
    @State private var loadingStatus = ""
    @State private var showResults = false
    @State private var isCancelled = false
    @State private var isImportingAnnotations = false
    
    var body: some View {
        VStack(spacing: 20) {
            videoPreviewArea
            
            if selectedVideoURL != nil {
                videoInfoSection
            }
            
            if isProcessing {
                progressSection
            }
            
            actionButtons
            
            Spacer()
        }
        .padding()
        .navigationTitle("Video Stream Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isImportingAnnotations = true }) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Annotations")
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingAnnotations,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleAnnotationImport(result)
        }
        .navigationDestination(isPresented: $showResults) {
            BenchmarkResultViewWithHeader()
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                await loadSelectedVideo(from: newItem)
            }
        }
    }
    
    // MARK: - Video Preview Area
    private var videoPreviewArea: some View {
        Group {
            if let thumbnail = videoThumbnail {
                ZStack {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .cornerRadius(12)
                    
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.8))
                }
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
    }
    
    // MARK: - Placeholder View
    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Select a video to benchmark")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Video stream mode - SDKs process video as a stream")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Video Info Section
    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.sourceFileName ?? "Video")
                .font(.headline)
            
            let minutes = Int(videoDuration) / 60
            let seconds = Int(videoDuration) % 60
            Text("Duration: \(minutes):\(String(format: "%02d", seconds))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Stream mode allows SDKs to skip frames for optimal performance")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !viewModel.annotations.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(viewModel.annotations.count) Annotations Loaded")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .benchmarkPurple))
            
            Text(loadingStatus)
                .font(.headline)
            
            Button("Cancel") {
                isCancelled = true
            }
            .foregroundColor(.red)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedItem, matching: .videos) {
                Label("Select Video", systemImage: "video.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dynamsoftBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isProcessing)
            
            if selectedVideoURL != nil {
                Button(action: {
                    Task {
                        await startStreamBenchmark()
                    }
                }) {
                    Label("Start Stream Benchmark", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.benchmarkPurple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(isProcessing)
            }
        }
    }
    
    // MARK: - Load Selected Video
    private func loadSelectedVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        await MainActor.run {
            loadingStatus = "Loading video..."
        }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                print("Failed to load video data")
                return
            }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try data.write(to: tempURL)
            
            var fileName = "video.mp4"
            if let identifier = item.itemIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                if let asset = fetchResult.firstObject {
                    let resources = PHAssetResource.assetResources(for: asset)
                    if let resource = resources.first {
                        fileName = resource.originalFilename
                    }
                } else {
                    let components = identifier.components(separatedBy: "/")
                    if let lastComponent = components.last, !lastComponent.isEmpty {
                        fileName = lastComponent
                    }
                }
            }
            
            await MainActor.run {
                viewModel.sourceFileName = fileName
                selectedVideoURL = tempURL
            }
            
            let asset = AVAsset(url: tempURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            await MainActor.run {
                videoDuration = durationSeconds
            }
            
            if let thumbnail = await generateThumbnail(from: tempURL) {
                await MainActor.run {
                    videoThumbnail = thumbnail
                }
            }
            
        } catch {
            print("Error loading video: \(error)")
        }
    }
    
    // MARK: - Generate Thumbnail
    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    // MARK: - Handle Annotation Import
    private func handleAnnotationImport(_ result: Result<[URL], Error>) {
        do {
            guard let selectedFile: URL = try result.get().first else { return }
            if selectedFile.startAccessingSecurityScopedResource() {
                defer { selectedFile.stopAccessingSecurityScopedResource() }
                
                let content = try String(contentsOf: selectedFile)
                let lines = content.components(separatedBy: .newlines)
                
                var newAnnotations: [Annotation] = []
                for line in lines.dropFirst() { // First line is header "format,value"
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        let quoteCharacters = CharacterSet(charactersIn: "\"\"\"'`«»\u{201C}\u{201D}")
                        let format = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: quoteCharacters).joined()
                        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: quoteCharacters).joined()
                        if !format.isEmpty && !value.isEmpty {
                            newAnnotations.append(Annotation(format: format, value: value))
                        }
                    }
                }
                
                if !newAnnotations.isEmpty {
                    Task {
                        await MainActor.run {
                            viewModel.annotations = newAnnotations
                        }
                    }
                }
            }
        } catch {
            print("Error reading annotation file: \(error.localizedDescription)")
        }
    }

    // MARK: - Start Stream Benchmark
    private func startStreamBenchmark() async {
        guard let videoURL = selectedVideoURL else { return }
        
        isCancelled = false
        isProcessing = true
        
        await MainActor.run {
            viewModel.benchmarkMode = "video"
            viewModel.dynamsoftResult = nil
            viewModel.mlkitResult = nil
            
            let videoName = viewModel.sourceFileName ?? "video"
            viewModel.csvLogger = VideoBenchmarkCSVLogger(videoName: videoName, annotations: viewModel.annotations)
        }
        
        // Run Dynamsoft
        await runSDKBenchmark(
            label: "Dynamsoft",
            processor: { url, annotations, logger in
                let p = DynamsoftVideoStreamProcessor()
                return try await p.processVideoStream(url: url, annotations: annotations, csvLogger: logger, cancelled: { self.isCancelled })
            },
            videoURL: videoURL,
            assignResult: { result in viewModel.dynamsoftResult = result }
        )
        
        guard !isCancelled else {
            await MainActor.run { isProcessing = false }
            return
        }
        
        // Run MLKit
        await runSDKBenchmark(
            label: "MLKit",
            processor: { url, annotations, logger in
                let p = MLKitVideoStreamProcessor()
                return try await p.processVideoStream(url: url, annotations: annotations, csvLogger: logger, cancelled: { self.isCancelled })
            },
            videoURL: videoURL,
            assignResult: { result in viewModel.mlkitResult = result }
        )
        
        if !isCancelled {
            await MainActor.run {
                if let csvLogger = viewModel.csvLogger, let csvURL = csvLogger.saveToFile() {
                    viewModel.csvFileURL = csvURL
                    
                    let session = BenchmarkSession(
                        videoName: viewModel.sourceFileName ?? "video",
                        summary: "Completed",
                        csvContent: csvLogger.getCSVContent()
                    )
                    viewModel.historyStore.addSession(session)
                }
                showResults = true
            }
        }
        
        await MainActor.run { isProcessing = false }
    }
    
    // MARK: - Generic SDK Runner
    private func runSDKBenchmark(
        label: String,
        processor: @escaping (URL, [Annotation], VideoBenchmarkCSVLogger?) async throws -> VideoStreamResult,
        videoURL: URL,
        assignResult: @escaping (BenchmarkResult) -> Void
    ) async {
        await MainActor.run {
            loadingStatus = "Testing \(label) (Stream Mode)..."
        }
        
        do {
            let result = try await processor(videoURL, viewModel.annotations, viewModel.csvLogger)
            
            await MainActor.run {
                let benchmarkResult = BenchmarkResult(engineName: label)
                benchmarkResult.totalTimeMs = Int64(result.totalTime * 1000)
                benchmarkResult.framesProcessed = result.framesProcessed
                benchmarkResult.framesWithBarcodeVisible = result.framesProcessed
                benchmarkResult.barcodes = result.barcodes
                benchmarkResult.successfulDecodes = result.successfulDecodes
                benchmarkResult.timeToFirstReadMs = result.timeToFirstReadMs
                benchmarkResult.firstReadFrameIndex = result.firstReadFrameIndex
                assignResult(benchmarkResult)
                print("[\(label) Stream] Completed: \(result.barcodes.count) barcodes in \(String(format: "%.2f", result.totalTime))s, frames processed: \(result.framesProcessed)")
            }
        } catch {
            print("[\(label) Stream] Error: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        VideoStreamBenchmarkView()
            .environmentObject(MainViewModel())
    }
}
