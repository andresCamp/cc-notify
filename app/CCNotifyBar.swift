import AppKit
import Foundation

// MARK: - Models

struct CCSession {
    let sessionId: String
    let project: String
    let latestTitle: String
    let latestEvent: String
    let terminalKind: String
    let timestamp: Date
    let notificationCount: Int
}

// MARK: - App Delegate

class CCNotifyBar: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let logDir: String
    private let stateDir: String
    private var sessions: [CCSession] = []
    private var fileDescriptor: Int32 = -1
    private var dirSource: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?

    override init() {
        let home = NSHomeDirectory()
        logDir = (home as NSString).appendingPathComponent(".cc-notify/log")
        stateDir = (home as NSString).appendingPathComponent(".cc-notify/state")
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(count: 0)

        reload()
        watchLogDir()
    }

    // MARK: - Icon

    private func updateIcon(count: Int) {
        guard let button = statusItem.button else { return }
        let name = count > 0 ? "bell.badge.fill" : "bell"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: "CC Notify") {
            img.isTemplate = true
            button.image = img
        }
        button.title = count > 0 ? " \(count)" : ""
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated

            // Header
            let header = NSMenuItem(title: "Sessions", action: nil, keyEquivalent: "")
            header.isEnabled = false
            let headerAttr = NSAttributedString(string: "Sessions", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
            header.attributedTitle = headerAttr
            menu.addItem(header)

            for s in sessions {
                let ago = formatter.localizedString(for: s.timestamp, relativeTo: Date())

                let statusIcon: String
                switch s.latestEvent {
                case "Notification": statusIcon = "\u{1F7E1}"  // yellow circle - needs attention
                case "Stop":        statusIcon = "\u{1F7E2}"  // green circle - done
                default:            statusIcon = "\u{26AA}"    // white circle
                }

                let item = NSMenuItem(title: "", action: #selector(focusSession(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.sessionId

                let title = NSMutableAttributedString()

                // Status icon
                title.append(NSAttributedString(string: "\(statusIcon) ", attributes: [
                    .font: NSFont.systemFont(ofSize: 12)
                ]))

                // Project name
                title.append(NSAttributedString(string: s.project, attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
                ]))

                // Latest status
                title.append(NSAttributedString(string: "  \(s.latestTitle)", attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))

                // Time ago
                title.append(NSAttributedString(string: "  \(ago)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]))

                item.attributedTitle = title
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear All", action: #selector(clearAll), keyEquivalent: "k")
        clear.target = self
        clear.keyEquivalentModifierMask = [.command]
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit CC Notify", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc func focusSession(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? String else { return }

        // Read the state file for the terminal ID
        let stateFile = (stateDir as NSString).appendingPathComponent("\(sessionId).json")
        guard let data = FileManager.default.contents(atPath: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let terminalId = json["ghostty_terminal_id"] as? String,
              !terminalId.isEmpty
        else {
            // Fallback: just activate the terminal app
            if let app = jsonField(stateFile, key: "app") {
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId(for: app))
                if let url = url {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            }
            return
        }

        // Focus the exact Ghostty terminal via AppleScript
        let script = """
        tell application "Ghostty"
            activate
            set wList to every window
            repeat with w in wList
                try
                    set tList to every tab of w
                    repeat with tb in tList
                        try
                            set sList to every terminal of tb
                            repeat with t in sList
                                try
                                    if (id of t) is "\(terminalId)" then
                                        activate window w
                                        select tab tb
                                        focus t
                                        return "ok"
                                    end if
                                end try
                            end repeat
                        end try
                    end repeat
                end try
            end repeat
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
        }
    }

    @objc private func clearAll() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: logDir) {
            for f in files where f.hasSuffix(".json") {
                try? fm.removeItem(atPath: (logDir as NSString).appendingPathComponent(f))
            }
        }
        sessions.removeAll()
        updateIcon(count: 0)
        buildMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Load and deduplicate by session

    private func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: logDir) else {
            sessions = []
            updateIcon(count: 0)
            buildMenu()
            return
        }

        // Parse all log entries
        struct LogEntry {
            let sessionId: String
            let title: String
            let body: String
            let project: String
            let event: String
            let terminalKind: String
            let timestamp: Date
            let filename: String
        }

        let entries: [LogEntry] = files
            .filter { $0.hasSuffix(".json") }
            .compactMap { filename -> LogEntry? in
                let path = (logDir as NSString).appendingPathComponent(filename)
                guard let data = fm.contents(atPath: path),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessionId = json["session_id"] as? String,
                      let title = json["title"] as? String,
                      let body = json["body"] as? String,
                      let project = json["project"] as? String,
                      let event = json["event"] as? String,
                      let ts = json["ts"] as? Int
                else { return nil }

                return LogEntry(
                    sessionId: sessionId,
                    title: title,
                    body: body,
                    project: project,
                    event: event,
                    terminalKind: json["terminal_kind"] as? String ?? "",
                    timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                    filename: filename
                )
            }

        // Group by session, keep latest per session
        var sessionMap: [String: (latest: LogEntry, count: Int)] = [:]
        for entry in entries {
            if let existing = sessionMap[entry.sessionId] {
                let newer = entry.timestamp > existing.latest.timestamp ? entry : existing.latest
                sessionMap[entry.sessionId] = (latest: newer, count: existing.count + 1)
            } else {
                sessionMap[entry.sessionId] = (latest: entry, count: 1)
            }
        }

        sessions = sessionMap.values
            .map { pair in
                CCSession(
                    sessionId: pair.latest.sessionId,
                    project: pair.latest.project,
                    latestTitle: pair.latest.title,
                    latestEvent: pair.latest.event,
                    terminalKind: pair.latest.terminalKind,
                    timestamp: pair.latest.timestamp,
                    notificationCount: pair.count
                )
            }
            .sorted { $0.timestamp > $1.timestamp }

        // Prune old log entries: keep only logs from the last hour
        let cutoff = Date().addingTimeInterval(-3600)
        for entry in entries where entry.timestamp < cutoff {
            try? fm.removeItem(atPath: (logDir as NSString).appendingPathComponent(entry.filename))
        }

        updateIcon(count: sessions.count)
        buildMenu()
    }

    // MARK: - Directory watcher

    private func watchLogDir() {
        fileDescriptor = open(logDir, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        dirSource?.setEventHandler { [weak self] in
            self?.debounceWork?.cancel()
            let work = DispatchWorkItem { self?.reload() }
            self?.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        dirSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
        }

        dirSource?.resume()
    }

    // MARK: - Helpers

    private func jsonField(_ path: String, key: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val = json[key] as? String, !val.isEmpty
        else { return nil }
        return val
    }

    private func bundleId(for appName: String) -> String {
        switch appName {
        case "Ghostty":   return "com.mitchellh.ghostty"
        case "iTerm2":    return "com.googlecode.iterm2"
        case "Terminal":  return "com.apple.Terminal"
        case "WezTerm":   return "org.wezfurlong.wezterm"
        case "kitty":     return "net.kovidgoyal.kitty"
        case "Alacritty": return "org.alacritty"
        default:          return ""
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = CCNotifyBar()
app.delegate = delegate
app.run()
