import SwiftUI
import AppKit

struct LogViewerWindow: View {
    let xrayService: XrayService
    @State private var selectedLog: String? = "Current"
    @State private var logContent: String = ""
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var logFiles: [String] = []
    @State private var fileMonitor: DispatchSourceFileSystemObject?
    @State private var refreshTimer: Timer?

    private var allLogItems: [String] {
        ["Current"] + logFiles
    }

    var body: some View {
        HSplitView {
            // Left sidebar - log file list
            VStack(alignment: .leading, spacing: 0) {
                List(allLogItems, id: \.self, selection: $selectedLog) { item in
                    if item == "Current" {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Current")
                                .fontWeight(selectedLog == "Current" ? .semibold : .regular)
                        }
                        .tag(item as String?)
                    } else {
                        Text(item)
                            .tag(item as String?)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, maxWidth: 250)

            // Right pane - log content
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Log content
                LogContentView(content: filteredContent, autoScroll: $autoScroll, isCurrentLog: selectedLog == "Current")

                Divider()

                // Bottom bar with auto-scroll toggle
                HStack {
                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.checkbox)
                        .disabled(selectedLog != "Current")
                    Spacer()
                    Text(selectedLog == "Current" ? "Viewing live logs" : (selectedLog ?? ""))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            refreshLogFiles()
            loadSelectedLog()
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
        .onChange(of: selectedLog) { _ in
            loadSelectedLog()
        }
    }

    private var filteredContent: String {
        guard !searchText.isEmpty else { return logContent }
        let lines = logContent.components(separatedBy: .newlines)
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
        return filtered.joined(separator: "\n")
    }

    private func refreshLogFiles() {
        logFiles = xrayService.listLogs()
    }

    private func loadSelectedLog() {
        guard let selected = selectedLog else {
            logContent = ""
            return
        }

        if selected == "Current" {
            if let currentFileName = xrayService.currentLogFileName {
                let path = xrayService.logFilePath(for: currentFileName)
                logContent = (try? String(contentsOf: path, encoding: .utf8)) ?? "No current log available"
            } else {
                logContent = "Service not running. No current log."
            }
        } else {
            let path = xrayService.logFilePath(for: selected)
            logContent = (try? String(contentsOf: path, encoding: .utf8)) ?? "Unable to read log file"
        }
    }

    private func startMonitoring() {
        // Poll for updates when viewing current log
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if selectedLog == "Current" {
                loadSelectedLog()
            }
            refreshLogFiles()
        }
    }

    private func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

struct LogContentView: NSViewRepresentable {
    let content: String
    @Binding var autoScroll: Bool
    let isCurrentLog: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let previousLength = textView.string.count
        textView.string = content

        // Auto-scroll to bottom if enabled and content changed
        if autoScroll && isCurrentLog && content.count > previousLength {
            textView.scrollToEndOfDocument(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var textView: NSTextView?
        var scrollView: NSScrollView?
    }
}

class LogViewerWindowController: NSWindowController {
    convenience init(xrayService: XrayService) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Log Viewer"
        window.contentView = NSHostingView(rootView: LogViewerWindow(xrayService: xrayService))
        window.center()

        self.init(window: window)
    }
}
