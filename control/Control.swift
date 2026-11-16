import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────
// Pithagoras control — a menu-bar icon to start/stop the stack
// and flip voice, without a terminal and without killing an
// in-flight task. Backed by scripts/assistant.sh.
// ─────────────────────────────────────────────────────────────────────

// Read script path from env var or use a sensible default relative to the repo root
let scriptPath = ProcessInfo.processInfo.environment["LIFECYCLE_SCRIPT"]
    ?? ("/Users/" + NSUserName()) + "/Documents/New Project/pithagoras/scripts/assistant.sh"
let script = scriptPath

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var header: NSMenuItem!
    private var timer: Timer?
    // One live status row per service; refreshed on each tick.
    private var serviceRows: [(key: String, base: String, item: NSMenuItem)] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Pithagoras")
            btn.image?.isTemplate = true
        }

        let menu = NSMenu()

        header = NSMenuItem(title: "loading…", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Live per-service status: one row each, so you can see what's on/off.
        let section = NSMenuItem(title: "──  Services  ──", action: nil, keyEquivalent: "")
        section.isEnabled = false
        menu.addItem(section)
        for (key, icon, name) in [
            ("portal", "🌐", "Portal"),
            ("ollama", "🧠", "Ollama"),
            ("omni",   "🔀", "OmniRoute"),
            ("voice",  "🎤", "Voice"),
            ("docker", "🐳", "Docker"),
        ] {
            let base = "\(icon)  \(name)"
            let item = NSMenuItem(title: base, action: nil, keyEquivalent: "")
            item.isEnabled = false
            serviceRows.append((key, base, item))
            menu.addItem(item)
        }

        menu.addItem(.separator())

        menu.addItem(action("▶  Start Pithagoras", "login"))
        menu.addItem(action("⏻  Stop Pithagoras", "logout"))
        menu.addItem(.separator())
        menu.addItem(action("🎤  Voice ON", "voice on"))
        menu.addItem(action("🔇  Voice OFF", "voice off"))
        menu.addItem(.separator())
        menu.addItem(action("↻  Refresh status", ""))
        menu.addItem(.separator())
        menu.addItem(action("Quit control", "quit"))

        statusItem.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func action(_ title: String, _ cmd: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(onAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = cmd
        return item
    }

    @objc private func onAction(_ sender: NSMenuItem) {
        let cmd = sender.representedObject as? String ?? ""
        if cmd == "quit" { NSApp.terminate(nil); return }
        if cmd == "" { refresh(); return }   // refresh only
        run(cmd.split(separator: " ").map(String.init))
        refresh()
    }

    private func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script] + args
        p.terminationHandler = { _ in DispatchQueue.main.async { self.refresh() } }
        try? p.run()
    }

    private func refresh() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, "status-compact"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "…"
        if header == nil { return }
        header.title = "  \(line)"
        // Light green dot when the core is up, amber when it's down.
        let up = line.contains("portal ●") && line.contains("ollama ●")
        if let btn = statusItem.button {
            btn.title = up ? " ◉" : " ○"
        }

        // Refresh the per-service rows from the same compact line: green ● when
        // a service is up, grey ○ when it's down.
        for row in serviceRows {
            let on = line.contains("\(row.key) ●")
            row.item.attributedTitle = serviceAttr(row.base, on: on)
        }
    }

    // A service row title: green when up, secondary grey when down.
    private func serviceAttr(_ base: String, on: Bool) -> NSAttributedString {
        let dot = on ? "●" : "○"
        return NSAttributedString(
            string: "\(dot)  \(base)",
            attributes: [.foregroundColor: on ? NSColor.systemGreen : NSColor.secondaryLabelColor,
                         .font: NSFont.menuFont(ofSize: 0)]
        )
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
