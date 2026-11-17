import AppKit
import QuartzCore

@MainActor
public final class LifeView: NSView {
    public enum Playback {
        case continuous
        case settleOnReveal
    }

    public var playback: Playback = .continuous {
        didSet {
            guard oldValue != playback else { return }
            stopClock()
            needsSettle = true
            settleDelays = []
            updateClock()
        }
    }

    public var settings: LifeSettings {
        didSet {
            guard oldValue != settings else { return }
            rebuild()
            if oldValue.paused != settings.paused {
                updateClock()
            } else if oldValue.speed != settings.speed && playback == .continuous {
                stopClock()
                updateClock()
            }
        }
    }

    public var playbackEnabled = true {
        didSet { updateClock() }
    }

    public var branding: LifeBranding {
        didSet {
            if oldValue != branding { art.brandingArtwork = LifeBrandingArtwork(branding) }
        }
    }

    private let previewScale: CGFloat
    private let tracksWindowOcclusion: Bool
    private let art = LifeLayers()
    private var scene: LifeScene?
    private var clock: Timer?
    private var needsSettle = true
    private var settleDelays: ArraySlice<TimeInterval> = []
    private var displaysAwake = true
    private var sessionActive = true

    public init(frame: CGRect, settings: LifeSettings, branding: LifeBranding = LifeBranding(), previewScale: CGFloat = 1,
                tracksWindowOcclusion: Bool = true) {
        self.settings = settings
        self.branding = branding
        self.previewScale = previewScale
        self.tracksWindowOcclusion = tracksWindowOcclusion
        super.init(frame: frame)
        wantsLayer = true
        layer = art.root
        art.brandingArtwork = LifeBrandingArtwork(branding)
        NotificationCenter.default.addObserver(self, selector: #selector(systemColorsChanged(_:)),
                                               name: NSColor.systemColorsDidChangeNotification, object: nil)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(suspendDisplays(_:)),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wakeDisplays(_:)),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(suspendDisplays(_:)),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wakeDisplays(_:)),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(suspendSession(_:)),
                              name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wakeSession(_:)),
                              name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        rebuild()
    }

    public required init?(coder: NSCoder) { nil }

    deinit {
        clock?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    public override var isOpaque: Bool { true }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification,
                                                  object: window)
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, tracksWindowOcclusion {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged(_:)),
                                                   name: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window)
        }
        updateBackingScale()
        updateClock()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingScale()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updateClock()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateClock()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePalette()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if scene?.layout.viewport != bounds.size { rebuild() }
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? 1
        art.contentsScale = scale
    }

    @objc private func visibilityChanged(_ notification: Notification) { updateClock() }
    @objc private func systemColorsChanged(_ notification: Notification) {
        if settings.colour == .accent { updatePalette() }
    }
    @objc private func suspendDisplays(_ notification: Notification) { displaysAwake = false; updateClock() }
    @objc private func wakeDisplays(_ notification: Notification) { displaysAwake = true; updateClock() }
    @objc private func suspendSession(_ notification: Notification) { sessionActive = false; updateClock() }
    @objc private func wakeSession(_ notification: Notification) { sessionActive = true; updateClock() }

    private func updateClock() {
        guard let window, playbackEnabled, !settings.paused, displaysAwake, sessionActive,
              !isHiddenOrHasHiddenAncestor,
              !tracksWindowOcclusion || window.occlusionState.contains(.visible) else {
            needsSettle = true
            settleDelays = []
            if clock != nil {
                stopClock()
                drawGeneration(animate: false)
            }
            return
        }
        guard clock == nil else { return }
        switch playback {
        case .continuous:
            let interval = 1 / settings.speed
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated { self?.advance(by: timer.timeInterval) }
            }
            startClock(timer)
        case .settleOnReveal:
            if needsSettle {
                needsSettle = false
                settleDelays = SettleCadence.delays(speed: settings.speed)[...]
            }
            guard let delay = settleDelays.popFirst() else { return }
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.clock = nil
                    // Pattern injection belongs to sustained playback. The desktop
                    // settles by evolving its current cells for a few generations.
                    self.advance(by: 0, transition: min(0.60, max(0.12, delay * 0.48)))
                    self.updateClock()
                }
            }
            startClock(timer)
        }
    }

    public func replaySettleIfIdle() {
        guard playback == .settleOnReveal, clock == nil else { return }
        needsSettle = true
        updateClock()
    }

    private func startClock(_ timer: Timer) {
        timer.tolerance = min(0.05, timer.timeInterval * 0.05)
        clock = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    private func rebuild() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        var geometry = settings
        geometry.size *= previewScale
        geometry.spacing *= previewScale
        if scene == nil {
            scene = LifeScene(viewport: bounds.size, settings: geometry)
        } else {
            scene?.configure(viewport: bounds.size, settings: geometry)
        }
        updatePalette()
        drawGeneration(animate: false)
    }

    private func updatePalette() {
        guard let scene else { return }
        art.setPalette(scene.palette(darkness: settings.appearance.isDark(in: effectiveAppearance) ? 1 : 0))
    }

    private func advance(by interval: TimeInterval, transition: TimeInterval? = nil) {
        scene?.advance(by: interval)
        if settings.colour == .spectrum || settings.colour == .random { updatePalette() }
        drawGeneration(animate: true, transition: transition)
    }

    private func drawGeneration(animate: Bool, transition: TimeInterval? = nil) {
        guard let scene else { return }
        let duration = transition ?? min(0.27, 0.55 / settings.speed)
        art.draw(scene, animate: animate, duration: duration)
    }

    public func snapshot(scale: CGFloat) -> CGImage? {
        scene?.image(scale: scale, darkness: settings.appearance.isDark(in: effectiveAppearance) ? 1 : 0,
                     branding: art.brandingArtwork)
    }
}
