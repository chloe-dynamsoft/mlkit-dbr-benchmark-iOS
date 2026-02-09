import Foundation

/// Represents the result of processing a video stream through a barcode SDK.
struct VideoStreamResult {
    let barcodes: [BarcodeInfo]
    let totalTime: Double
    let framesProcessed: Int
    let successfulDecodes: Int
    let timeToFirstReadMs: Double?
    let firstReadFrameIndex: Int?
}
