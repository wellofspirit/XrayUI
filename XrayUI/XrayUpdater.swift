import Foundation
import AppKit

protocol XrayUpdaterDelegate: AnyObject {
    func xrayUpdater(_ updater: XrayUpdater, didUpdateStatus status: String)
    func xrayUpdater(_ updater: XrayUpdater, didFinishWithSuccess success: Bool, error: String?)
}

class XrayUpdater {
    weak var delegate: XrayUpdaterDelegate?

    private let appSupportDirectory: URL
    private let binDirectory: URL
    private let versionFile: URL

    private let githubAPIURL = "https://api.github.com/repos/XTLS/Xray-core/releases/latest"

    init(appSupportDirectory: URL) {
        self.appSupportDirectory = appSupportDirectory
        self.binDirectory = appSupportDirectory.appendingPathComponent("bin")
        self.versionFile = appSupportDirectory.appendingPathComponent("xray-version")

        // Ensure bin directory exists
        try? FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    }

    var xrayBinaryPath: URL {
        return binDirectory.appendingPathComponent("xray")
    }

    var isXrayInstalled: Bool {
        return FileManager.default.fileExists(atPath: xrayBinaryPath.path)
    }

    var installedVersion: String? {
        guard let version = try? String(contentsOf: versionFile, encoding: .utf8) else {
            return nil
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveInstalledVersion(_ version: String) {
        try? version.write(to: versionFile, atomically: true, encoding: .utf8)
    }

    func checkAndUpdate(completion: @escaping (Bool, String?) -> Void) {
        delegate?.xrayUpdater(self, didUpdateStatus: "Checking for updates...")

        fetchLatestRelease { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let release):
                let latestVersion = release.tagName

                if self.isXrayInstalled, let installed = self.installedVersion, installed == latestVersion {
                    DispatchQueue.main.async {
                        self.delegate?.xrayUpdater(self, didUpdateStatus: "Xray is up to date (\(latestVersion))")
                        self.delegate?.xrayUpdater(self, didFinishWithSuccess: true, error: nil)
                        completion(true, nil)
                    }
                    return
                }

                // Need to download
                let statusMsg = self.isXrayInstalled ? "Updating to \(latestVersion)..." : "Downloading \(latestVersion)..."
                DispatchQueue.main.async {
                    self.delegate?.xrayUpdater(self, didUpdateStatus: statusMsg)
                }

                self.downloadAndInstall(release: release) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            self.saveInstalledVersion(latestVersion)
                            self.delegate?.xrayUpdater(self, didUpdateStatus: "Xray \(latestVersion) ready")
                        }
                        self.delegate?.xrayUpdater(self, didFinishWithSuccess: success, error: error)
                        completion(success, error)
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    // If we have an existing installation, continue with it
                    if self.isXrayInstalled {
                        self.delegate?.xrayUpdater(self, didUpdateStatus: "Using existing installation")
                        self.delegate?.xrayUpdater(self, didFinishWithSuccess: true, error: nil)
                        completion(true, nil)
                    } else {
                        self.delegate?.xrayUpdater(self, didFinishWithSuccess: false, error: error.localizedDescription)
                        completion(false, error.localizedDescription)
                    }
                }
            }
        }
    }

    private func fetchLatestRelease(completion: @escaping (Result<GitHubRelease, Error>) -> Void) {
        guard let url = URL(string: githubAPIURL) else {
            completion(.failure(NSError(domain: "XrayUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("XrayUI/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "XrayUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                completion(.success(release))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func downloadAndInstall(release: GitHubRelease, completion: @escaping (Bool, String?) -> Void) {
        // Determine the correct asset for this platform
        let arch = getArchitecture()
        let assetName = "Xray-macos-\(arch).zip"

        guard let asset = release.assets.first(where: { $0.name == assetName }) else {
            completion(false, "No compatible binary found for macOS \(arch)")
            return
        }

        guard let downloadURL = URL(string: asset.browserDownloadUrl) else {
            completion(false, "Invalid download URL")
            return
        }

        DispatchQueue.main.async {
            self.delegate?.xrayUpdater(self, didUpdateStatus: "Downloading \(assetName)...")
        }

        // Download the zip file
        let downloadTask = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(false, "Download failed: \(error.localizedDescription)")
                return
            }

            guard let tempURL = tempURL else {
                completion(false, "Download failed: No file received")
                return
            }

            DispatchQueue.main.async {
                self.delegate?.xrayUpdater(self, didUpdateStatus: "Installing...")
            }

            // Extract and install
            self.extractAndInstall(zipURL: tempURL, completion: completion)
        }

        downloadTask.resume()
    }

    private func extractAndInstall(zipURL: URL, completion: @escaping (Bool, String?) -> Void) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            // Create temp directory
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Unzip using ditto (built-in macOS tool)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", zipURL.path, tempDir.path]

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(domain: "XrayUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract archive"])
            }

            // Find and copy the xray binary
            let extractedXray = tempDir.appendingPathComponent("xray")
            guard fileManager.fileExists(atPath: extractedXray.path) else {
                throw NSError(domain: "XrayUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "xray binary not found in archive"])
            }

            // Remove old binary if exists
            if fileManager.fileExists(atPath: xrayBinaryPath.path) {
                try fileManager.removeItem(at: xrayBinaryPath)
            }

            // Copy new binary
            try fileManager.copyItem(at: extractedXray, to: xrayBinaryPath)

            // Make executable
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xrayBinaryPath.path)

            // Also copy geoip.dat and geosite.dat if present
            let geoipSource = tempDir.appendingPathComponent("geoip.dat")
            let geositeSource = tempDir.appendingPathComponent("geosite.dat")
            let geoipDest = binDirectory.appendingPathComponent("geoip.dat")
            let geositeDest = binDirectory.appendingPathComponent("geosite.dat")

            if fileManager.fileExists(atPath: geoipSource.path) {
                try? fileManager.removeItem(at: geoipDest)
                try fileManager.copyItem(at: geoipSource, to: geoipDest)
            }

            if fileManager.fileExists(atPath: geositeSource.path) {
                try? fileManager.removeItem(at: geositeDest)
                try fileManager.copyItem(at: geositeSource, to: geositeDest)
            }

            // Cleanup temp directory
            try? fileManager.removeItem(at: tempDir)

            completion(true, nil)

        } catch {
            // Cleanup on failure
            try? fileManager.removeItem(at: tempDir)
            completion(false, "Installation failed: \(error.localizedDescription)")
        }
    }

    private func getArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        if machine.contains("arm64") {
            return "arm64-v8a"
        } else {
            return "64"
        }
    }
}

// MARK: - GitHub API Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}
