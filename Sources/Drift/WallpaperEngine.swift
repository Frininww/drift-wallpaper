import AppKit
import AVFoundation
import DriftCore
import IOKit.ps

@MainActor
final class WallpaperEngine: NSObject {
    private weak var model: AppModel?
    private var renderers: [String: DesktopRenderer] = [:]
    private var environment = PlaybackEnvironment()
    private var systemSleeping = false
    private var screensSleeping = false
    private var powerSource: CFRunLoopSource?
    private var started = false

    init(model: AppModel) { self.model = model }

    func start() {
        guard !started else { return }
        started = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(energyChanged), name: name, object: nil)
        }
        // IOKit invokes this on the main run loop. No timer or polling is needed.
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let engine = Unmanaged<WallpaperEngine>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { engine.energyChanged() }
        }, Unmanaged.passUnretained(self).toOpaque()).takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        energyChanged()
        refresh()
    }

    func stop() {
        started = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        for renderer in renderers.values { renderer.stop() }
        renderers.removeAll()
        model?.displayStatus = [:]
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: systemSleeping = true
        case NSWorkspace.didWakeNotification: systemSleeping = false
        case NSWorkspace.screensDidSleepNotification: screensSleeping = true
        case NSWorkspace.screensDidWakeNotification: screensSleeping = false
        case NSWorkspace.sessionDidResignActiveNotification: environment.sessionActive = false
        case NSWorkspace.sessionDidBecomeActiveNotification: environment.sessionActive = true
        default: break
        }
        environment.sleeping = systemSleeping || screensSleeping
        energyChanged()
    }

    @objc private func displaysChanged() { refresh() }

    @objc fileprivate func energyChanged() {
        environment.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ProcessInfo.processInfo.thermalState
        environment.thermallyConstrained = thermal == .serious || thermal == .critical
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            environment.onBattery = (type as String) == kIOPSBatteryPowerValue
        }
        reconcile()
    }

    func refresh() {
        guard let model else { return }
        model.screens = NSScreen.screens
        let enabled = model.screens.filter { !model.settings.disabledDisplays.contains($0.driftID) }
        let activeIDs = Set(enabled.map(\.driftID))
        for key in Array(renderers.keys) where !activeIDs.contains(key) {
            renderers.removeValue(forKey: key)?.stop()
        }
        guard let selected = model.selected,
              let url = model.state.mediaURL(for: selected, in: model.directory) else {
            for renderer in renderers.values { renderer.stop() }
            renderers.removeAll()
            model.displayStatus = [:]
            return
        }
        for screen in enabled {
            let id = screen.driftID
            if renderers[id]?.wallpaperID != selected.id || renderers[id]?.quality != model.settings.quality {
                renderers.removeValue(forKey: id)?.stop()
                let renderer = DesktopRenderer(screen: screen, wallpaperID: selected.id, url: url, quality: model.settings.quality)
                renderer.onChange = { [weak self] in self?.reconcile() }
                renderers[id] = renderer
                renderer.prepare()
            }
            renderers[id]?.configure(screen: screen, fit: model.settings.fit)
        }
        reconcile()
    }

    private func reconcile() {
        guard let model else { return }
        environment.manuallyPaused = model.settings.manuallyPaused
        var statuses: [String: DisplayPlaybackStatus] = [:]
        for (id, renderer) in renderers {
            var local = environment
            local.desktopVisible = renderer.window.occlusionState.contains(.visible)
            let reason = PlaybackPolicy.pauseReason(environment: local, settings: model.settings.energy)
            renderer.setPlaying(reason == nil)
            if renderer.failure != nil { statuses[id] = .failed }
            else if !renderer.ready { statuses[id] = .preparing }
            else if let reason { statuses[id] = .paused(reason) }
            else { statuses[id] = .playing }
        }
        if model.displayStatus != statuses { model.displayStatus = statuses }
    }
}

@MainActor
private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class PlayerSurface: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = playerLayer
        playerLayer.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class DesktopRenderer: NSObject, NSWindowDelegate {
    let wallpaperID: UUID
    let quality: PlaybackQuality
    let window: NSWindow
    private let surface: PlayerSurface
    private let url: URL
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var preparation: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var loopObservation: NSKeyValueObservation?
    private(set) var stopped = false
    var hasPlayer: Bool { player != nil }
    private(set) var ready = false
    private(set) var failure: String?
    var onChange: (() -> Void)?

    init(screen: NSScreen, wallpaperID: UUID, url: URL, quality: PlaybackQuality) {
        self.wallpaperID = wallpaperID
        self.quality = quality
        self.url = url
        surface = PlayerSurface(frame: NSRect(origin: .zero, size: screen.frame.size))
        window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.contentView = surface
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.setAccessibilityElement(false)
        surface.setAccessibilityElement(false)
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
    }

    func prepare() {
        guard !stopped, preparation == nil else { return }
        preparation = Task { [weak self] in
            guard let self else { return }
            do {
                let item = try await VideoPipeline.makeItem(url: url, quality: quality)
                try Task.checkCancellation()
                guard !stopped else { return }
                let queue = AVQueuePlayer()
                queue.isMuted = true
                queue.volume = 0
                queue.preventsDisplaySleepDuringVideoPlayback = false
                queue.automaticallyWaitsToMinimizeStalling = false
                player = queue
                looper = AVPlayerLooper(player: queue, templateItem: item)
                surface.playerLayer.player = queue
                statusObservation = queue.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.readStatus() }
                }
                if let looper {
                    loopObservation = looper.observe(\.status, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor [weak self] in self?.readStatus() }
                    }
                }
                window.orderFrontRegardless()
                onChange?()
            } catch is CancellationError { return }
            catch { failure = error.localizedDescription; onChange?() }
        }
    }

    func configure(screen: NSScreen, fit: VideoFit) {
        window.setFrame(screen.frame, display: true)
        surface.playerLayer.videoGravity = fit == .fill ? .resizeAspectFill : .resizeAspect
    }

    func setPlaying(_ value: Bool) {
        guard !stopped, failure == nil, let player else { return }
        if value {
            if player.rate == 0 { player.play() }
        } else if player.rate != 0 { player.pause() }
    }

    private func readStatus() {
        guard !stopped else { return }
        if player?.currentItem?.status == .failed || looper?.status == .failed {
            failure = "Playback failed"
            player?.pause()
        }
        ready = player?.currentItem?.status == .readyToPlay
        onChange?()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { onChange?() }

    func stop() {
        guard !stopped else { return }
        stopped = true
        onChange = nil
        preparation?.cancel()
        preparation = nil
        statusObservation = nil
        loopObservation = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        surface.playerLayer.player = nil
        surface.playerLayer.isHidden = true
        player = nil
        ready = false
        window.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}
