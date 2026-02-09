import Foundation
import AVFoundation
import UIKit
import MLKitBarcodeScanning
import MLKitVision

/// Processes video frames through Google MLKit Barcode Scanning SDK.
///
/// MLKit does **not** provide a true streaming / multi-frame pipeline —
/// each frame is processed independently via `BarcodeScanner.results(in:)`.
/// There is no cross-frame verification or deduplication built into the
/// SDK, so every frame is treated as a standalone image.
class MLKitVideoStreamProcessor {
    private lazy var barcodeScanner: BarcodeScanner = {
        let options = BarcodeScannerOptions(formats: [.all])
        return BarcodeScanner.barcodeScanner(options: options)
    }()
    
    func processVideoStream(url: URL, annotations: [Annotation], csvLogger: VideoBenchmarkCSVLogger?, cancelled: @escaping () -> Bool) async throws -> VideoStreamResult {
        var detectedBarcodes: [BarcodeInfo] = []
        var uniqueBarcodeKeys: Set<String> = []
        let startTime = Date()
        var framesProcessed = 0
        var successfulDecodes = 0
        var timeToFirstReadMs: Double? = nil
        var firstReadFrameIndex: Int? = nil
        
        // Create video asset and reader
        let asset = AVAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "VideoStreamProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let frameDuration = 1.0 / Double(frameRate)
        
        let reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        
        if reader.canAdd(readerOutput) {
            reader.add(readerOutput)
        }
        
        reader.startReading()
        
        // Pre-compute normalised annotation values for matching
        let normalizedAnnotations = Set(annotations.map {
            $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
        })
        
        var frameCount = 0
        
        while reader.status == .reading {
            if cancelled() {
                reader.cancelReading()
                break
            }
            
            autoreleasepool {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { return }
                
                frameCount += 1
                framesProcessed += 1
                
                let timestamp = Double(framesProcessed) * frameDuration
                
                let visionImage = VisionImage(buffer: sampleBuffer)
                visionImage.orientation = .up
                
                let frameStartTime = Date()
                var decodedText = ""
                var success = false
                var correctCount = 0
                var misreadCount = 0
                
                do {
                    let barcodes = try self.barcodeScanner.results(in: visionImage)
                    let frameLatency = Date().timeIntervalSince(frameStartTime) * 1000
                    
                    if !barcodes.isEmpty {
                        successfulDecodes += 1
                        success = true
                    }
                    
                    // Collect all decoded texts for CSV
                    var texts: [String] = []
                    for barcode in barcodes {
                        let format = self.getMLKitFormatName(barcode.format)
                        let text = barcode.rawValue ?? ""
                        let key = "\(format):\(text)"
                        let normalizedDecoded = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\"", with: "")
                        
                        // Check against annotations if available
                        if !annotations.isEmpty {
                            if normalizedAnnotations.contains(normalizedDecoded) {
                                correctCount += 1
                            } else {
                                misreadCount += 1
                            }
                        }
                        
                        if !uniqueBarcodeKeys.contains(key) {
                            uniqueBarcodeKeys.insert(key)
                            let info = BarcodeInfo(
                                format: format,
                                text: text,
                                decodeTimeMs: 0
                            )
                            detectedBarcodes.append(info)
                        }
                        texts.append(text)
                    }
                    
                    // Track Time-to-First-Read only if we have correct read (if annotations present) or just any read (if no annotations)
                    let hasValidRead = !annotations.isEmpty ? (correctCount > 0) : true
                    if timeToFirstReadMs == nil && success && hasValidRead {
                        timeToFirstReadMs = Date().timeIntervalSince(startTime) * 1000
                        firstReadFrameIndex = framesProcessed
                    }
                    
                    decodedText = texts.joined(separator: "; ")
                    
                    // Log to CSV
                    let entry = FrameLogEntry(
                        frameID: framesProcessed,
                        timestamp: timestamp,
                        sdkName: "MLKit",
                        success: success,
                        decodedText: decodedText,
                        latencyMs: frameLatency,
                        boundingBoxArea: 0,
                        correctCount: correctCount,
                        misreadCount: misreadCount
                    )
                    csvLogger?.addEntry(entry)
                } catch {
                    // Log failed frame to CSV
                    let frameLatency = Date().timeIntervalSince(frameStartTime) * 1000
                    let entry = FrameLogEntry(
                        frameID: framesProcessed,
                        timestamp: timestamp,
                        sdkName: "MLKit",
                        success: false,
                        decodedText: "",
                        latencyMs: frameLatency,
                        boundingBoxArea: 0,
                        correctCount: 0,
                        misreadCount: 0
                    )
                    csvLogger?.addEntry(entry)
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
