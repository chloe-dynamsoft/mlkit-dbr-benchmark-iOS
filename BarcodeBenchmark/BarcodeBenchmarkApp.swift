import SwiftUI
import DynamsoftCaptureVisionBundle

@main
struct BarcodeBenchmarkApp: App {
    @StateObject private var viewModel = MainViewModel()
    
    init() {
        // Initialize Dynamsoft License at app startup
        DynamsoftLicenseManager.shared.initLicense()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Dynamsoft License Manager
class DynamsoftLicenseManager: NSObject, LicenseVerificationListener {
    static let shared = DynamsoftLicenseManager()
    
    // Trial license key
    private let licenseKey = "DLS2eyJoYW5kc2hha2VDb2RlIjoiMjAwMDAxLTE2NDk4Mjk3OTI2MzUiLCJvcmdhbml6YXRpb25JRCI6IjIwMDAwMSIsInNlc3Npb25QYXNzd29yZCI6IndTcGR6Vm05WDJrcEQ5YUoifQ=="
    
    private override init() {
        super.init()
    }
    
    func initLicense() {
        print("[Dynamsoft] Initializing license...")
        LicenseManager.initLicense(licenseKey, verificationDelegate: self)
    }
    
    func onLicenseVerified(_ isSuccess: Bool, error: Error?) {
        if isSuccess {
            print("[Dynamsoft] License verified successfully!")
        } else {
            print("[Dynamsoft] License verification FAILED: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
}
