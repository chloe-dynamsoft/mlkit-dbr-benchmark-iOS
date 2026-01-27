# Barcode Benchmark iOS

A Swift iOS application that benchmarks barcode scanning performance, comparing **Dynamsoft Barcode Reader v11** with **Google MLKit**.

## Features

- **Camera Scanning**: Real-time barcode scanning with both Dynamsoft and Google MLKit
- **Image Benchmark**: Load an image and compare decoding performance
- **Video Benchmark**: Process video frames and compare detection across engines
- **Resolution Selection**: Choose between 720p and 1080p camera resolution
- **Web Server**: Built-in web server for remote benchmarking via browser

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- CocoaPods (for Google MLKit)

## Project Structure

```
BarcodeBenchmark-iOS/
├── BarcodeBenchmark/
│   ├── BarcodeBenchmarkApp.swift    # App entry point with license init
│   ├── ContentView.swift             # Main content view
│   ├── Info.plist                    # App configuration
│   ├── Assets.xcassets/              # App assets
│   ├── Models/
│   │   └── Models.swift              # Data models (ViewModel, BarcodeInfo, etc.)
│   ├── Views/
│   │   ├── HomeView.swift            # Home screen with benchmark options
│   │   ├── DynamsoftScannerView.swift # Dynamsoft camera scanner
│   │   ├── MLKitScannerView.swift    # Google MLKit camera scanner
│   │   ├── ImageBenchmarkView.swift  # Image benchmark screen
│   │   ├── VideoBenchmarkView.swift  # Video benchmark screen
│   │   └── BenchmarkResultView.swift # Results display screen
│   └── Utilities/
│       ├── FileUtil.swift            # File utilities
│       └── BenchmarkWebServer.swift  # HTTP server for web interface
├── BarcodeBenchmark.xcodeproj/       # Xcode project
├── Podfile                           # CocoaPods for Google MLKit
└── Package.swift                      # Swift Package Manager config
```

## Installation

### Step 1: Install CocoaPods Dependencies

```bash
cd BarcodeBenchmark-iOS
pod install
```

### Step 2: Open in Xcode

1. **IMPORTANT**: Open `BarcodeBenchmark.xcworkspace` (NOT `.xcodeproj`)
2. Wait for Swift Package Manager to resolve Dynamsoft dependencies
3. Select your target device or simulator
4. Build and run (⌘+R)

## SDK Configuration

### Dynamsoft Barcode Reader v11

The project uses Dynamsoft Capture Vision Bundle SDK v11 via Swift Package Manager:

```swift
.package(url: "https://github.com/Dynamsoft/capture-vision-spm.git", from: "11.0.0")
```

Usage example:
```swift
import DynamsoftCaptureVisionBundle

// Initialize license (done in BarcodeBenchmarkApp.swift)
LicenseManager.initLicense("YOUR-LICENSE-KEY") { isSuccess, error in
    // Handle result
}

// Use CaptureVisionRouter for barcode scanning
let cvr = CaptureVisionRouter()
let result = cvr.captureFromImage(image, templateName: PresetTemplate.readBarcodes.rawValue)
```

### Google MLKit Barcode Scanning

The project uses Google MLKit via CocoaPods:

```ruby
pod 'GoogleMLKit/BarcodeScanning', '~> 8.0.0'
```

Usage example:
```swift
import MLKitBarcodeScanning
import MLKitVision

// Create VisionImage from UIImage
let visionImage = VisionImage(image: uiImage)

// Create barcode scanner
let options = BarcodeScannerOptions(formats: [.all])
let barcodeScanner = BarcodeScanner.barcodeScanner(options: options)

// Scan barcodes
let barcodes = try barcodeScanner.results(in: visionImage)
```

## Usage

### Home Screen
- Select camera resolution (720p or 1080p)
- Choose a benchmark mode:
  - **Image**: Select a photo to benchmark
  - **Video**: Select a video to process frames
  - **Dynamsoft Camera**: Live scanning with Dynamsoft SDK
  - **MLKit Camera**: Live scanning with Google MLKit

### Web Server
- Toggle the web server switch to start the HTTP server
- Access the benchmark interface from any device on the same network
- Upload images/videos for remote benchmarking

## Comparison: Android Java → Swift

| Android (Java) | iOS (Swift) |
|----------------|-------------|
| `MainActivity.java` | `BarcodeBenchmarkApp.swift` |
| `MainViewModel.java` | `Models.swift` (MainViewModel class) |
| `FileUtil.java` | `FileUtil.swift` |
| `HomeFragment.java` | `HomeView.swift` |
| `DynamsoftScannerFragment.java` | `DynamsoftScannerView.swift` |
| `MLkitScannerFragment.java` | `MLKitScannerView.swift` |
| `ImageBenchmarkFragment.java` | `ImageBenchmarkView.swift` |
| `VideoBenchmarkFragment.java` | `VideoBenchmarkView.swift` |
| `BenchmarkResultFragment.java` | `BenchmarkResultView.swift` |
| `BenchmarkWebServer.java` | `BenchmarkWebServer.swift` |
| XML Layouts | SwiftUI Views |
| `CameraSource.java` | AVFoundation (built into scanner views) |
| Google MLKit | Google MLKit (via CocoaPods) |

## Key Differences from Android Version

1. **UI Framework**: Uses SwiftUI instead of XML layouts
2. **Navigation**: Uses NavigationStack instead of Fragments with Navigation Component
3. **Camera**: Uses AVFoundation instead of Android Camera API
4. **Barcode Detection**: Uses Google MLKit via CocoaPods (same API as Android)
5. **Image/Video Picking**: Uses PhotosPicker instead of ActivityResultLauncher
6. **Async Operations**: Uses Swift async/await instead of ExecutorService

## License

This project is for benchmarking and demonstration purposes.

## Credits

- Original Android project translated to Swift
- Dynamsoft Barcode Reader SDK
- Apple Vision Framework
