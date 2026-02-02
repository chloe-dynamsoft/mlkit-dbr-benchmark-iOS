import SwiftUI
import PhotosUI
import AVFoundation
import DynamsoftCaptureVisionBundle
import MLKitBarcodeScanning
import MLKitVision
import CoreImage

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
    
    var body: some View {
        VStack(spacing: 20) {
            // Video Preview Area
            videoPreviewArea
            
            // Video Info
            if selectedVideoURL != nil {
                videoInfoSection
            }
            
            // Progress Section
            if isProcessing {
                progressSection
            }
            
            // Action Buttons
            actionButtons
            
            Spacer()
        }
        .padding()
        .navigationTitle("Video Stream Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResults) {
            BenchmarkResultView()
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
            // Load the video data
            guard let data = try await item.loadTransferable(type: Data.self) else {
                print("Failed to load video data")
                return
            }
            
            // Save to temporary location
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try data.write(to: tempURL)
            
            // Store filename from the item's suggestion
            if let identifier = item.itemIdentifier {
                await MainActor.run {
                    viewModel.sourceFileName = identifier.components(separatedBy: "/").last ?? "video.mp4"
                }
            }
            
            await MainActor.run {
                selectedVideoURL = tempURL
            }
            
            // Load thumbnail and duration
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
    
    // MARK: - Start Stream Benchmark
    private func startStreamBenchmark() async {
        guard let videoURL = selectedVideoURL else { return }
        
        isCancelled = false
        isProcessing = true
        
        // Clear previous results and set benchmark mode
        await MainActor.run {
            viewModel.benchmarkMode = "video"
            viewModel.dynamsoftResult = nil
            viewModel.mlkitResult = nil
        }
        
        // Run both SDK benchmarks with video stream processing
        await runDynamsoftStreamBenchmark(videoURL: videoURL)
        
        if isCancelled {
            await MainActor.run {
                isProcessing = false
            }
            return
        }
        
        await runMLKitStreamBenchmark(videoURL: videoURL)
        
        if !isCancelled {
            // Show results
            await MainActor.run {
                showResults = true
            }
        }
        
        await MainActor.run {
            isProcessing = false
        }
    }
    
    // MARK: - Dynamsoft Stream Benchmark
    private func runDynamsoftStreamBenchmark(videoURL: URL) async {
        await MainActor.run {
            loadingStatus = "Testing Dynamsoft (Stream Mode)..."
        }
        
        let processor = DynamsoftVideoStreamProcessor()
        
        do {
            let result = try await processor.processVideoStream(url: videoURL, cancelled: { isCancelled })
            
            await MainActor.run {
                let benchmarkResult = BenchmarkResult(engineName: "Dynamsoft")
                benchmarkResult.totalTimeMs = Int64(result.totalTime * 1000)
                benchmarkResult.framesProcessed = result.framesProcessed
                benchmarkResult.framesWithBarcodeVisible = result.framesProcessed
                benchmarkResult.barcodes = result.barcodes
                benchmarkResult.successfulDecodes = result.successfulDecodes
                benchmarkResult.timeToFirstReadMs = result.timeToFirstReadMs
                benchmarkResult.firstReadFrameIndex = result.firstReadFrameIndex
                viewModel.dynamsoftResult = benchmarkResult
                print("[Dynamsoft Stream] Completed: \(result.barcodes.count) barcodes in \(String(format: "%.2f", result.totalTime))s, frames processed: \(result.framesProcessed)")
            }
        } catch {
            print("[Dynamsoft Stream] Error: \(error)")
        }
    }
    
    // MARK: - MLKit Stream Benchmark
    private func runMLKitStreamBenchmark(videoURL: URL) async {
        await MainActor.run {
            loadingStatus = "Testing MLKit (Stream Mode)..."
        }
        
        let processor = MLKitVideoStreamProcessor()
        
        do {
            let result = try await processor.processVideoStream(url: videoURL, cancelled: { isCancelled })
            
            await MainActor.run {
                let benchmarkResult = BenchmarkResult(engineName: "MLKit")
                benchmarkResult.totalTimeMs = Int64(result.totalTime * 1000)
                benchmarkResult.framesProcessed = result.framesProcessed
                benchmarkResult.framesWithBarcodeVisible = result.framesProcessed
                benchmarkResult.barcodes = result.barcodes
                benchmarkResult.successfulDecodes = result.successfulDecodes
                benchmarkResult.timeToFirstReadMs = result.timeToFirstReadMs
                benchmarkResult.firstReadFrameIndex = result.firstReadFrameIndex
                viewModel.mlkitResult = benchmarkResult
                print("[MLKit Stream] Completed: \(result.barcodes.count) barcodes in \(String(format: "%.2f", result.totalTime))s, frames processed: \(result.framesProcessed)")
            }
        } catch {
            print("[MLKit Stream] Error: \(error)")
        }
    }
}

// MARK: - Video Stream Result
struct VideoStreamResult {
    let barcodes: [BarcodeInfo]
    let totalTime: Double
    let framesProcessed: Int
    let successfulDecodes: Int
    let timeToFirstReadMs: Double?
    let firstReadFrameIndex: Int?
}

// MARK: - Dynamsoft Video Stream Processor
class DynamsoftVideoStreamProcessor: NSObject {
    private var detectedBarcodes: [BarcodeInfo] = []
    private var uniqueBarcodeKeys: Set<String> = []
    private var startTime: Date?
    private var framesProcessed = 0
    private var successfulDecodes = 0
    private var timeToFirstReadMs: Double? = nil
    private var firstReadFrameIndex: Int? = nil
    
    func processVideoStream(url: URL, cancelled: @escaping () -> Bool) async throws -> VideoStreamResult {
        startTime = Date()
        detectedBarcodes.removeAll()
        uniqueBarcodeKeys.removeAll()
        framesProcessed = 0
        successfulDecodes = 0
        timeToFirstReadMs = nil
        firstReadFrameIndex = nil
        
        // Setup Dynamsoft
        let cvr = CaptureVisionRouter()
        
        // Create video asset and reader
        let asset = AVAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "VideoStreamProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        
        if reader.canAdd(readerOutput) {
            reader.add(readerOutput)
        }
        
        reader.startReading()
        
        var frameCount = 0
        let captureInterval = 1 // Process all frames, let SDK handle frame queue optimization
        
        while reader.status == .reading {
            if cancelled() {
                reader.cancelReading()
                break
            }
            
            autoreleasepool {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { return }
                
                frameCount += 1
                
                // Skip frames to simulate streaming behavior
                if frameCount % captureInterval != 0 {
                    return
                }
                
                framesProcessed += 1
                
                // Convert sample buffer to UIImage for Dynamsoft
                if let uiImage = imageFromSampleBuffer(sampleBuffer) {
                    let capturedResult = cvr.captureFromImage(uiImage, templateName: PresetTemplate.readBarcodes.rawValue)
                    
                    if let decodedBarcodes = capturedResult.decodedBarcodesResult, 
                       let items = decodedBarcodes.items, !items.isEmpty {
                        successfulDecodes += 1
                        
                        // Track Time-to-First-Read
                        if timeToFirstReadMs == nil, let start = startTime {
                            timeToFirstReadMs = Date().timeIntervalSince(start) * 1000
                            firstReadFrameIndex = framesProcessed
                        }
                        
                        for item in items {
                            let key = "\(item.formatString):\(item.text)"
                            if !uniqueBarcodeKeys.contains(key) {
                                uniqueBarcodeKeys.insert(key)
                                let info = BarcodeInfo(
                                    format: item.formatString,
                                    text: item.text,
                                    decodeTimeMs: 0
                                )
                                detectedBarcodes.append(info)
                            }
                        }
                    }
                }
            }
        }
        
        let totalTime = Date().timeIntervalSince(startTime ?? Date())
        return VideoStreamResult(
            barcodes: detectedBarcodes,
            totalTime: totalTime,
            framesProcessed: framesProcessed,
            successfulDecodes: successfulDecodes,
            timeToFirstReadMs: timeToFirstReadMs,
            firstReadFrameIndex: firstReadFrameIndex
        )
    }
    
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - MLKit Video Stream Processor
class MLKitVideoStreamProcessor {
    private lazy var barcodeScanner: BarcodeScanner = {
        let options = BarcodeScannerOptions(formats: [.all])
        return BarcodeScanner.barcodeScanner(options: options)
    }()
    
    func processVideoStream(url: URL, cancelled: @escaping () -> Bool) async throws -> VideoStreamResult {
        var detectedBarcodes: [BarcodeInfo] = []
        var uniqueBarcodeKeys: Set<String> = []
        let startTime = Date()
        var framesProcessed = 0
        var successfulDecodes = 0
        var timeToFirstReadMs: Double? = nil
        var firstReadFrameIndex: Int? = nil
        
        // Create video asset and reader
        let asset = AVAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "VideoStreamProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        
        if reader.canAdd(readerOutput) {
            reader.add(readerOutput)
        }
        
        reader.startReading()
        
        var frameCount = 0
        let captureInterval = 1 // Process all frames, let SDK handle frame queue optimization
        
        while reader.status == .reading {
            if cancelled() {
                reader.cancelReading()
                break
            }
            
            autoreleasepool {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { return }
                
                frameCount += 1
                
                // Skip frames to simulate streaming behavior
                if frameCount % captureInterval != 0 {
                    return
                }
                
                framesProcessed += 1
                
                let visionImage = VisionImage(buffer: sampleBuffer)
                visionImage.orientation = .up
                
                do {
                    let barcodes = try self.barcodeScanner.results(in: visionImage)
                    
                    if !barcodes.isEmpty {
                        successfulDecodes += 1
                        
                        // Track Time-to-First-Read
                        if timeToFirstReadMs == nil {
                            timeToFirstReadMs = Date().timeIntervalSince(startTime) * 1000
                            firstReadFrameIndex = framesProcessed
                        }
                    }
                    
                    for barcode in barcodes {
                        let format = self.getMLKitFormatName(barcode.format)
                        let text = barcode.rawValue ?? ""
                        let key = "\(format):\(text)"
                        
                        if !uniqueBarcodeKeys.contains(key) {
                            uniqueBarcodeKeys.insert(key)
                            let info = BarcodeInfo(
                                format: format,
                                text: text,
                                decodeTimeMs: 0
                            )
                            detectedBarcodes.append(info)
                        }
                    }
                } catch {
                    // Continue processing on error
                }
            }
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        return VideoStreamResult(
            barcodes: detectedBarcodes,
            totalTime: totalTime,
            framesProcessed: framesProcessed,
            successfulDecodes: successfulDecodes,
            timeToFirstReadMs: timeToFirstReadMs,
            firstReadFrameIndex: firstReadFrameIndex
        )
    }
    
    private func getMLKitFormatName(_ format: MLKitBarcodeScanning.BarcodeFormat) -> String {
        if format == .code128 { return "CODE_128" }
        if format == .code39 { return "CODE_39" }
        if format == .code93 { return "CODE_93" }
        if format == .codaBar { return "CODABAR" }
        if format == .dataMatrix { return "DATA_MATRIX" }
        if format == .EAN13 { return "EAN_13" }
        if format == .EAN8 { return "EAN_8" }
        if format == .ITF { return "ITF" }
        if format == .qrCode { return "QR_CODE" }
        if format == .UPCA { return "UPC_A" }
        if format == .UPCE { return "UPC_E" }
        if format == .PDF417 { return "PDF417" }
        if format == .aztec { return "AZTEC" }
        return "UNKNOWN"
    }
}

#Preview {
    NavigationStack {
        VideoStreamBenchmarkView()
            .environmentObject(MainViewModel())
    }
}
