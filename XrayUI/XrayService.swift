import Foundation

class XrayService {
    private var process: Process?
    private var logFileHandle: FileHandle?
    private(set) var isRunning: Bool = false
    private(set) var selectedConfigName: String = "config.json"
    private(set) var currentLogFileName: String?

    private let appSupportDirectory: URL = {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("com.daniel.xray-service")

        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        return appDirectory
    }()

    private var logsDirectory: URL {
        let logsDir = appSupportDirectory.appendingPathComponent("logs")
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        return logsDir
    }

    private var configsDirectory: URL {
        let configsDir = appSupportDirectory.appendingPathComponent("configs")
        if !FileManager.default.fileExists(atPath: configsDir.path) {
            try? FileManager.default.createDirectory(at: configsDir, withIntermediateDirectories: true)
        }
        return configsDir
    }

    private var selectedConfigPath: URL {
        return configsDirectory.appendingPathComponent(selectedConfigName)
    }

    private var binDirectory: URL {
        let binDir = appSupportDirectory.appendingPathComponent("bin")
        if !FileManager.default.fileExists(atPath: binDir.path) {
            try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        }
        return binDir
    }

    private var xrayBinaryPath: URL? {
        let path = binDirectory.appendingPathComponent("xray")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    var isXrayInstalled: Bool {
        return xrayBinaryPath != nil
    }

    var supportDirectory: URL {
        return appSupportDirectory
    }

    var configsDirectoryURL: URL {
        return configsDirectory
    }

    var logsDirectoryURL: URL {
        return logsDirectory
    }

    var currentLogPath: URL? {
        guard let handle = logFileHandle else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let files = listLogs()
        return files.first.map { logsDirectory.appendingPathComponent($0) }
    }

    func listLogs() -> [String] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: logsDirectory.path) else {
            return []
        }
        return files.filter { $0.hasSuffix(".log") }.sorted().reversed()
    }

    func logFilePath(for name: String) -> URL {
        return logsDirectory.appendingPathComponent(name)
    }

    private let selectedConfigKey = "selectedConfig"

    private var pidFilePath: URL {
        return appSupportDirectory.appendingPathComponent("xray.pid")
    }

    init() {
        cleanupOrphanedProcess()
        migrateOldConfig()
        loadSelectedConfig()
        ensureConfigExists()
    }

    private func cleanupOrphanedProcess() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pidFilePath.path),
              let pidString = try? String(contentsOf: pidFilePath, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        // Check if process is still running
        if kill(pid, 0) == 0 {
            // Process exists, kill it
            print("Cleaning up orphaned xray process (PID: \(pid))")
            kill(pid, SIGTERM)

            // Wait briefly for graceful shutdown, then force kill if needed
            usleep(500000) // 0.5 seconds
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }

        // Remove the stale PID file
        try? fileManager.removeItem(at: pidFilePath)
    }

    private func savePid(_ pid: Int32) {
        try? String(pid).write(to: pidFilePath, atomically: true, encoding: .utf8)
    }

    private func removePidFile() {
        try? FileManager.default.removeItem(at: pidFilePath)
    }

    private func migrateOldConfig() {
        let fileManager = FileManager.default
        let oldConfigPath = appSupportDirectory.appendingPathComponent("config.json")

        if fileManager.fileExists(atPath: oldConfigPath.path) {
            _ = configsDirectory
            let newConfigPath = configsDirectory.appendingPathComponent("config.json")
            if !fileManager.fileExists(atPath: newConfigPath.path) {
                try? fileManager.moveItem(at: oldConfigPath, to: newConfigPath)
            }
        }
    }

    private func loadSelectedConfig() {
        if let saved = UserDefaults.standard.string(forKey: selectedConfigKey) {
            selectedConfigName = saved
        }
    }

    private func saveSelectedConfig() {
        UserDefaults.standard.set(selectedConfigName, forKey: selectedConfigKey)
    }

    private func ensureConfigExists() {
        let configs = listConfigs()
        if configs.isEmpty {
            generateExampleConfig()
        }
        if !configs.contains(selectedConfigName) {
            if let first = listConfigs().first {
                selectedConfigName = first
                saveSelectedConfig()
            }
        }
    }

    func listConfigs() -> [String] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: configsDirectory.path) else {
            return []
        }
        return files.filter { $0.hasSuffix(".json") }.sorted()
    }

    func selectConfig(_ name: String) {
        guard listConfigs().contains(name) else { return }
        selectedConfigName = name
        saveSelectedConfig()

        if isRunning {
            stop()
            start()
        }
    }

    @discardableResult
    func generateExampleConfig() -> String {
        let fileManager = FileManager.default
        var baseName = "config"
        var fileName = "\(baseName).json"
        var counter = 1

        while fileManager.fileExists(atPath: configsDirectory.appendingPathComponent(fileName).path) {
            counter += 1
            fileName = "\(baseName)_\(counter).json"
        }

        let exampleConfig = """
        {
            "log": {
                "loglevel": "warning"
            },
            "inbounds": [],
            "outbounds": [
                {
                    "protocol": "freedom",
                    "tag": "direct"
                }
            ]
        }
        """

        let configPath = configsDirectory.appendingPathComponent(fileName)
        try? exampleConfig.write(to: configPath, atomically: true, encoding: .utf8)

        return fileName
    }

    private func createLogFile() -> FileHandle? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let logFileName = "xray_\(timestamp).log"
        let logFilePath = logsDirectory.appendingPathComponent(logFileName)

        FileManager.default.createFile(atPath: logFilePath.path, contents: nil)
        currentLogFileName = logFileName
        return try? FileHandle(forWritingTo: logFilePath)
    }

    func start() {
        guard !isRunning else { return }

        guard let binaryPath = xrayBinaryPath else {
            print("Error: xray binary not found in bundle")
            return
        }

        let process = Process()
        process.executableURL = binaryPath
        process.arguments = ["-c", selectedConfigPath.path]
        process.currentDirectoryURL = binaryPath.deletingLastPathComponent()

        logFileHandle = createLogFile()

        if let fileHandle = logFileHandle {
            process.standardOutput = fileHandle
            process.standardError = fileHandle
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.logFileHandle?.closeFile()
                self?.logFileHandle = nil
                self?.isRunning = false
                self?.removePidFile()
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            savePid(process.processIdentifier)
            print("Xray service started with config: \(selectedConfigPath.path)")
        } catch {
            print("Failed to start xray: \(error)")
            logFileHandle?.closeFile()
            logFileHandle = nil
        }
    }

    func stop() {
        guard isRunning, let process = process else { return }

        process.terminate()
        process.waitUntilExit()
        self.process = nil
        logFileHandle?.closeFile()
        logFileHandle = nil
        isRunning = false
        removePidFile()
        print("Xray service stopped")
    }
}
