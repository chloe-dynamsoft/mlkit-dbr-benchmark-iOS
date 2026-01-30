import Foundation
import SwiftUI
import Combine

// MARK: - Frame Log Entry for CSV Export
struct FrameLogEntry {
    let frameID: Int
    let timestamp: Double  // seconds from video start
    let sdkName: String
    let success: Bool
    let decodedText: String
    let latencyMs: Double
    let boundingBoxArea: Int  // 0 if no barcode found
    
    /// Format as CSV row
    func toCSVRow() -> String {
        let frameIDStr = String(format: "%04d", frameID)
        let timestampStr = String(format: "%.3f", timestamp)
        let successInt = success ? 1 : 0
        let escapedText = decodedText.replacingOccurrences(of: "\"", with: "\"\"")
        let latencyStr = String(format: "%.1f", latencyMs)
        return "\(frameIDStr), \(timestampStr), \(sdkName), \(successInt), \"\(escapedText)\", \(latencyStr), \(boundingBoxArea)"
    }
    
    static var csvHeader: String {
        return "Frame_ID, Timestamp, SDK_Name, Success, Decoded_Text, Latency_ms, BoundingBox_Area"
    }
}

// MARK: - CSV Logger for Video Benchmark
class VideoBenchmarkCSVLogger {
    private var entries: [FrameLogEntry] = []
    private let logFileName: String
    
    init(videoName: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedVideoName = videoName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        self.logFileName = "benchmark_\(sanitizedVideoName)_\(timestamp).csv"
    }
    
    func addEntry(_ entry: FrameLogEntry) {
        entries.append(entry)
    }
    
    func addEntries(_ newEntries: [FrameLogEntry]) {
        entries.append(contentsOf: newEntries)
    }
    
    func getCSVContent() -> String {
        var csv = FrameLogEntry.csvHeader + "\n"
        for entry in entries.sorted(by: { ($0.frameID, $0.sdkName) < ($1.frameID, $1.sdkName) }) {
            csv += entry.toCSVRow() + "\n"
        }
        return csv
    }
    
    func saveToFile() -> URL? {
        let content = getCSVContent()
        let fileURL = FileUtil.documentsDirectory.appendingPathComponent(logFileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[CSV Logger] Saved benchmark log to: \(fileURL.path)")
            return fileURL
        } catch {
            print("[CSV Logger] Failed to save CSV: \(error)")
            return nil
        }
    }
    
    func getEntries() -> [FrameLogEntry] {
        return entries
    }
}

// MARK: - Main ViewModel
class MainViewModel: ObservableObject {
    // Resolution setting: 0 = 720P, 1 = 1080P
    @Published var resolutionIndex: Int = 0
    
    // Benchmark mode: "camera", "image", "video"
    @Published var benchmarkMode: String = "camera"
    
    // Source file name (for image/video modes)
    @Published var sourceFileName: String?
    
    // Dynamsoft benchmark results
    @Published var dynamsoftResult: BenchmarkResult?
    
    // MLkit benchmark results
    @Published var mlkitResult: BenchmarkResult?
    
    // Camera scan results (for real-time display)
    @Published var cameraScanResults: [BarcodeInfo] = []
    
    // CSV Logger for video benchmark
    @Published var csvLogger: VideoBenchmarkCSVLogger?
    @Published var csvFileURL: URL?
    
    // Selected resolution
    var selectedResolution: CameraResolution {
        resolutionIndex == 0 ? .hd720p : .fullHD1080p
    }
    
    func reset() {
        dynamsoftResult = nil
        mlkitResult = nil
        cameraScanResults.removeAll()
        sourceFileName = nil
        csvLogger = nil
        csvFileURL = nil
    }
}

// MARK: - Camera Resolution
enum CameraResolution: String, CaseIterable {
    case hd720p = "720P"
    case fullHD1080p = "1080P"
    
    var width: Int {
        switch self {
        case .hd720p: return 1280
        case .fullHD1080p: return 1920
        }
    }
    
    var height: Int {
        switch self {
        case .hd720p: return 720
        case .fullHD1080p: return 1080
        }
    }
}

// MARK: - Benchmark Result
class BenchmarkResult: ObservableObject, Identifiable {
    let id = UUID()
    let engineName: String
    @Published var totalTimeMs: Int64 = 0
    @Published var framesProcessed: Int = 0
    @Published var barcodes: [BarcodeInfo] = []
    
    // New metrics for video benchmark
    @Published var framesWithBarcodeVisible: Int = 0  // Total frames where barcode is visible (ground truth)
    @Published var successfulDecodes: Int = 0         // Frames where SDK successfully decoded
    @Published var timeToFirstReadMs: Double? = nil   // Time-to-First-Read (TTFR) in milliseconds
    @Published var firstReadFrameIndex: Int? = nil    // Frame index of first successful read
    
    init(engineName: String) {
        self.engineName = engineName
    }
    
    var avgTimePerFrame: Double {
        guard framesProcessed > 0 else { return 0 }
        return Double(totalTimeMs) / Double(framesProcessed)
    }
    
    var totalBarcodesFound: Int {
        return barcodes.count
    }
    
    var uniqueBarcodeCount: Int {
        var unique: Set<String> = []
        for info in barcodes {
            let key = "\(info.format):\(info.text)"
            unique.insert(key)
        }
        return unique.count
    }
    
    /// Success rate: Successful Decodes / Frames with Barcode Visible
    var successRate: Double {
        guard framesWithBarcodeVisible > 0 else { return 0 }
        return Double(successfulDecodes) / Double(framesWithBarcodeVisible) * 100.0
    }
    
    /// TTFR formatted string
    var ttfrFormatted: String {
        guard let ttfr = timeToFirstReadMs else { return "N/A" }
        return String(format: "%.1f ms", ttfr)
    }
}

// MARK: - Barcode Info
struct BarcodeInfo: Identifiable, Hashable {
    let id = UUID()
    let format: String
    let text: String
    let decodeTimeMs: Int64
    var frameIndex: Int = 0
    
    init(format: String, text: String, decodeTimeMs: Int64, frameIndex: Int = 0) {
        self.format = format
        self.text = text
        self.decodeTimeMs = decodeTimeMs
        self.frameIndex = frameIndex
    }
    
    var displayString: String {
        return "\(format): \(text)"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(format)
        hasher.combine(text)
    }
    
    static func == (lhs: BarcodeInfo, rhs: BarcodeInfo) -> Bool {
        return lhs.format == rhs.format && lhs.text == rhs.text
    }
}

// MARK: - Barcode Format Helper
enum BarcodeFormat: String, CaseIterable {
    case code128 = "CODE_128"
    case code39 = "CODE_39"
    case code93 = "CODE_93"
    case codabar = "CODABAR"
    case dataMatrix = "DATA_MATRIX"
    case ean13 = "EAN_13"
    case ean8 = "EAN_8"
    case itf = "ITF"
    case qrCode = "QR_CODE"
    case upcA = "UPC_A"
    case upcE = "UPC_E"
    case pdf417 = "PDF417"
    case aztec = "AZTEC"
    case unknown = "UNKNOWN"
    
    static func fromMLKitFormat(_ format: Int) -> String {
        switch format {
        case 1: return "CODE_128"
        case 2: return "CODE_39"
        case 4: return "CODE_93"
        case 8: return "CODABAR"
        case 16: return "DATA_MATRIX"
        case 32: return "EAN_13"
        case 64: return "EAN_8"
        case 128: return "ITF"
        case 256: return "QR_CODE"
        case 512: return "UPC_A"
        case 1024: return "UPC_E"
        case 2048: return "PDF417"
        case 4096: return "AZTEC"
        default: return "UNKNOWN"
        }
    }
}

// MARK: - App Theme Colors
extension Color {
    static let dynamsoftBlue = Color(red: 0.1, green: 0.46, blue: 0.82) // #1976D2
    static let mlkitGreen = Color(red: 0.3, green: 0.69, blue: 0.31) // #4CAF50
    static let benchmarkPurple = Color(red: 0.4, green: 0.23, blue: 0.72) // #673AB7
}
