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
    @Published var displayStatus: [String: String] = [:]
    @Published var screens: [NSScreen] = NSScreen.screens
    @Published var loginEnabled = false
    private(set) var storageAvailable = false
    private var importTask: Task<Void, Never>?
    private let thumbnailCache = NSCache<NSUUID, NSImage>()
    private var loadingThumbnails: Set<UUID> = []
    let directory: URL
    let manifest: URL
    lazy var engine = WallpaperEngine(model: self)

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
                    errorMessage = "Библиотека не открылась. Её резервная копия сохранена рядом с library.json."
                }
            }
            storageAvailable = true
        } catch { errorMessage = "Не удалось открыть папку библиотеки: \(error.localizedDescription)" }
    }

    var selected: Wallpaper? { state.wallpapers.first { $0.id == state.settings.selectedID } }
    var settings: AppSettings { state.settings }
    var statusSummary: String {
        if state.wallpapers.isEmpty { return "Добавь своё первое видео" }
        if selected == nil { return "Обои выключены" }
        if screens.allSatisfy({ settings.disabledDisplays.contains($0.driftID) }) { return "Все экраны выключены" }
        if displayStatus.values.contains("Воспроизводится") { return "Воспроизводится" }
        return displayStatus.sorted(by: { $0.key < $1.key }).first?.value ?? "Подготовка…"
    }

    func start() {
        engine.start()
        if let selected { loadThumbnail(selected) }
        if state.wallpapers.isEmpty, storageAvailable,
           let demo = DriftResources.bundle.url(forResource: "Aurora", withExtension: "mp4") {
            importVideos([demo], demo: true)
        }
    }

    func update(_ change: (inout AppSettings) -> Void) {
        change(&state.settings)
        save()
        engine.refresh()
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
        panel.prompt = "Добавить"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.importVideos(panel.urls) }
        }
    }

    func importVideos(_ urls: [URL], demo: Bool = false) {
        guard !importing, storageAvailable else { return }
        importing = true
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { importing = false }
            var failures: [String] = []
            for url in urls {
                do {
                    let target = directory
                    var wallpaper = try await Task.detached(priority: .utility) {
                        try await MediaImporter.inspectAndCopy(url, into: target)
                    }.value
                    if demo { wallpaper.name = "Aurora" }
                    state.wallpapers.append(wallpaper)
                    if state.settings.selectedID == nil { state.settings.selectedID = wallpaper.id }
                    save()
                    if state.settings.selectedID == wallpaper.id { loadThumbnail(wallpaper) }
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n\n") }
            engine.refresh()
        }
    }

    func remove(_ wallpaper: Wallpaper) {
        let url = state.mediaURL(for: wallpaper, in: directory)
        state.remove(wallpaper.id)
        thumbnailCache.removeObject(forKey: wallpaper.id as NSUUID)
        save()
        engine.refresh()
        if let url {
            do { try FileManager.default.removeItem(at: url) }
            catch { errorMessage = "Запись удалена, но файл остался в библиотеке: \(error.localizedDescription)" }
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
        catch { errorMessage = "Не удалось сохранить настройки: \(error.localizedDescription)" }
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

extension PauseReason {
    var title: String {
        switch self {
        case .manual: return "Пауза вручную"
        case .sleeping: return "Экран спит"
        case .inactiveSession: return "Сеанс неактивен"
        case .thermal: return "Пауза: высокая температура"
        case .lowPower: return "Режим энергосбережения"
        case .battery: return "Работа от аккумулятора"
        case .covered: return "Рабочий стол скрыт"
        }
    }
}
