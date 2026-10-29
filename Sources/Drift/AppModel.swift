import AppKit
import Combine
import DriftCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = LibraryState()
    @Published private(set) var thumbnailRevision = 0
    @Published var importing = false
    @Published var errorMessage: String?
    @Published var displayStatus: [String: DisplayPlaybackStatus] = [:]
    @Published var screens: [NSScreen] = NSScreen.screens
    @Published var loginEnabled = false
    @Published var backgroundBusy = false
    @Published var backgroundCanRestore = false
    @Published var backgroundStatus: BackgroundActionStatus?
    @Published var posterFrameSeconds = 0.0
    private(set) var storageAvailable = false
    private var importTask: Task<Void, Never>?
    private let thumbnailCache = NSCache<NSUUID, NSImage>()
    private var loadingThumbnails: Set<UUID> = []
    private var systemBackground: SystemBackgroundController?
    private var backgroundTask: Task<Void, Never>?
    private var backgroundRequest = UUID()
    let directory: URL
    let manifest: URL
    lazy var engine = WallpaperEngine(model: self)
    var onLanguageChange: (() -> Void)?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drift/Wallpapers", isDirectory: true)
        manifest = self.directory.deletingLastPathComponent().appendingPathComponent("library.json")
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
        thumbnailCache.countLimit = 64
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifest.path) {
                do { state = try LibraryStorage.load(from: manifest) }
                catch {
                    // Preserve a damaged manifest instead of silently overwriting it.
                    let backup = manifest.deletingLastPathComponent().appendingPathComponent("library-backup-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at: manifest, to: backup)
                    errorMessage = text("error.recovery")
                }
            }
            storageAvailable = true
        } catch { errorMessage = localizer.format("error.openLibrary", error.localizedDescription) }
    }

    var selected: Wallpaper? { state.wallpapers.first { $0.id == state.settings.selectedID } }
    var settings: AppSettings { state.settings }
    var localizer: Localizer { Localizer(language: settings.language) }
    func text(_ key: String) -> String { localizer.text(key) }
    var isPlaying: Bool { displayStatus.values.contains(.playing) }
    var statusSummary: String {
        if state.wallpapers.isEmpty { return text("status.empty") }
        if selected == nil { return text("status.off") }
        if screens.allSatisfy({ settings.disabledDisplays.contains($0.driftID) }) { return text("status.displaysOff") }
        if isPlaying { return text("status.playing") }
        return (displayStatus.sorted(by: { $0.key < $1.key }).first?.value ?? .preparing).label(using: localizer)
    }

    var outputDescription: String? {
        guard let selected else { return nil }
        let plan = settings.quality.plan(width: selected.width, height: selected.height, framesPerSecond: selected.framesPerSecond)
        return localizer.format("quality.output", plan.width, plan.height, fpsLabel(plan.framesPerSecond))
    }

    func fpsLabel(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.01 ? String(Int(value.rounded()))
            : String(format: "%.2f", locale: Locale(identifier: settings.language.rawValue), value)
    }

    func start() {
        engine.start()
        do { backgroundCanRestore = try backgroundController().canRestore }
        catch { errorMessage = localizer.format("background.error", error.localizedDescription) }
        if let selected { loadThumbnail(selected) }
        if state.wallpapers.isEmpty, storageAvailable,
           let demo = DriftResources.bundle.url(forResource: "Aurora", withExtension: "mp4") {
            importVideos([demo], demoName: "Aurora", bundledID: "aurora")
        }
        if settings.syncSystemBackground, selected != nil { applySelectedFrame(seconds: 0) }
    }

    func stop() {
        cancelBackgroundRequest()
        importTask?.cancel()
        engine.stop()
    }

    func update(_ change: (inout AppSettings) -> Void) {
        let previous = settings
        change(&state.settings)
        save()
        engine.refresh()
        if settings.language != previous.language { onLanguageChange?() }
        if settings.selectedID != previous.selectedID { posterFrameSeconds = 0 }
        if previous.syncSystemBackground, !settings.syncSystemBackground { cancelBackgroundRequest() }
        if settings.syncSystemBackground, selected != nil,
           settings.selectedID != previous.selectedID || settings.fit != previous.fit || !previous.syncSystemBackground {
            applySelectedFrame(seconds: 0)
        }
    }

    func select(_ wallpaper: Wallpaper) {
        loadThumbnail(wallpaper)
        update { $0.selectedID = wallpaper.id; $0.manuallyPaused = false }
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = text("action.add")
        panel.title = text("action.chooseVideo")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.importVideos(panel.urls) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func addHighQualityDemo() {
        if let existing = state.wallpapers.first(where: { $0.bundledID == "aurora4k" }) {
            select(existing)
        } else if let url = DriftResources.bundle.url(forResource: "Aurora4K", withExtension: "mp4") {
            importVideos([url], demoName: "Aurora 4K", bundledID: "aurora4k")
        }
    }

    func importVideos(_ urls: [URL], demoName: String? = nil, bundledID: String? = nil) {
        guard !importing, storageAvailable else { return }
        importing = true
        importTask = Task { [weak self] in
            guard let self else { return }
            let previousSelection = settings.selectedID
            defer { importing = false }
            var failures: [String] = []
            for url in urls {
                do {
                    let target = directory
                    var wallpaper = try await Task.detached(priority: .utility) {
                        try await MediaImporter.inspectAndCopy(url, into: target)
                    }.value
                    if let demoName { wallpaper.name = demoName; wallpaper.bundledID = bundledID }
                    state.wallpapers.append(wallpaper)
                    if state.settings.selectedID == nil || bundledID == "aurora4k" { state.settings.selectedID = wallpaper.id }
                    save()
                    if state.settings.selectedID == wallpaper.id { loadThumbnail(wallpaper) }
                } catch { failures.append("\(url.lastPathComponent): \(description(for: error))") }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n\n") }
            engine.refresh()
            if settings.syncSystemBackground, settings.selectedID != previousSelection { applySelectedFrame(seconds: 0) }
        }
    }

    var maximumPosterTime: Double { max(0, (selected?.duration ?? 0) - 0.1) }

    func applySelectedFrame(seconds: Double? = nil) {
        guard let selected, let url = state.mediaURL(for: selected, in: directory) else { return }
        let time = min(max(0, seconds ?? posterFrameSeconds), maximumPosterTime)
        runBackgroundRequest { directory, displays, fit in
            let image = try await BackgroundImageRenderer.videoFrame(url, seconds: time)
            return try BackgroundImageRenderer.write(image, for: displays, fit: fit,
                                                     key: "video|\(selected.id)|\(Int(time * 1000))", in: directory)
        }
    }

    func chooseBackgroundPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = text("background.choosePhoto")
        panel.prompt = text("background.applyPhoto")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                self.update { $0.syncSystemBackground = false }
                self.runBackgroundRequest { directory, displays, fit in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let key = "photo|\(url.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                    let image = try BackgroundImageRenderer.photo(url)
                    return try BackgroundImageRenderer.write(image, for: displays, fit: fit, key: key, in: directory)
                }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    func restoreSystemBackground() {
        update { $0.syncSystemBackground = false }
        cancelBackgroundRequest()
        do {
            let controller = try backgroundController()
            try controller.restore()
            backgroundCanRestore = controller.canRestore
            backgroundStatus = .restored
        } catch {
            backgroundCanRestore = systemBackground?.canRestore ?? false
            errorMessage = localizer.format("background.error", error.localizedDescription)
        }
    }

    func openWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func backgroundController() throws -> SystemBackgroundController {
        if let systemBackground { return systemBackground }
        let controller = try SystemBackgroundController(directory: directory.deletingLastPathComponent().appendingPathComponent("SystemBackground", isDirectory: true))
        systemBackground = controller
        return controller
    }

    private func runBackgroundRequest(_ operation: @escaping @Sendable (URL, [BackgroundDisplay], VideoFit) async throws -> [String: URL]) {
        cancelBackgroundRequest()
        do {
            let controller = try backgroundController()
            let targets = controller.displays
            let destination = controller.directory
            let fit = settings.fit
            let request = backgroundRequest
            backgroundBusy = true
            backgroundTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    if backgroundRequest == request {
                        backgroundBusy = false
                        backgroundCanRestore = controller.canRestore
                    }
                }
                do {
                    let worker = Task.detached(priority: .utility) { try await operation(destination, targets, fit) }
                    let images = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    guard backgroundRequest == request else { return }
                    let count = try controller.apply(images)
                    backgroundStatus = .applied(count)
                } catch is CancellationError { return }
                catch {
                    guard backgroundRequest == request else { return }
                    errorMessage = localizer.format("background.error", error.localizedDescription)
                }
            }
        } catch { errorMessage = localizer.format("background.error", error.localizedDescription) }
    }

    private func cancelBackgroundRequest() {
        backgroundRequest = UUID()
        backgroundTask?.cancel()
        backgroundTask = nil
        backgroundBusy = false
    }

    func remove(_ wallpaper: Wallpaper) {
        let url = state.mediaURL(for: wallpaper, in: directory)
        state.remove(wallpaper.id)
        thumbnailCache.removeObject(forKey: wallpaper.id as NSUUID)
        save()
        engine.refresh()
        if let url {
            do { try FileManager.default.removeItem(at: url) }
            catch { errorMessage = localizer.format("error.removeFile", error.localizedDescription) }
        }
    }

    func loadThumbnail(_ wallpaper: Wallpaper) {
        guard thumbnail(for: wallpaper.id) == nil, !loadingThumbnails.contains(wallpaper.id) else { return }
        guard let url = state.mediaURL(for: wallpaper, in: directory) else { return }
        loadingThumbnails.insert(wallpaper.id)
        Task { [weak self] in
            let thumbnail = await MediaImporter.thumbnail(url)
            guard let self else { return }
            loadingThumbnails.remove(wallpaper.id)
            guard state.wallpapers.contains(where: { $0.id == wallpaper.id }), let thumbnail else { return }
            // Bound preview memory independently of the number of imported files.
            let pixels = thumbnail.representations.first
            let cost = (pixels?.pixelsWide ?? 720) * (pixels?.pixelsHigh ?? 450) * 4
            thumbnailCache.setObject(thumbnail, forKey: wallpaper.id as NSUUID, cost: cost)
            thumbnailRevision &+= 1
        }
    }

    func thumbnail(for id: UUID) -> NSImage? { thumbnailCache.object(forKey: id as NSUUID) }

    private func save() {
        guard storageAvailable else { return }
        do { try LibraryStorage.save(state, to: manifest) }
        catch { errorMessage = localizer.format("error.save", error.localizedDescription) }
    }

    private func description(for error: Error) -> String {
        guard let media = error as? MediaError else { return error.localizedDescription }
        return text(media.localizationKey)
    }
}

enum DriftResources {
    // Explicitly support packaged apps as well as SwiftPM executables. Older
    // SwiftPM versions do not search Contents/Resources in Bundle.module.
    static let bundle: Bundle = {
        if let root = Bundle.main.resourceURL,
           let bundle = Bundle(url: root.appendingPathComponent("Drift_Drift.bundle")) {
            return bundle
        }
        return Bundle.module
    }()
}

extension NSScreen {
    var driftID: String { String((deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
}
