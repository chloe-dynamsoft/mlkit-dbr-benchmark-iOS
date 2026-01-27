import SwiftUI
import PhotosUI
import AVFoundation
import DynamsoftCaptureVisionBundle
import MLKitBarcodeScanning
import MLKitVision

struct VideoBenchmarkView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selectedVideoURL: URL?
    @State private var selectedItem: PhotosPickerItem?
    @State private var videoThumbnail: UIImage?
    @State private var videoDuration: TimeInterval = 0
    @State private var totalFrames = 0
    @State private var isProcessing = false
    @State private var loadingStatus = ""
    @State private var progressValue: Double = 0
    @State private var progressDetail = ""
    @State private var showResults = false
    @State private var isCancelled = false
    
    // Frame extraction interval in seconds (process 2 frames per second)
    private let frameIntervalSeconds: Double = 0.5
    
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
        .navigationTitle("Video Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResults) {
            BenchmarkResultView()
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
            Text("Duration: \(minutes):\(String(format: "%02d", seconds)) | ~\(totalFrames) frames to process")
                .font(.subheadline)
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
            ProgressView(value: progressValue, total: 100)
                .progressViewStyle(LinearProgressViewStyle(tint: .benchmarkPurple))
            
            Text(loadingStatus)
                .font(.headline)
            
            Text(progressDetail)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
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
            .onChange(of: selectedItem) { newItem in
                loadVideo(from: newItem)
            }
            
            Button(action: runBenchmark) {
                Label("Run Benchmark", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedVideoURL != nil && !isProcessing ? Color.benchmarkPurple : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(selectedVideoURL == nil || isProcessing)
        }
    }
    
    // MARK: - Methods
    private func loadVideo(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                await MainActor.run {
                    selectedVideoURL = movie.url
                    loadVideoMetadata(from: movie.url)
                }
            }
        }
    }
    
    private func loadVideoMetadata(from url: URL) {
        let asset = AVAsset(url: url)
        
        Task {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                
                // Generate thumbnail
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                
                // Calculate frames
                let frames = max(1, Int(durationSeconds / frameIntervalSeconds))
                
                await MainActor.run {
                    videoDuration = durationSeconds
                    videoThumbnail = thumbnail
                    totalFrames = frames
                    viewModel.sourceFileName = url.lastPathComponent
                }
            } catch {
                print("Failed to load video metadata: \(error)")
            }
        }
    }
    
    private func runBenchmark() {
        guard let videoURL = selectedVideoURL else { return }
        
        isProcessing = true
        isCancelled = false
        progressValue = 0
        viewModel.reset()
        viewModel.benchmarkMode = "video"
        
        Task {
            do {
                // Extract frames
                await MainActor.run {
                    loadingStatus = "Extracting frames..."
                }
                
                let frames = try await extractFrames(from: videoURL)
                
                if isCancelled || frames.isEmpty {
                    await resetUI()
                    return
                }
                
                // Run Dynamsoft benchmark
                await MainActor.run {
                    loadingStatus = "Running Dynamsoft benchmark..."
                }
                let dynamsoftResult = await runDynamsoftVideoBenchmark(frames: frames)
                viewModel.dynamsoftResult = dynamsoftResult
                
                if isCancelled {
                    await resetUI()
                    return
                }
                
                // Run MLKit benchmark
                await MainActor.run {
                    loadingStatus = "Running MLKit benchmark..."
                    progressValue = 75
                }
                let mlkitResult = await runMLKitVideoBenchmark(frames: frames)
                viewModel.mlkitResult = mlkitResult
                
                await MainActor.run {
                    isProcessing = false
                    showResults = true
                }
            } catch {
                print("Benchmark error: \(error)")
                await resetUI()
            }
        }
    }
    
    private func resetUI() async {
        await MainActor.run {
            isProcessing = false
            progressValue = 0
            loadingStatus = ""
            progressDetail = ""
        }
    }
    
    private func extractFrames(from url: URL) async throws -> [CGImage] {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        
        var frames: [CGImage] = []
        var currentTime: Double = 0
        var frameIndex = 0
        
        while currentTime < durationSeconds && !isCancelled {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                frames.append(cgImage)
            } catch {
                print("Failed to extract frame at \(currentTime): \(error)")
            }
            
            frameIndex += 1
            currentTime += frameIntervalSeconds
            
            let progress = Double(frameIndex * 50) / Double(totalFrames)
            await MainActor.run {
                progressValue = progress
                progressDetail = "Frame \(frameIndex)/\(totalFrames)"
            }
        }
        
        return frames
    }
    
    private func runDynamsoftVideoBenchmark(frames: [CGImage]) async -> BenchmarkResult {
        let result = BenchmarkResult(engineName: "Dynamsoft")
        result.framesProcessed = frames.count
        
        var uniqueBarcodes: Set<String> = []
        var totalTime: Int64 = 0
        
        print("[Dynamsoft Video] Starting video benchmark with \(frames.count) frames...")
        
        // Create Capture Vision Router for processing
        let cvr = CaptureVisionRouter()
        
        for (index, frame) in frames.enumerated() {
            if isCancelled { break }
            
            let progress = 50 + Double((index + 1) * 25) / Double(frames.count)
            await MainActor.run {
                progressValue = progress
                progressDetail = "Dynamsoft: Frame \(index + 1)/\(frames.count)"
            }
            
            let startTime = Date()
            
            // Convert CGImage to UIImage for Dynamsoft SDK
            let uiImage = UIImage(cgImage: frame)
            
            // Use captureFromImage API to decode barcodes
            let capturedResult = cvr.captureFromImage(uiImage, templateName: PresetTemplate.readBarcodes.rawValue)
            
            if let decodedBarcodes = capturedResult.decodedBarcodesResult, let items = decodedBarcodes.items {
                for item in items {
                    let key = "\(item.formatString):\(item.text)"
                    
                    if !uniqueBarcodes.contains(key) {
                        uniqueBarcodes.insert(key)
                        print("[Dynamsoft Video] Frame \(index): Barcode - \(item.formatString): \(item.text)")
                        
                        let endTime = Date()
                        let decodeTime = Int64(endTime.timeIntervalSince(startTime) * 1000)
                        
                        let info = BarcodeInfo(
                            format: item.formatString,
                            text: item.text,
                            decodeTimeMs: decodeTime,
                            frameIndex: index
                        )
                        result.barcodes.append(info)
                    }
                }
            }
            
            let endTime = Date()
            totalTime += Int64(endTime.timeIntervalSince(startTime) * 1000)
        }
        
        result.totalTimeMs = totalTime
        print("[Dynamsoft Video] Video benchmark completed. Total time: \(totalTime)ms, unique barcodes: \(uniqueBarcodes.count)")
        return result
    }
    
    private func runMLKitVideoBenchmark(frames: [CGImage]) async -> BenchmarkResult {
        let result = BenchmarkResult(engineName: "MLKit")
        result.framesProcessed = frames.count
        
        var uniqueBarcodes: Set<String> = []
        var totalTime: Int64 = 0
        
        print("[MLKit Video] Starting video benchmark with \(frames.count) frames using Google MLKit...")
        
        // Create barcode scanner with options for all barcode formats
        let options = BarcodeScannerOptions(formats: [.all])
        let barcodeScanner = BarcodeScanner.barcodeScanner(options: options)
        
        for (index, frame) in frames.enumerated() {
            if isCancelled { break }
            
            let progress = 75 + Double((index + 1) * 25) / Double(frames.count)
            await MainActor.run {
                progressValue = progress
                progressDetail = "MLKit: Frame \(index + 1)/\(frames.count)"
            }
            
            let startTime = Date()
            
            // Convert CGImage to UIImage for MLKit
            let uiImage = UIImage(cgImage: frame)
            let visionImage = VisionImage(image: uiImage)
            visionImage.orientation = uiImage.imageOrientation
            
            // MLKit requires processing on a background thread
            let barcodes: [MLKitBarcodeScanning.Barcode] = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let results = try barcodeScanner.results(in: visionImage)
                        continuation.resume(returning: results)
                    } catch {
                        print("[MLKit Video] Barcode detection failed on frame \(index): \(error)")
                        continuation.resume(returning: [])
                    }
                }
            }
            
            for barcode in barcodes {
                let format = getMLKitFormatName(barcode.format)
                let text = barcode.rawValue ?? ""
                let key = "\(format):\(text)"
                
                if !uniqueBarcodes.contains(key) {
                    uniqueBarcodes.insert(key)
                    print("[MLKit Video] Frame \(index): Barcode - \(format): \(text)")
                    
                    let endTime = Date()
                    let decodeTime = Int64(endTime.timeIntervalSince(startTime) * 1000)
                    
                    let info = BarcodeInfo(
                        format: format,
                        text: text,
                        decodeTimeMs: decodeTime,
                        frameIndex: index
                    )
                    result.barcodes.append(info)
                }
            }
            
            let endTime = Date()
            totalTime += Int64(endTime.timeIntervalSince(startTime) * 1000)
        }
        
        result.totalTimeMs = totalTime
        print("[MLKit Video] Video benchmark completed. Total time: \(totalTime)ms, unique barcodes: \(uniqueBarcodes.count)")
        return result
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

// MARK: - Video Transferable
struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "video_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

#Preview {
    NavigationStack {
        VideoBenchmarkView()
            .environmentObject(MainViewModel())
    }
}
