import AppKit
import DesignArt
import DesignEngine

@MainActor
final class LivePreview: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let seed: UInt64 = 136
    private let canvas = NSView()
    private let systems = NSPopUpButton(frame: .zero, pullsDown: true)
    private let palettes = NSPopUpButton(frame: .zero, pullsDown: false)
    private let renderer = DesignRenderer()
    private var style = DesignStyle()
    private var playback = Playback(Exploration(seed: LivePreview.seed))
    private var selectedSystem: NSMenuItem?
    private var window: NSWindow?
    private var timer: Timer?
    private var lastUpdate = 0.0

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let preview = LivePreview()
        app.delegate = preview
        withExtendedLifetime(preview) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let size = CGSize(width: min(1152, available.width * 0.9), height: min(720, available.height * 0.85))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        self.window = window
        window.title = "System Design Preview"
        window.delegate = self
        window.isReleasedWhenClosed = false

        configurePickers()
        let controls = NSStackView(views: [NSTextField(labelWithString: "System"), systems,
                                           NSTextField(labelWithString: "Palette"), palettes])
        controls.setCustomSpacing(20, after: systems)
        let content = NSView()
        window.contentView = content
        canvas.wantsLayer = true
        canvas.layer?.addSublayer(renderer.root)
        for view in [controls, canvas] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            canvas.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 10),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.contentMinSize = CGSize(width: controls.fittingSize.width + 32, height: 280)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateVisibility()
    }

    private func configurePickers() {
        let catalogue = Catalogue.bundled
        let menu = NSMenu()
        // AppKit reserves the first item in a pull-down for the button's title.
        menu.addItem(withTitle: "Entire catalogue", action: nil, keyEquivalent: "")
        func addSystem(_ title: String, id: String, to menu: NSMenu) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: #selector(selectSystem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            return item
        }
        selectedSystem = addSystem("Entire catalogue", id: "all", to: menu)
        selectedSystem?.state = .on
        menu.addItem(.separator())
        for subject in Subject.allCases {
            let group = NSMenu(title: subject.title)
            for graph in catalogue.candidates(subject.rawValue).sorted(by: { $0.name < $1.name }) {
                _ = addSystem(graph.name, id: graph.id, to: group)
            }
            menu.addItem(withTitle: subject.title, action: nil, keyEquivalent: "").submenu = group
        }
        systems.menu = menu
        systems.setAccessibilityLabel("System")
        // Reserve the longest title so switching diagrams keeps the controls in place.
        let font = systems.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let titleWidth = catalogue.graphs.map { ($0.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        systems.widthAnchor.constraint(equalToConstant: ceil(titleWidth) + 42).isActive = true

        for colour in Colour.allCases {
            palettes.addItem(withTitle: colour.title)
            palettes.lastItem?.representedObject = colour.rawValue
        }
        palettes.selectItem(withTitle: style.colour.title)
        palettes.target = self
        palettes.action = #selector(selectPalette(_:))
        palettes.setAccessibilityLabel("Palette")
    }

    @objc private func selectSystem(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, id != playback.exploration.scope else { return }
        selectedSystem?.state = .off
        selectedSystem = item
        item.state = .on
        systems.item(at: 0)?.title = item.title
        systems.synchronizeTitleAndSelectedItem()
        playback = Playback(Exploration(seed: Self.seed, scope: id))
        lastUpdate = ProcessInfo.processInfo.systemUptime
        updateVisibility()
        render()
    }

    @objc private func selectPalette(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String, let colour = Colour(rawValue: id) else { return }
        style.colour = colour
        render()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }

    private func updateVisibility() {
        let visible = window?.occlusionState.contains(.visible) == true
        playback.present(visible: visible, animated: visible)
        guard visible else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        lastUpdate = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / Double(Exploration.ticksPerSecond), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        render()
    }

    private func advance() {
        let now = ProcessInfo.processInfo.systemUptime
        playback.advance(elapsed: now - lastUpdate)
        lastUpdate = now
        render()
    }

    private func render() {
        guard let window, !canvas.bounds.isEmpty else { return }
        renderer.draw(playback.exploration, size: canvas.bounds.size, scale: window.backingScaleFactor, style: style,
                      systemDark: canvas.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    func windowWillClose(_ notification: Notification) { timer?.invalidate() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
