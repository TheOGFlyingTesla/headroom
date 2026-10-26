import AppKit
import SwiftUI
import Combine
import HeadroomCore
import ServiceManagement

@main
struct HeadroomMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--enable-login") || CommandLine.arguments.contains("--login-status") {
            do {
                if CommandLine.arguments.contains("--enable-login"), SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                switch SMAppService.mainApp.status {
                case .enabled: print("Launch at login: enabled")
                case .requiresApproval:
                    fputs("Launch at login requires approval in System Settings > General > Login Items.\n", stderr)
                    exit(2)
                case .notRegistered: print("Launch at login: not registered"); exit(1)
                case .notFound: print("Launch at login: application not found"); exit(1)
                @unknown default: print("Launch at login: unknown status"); exit(1)
                }
            } catch {
                fputs("Login registration failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--probe") {
            Task { @MainActor in
            let client = CodexClient()
            do {
                let disk = try DiskReading.read()
                let quota = try await client.readWeekly()
                print("Disk available: \(disk.formatted)")
                print("Codex weekly remaining: \(Int(quota.remaining))%")
                print("Weekly duration: \(quota.windowDurationMins ?? 0) minutes")
                client.stop()
            } catch {
                client.stop()
                fputs("Probe failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            exit(0)
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let monitor = Monitor()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panel: NSPanel?
    private var previewWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSignal?.setEventHandler { NSApp.terminate(nil) }
        terminationSignal?.resume()
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Headroom")
        let showItem = NSMenuItem(title: "Show Headroom", action: #selector(togglePopover), keyEquivalent: "h")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        showItem.target = self
        appMenu.addItem(showItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Headroom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let symbol = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Headroom")
        symbol?.isTemplate = true
        statusItem.button?.image = symbol
        statusItem.button?.imagePosition = .imageLeading
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: card(floating: false))
        monitor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.monitor.sleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.monitor.wake() }
        })
        workspaceObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.keepPanelOnScreen() }
        })
        monitor.start()
        updateStatus()
        if CommandLine.arguments.contains("--show") {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 330),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Headroom Preview"
            window.contentViewController = NSHostingController(rootView: card(floating: false))
            window.center()
            window.isReleasedWhenClosed = false
            previewWindow = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func card(floating: Bool) -> CardView {
        CardView(monitor: monitor, isFloating: floating,
                 toggleFloating: { [weak self] in self?.toggleFloating() },
                 quit: { NSApp.terminate(nil) })
    }

    private func updateStatus() {
        let disk = monitor.diskError == nil ? (monitor.disk?.formatted ?? "—") : "—"
        let weekly = monitor.weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—"
        let marker = monitor.stale ? " · !" : ""
        statusItem.button?.title = monitor.showNumbers ? "  \(disk)  ·  \(weekly)\(marker)" : ""
        statusItem.button?.toolTip = "Disk: \(disk) available\nCodex: \(weekly) weekly remaining\(monitor.stale ? " (out of date)" : "")"
        statusItem.button?.setAccessibilityLabel("Headroom. Disk \(disk) available. Codex \(weekly) weekly remaining\(monitor.stale ? ", out of date" : "").")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            monitor.opened()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func toggleFloating() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            monitor.floating = false
            return
        }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 175),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Headroom"
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(rootView: card(floating: true))
            panel.setFrameAutosaveName("HeadroomFloatingPanel")
            if !panel.setFrameUsingName("HeadroomFloatingPanel") { panel.center() }
            panel.delegate = self
            self.panel = panel
        }
        keepPanelOnScreen()
        panel?.orderFrontRegardless()
        monitor.floating = true
        popover.performClose(nil)
    }

    private func keepPanelOnScreen() {
        guard let panel, !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }),
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let rect = screen.visibleFrame
        let x = min(max(panel.frame.minX, rect.minX), rect.maxX - panel.frame.width)
        let y = min(max(panel.frame.minY, rect.minY), rect.maxY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowDidMove(_ notification: Notification) { panel?.saveFrame(usingName: "HeadroomFloatingPanel") }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
