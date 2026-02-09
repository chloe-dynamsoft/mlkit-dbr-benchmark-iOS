import Foundation
import AVFoundation
import UIKit
import DynamsoftCaptureVisionBundle

/// Feeds pre-recorded video frames into `CaptureVisionRouter` through its
/// streaming pipeline (`ImageSourceAdapter` → `startCapturing` →
/// `CapturedResultReceiver`), exactly the same path the SDK takes when
/// reading from a live camera.
///
/// `MultiFrameResultCrossFilter` is enabled so that cross-verification
/// and latest-overlapping are active — these features are only available
/// in streaming mode.
class DynamsoftVideoStreamProcessor: ImageSourceAdapter, CapturedResultReceiver {

    // MARK: – Public result / control
    private var detectedBarcodes: [BarcodeInfo] = []
    private var uniqueBarcodeKeys: Set<String> = []
    private var framesProcessed = 0
    private var successfulDecodes = 0
    private var timeToFirstReadMs: Double? = nil
    private var firstReadFrameIndex: Int? = nil

    // MARK: – Streaming infrastructure
    private let cvr = CaptureVisionRouter()
    private var startTime: Date?
    private var frameDuration: Double = 0          // seconds per frame
    private var totalFramesFed = 0                 // frames pushed to the buffer
    private var frameIDForResult = 0               // counter bumped per callback
    private var annotations: [Annotation] = []
    private var csvLoggerRef: VideoBenchmarkCSVLogger?
    private var normalizedAnnotations: Set<String> = []
    private var isCancelled: (() -> Bool)?

    /// Guards shared mutable state touched from both the feeding thread
    /// and the result-callback thread.
    private let lock = NSLock()

    // MARK: – Entry point

    func processVideoStream(
        url: URL,
        annotations: [Annotation],
        csvLogger: VideoBenchmarkCSVLogger?,
        cancelled: @escaping () -> Bool
    ) async throws -> VideoStreamResult {

        // ── Reset state ──────────────────────────────────────────────
        detectedBarcodes.removeAll()
        uniqueBarcodeKeys.removeAll()
        framesProcessed = 0
        successfulDecodes = 0
        timeToFirstReadMs = nil
        firstReadFrameIndex = nil
        totalFramesFed = 0
        frameIDForResult = 0
        self.annotations = annotations
        self.csvLoggerRef = csvLogger
        self.isCancelled = cancelled
        self.normalizedAnnotations = Set(annotations.map {
            $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
        })

        // ── Load video metadata ──────────────────────────────────────
        let asset = AVAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "DynamsoftVideoStreamProcessor", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }

        let frameRate = try await videoTrack.load(.nominalFrameRate)
        frameDuration = 1.0 / Double(frameRate)

        // ── Configure ImageSourceAdapter ─────────────────────────────
        maxImageCount = 4
        bufferOverflowProtectionMode = .update   // drop oldest when full

        // ── Connect to CaptureVisionRouter ───────────────────────────
        try cvr.setInput(self)
        cvr.addResultReceiver(self)

        let filter = MultiFrameResultCrossFilter()
        filter.enableResultCrossVerification(.barcode, isEnabled: true)
        filter.enableLatestOverlapping(.barcode, isEnabled: true)
        filter.setMaxOverlappingFrames(.barcode, maxOverlappingFrames: 10)
        cvr.addResultFilter(filter)

        startTime = Date()

        // ── Start capturing (streaming mode) ─────────────────────────
        cvr.startCapturing(PresetTemplate.readBarcodes.rawValue) { ok, err in
            if !ok {
                print("[Dynamsoft Stream] startCapturing failed: \(err?.localizedDescription ?? "unknown")")
            }
        }

        // ── Feed frames on a background queue ────────────────────────
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.feedFrames(from: asset, track: videoTrack)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        // ── Wait until the SDK drains the buffer ─────────────────────
        await waitForBufferDrain()

        // ── Tear down ────────────────────────────────────────────────
        cvr.stopCapturing()
        cvr.removeResultReceiver(self)
        clearBuffer()

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

    // MARK: – Frame feeding

    /// Reads every frame from the video file and pushes it into the
    /// `ImageSourceAdapter` buffer where `CaptureVisionRouter` will
    /// pick it up automatically.
    private func feedFrames(from asset: AVAsset, track: AVAssetTrack) throws {
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        if reader.canAdd(output) { reader.add(output) }
        reader.startReading()

        // Signal the SDK that images are available.
        setImageFetchState(true)

        while reader.status == .reading {
            if isCancelled?() == true {
                reader.cancelReading()
                break
            }

            autoreleasepool {
                guard let sampleBuffer = output.copyNextSampleBuffer(),
                      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                else { return }

                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

                guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
                let size   = CVPixelBufferGetDataSize(pixelBuffer)
                let width  = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let bpr    = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let bytes  = Data(bytes: base, count: size)

                lock.lock()
                totalFramesFed += 1
                lock.unlock()

                let imageData = ImageData(
                    bytes: bytes,
                    width: UInt(width),
                    height: UInt(height),
                    stride: UInt(bpr),
                    format: .ARGB8888,
                    orientation: 0,
                    tag: nil
                )
                addImageToBuffer(imageData)
            }
        }

        // No more frames — tell the SDK.
        setImageFetchState(false)
    }

    // MARK: – Buffer drain

    /// Waits until the SDK has consumed all buffered frames (or a
    /// timeout elapses).
    private func waitForBufferDrain() async {
        let deadline = Date().addingTimeInterval(5.0)
        while !isBufferEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        }
        // Grace period for the last callback(s)
        try? await Task.sleep(nanoseconds: 300_000_000)    // 300 ms
    }

    // MARK: – CapturedResultReceiver

    func onDecodedBarcodesReceived(_ result: DecodedBarcodesResult) {
        lock.lock()
        frameIDForResult += 1
        let currentFrameID = frameIDForResult
        framesProcessed = currentFrameID
        let timestamp = Double(currentFrameID) * frameDuration
        lock.unlock()

        var decodedText = ""
        var success = false
        var correctCount = 0
        var misreadCount = 0

        guard let items = result.items, !items.isEmpty else {
            // Log empty frame
            let entry = FrameLogEntry(
                frameID: currentFrameID,
                timestamp: timestamp,
                sdkName: "Dynamsoft",
                success: false,
                decodedText: "",
                latencyMs: 0,
                boundingBoxArea: 0,
                correctCount: 0,
                misreadCount: 0
            )
            csvLoggerRef?.addEntry(entry)
            return
        }

        lock.lock()
        successfulDecodes += 1
        lock.unlock()
        success = true

        var texts: [String] = []
        for item in items {
            let key = "\(item.formatString):\(item.text)"
            let normalizedDecoded = item.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")

            if !annotations.isEmpty {
                if normalizedAnnotations.contains(normalizedDecoded) {
                    correctCount += 1
                } else {
                    misreadCount += 1
                }
            }

            lock.lock()
            if !uniqueBarcodeKeys.contains(key) {
                uniqueBarcodeKeys.insert(key)
                let info = BarcodeInfo(
                    format: item.formatString,
                    text: item.text,
                    decodeTimeMs: 0
                )
                detectedBarcodes.append(info)
            }
            lock.unlock()

            texts.append(item.text)
        }

        // Track TTFR
        let hasValidRead = !annotations.isEmpty ? (correctCount > 0) : true
        lock.lock()
        if timeToFirstReadMs == nil, let start = startTime, hasValidRead {
            timeToFirstReadMs = Date().timeIntervalSince(start) * 1000
            firstReadFrameIndex = currentFrameID
        }
        lock.unlock()

        decodedText = texts.joined(separator: "; ")

        let entry = FrameLogEntry(
            frameID: currentFrameID,
            timestamp: timestamp,
            sdkName: "Dynamsoft",
            success: success,
            decodedText: decodedText,
            latencyMs: 0,         // latency is internal to the SDK in streaming mode
            boundingBoxArea: 0,
            correctCount: correctCount,
            misreadCount: misreadCount
        )
        csvLoggerRef?.addEntry(entry)
    }
}
