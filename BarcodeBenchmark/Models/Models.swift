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
    let correctCount: Int
    let misreadCount: Int
    
    /// Format as CSV row
    func toCSVRow() -> String {
        let frameIDStr = String(format: "%04d", frameID)
        let timestampStr = String(format: "%.3f", timestamp)
        let successInt = success ? 1 : 0
        let escapedText = decodedText.replacingOccurrences(of: "\"", with: "\"\"")
        let latencyStr = String(format: "%.1f", latencyMs)
        return "\(frameIDStr), \(timestampStr), \(sdkName), \(successInt), \"\(escapedText)\", \(latencyStr), \(boundingBoxArea), \(correctCount), \(misreadCount)"
    }
    
    static var csvHeader: String {
        return "Frame_ID, Timestamp, SDK_Name, Success, Decoded_Text, Latency_ms, BoundingBox_Area, Correct_Count, Misread_Count"
    }
}

// MARK: - Annotation Model
struct Annotation: Identifiable, Hashable {
    let id = UUID()
    let format: String
    let value: String
    
    var key: String {
        return "\(format):\(value)"
    }
}

// MARK: - Benchmark Session
struct BenchmarkSession: Identifiable, Codable {
    let id: UUID
    let date: Date
    let videoName: String
    let summary: String
    let csvContent: String
    
    init(videoName: String, summary: String, csvContent: String) {
        self.id = UUID()
        self.date = Date()
        self.videoName = videoName
        self.summary = summary
        self.csvContent = csvContent
    }
}

// MARK: - History Store
class HistoryStore: ObservableObject {
    @Published var sessions: [BenchmarkSession] = []
    
    func addSession(_ session: BenchmarkSession) {
        sessions.append(session)
    }
    
    func clearHistory() {
        sessions.removeAll()
    }
    
    func exportAllSessions() -> URL? {
        // Create a temporary directory for export
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BenchmarkExport_\(Date().timeIntervalSince1970)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            for session in sessions {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let dateStr = dateFormatter.string(from: session.date)
                let filename = "benchmark_\(session.videoName)_\(dateStr).csv"
                let fileURL = tempDir.appendingPathComponent(filename)
                
                try session.csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            // Zip the directory? Or just return the directory?
            // For simplicity, let's just use the directory for now, user can share multiple files.
            // Or better, combine into one large CSV if structure matches? No, multiple files is better.
            return tempDir
        } catch {
            print("Failed to export history: \(error)")
            return nil
        }
    }
}

// MARK: - CSV Logger for Video Benchmark
class VideoBenchmarkCSVLogger {
    private var entries: [FrameLogEntry] = []
    private let logFileName: String
    private let annotations: [Annotation]
    private var summaryStats: [String: (totalFrames: Int, totalTime: Double, correctFrames: Int, misreadFrames: Int)] = [:]
    /// Global tally: decoded value → count of distinct frames that produced it, per SDK.
    /// Using a bag (multiset) so that duplicate annotations are matched against
    /// duplicate detections, not just unique values.
    private var foundBags: [String: [String: Int]] = [:]
    /// TTFR: frame ID and video timestamp (ms) at which the cumulative found bag
    /// first fully satisfies the annotation bag (multiset match).
    /// Tracked per SDK.  `nil` means the annotations were never fully matched.
    private var ttfrInfo: [String: (frameID: Int, timestampMs: Double)] = [:]
    
    init(videoName: String, annotations: [Annotation] = []) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedVideoName = videoName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        self.logFileName = "benchmark_\(sanitizedVideoName)_\(timestamp).csv"
        self.annotations = annotations
    }
    
    func addEntry(_ entry: FrameLogEntry) {
        entries.append(entry)
        
        // Update summary stats (for frame-level tracking)
        var stats = summaryStats[entry.sdkName] ?? (0, 0, 0, 0)
        stats.totalFrames += 1
        stats.totalTime = entry.timestamp
        if entry.correctCount > 0 { stats.correctFrames += 1 }
        if entry.misreadCount > 0 { stats.misreadFrames += 1 }
        summaryStats[entry.sdkName] = stats
        
        // Update global tally: count how many times each value was decoded
        if entry.success && !entry.decodedText.isEmpty {
            var sdkBag = foundBags[entry.sdkName] ?? [:]
            // Handle multiple barcodes separated by "; "
            let values = entry.decodedText.components(separatedBy: "; ")
            for value in values {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                if !normalized.isEmpty {
                    sdkBag[normalized, default: 0] += 1
                }
            }
            foundBags[entry.sdkName] = sdkBag
            
            // Check TTFR: has the cumulative found bag now fully satisfied the annotation bag?
            if ttfrInfo[entry.sdkName] == nil && !annotations.isEmpty {
                let annoBag = annotationBag
                let allMatched = annoBag.allSatisfy { (value, annoCount) in
                    (sdkBag[value] ?? 0) >= annoCount
                }
                if allMatched {
                    ttfrInfo[entry.sdkName] = (frameID: entry.frameID, timestampMs: entry.timestamp * 1000)
                }
            }
        }
    }
    
    func addEntries(_ newEntries: [FrameLogEntry]) {
        for entry in newEntries {
            addEntry(entry)
        }
    }
    
    /// Build an annotation bag: value → expected count (respects duplicates).
    private var annotationBag: [String: Int] {
        var bag: [String: Int] = [:]
        for a in annotations {
            let v = a.value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            bag[v, default: 0] += 1
        }
        return bag
    }
    
    /// Number of unique annotation values (deduplicated).
    var uniqueAnnotationCount: Int {
        return annotationBag.count
    }
    
    /// Calculate global tally stats for a given SDK using **multiset** comparison.
    ///
    /// For each annotation value that appears N times in the annotation list,
    /// the SDK gets credit for min(N, foundCount) matches.  Any decoded value
    /// that is NOT in the annotation list at all counts as a misread.
    ///
    /// Example: annotations = [A, A, A, B, B]  (5 total, 2 unique)
    ///          SDK found    = {A:2, B:3, C:1}
    ///          matched      = min(3,2) + min(2,3) = 2+2 = 4 out of 5
    ///          misread      = C  (1 unique value not in annotations)
    ///          accuracy     = 4/5 = 80%
    private func calculateGlobalTally(sdkName: String) -> (successCount: Int, misreadCount: Int, accuracy: Double, misreadRate: Double) {
        let sdkBag = foundBags[sdkName] ?? [:]
        let annoBag = annotationBag
        
        // Matched count (multiset intersection): for each annotated value,
        // credit = min(annotation count, found count).
        var matchedCount = 0
        for (value, annoCount) in annoBag {
            let foundCount = sdkBag[value] ?? 0
            matchedCount += min(annoCount, foundCount)
        }
        
        // Misread: unique values the SDK decoded that are NOT in annotations at all
        let misreadCount = sdkBag.keys.filter { annoBag[$0] == nil }.count
        
        // Accuracy: matchedCount / total annotation rows
        let totalAnnotations = annotations.count
        let accuracy = totalAnnotations == 0 ? 0.0 : (Double(matchedCount) / Double(totalAnnotations)) * 100.0
        
        // Misread Rate: misread unique values / total unique values found
        let totalUniqueFound = sdkBag.count
        let misreadRate = totalUniqueFound > 0 ? (Double(misreadCount) / Double(totalUniqueFound)) * 100.0 : 0.0
        
        return (matchedCount, misreadCount, accuracy, misreadRate)
    }
    
    func getCSVContent() -> String {
        var content = ""
        
        // Generate Summary Header using Global Tally (multiset)
        if !annotations.isEmpty {
            let uniqueAnno = uniqueAnnotationCount
            let totalAnno = annotations.count
            content += "SUMMARY HEADER (Global Tally) — Annotations: \(totalAnno) total (\(uniqueAnno) unique)\n"
            content += "SDK, Unique_Found, Annotations_Matched, Misreads, Accuracy%, Misread_Rate%, TTFR (ms)\n"
            
            for (sdk, stats) in summaryStats.sorted(by: { $0.key < $1.key }) {
                let tally = calculateGlobalTally(sdkName: sdk)
                let foundCount = foundBags[sdk]?.count ?? 0  // unique values found
                let ttfr = ttfrInfo[sdk]
                let ttfrStr = ttfr != nil ? String(format: "%.1f (Frame #%d)", ttfr!.timestampMs, ttfr!.frameID) : "N/A"
                
                content += "\(sdk), \(foundCount), \(tally.successCount)/\(totalAnno), \(tally.misreadCount), \(String(format: "%.2f", tally.accuracy)), \(String(format: "%.2f", tally.misreadRate)), \(ttfrStr)\n"
            }
            content += "\n"
        }
        
        content += FrameLogEntry.csvHeader + "\n"
        for entry in entries.sorted(by: { ($0.frameID, $0.sdkName) < ($1.frameID, $1.sdkName) }) {
            content += entry.toCSVRow() + "\n"
        }
        return content
    }
    
    func saveToFile() -> URL? {
        let content = getCSVContent()
        let fileURL = FileUtil.documentsDirectory.appendingPathComponent(logFileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[CSV Logger] Saved benchmark log to: \(fileURL.path)")
            printDebugTally()
            return fileURL
        } catch {
            print("[CSV Logger] Failed to save CSV: \(error)")
            return nil
        }
    }
    
    // MARK: - Debug Tally Output
    /// Prints a detailed breakdown of the global tally to the console:
    /// annotation list, per-SDK found list with match/misread labels, and summary header.
    func printDebugTally() {
        let annoBag = annotationBag
        let totalAnno = annotations.count
        let uniqueAnno = uniqueAnnotationCount
        
        print("")
        print("╔══════════════════════════════════════════════════════════════")
        print("║  DEBUG TALLY")
        print("╠══════════════════════════════════════════════════════════════")
        
        // 1. Annotation list
        print("║")
        print("║  ANNOTATIONS: \(totalAnno) total, \(uniqueAnno) unique")
        for (value, count) in annoBag.sorted(by: { $0.key < $1.key }) {
            print("║    [\(count)x] \(value)")
        }
        
        // 2. Per-SDK found list with match/misread labels
        for sdk in foundBags.keys.sorted() {
            let sdkBag = foundBags[sdk] ?? [:]
            let tally = calculateGlobalTally(sdkName: sdk)
            
            print("║")
            print("║  \(sdk) — Found \(sdkBag.count) unique values:")
            for (value, count) in sdkBag.sorted(by: { $0.key < $1.key }) {
                if let annoCount = annoBag[value] {
                    let credited = min(annoCount, count)
                    if credited == annoCount {
                        print("║    ✅ MATCH    [\(count)x found, \(annoCount)x expected → \(credited) credited] \(value)")
                    } else {
                        print("║    ⚠️  PARTIAL [\(count)x found, \(annoCount)x expected → \(credited) credited] \(value)")
                    }
                } else {
                    print("║    ❌ MISREAD  [\(count)x found, not in annotations] \(value)")
                }
            }
            
            // Values in annotations but never found by this SDK
            let missingFromSDK = annoBag.filter { sdkBag[$0.key] == nil }
            if !missingFromSDK.isEmpty {
                print("║    ── Not found by \(sdk):")
                for (value, count) in missingFromSDK.sorted(by: { $0.key < $1.key }) {
                    print("║    ⬜ MISSING  [\(count)x expected] \(value)")
                }
            }
            
            print("║")
            print("║    Matched: \(tally.successCount)/\(totalAnno)  Misreads: \(tally.misreadCount)  Accuracy: \(String(format: "%.2f", tally.accuracy))%  Misread Rate: \(String(format: "%.2f", tally.misreadRate))%")
            if let ttfr = ttfrInfo[sdk] {
                print("║    TTFR: \(String(format: "%.1f", ttfr.timestampMs)) ms (Frame #\(ttfr.frameID))")
            } else {
                print("║    TTFR: N/A (annotations never fully matched)")
            }
        }
        
        // 3. Summary header lines
        print("║")
        print("║  SUMMARY HEADER:")
        for line in getSummaryHeader() {
            print("║    \(line)")
        }
        print("╚══════════════════════════════════════════════════════════════")
        print("")
    }
    
    func getEntries() -> [FrameLogEntry] {
        return entries
    }
    
    func getSummaryHeader() -> [String] {
        var lines: [String] = []
        
        if !annotations.isEmpty {
            let uniqueAnno = uniqueAnnotationCount
            let totalAnno = annotations.count
            lines.append("Annotations: \(totalAnno) total (\(uniqueAnno) unique)")
            lines.append("")
            
            for (sdk, stats) in summaryStats.sorted(by: { $0.key < $1.key }) {
                let tally = calculateGlobalTally(sdkName: sdk)
                let foundCount = foundBags[sdk]?.count ?? 0  // unique values found
                let ttfr = ttfrInfo[sdk]
                let ttfrStr = ttfr != nil ? String(format: "%.1f ms (Frame #%d)", ttfr!.timestampMs, ttfr!.frameID) : "N/A"
                
                lines.append("\(sdk):")
                lines.append("  Unique Values Found: \(foundCount)")
                lines.append("  Misreads: \(tally.misreadCount) out of \(foundCount)")
                lines.append("  Misread Rate: \(String(format: "%.2f", tally.misreadRate))%")
                lines.append("  Annotations Matched: \(tally.successCount)/\(totalAnno)")

                lines.append("  Accuracy: \(String(format: "%.2f", tally.accuracy))%")

                lines.append("  TTFR: \(ttfrStr)")
                lines.append("")
            }
        }
        
        return lines
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
    
    // History Store
    @Published var historyStore = HistoryStore()
    
    // Annotations
    @Published var annotations: [Annotation] = []
    
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
