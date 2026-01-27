import SwiftUI
import PhotosUI
import DynamsoftCaptureVisionBundle
import MLKitBarcodeScanning
import MLKitVision

struct ImageBenchmarkView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var loadingStatus = ""
    @State private var showResults = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Image Preview Area
            imagePreviewArea
            
            // Action Buttons
            actionButtons
            
            Spacer()
        }
        .padding()
        .navigationTitle("Image Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResults) {
            BenchmarkResultView()
        }
        .overlay {
            if isProcessing {
                loadingOverlay
            }
        }
    }
    
    // MARK: - Image Preview Area
    private var imagePreviewArea: some View {
        Group {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 300)
    }
    
    // MARK: - Placeholder View
    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Select an image to benchmark")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Select Image", systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dynamsoftBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .onChange(of: selectedItem) { newItem in
                loadImage(from: newItem)
            }
            
            Button(action: runBenchmark) {
                Label("Run Benchmark", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedImage != nil ? Color.benchmarkPurple : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(selectedImage == nil || isProcessing)
        }
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text(loadingStatus)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(Color(.systemGray5).opacity(0.9))
            .cornerRadius(16)
        }
    }
    
    // MARK: - Methods
    private func loadImage(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = image
                    viewModel.sourceFileName = "Selected Image"
                }
            }
        }
    }
    
    private func runBenchmark() {
        guard let image = selectedImage else { return }
        
        isProcessing = true
        viewModel.reset()
        viewModel.benchmarkMode = "image"
        
        Task {
            // Run Dynamsoft benchmark
            await MainActor.run {
                loadingStatus = "Processing with Dynamsoft..."
            }
            let dynamsoftResult = await runDynamsoftBenchmark(image: image)
            viewModel.dynamsoftResult = dynamsoftResult
            
            // Run MLKit/Vision benchmark
            await MainActor.run {
                loadingStatus = "Processing with MLKit..."
            }
            let mlkitResult = await runMLKitBenchmark(image: image)
            viewModel.mlkitResult = mlkitResult
            
            await MainActor.run {
                isProcessing = false
                showResults = true
            }
        }
    }
    
    private func runDynamsoftBenchmark(image: UIImage) async -> BenchmarkResult {
        let result = BenchmarkResult(engineName: "Dynamsoft")
        result.framesProcessed = 1
        
        let startTime = Date()
        
        print("[Dynamsoft Image] Starting image barcode decoding...")
        
        // Use Dynamsoft Capture Vision Router v11 to decode barcode from image
        let cvr = CaptureVisionRouter()
        let capturedResult = cvr.captureFromImage(image, templateName: PresetTemplate.readBarcodes.rawValue)
        
        print("[Dynamsoft Image] Capture completed")
        
        // Check for errors in the result
        if let errorCode = capturedResult.errorCode as? Int, errorCode != 0 {
            print("[Dynamsoft Image] Error code: \(errorCode)")
        }
        
        if let decodedBarcodes = capturedResult.decodedBarcodesResult {
            print("[Dynamsoft Image] DecodedBarcodesResult found, items count: \(decodedBarcodes.items?.count ?? 0)")
            
            if let items = decodedBarcodes.items {
                for item in items {
                    print("[Dynamsoft Image] Barcode - Format: \(item.formatString), Text: \(item.text)")
                    let info = BarcodeInfo(
                        format: item.formatString,
                        text: item.text,
                        decodeTimeMs: 0
                    )
                    result.barcodes.append(info)
                }
            }
        } else {
            print("[Dynamsoft Image] No DecodedBarcodesResult in captured result")
        }
        
        let endTime = Date()
        result.totalTimeMs = Int64(endTime.timeIntervalSince(startTime) * 1000)
        
        print("[Dynamsoft Image] Total time: \(result.totalTimeMs)ms, barcodes found: \(result.barcodes.count)")
        
        return result
    }
    
    private func runMLKitBenchmark(image: UIImage) async -> BenchmarkResult {
        let result = BenchmarkResult(engineName: "MLKit")
        result.framesProcessed = 1
        
        let startTime = Date()
        
        print("[MLKit Image] Starting image barcode decoding with Google MLKit...")
        
        // Create VisionImage from UIImage
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation
        
        // Create barcode scanner with options for all barcode formats
        let options = BarcodeScannerOptions(formats: [
            .all
        ])
        let barcodeScanner = BarcodeScanner.barcodeScanner(options: options)
        
        // MLKit requires processing on a background thread
        let detectedBarcodes: [BarcodeInfo] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var barcodes: [BarcodeInfo] = []
                do {
                    let results = try barcodeScanner.results(in: visionImage)
                    print("[MLKit Image] Found \(results.count) barcodes")
                    
                    for barcode in results {
                        let format = self.getMLKitFormatName(barcode.format)
                        let text = barcode.rawValue ?? ""
                        print("[MLKit Image] Barcode - Format: \(format), Text: \(text)")
                        
                        let info = BarcodeInfo(
                            format: format,
                            text: text,
                            decodeTimeMs: 0
                        )
                        barcodes.append(info)
                    }
                } catch {
                    print("[MLKit Image] Barcode detection failed: \(error)")
                }
                continuation.resume(returning: barcodes)
            }
        }
        
        result.barcodes = detectedBarcodes
        
        let endTime = Date()
        result.totalTimeMs = Int64(endTime.timeIntervalSince(startTime) * 1000)
        
        print("[MLKit Image] Total time: \(result.totalTimeMs)ms, barcodes found: \(result.barcodes.count)")
        
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

#Preview {
    NavigationStack {
        ImageBenchmarkView()
            .environmentObject(MainViewModel())
    }
}
