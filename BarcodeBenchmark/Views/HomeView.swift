import SwiftUI
import Network

struct HomeView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var isServerRunning = false
    @State private var serverURL = ""
    @State private var webServer: BenchmarkWebServer?
    
    private let serverPort: UInt16 = 8080
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Resolution Selection
                resolutionSection
                
                // Benchmark Options
                benchmarkCardsSection
                
                // Web Server Section
                webServerSection
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Barcode Benchmark")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear {
            stopWebServer()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.dynamsoftBlue)
            
            Text("Compare barcode scanning performance")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }
    
    // MARK: - Resolution Section
    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera Resolution")
                .font(.headline)
            
            Picker("Resolution", selection: $viewModel.resolutionIndex) {
                Text("720P").tag(0)
                Text("1080P").tag(1)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Benchmark Cards Section
    private var benchmarkCardsSection: some View {
        VStack(spacing: 16) {
            // Image and Video Benchmark Row
            HStack(spacing: 16) {
                NavigationLink(destination: ImageBenchmarkView()) {
                    BenchmarkCard(
                        title: "Image",
                        subtitle: "Benchmark",
                        icon: "photo",
                        color: .benchmarkPurple
                    )
                }
                
                NavigationLink(destination: VideoBenchmarkView()) {
                    BenchmarkCard(
                        title: "Video",
                        subtitle: "Benchmark",
                        icon: "video",
                        color: .benchmarkPurple
                    )
                }
            }
            
            // Camera Scanners Row
            HStack(spacing: 16) {
                NavigationLink(destination: DynamsoftScannerView()) {
                    BenchmarkCard(
                        title: "Dynamsoft",
                        subtitle: "Camera",
                        icon: "camera.viewfinder",
                        color: .dynamsoftBlue
                    )
                }
                
                NavigationLink(destination: MLKitScannerView()) {
                    BenchmarkCard(
                        title: "MLKit",
                        subtitle: "Camera",
                        icon: "camera.viewfinder",
                        color: .mlkitGreen
                    )
                }
            }
        }
    }
    
    // MARK: - Web Server Section
    private var webServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Web Server")
                    .font(.headline)
                
                Spacer()
                
                Toggle("", isOn: $isServerRunning)
                    .labelsHidden()
                    .onChange(of: isServerRunning) { newValue in
                        if newValue {
                            startWebServer()
                        } else {
                            stopWebServer()
                        }
                    }
            }
            
            if isServerRunning && !serverURL.isEmpty {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.green)
                    
                    Text(serverURL)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        UIPasteboard.general.string = serverURL
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Web Server Methods
    private func startWebServer() {
        let ipAddress = getLocalIPAddress()
        serverURL = "http://\(ipAddress):\(serverPort)"
        webServer = BenchmarkWebServer(port: serverPort)
        webServer?.start()
        print("Web server started: \(serverURL)")
    }
    
    private func stopWebServer() {
        webServer?.stop()
        webServer = nil
        serverURL = ""
        print("Web server stopped")
    }
    
    private func getLocalIPAddress() -> String {
        var address: String = "localhost"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
}

// MARK: - Benchmark Card Component
struct BenchmarkCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(MainViewModel())
    }
}
