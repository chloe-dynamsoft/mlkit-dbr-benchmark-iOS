import SwiftUI
import AVFoundation
import DynamsoftCaptureVisionBundle

struct DynamsoftScannerView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @StateObject private var scanner = DynamsoftCameraScanner()
    @State private var barcodeCount = 0
    @State private var elapsedTime = 0
    @State private var lastBarcodeResult = ""
    @State private var timer: Timer?
    @State private var startTime = Date()
    
    var body: some View {
        ZStack {
            // Camera Preview
            DynamsoftCameraPreviewView(scanner: scanner)
                .ignoresSafeArea()
            
            // Overlay
            VStack {
                // Top Info Bar
                topInfoBar
                
                Spacer()
                
                // Bottom Results Panel
                bottomResultsPanel
            }
        }
        .navigationTitle("Dynamsoft Scanner")
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
                .foregroundColor(.dynamsoftBlue)
            
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

// MARK: - Dynamsoft Camera Scanner
class DynamsoftCameraScanner: NSObject, ObservableObject, LicenseVerificationListener {
    @Published var currentResolution = "Initializing..."
    
    private var cameraView: CameraView?
    private var cameraEnhancer: CameraEnhancer?
    private var captureVisionRouter: CaptureVisionRouter?
    
    var onBarcodesDetected: (([BarcodeInfo]) -> Void)?
    
    override init() {
        super.init()
        setupDynamsoft()
    }
    
    private func setupDynamsoft() {
        // Initialize license
        print("[Dynamsoft] Initializing license...")
        LicenseManager.initLicense("t0088pwAAADNYckHyPikZ2O5DtQp+Ry3yU3GHFQAzoepUNwJJDfWVm7ffMr8wicSL1OPY4LpwQ/uCKGKI3ubMCIygxwFKmIWrC/kJ5likr48/SiseX34CXV8ifA==", verificationDelegate: self)
        
        // Initialize Camera Enhancer
        print("[Dynamsoft] Creating CameraView and CameraEnhancer...")
        cameraView = CameraView()
        cameraEnhancer = CameraEnhancer()
        if let view = cameraView {
            cameraEnhancer?.cameraView = view
            print("[Dynamsoft] CameraView assigned to CameraEnhancer")
        }
        
        // Initialize Capture Vision Router
        print("[Dynamsoft] Creating CaptureVisionRouter...")
        captureVisionRouter = CaptureVisionRouter()
        
        // Set camera enhancer as input
        if let enhancer = cameraEnhancer {
            do {
                try captureVisionRouter?.setInput(enhancer)
                print("[Dynamsoft] CameraEnhancer set as input successfully")
            } catch {
                print("[Dynamsoft] Failed to set input: \(error)")
            }
        }
        
        // Add result receiver
        captureVisionRouter?.addResultReceiver(self)
        print("[Dynamsoft] Result receiver added")
    }
    
    // MARK: - LicenseVerificationListener
    func onLicenseVerified(_ isSuccess: Bool, error: Error?) {
        if isSuccess {
            print("[Dynamsoft] License verified successfully!")
        } else {
            print("[Dynamsoft] License verification FAILED: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
    
    func setResolution(_ resolution: CameraResolution) {
        // Set resolution via camera enhancer
        let resolutionValue: Resolution
        switch resolution {
        case .hd720p:
            resolutionValue = .resolution720P
        case .fullHD1080p:
            resolutionValue = .resolution1080P
        }
        
        cameraEnhancer?.setResolution(resolutionValue)
        print("[Dynamsoft] Resolution set to \(resolution.width)x\(resolution.height)")
        
        DispatchQueue.main.async {
            self.currentResolution = "\(resolution.width)x\(resolution.height)"
        }
    }
    
    func startScanning() {
        print("[Dynamsoft] Opening camera...")
        cameraEnhancer?.open()
        
        print("[Dynamsoft] Starting capture with template: \(PresetTemplate.readBarcodes.rawValue)")
        captureVisionRouter?.startCapturing(PresetTemplate.readBarcodes.rawValue) { isSuccess, error in
            if isSuccess {
                print("[Dynamsoft] Capturing started successfully!")
            } else {
                print("[Dynamsoft] Start capturing FAILED: \(error?.localizedDescription ?? "Unknown")")
            }
        }
    }
    
    func stopScanning() {
        print("[Dynamsoft] Stopping capture...")
        captureVisionRouter?.stopCapturing()
        cameraEnhancer?.close()
        cameraEnhancer?.clearBuffer()
    }
    
    func getCameraView() -> CameraView? {
        return cameraView
    }
}

// MARK: - CapturedResultReceiver
extension DynamsoftCameraScanner: CapturedResultReceiver {
    func onDecodedBarcodesReceived(_ result: DecodedBarcodesResult) {
        print("[Dynamsoft] onDecodedBarcodesReceived called, items count: \(result.items?.count ?? 0)")
        
        guard let items = result.items, !items.isEmpty else { return }
        
        var barcodes: [BarcodeInfo] = []
        for item in items {
            print("[Dynamsoft] Barcode found - Format: \(item.formatString), Text: \(item.text)")
            let info = BarcodeInfo(
                format: item.formatString,
                text: item.text,
                decodeTimeMs: 0
            )
            barcodes.append(info)
        }
        
        DispatchQueue.main.async {
            self.onBarcodesDetected?(barcodes)
        }
    }
}

// MARK: - Dynamsoft Camera Preview View
struct DynamsoftCameraPreviewView: UIViewRepresentable {
    let scanner: DynamsoftCameraScanner
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView(frame: .zero)
        
        if let cameraView = scanner.getCameraView() {
            cameraView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(cameraView)
            
            NSLayoutConstraint.activate([
                cameraView.topAnchor.constraint(equalTo: containerView.topAnchor),
                cameraView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                cameraView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                cameraView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    NavigationStack {
        DynamsoftScannerView()
            .environmentObject(MainViewModel())
    }
}
