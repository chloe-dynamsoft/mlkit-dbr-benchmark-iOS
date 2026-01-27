import SwiftUI
import AVFoundation
import MLKitBarcodeScanning
import MLKitVision

struct MLKitScannerView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @StateObject private var scanner = MLKitCameraScanner()
    @State private var barcodeCount = 0
    @State private var elapsedTime = 0
    @State private var lastBarcodeResult = ""
    @State private var timer: Timer?
    @State private var startTime = Date()
    
    var body: some View {
        ZStack {
            // Camera Preview
            MLKitCameraPreviewView(scanner: scanner)
                .ignoresSafeArea()
            
            // Barcode Overlay
            BarcodeOverlayView(barcodes: scanner.detectedBarcodeRects)
            
            // Info Overlay
            VStack {
                // Top Info Bar
                topInfoBar
                
                Spacer()
                
                // Bottom Results Panel
                bottomResultsPanel
            }
        }
        .navigationTitle("MLKit Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startScanning()
        }
        .onDisappear {
            stopScanning()
        }
    }
    
    // MARK: - Top Info Bar
    private var topInfoBar: some View {
        HStack {
            // Resolution Display
            Text("Resolution: \(scanner.currentResolution)")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(8)
            
            Spacer()
            
            // Stats Display
            Text("Barcodes: \(barcodeCount) | Time: \(elapsedTime)s")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .padding()
    }
    
    // MARK: - Bottom Results Panel
    private var bottomResultsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected Barcodes")
                .font(.headline)
                .foregroundColor(.mlkitGreen)
            
            if lastBarcodeResult.isEmpty {
                Text("Scanning...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ScrollView {
                    Text(lastBarcodeResult)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .frame(maxHeight: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground).opacity(0.95))
        .cornerRadius(16, corners: [.topLeft, .topRight])
    }
    
    // MARK: - Scanning Methods
    private func startScanning() {
        barcodeCount = 0
        startTime = Date()
        updateElapsedTime()
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsedTime()
        }
        
        // Configure resolution
        scanner.setResolution(viewModel.selectedResolution)
        
        // Set barcode callback
        scanner.onBarcodesDetected = { barcodes in
            barcodeCount += barcodes.count
            
            var resultText = ""
            for barcode in barcodes {
                resultText += "[\(barcode.format)]\n"
                let text = barcode.text.count > 50 ? String(barcode.text.prefix(50)) + "..." : barcode.text
                resultText += text + "\n\n"
            }
            lastBarcodeResult = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Start camera
        scanner.startScanning()
    }
    
    private func stopScanning() {
        timer?.invalidate()
        timer = nil
        scanner.stopScanning()
    }
    
    private func updateElapsedTime() {
        elapsedTime = Int(Date().timeIntervalSince(startTime))
    }
}

// MARK: - MLKit Camera Scanner
class MLKitCameraScanner: NSObject, ObservableObject {
    @Published var currentResolution = "Initializing..."
    @Published var detectedBarcodeRects: [CGRect] = []
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.mlkit.camera.session")
    
    // Google MLKit barcode scanner
    private lazy var barcodeScanner: BarcodeScanner = {
        let options = BarcodeScannerOptions(formats: [.all])
        return BarcodeScanner.barcodeScanner(options: options)
    }()
    
    var onBarcodesDetected: (([BarcodeInfo]) -> Void)?
    
    override init() {
        super.init()
    }
    
    func setResolution(_ resolution: CameraResolution) {
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession else { return }
            
            session.beginConfiguration()
            
            switch resolution {
            case .hd720p:
                if session.canSetSessionPreset(.hd1280x720) {
                    session.sessionPreset = .hd1280x720
                }
            case .fullHD1080p:
                if session.canSetSessionPreset(.hd1920x1080) {
                    session.sessionPreset = .hd1920x1080
                }
            }
            
            session.commitConfiguration()
            
            DispatchQueue.main.async {
                self?.currentResolution = "\(resolution.width)x\(resolution.height)"
            }
        }
    }
    
    func startScanning() {
        sessionQueue.async { [weak self] in
            self?.setupCaptureSession()
            self?.captureSession?.startRunning()
        }
    }
    
    func stopScanning() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        guard let session = captureSession,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.mlkit.camera.output"))
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if let output = videoOutput, session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        session.commitConfiguration()
        
        // Create preview layer after session is configured
        DispatchQueue.main.async {
            self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
            self.previewLayer?.videoGravity = .resizeAspectFill
            self.currentResolution = "1280x720"
        }
    }
    
    private func processBarcodesFromBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create VisionImage from the sample buffer
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation(from: UIDevice.current.orientation)
        
        do {
            let barcodes = try barcodeScanner.results(in: visionImage)
            
            var detectedBarcodes: [BarcodeInfo] = []
            var rects: [CGRect] = []
            
            for barcode in barcodes {
                let format = getMLKitFormatName(barcode.format)
                let text = barcode.rawValue ?? ""
                
                let info = BarcodeInfo(
                    format: format,
                    text: text,
                    decodeTimeMs: 0
                )
                detectedBarcodes.append(info)
                
                // Convert MLKit bounding box to normalized coordinates
                if let frame = barcode.frame as CGRect? {
                    let width = CVPixelBufferGetWidth(imageBuffer)
                    let height = CVPixelBufferGetHeight(imageBuffer)
                    let normalizedRect = CGRect(
                        x: frame.minX / CGFloat(width),
                        y: frame.minY / CGFloat(height),
                        width: frame.width / CGFloat(width),
                        height: frame.height / CGFloat(height)
                    )
                    rects.append(normalizedRect)
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.detectedBarcodeRects = rects
                if !detectedBarcodes.isEmpty {
                    self?.onBarcodesDetected?(detectedBarcodes)
                }
            }
        } catch {
            print("[MLKit Camera] Barcode detection failed: \(error)")
        }
    }
    
    private func imageOrientation(from deviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
        switch deviceOrientation {
        case .portrait:
            return .right
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        default:
            return .right
        }
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
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension MLKitCameraScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processBarcodesFromBuffer(sampleBuffer)
    }
}

// MARK: - MLKit Camera Preview View
struct MLKitCameraPreviewView: UIViewRepresentable {
    let scanner: MLKitCameraScanner
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        // Add observer for when preview layer is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previewLayer = scanner.getPreviewLayer() {
                previewLayer.frame = view.bounds
                if previewLayer.superlayer == nil {
                    view.layer.addSublayer(previewLayer)
                }
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = scanner.getPreviewLayer() {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
                if previewLayer.superlayer == nil {
                    uiView.layer.addSublayer(previewLayer)
                }
            }
        }
    }
}

// MARK: - Barcode Overlay View
struct BarcodeOverlayView: View {
    let barcodes: [CGRect]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(barcodes.enumerated()), id: \.offset) { _, rect in
                // Convert from Vision coordinates (origin bottom-left, normalized)
                // to SwiftUI coordinates (origin top-left)
                let convertedRect = CGRect(
                    x: rect.minX * geometry.size.width,
                    y: (1 - rect.maxY) * geometry.size.height,
                    width: rect.width * geometry.size.width,
                    height: rect.height * geometry.size.height
                )
                
                Rectangle()
                    .stroke(Color.mlkitGreen, lineWidth: 3)
                    .frame(width: convertedRect.width, height: convertedRect.height)
                    .position(x: convertedRect.midX, y: convertedRect.midY)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MLKitScannerView()
            .environmentObject(MainViewModel())
    }
}
