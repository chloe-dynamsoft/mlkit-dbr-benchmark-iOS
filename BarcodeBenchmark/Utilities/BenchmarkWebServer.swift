import Foundation
import Network

/// A simple HTTP web server for benchmarking via browser
class BenchmarkWebServer {
    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.barcodebenchmark.webserver")
    
    init(port: UInt16 = 8080) {
        self.port = port
    }
    
    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Web server ready on port \(self?.port ?? 0)")
                case .failed(let error):
                    print("Web server failed: \(error)")
                case .cancelled:
                    print("Web server cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
        } catch {
            print("Failed to start web server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receiveRequest(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if let data = content, let request = String(data: data, encoding: .utf8) {
                self?.handleRequest(request, on: connection)
            }
            
            if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func handleRequest(_ request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendNotFound(on: connection)
            return
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            sendNotFound(on: connection)
            return
        }
        
        let method = components[0]
        let path = components[1]
        
        print("[\(method)] \(path)")
        
        switch path {
        case "/", "/index.html":
            sendHTML(getIndexHTML(), on: connection)
        case "/styles.css":
            sendCSS(getStylesCSS(), on: connection)
        case "/app.js":
            sendJS(getAppJS(), on: connection)
        case "/api/status":
            sendJSON("{\"status\":\"running\",\"dynamsoft\":true,\"mlkit\":true}", on: connection)
        default:
            sendNotFound(on: connection)
        }
    }
    
    private func sendHTML(_ content: String, on connection: NWConnection) {
        sendResponse(content, contentType: "text/html", on: connection)
    }
    
    private func sendCSS(_ content: String, on connection: NWConnection) {
        sendResponse(content, contentType: "text/css", on: connection)
    }
    
    private func sendJS(_ content: String, on connection: NWConnection) {
        sendResponse(content, contentType: "application/javascript", on: connection)
    }
    
    private func sendJSON(_ content: String, on connection: NWConnection) {
        sendResponse(content, contentType: "application/json", on: connection)
    }
    
    private func sendNotFound(on connection: NWConnection) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendResponse(_ content: String, contentType: String, on connection: NWConnection) {
        let data = content.data(using: .utf8) ?? Data()
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType); charset=utf-8\r
        Content-Length: \(data.count)\r
        Access-Control-Allow-Origin: *\r
        \r
        
        """
        
        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(data)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // MARK: - HTML Content
    
    private func getIndexHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Barcode Benchmark</title>
            <link rel="stylesheet" href="styles.css">
        </head>
        <body>
            <div class="container">
                <h1>🔍 Barcode Benchmark</h1>
                <p class="subtitle">Upload an image or video to compare Dynamsoft vs MLKit barcode scanning</p>
                
                <div class="upload-section">
                    <label for="fileInput" class="upload-btn">
                        📁 Select File
                    </label>
                    <input type="file" id="fileInput" accept="image/*,video/*" hidden>
                    <p id="fileName" class="file-name">No file selected</p>
                </div>
                
                <button id="benchmarkBtn" class="benchmark-btn" disabled>
                    ▶️ Run Benchmark
                </button>
                
                <div id="results" class="results hidden">
                    <h2>Results</h2>
                    <div class="result-grid">
                        <div class="result-card dynamsoft">
                            <h3>Dynamsoft</h3>
                            <p class="time" id="dynamsoftTime">-</p>
                            <p class="count" id="dynamsoftCount">0 barcodes</p>
                        </div>
                        <div class="result-card mlkit">
                            <h3>MLKit</h3>
                            <p class="time" id="mlkitTime">-</p>
                            <p class="count" id="mlkitCount">0 barcodes</p>
                        </div>
                    </div>
                </div>
            </div>
            
            <script src="app.js"></script>
        </body>
        </html>
        """
    }
    
    private func getStylesCSS() -> String {
        return """
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
        }
        
        h1 {
            text-align: center;
            margin-bottom: 10px;
            color: #333;
        }
        
        .subtitle {
            text-align: center;
            color: #666;
            margin-bottom: 30px;
        }
        
        .upload-section {
            text-align: center;
            margin-bottom: 20px;
        }
        
        .upload-btn {
            display: inline-block;
            padding: 15px 30px;
            background: #1976D2;
            color: white;
            border-radius: 10px;
            cursor: pointer;
            font-size: 16px;
            transition: background 0.3s;
        }
        
        .upload-btn:hover {
            background: #1565C0;
        }
        
        .file-name {
            margin-top: 10px;
            color: #888;
        }
        
        .benchmark-btn {
            width: 100%;
            padding: 15px;
            background: #673AB7;
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 18px;
            cursor: pointer;
            transition: background 0.3s;
        }
        
        .benchmark-btn:hover:not(:disabled) {
            background: #5E35B1;
        }
        
        .benchmark-btn:disabled {
            background: #ccc;
            cursor: not-allowed;
        }
        
        .results {
            margin-top: 30px;
        }
        
        .results.hidden {
            display: none;
        }
        
        .result-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            margin-top: 20px;
        }
        
        .result-card {
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        
        .result-card.dynamsoft {
            background: #E3F2FD;
            border: 2px solid #1976D2;
        }
        
        .result-card.mlkit {
            background: #E8F5E9;
            border: 2px solid #4CAF50;
        }
        
        .result-card h3 {
            margin-bottom: 10px;
        }
        
        .result-card .time {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .result-card.dynamsoft .time {
            color: #1976D2;
        }
        
        .result-card.mlkit .time {
            color: #4CAF50;
        }
        """
    }
    
    private func getAppJS() -> String {
        return """
        document.addEventListener('DOMContentLoaded', function() {
            const fileInput = document.getElementById('fileInput');
            const fileName = document.getElementById('fileName');
            const benchmarkBtn = document.getElementById('benchmarkBtn');
            const results = document.getElementById('results');
            
            fileInput.addEventListener('change', function(e) {
                if (e.target.files.length > 0) {
                    fileName.textContent = e.target.files[0].name;
                    benchmarkBtn.disabled = false;
                }
            });
            
            benchmarkBtn.addEventListener('click', async function() {
                const file = fileInput.files[0];
                if (!file) return;
                
                benchmarkBtn.disabled = true;
                benchmarkBtn.textContent = '⏳ Processing...';
                
                // Simulate benchmark results (in real implementation, this would upload to the device)
                setTimeout(function() {
                    document.getElementById('dynamsoftTime').textContent = '125 ms';
                    document.getElementById('dynamsoftCount').textContent = '3 barcodes';
                    document.getElementById('mlkitTime').textContent = '180 ms';
                    document.getElementById('mlkitCount').textContent = '2 barcodes';
                    
                    results.classList.remove('hidden');
                    benchmarkBtn.disabled = false;
                    benchmarkBtn.textContent = '▶️ Run Benchmark';
                }, 2000);
            });
        });
        """
    }
}
