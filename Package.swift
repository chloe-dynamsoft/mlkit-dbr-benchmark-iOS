// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarcodeBenchmark",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        // Dynamsoft Capture Vision Bundle SDK v11
        .package(url: "https://github.com/Dynamsoft/capture-vision-spm.git", from: "3.4.0"),
    ],
    targets: [
        .target(
            name: "BarcodeBenchmark",
            dependencies: [
                .product(name: "DynamsoftCaptureVisionBundle", package: "capture-vision-spm"),
            ]
        )
    ]
)
