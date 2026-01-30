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
    private let licenseKey = "t0088pwAAADNYckHyPikZ2O5DtQp+Ry3yU3GHFQAzoepUNwJJDfWVm7ffMr8wicSL1OPY4LpwQ/uCKGKI3ubMCIygxwFKmIWrC/kJ5likr48/SiseX34CXV8ifA=="
    
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
