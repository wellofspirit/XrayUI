import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, XrayUpdaterDelegate {
    private var statusItem: NSStatusItem!
    private var xrayService = XrayService()
    private var xrayUpdater: XrayUpdater!
    private var logViewerWindowController: LogViewerWindowController?
    private var updateStatus: String = "Initializing..."
    private var isUpdating: Bool = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        xrayUpdater = XrayUpdater(appSupportDirectory: xrayService.supportDirectory)
        xrayUpdater.delegate = self

        checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        xrayService.stop()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "XrayUI")
            button.image?.isTemplate = true
        }

        updateMenu()
    }

    private func checkForUpdates() {
        isUpdating = true
        updateMenu()

        xrayUpdater.checkAndUpdate { [weak self] success, error in
            self?.isUpdating = false
            self?.updateMenu()

            if !success, let error = error {
                self?.showAlert(title: "Xray Download Failed", message: error)
            }
        }
    }

    // MARK: - XrayUpdaterDelegate

    func xrayUpdater(_ updater: XrayUpdater, didUpdateStatus status: String) {
        updateStatus = status
        updateMenu()
    }

    func xrayUpdater(_ updater: XrayUpdater, didFinishWithSuccess success: Bool, error: String?) {
        isUpdating = false
        updateMenu()
    }

    // MARK: - Menu

    private func updateMenu() {
        let menu = NSMenu()

        // Update status (shown when updating)
        if isUpdating {
            let updateItem = NSMenuItem(title: updateStatus, action: nil, keyEquivalent: "")
            updateItem.isEnabled = false
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Service status
        let statusText: String
        if !xrayService.isXrayInstalled {
            statusText = "✕ Xray not installed"
        } else if xrayService.isRunning {
            statusText = "● Running"
        } else {
            statusText = "○ Stopped"
        }

        let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let startItem = NSMenuItem(title: "Start Service", action: #selector(startService), keyEquivalent: "s")
        startItem.target = self
        startItem.isEnabled = xrayService.isXrayInstalled && !xrayService.isRunning && !isUpdating
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Service", action: #selector(stopService), keyEquivalent: "x")
        stopItem.target = self
        stopItem.isEnabled = xrayService.isRunning
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let configsItem = NSMenuItem(title: "Configs", action: nil, keyEquivalent: "")
        configsItem.submenu = buildConfigsSubmenu()
        menu.addItem(configsItem)

        let logsItem = NSMenuItem(title: "Logs", action: nil, keyEquivalent: "")
        logsItem.submenu = buildLogsSubmenu()
        menu.addItem(logsItem)

        menu.addItem(NSMenuItem.separator())

        let checkUpdateItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdatesAction), keyEquivalent: "u")
        checkUpdateItem.target = self
        checkUpdateItem.isEnabled = !isUpdating
        menu.addItem(checkUpdateItem)

        menu.addItem(NSMenuItem.separator())

        let exitItem = NSMenuItem(title: "Exit", action: #selector(exitApp), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)

        statusItem.menu = menu
    }

    private func buildConfigsSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let configs = xrayService.listConfigs()
        for config in configs {
            let item = NSMenuItem(title: config, action: #selector(selectConfig(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = config
            if config == xrayService.selectedConfigName {
                item.state = .on
            }
            submenu.addItem(item)
        }

        if !configs.isEmpty {
            submenu.addItem(NSMenuItem.separator())
        }

        let generateItem = NSMenuItem(title: "Generate Example Config", action: #selector(generateConfig), keyEquivalent: "")
        generateItem.target = self
        submenu.addItem(generateItem)

        submenu.addItem(NSMenuItem.separator())

        let openConfigsItem = NSMenuItem(title: "Open Configs in Finder", action: #selector(openConfigsFolder), keyEquivalent: "")
        openConfigsItem.target = self
        submenu.addItem(openConfigsItem)

        return submenu
    }

    private func buildLogsSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let viewLogsItem = NSMenuItem(title: "View Logs", action: #selector(openLogViewer), keyEquivalent: "l")
        viewLogsItem.target = self
        submenu.addItem(viewLogsItem)

        let openLogsItem = NSMenuItem(title: "Open Logs in Finder", action: #selector(openLogsFolder), keyEquivalent: "")
        openLogsItem.target = self
        submenu.addItem(openLogsItem)

        return submenu
    }

    // MARK: - Actions

    @objc private func selectConfig(_ sender: NSMenuItem) {
        guard let configName = sender.representedObject as? String else { return }
        xrayService.selectConfig(configName)
        updateMenu()
        updateStatusIcon()
    }

    @objc private func generateConfig() {
        xrayService.generateExampleConfig()
        updateMenu()
    }

    @objc private func startService() {
        xrayService.start()
        updateMenu()
        updateStatusIcon()
    }

    @objc private func stopService() {
        xrayService.stop()
        updateMenu()
        updateStatusIcon()
    }

    @objc private func openConfigsFolder() {
        NSWorkspace.shared.open(xrayService.configsDirectoryURL)
    }

    @objc private func openLogsFolder() {
        NSWorkspace.shared.open(xrayService.logsDirectoryURL)
    }

    @objc private func openLogViewer() {
        if logViewerWindowController == nil {
            logViewerWindowController = LogViewerWindowController(xrayService: xrayService)
        }
        logViewerWindowController?.showWindow(nil)
        logViewerWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdatesAction() {
        checkForUpdates()
    }

    @objc private func exitApp() {
        xrayService.stop()
        NSApplication.shared.terminate(nil)
    }

    private func updateStatusIcon() {
        if let button = statusItem.button {
            let symbolName = xrayService.isRunning ? "network.badge.shield.half.filled" : "network"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "XrayUI")
            button.image?.isTemplate = true
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
