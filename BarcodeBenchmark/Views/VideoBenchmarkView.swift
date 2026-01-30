import SwiftUI
import PhotosUI
import AVFoundation
import DynamsoftCaptureVisionBundle
import MLKitBarcodeScanning
import MLKitVision

// MARK: - Frame Data for Benchmark
struct FrameData {
    let image: CGImage
    let timestamp: Double  // seconds from video start
    let frameIndex: Int
}

struct VideoBenchmarkView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selectedVideoURL: URL?
    @State private var selectedItem: PhotosPickerItem?
    @State private var videoThumbnail: UIImage?
    @State private var videoDuration: TimeInterval = 0
    @State private var totalFrames = 0
    @State private var actualFrameRate: Double = 30.0
    @State private var isProcessing = false
    @State private var loadingStatus = ""
    @State private var progressValue: Double = 0
    @State private var progressDetail = ""
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
                
                // Get video track to determine actual frame rate
                let tracks = try await asset.loadTracks(withMediaType: .video)
                var frameRate: Double = 30.0
                if let videoTrack = tracks.first {
                    frameRate = Double(try await videoTrack.load(.nominalFrameRate))
                }
                
                // Generate thumbnail
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                
                // Calculate total frames based on actual frame rate
                let frames = max(1, Int(durationSeconds * frameRate))
                
                await MainActor.run {
                    videoDuration = durationSeconds
                    videoThumbnail = thumbnail
                    totalFrames = frames
                    actualFrameRate = frameRate
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
        
        // Initialize CSV logger
        let videoName = viewModel.sourceFileName ?? "unknown_video"
        let csvLogger = VideoBenchmarkCSVLogger(videoName: videoName)
        viewModel.csvLogger = csvLogger
        
        Task {
            do {
                // Extract ALL frames from video
                await MainActor.run {
                    loadingStatus = "Extracting all frames..."
                }
                
                let frames = try await extractAllFrames(from: videoURL)
                
                if isCancelled || frames.isEmpty {
                    await resetUI()
                    return
                }
                
                // Run Dynamsoft benchmark
                await MainActor.run {
                    loadingStatus = "Running Dynamsoft benchmark..."
                }
                let (dynamsoftResult, dynamsoftLogs) = await runDynamsoftVideoBenchmark(frames: frames)
                viewModel.dynamsoftResult = dynamsoftResult
                csvLogger.addEntries(dynamsoftLogs)
                
                if isCancelled {
                    await resetUI()
                    return
                }
                
                // Run MLKit benchmark
                await MainActor.run {
                    loadingStatus = "Running MLKit benchmark..."
                    progressValue = 75
                }
                let (mlkitResult, mlkitLogs) = await runMLKitVideoBenchmark(frames: frames)
                viewModel.mlkitResult = mlkitResult
                csvLogger.addEntries(mlkitLogs)
                
                // Save CSV file
                if let csvURL = csvLogger.saveToFile() {
                    await MainActor.run {
                        viewModel.csvFileURL = csvURL
                    }
                }
                
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
    
    /// Extract ALL frames from the video at the native frame rate
    private func extractAllFrames(from url: URL) async throws -> [FrameData] {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Get video track for frame rate
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "VideoBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let frameRate = Double(try await videoTrack.load(.nominalFrameRate))
        let frameInterval = 1.0 / frameRate
        let estimatedFrameCount = Int(durationSeconds * frameRate)
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime(seconds: frameInterval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: frameInterval / 2, preferredTimescale: 600)
        
        var frames: [FrameData] = []
        var currentTime: Double = 0
        var frameIndex = 0
        
        print("[Frame Extraction] Extracting all frames at \(String(format: "%.2f", frameRate)) fps, estimated \(estimatedFrameCount) frames")
        
        while currentTime < durationSeconds && !isCancelled {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let frameData = FrameData(image: cgImage, timestamp: currentTime, frameIndex: frameIndex)
                frames.append(frameData)
            } catch {
                print("Failed to extract frame \(frameIndex) at \(currentTime): \(error)")
            }
            
            frameIndex += 1
            currentTime += frameInterval
            
            // Update progress (frame extraction is 0-40% of total progress)
            let progress = Double(frameIndex * 40) / Double(estimatedFrameCount)
            if frameIndex % 10 == 0 || frameIndex == estimatedFrameCount {
                await MainActor.run {
                    progressValue = min(progress, 40)
                    progressDetail = "Extracting frame \(frameIndex)/\(estimatedFrameCount)"
                }
            }
        }
        
        print("[Frame Extraction] Extracted \(frames.count) frames")
        return frames
    }
    
    private func runDynamsoftVideoBenchmark(frames: [FrameData]) async -> (BenchmarkResult, [FrameLogEntry]) {
        let result = BenchmarkResult(engineName: "Dynamsoft")
        result.framesProcessed = frames.count
        
        var uniqueBarcodes: Set<String> = []
        var totalTime: Int64 = 0
        var logEntries: [FrameLogEntry] = []
        var successfulFrames = 0
        var firstReadTime: Double? = nil
        var firstReadFrame: Int? = nil
        
        print("[Dynamsoft Video] Starting video benchmark with \(frames.count) frames...")
        
        // Create Capture Vision Router for processing
        let cvr = CaptureVisionRouter()
        
        for frameData in frames {
            if isCancelled { break }
            
            let index = frameData.frameIndex
            
            // Update progress (Dynamsoft is 40-70% of total progress)
            let progress = 40 + Double((index + 1) * 30) / Double(frames.count)
            if index % 10 == 0 || index == frames.count - 1 {
                await MainActor.run {
                    progressValue = progress
                    progressDetail = "Dynamsoft: Frame \(index + 1)/\(frames.count)"
                }
            }
            
            let startTime = Date()
            
            // Convert CGImage to UIImage for Dynamsoft SDK
            let uiImage = UIImage(cgImage: frameData.image)
            
            // Use captureFromImage API to decode barcodes
            let capturedResult = cvr.captureFromImage(uiImage, templateName: PresetTemplate.readBarcodes.rawValue)
            
            let endTime = Date()
            let latencyMs = endTime.timeIntervalSince(startTime) * 1000
            totalTime += Int64(latencyMs)
            
            var frameSuccess = false
            var decodedText = ""
            var boundingBoxArea = 0
            
            if let decodedBarcodes = capturedResult.decodedBarcodesResult, let items = decodedBarcodes.items, !items.isEmpty {
                frameSuccess = true
                successfulFrames += 1
                
                // Record first successful read for TTFR
                if firstReadTime == nil {
                    firstReadTime = frameData.timestamp * 1000  // Convert to ms
                    firstReadFrame = index
                }
                
                for item in items {
                    let key = "\(item.formatString):\(item.text)"
                    decodedText = item.text
                    
                    // Calculate bounding box area from location points
                    let location = item.location
                    let points = location.points as? [CGPoint] ?? []
                    if points.count >= 4 {
                        boundingBoxArea = calculatePolygonArea(points: points)
                    }
                    
                    if !uniqueBarcodes.contains(key) {
                        uniqueBarcodes.insert(key)
                        print("[Dynamsoft Video] Frame \(index): Barcode - \(item.formatString): \(item.text)")
                        
                        let info = BarcodeInfo(
                            format: item.formatString,
                            text: item.text,
                            decodeTimeMs: Int64(latencyMs),
                            frameIndex: index
                        )
                        result.barcodes.append(info)
                    }
                }
            }
            
            // Log entry for this frame
            let logEntry = FrameLogEntry(
                frameID: index,
                timestamp: frameData.timestamp,
                sdkName: "DBR",
                success: frameSuccess,
                decodedText: decodedText,
                latencyMs: latencyMs,
                boundingBoxArea: boundingBoxArea
            )
            logEntries.append(logEntry)
        }
        
        result.totalTimeMs = totalTime
        result.successfulDecodes = successfulFrames
        result.framesWithBarcodeVisible = frames.count  // Assume all frames may contain barcode
        result.timeToFirstReadMs = firstReadTime
        result.firstReadFrameIndex = firstReadFrame
        
        print("[Dynamsoft Video] Video benchmark completed. Total time: \(totalTime)ms, unique barcodes: \(uniqueBarcodes.count), successful frames: \(successfulFrames), TTFR: \(firstReadTime ?? -1)ms")
        return (result, logEntries)
    }
    
    /// Calculate approximate area of a polygon given its corner points
    private func calculatePolygonArea(points: [CGPoint]) -> Int {
        guard points.count >= 3 else { return 0 }
        
        var area: CGFloat = 0
        let n = points.count
        
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        
        return Int(abs(area / 2))
    }
    
    private func runMLKitVideoBenchmark(frames: [FrameData]) async -> (BenchmarkResult, [FrameLogEntry]) {
        let result = BenchmarkResult(engineName: "MLKit")
        result.framesProcessed = frames.count
        
        var uniqueBarcodes: Set<String> = []
        var logEntries: [FrameLogEntry] = []
        var successfulFrames = 0
        var firstReadTime: Double? = nil
        var firstReadFrame: Int? = nil
        var totalTime: Int64 = 0
        
        print("[MLKit Video] Starting video benchmark with \(frames.count) frames using Google MLKit...")
        
        // Create barcode scanner with options for all barcode formats
        let options = BarcodeScannerOptions(formats: [.all])
        let barcodeScanner = BarcodeScanner.barcodeScanner(options: options)
        
        for frameData in frames {
            if isCancelled { break }
            
            let index = frameData.frameIndex
            
            // Update progress (MLKit is 70-100% of total progress)
            let progress = 70 + Double((index + 1) * 30) / Double(frames.count)
            if index % 10 == 0 || index == frames.count - 1 {
                await MainActor.run {
                    progressValue = progress
                    progressDetail = "MLKit: Frame \(index + 1)/\(frames.count)"
                }
            }
            
            let startTime = Date()
            
            // Convert CGImage to UIImage for MLKit
            let uiImage = UIImage(cgImage: frameData.image)
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
            
            let endTime = Date()
            let latencyMs = endTime.timeIntervalSince(startTime) * 1000
            totalTime += Int64(latencyMs)
            
            var frameSuccess = false
            var decodedText = ""
            var boundingBoxArea = 0
            
            if !barcodes.isEmpty {
                frameSuccess = true
                successfulFrames += 1
                
                // Record first successful read for TTFR
                if firstReadTime == nil {
                    firstReadTime = frameData.timestamp * 1000  // Convert to ms
                    firstReadFrame = index
                }
            }
            
            for barcode in barcodes {
                let format = getMLKitFormatName(barcode.format)
                let text = barcode.rawValue ?? ""
                let key = "\(format):\(text)"
                decodedText = text
                
                // Calculate bounding box area
                let frame = barcode.frame
                boundingBoxArea = Int(frame.width * frame.height)
                
                if !uniqueBarcodes.contains(key) {
                    uniqueBarcodes.insert(key)
                    print("[MLKit Video] Frame \(index): Barcode - \(format): \(text)")
                    
                    let info = BarcodeInfo(
                        format: format,
                        text: text,
                        decodeTimeMs: Int64(latencyMs),
                        frameIndex: index
                    )
                    result.barcodes.append(info)
                }
            }
            
            // Log entry for this frame
            let logEntry = FrameLogEntry(
                frameID: index,
                timestamp: frameData.timestamp,
                sdkName: "MLKit",
                success: frameSuccess,
                decodedText: decodedText,
                latencyMs: latencyMs,
                boundingBoxArea: boundingBoxArea
            )
            logEntries.append(logEntry)
        }
        
        result.totalTimeMs = totalTime
        result.successfulDecodes = successfulFrames
        result.framesWithBarcodeVisible = frames.count  // Assume all frames may contain barcode
        result.timeToFirstReadMs = firstReadTime
        result.firstReadFrameIndex = firstReadFrame
        
        print("[MLKit Video] Video benchmark completed. Total time: \(totalTime)ms, unique barcodes: \(uniqueBarcodes.count), successful frames: \(successfulFrames), TTFR: \(firstReadTime ?? -1)ms")
        return (result, logEntries)
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
