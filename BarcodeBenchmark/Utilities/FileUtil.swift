import Foundation

/// Utility class for file operations
class FileUtil {
    
    /// Read contents of a file from the app bundle
    static func readBundleFile(named fileName: String, withExtension ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: ext) else {
            return nil
        }
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Error reading file \(fileName).\(ext): \(error)")
            return nil
        }
    }
    
    /// Get file name from URL
    static func getFileName(from url: URL) -> String {
        return url.lastPathComponent
    }
    
    /// Get file size in bytes
    static func getFileSize(at url: URL) -> Int64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            print("Error getting file size: \(error)")
            return nil
        }
    }
    
    /// Format file size to human readable string
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Get documents directory URL
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Get temporary directory URL
    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory
    }
    
    /// Create a unique temporary file URL
    static func createTemporaryFileURL(withExtension ext: String) -> URL {
        let fileName = UUID().uuidString
        return temporaryDirectory.appendingPathComponent(fileName).appendingPathExtension(ext)
    }
    
    /// Delete file at URL
    static func deleteFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Error deleting file: \(error)")
        }
    }
    
    /// Check if file exists
    static func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
}
