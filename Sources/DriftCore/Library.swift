import Foundation

public struct Wallpaper: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var filename: String
    public var width: Int
    public var height: Int
    public var duration: Double
    public var framesPerSecond: Double
    public var byteCount: Int64
    public var bundledID: String?

    public init(id: UUID = UUID(), name: String, filename: String, width: Int, height: Int,
                duration: Double, framesPerSecond: Double, byteCount: Int64) {
        self.id = id; self.name = name; self.filename = filename
        self.width = width; self.height = height; self.duration = duration
        self.framesPerSecond = framesPerSecond; self.byteCount = byteCount
    }

    public var needsOptimization: Bool { width > 2560 || height > 1600 || framesPerSecond > 30.5 }
}

public enum VideoFit: String, Codable, CaseIterable, Sendable {
    case fill, fit
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var energy = EnergySettings()
    public var fit = VideoFit.fill
    public var selectedID: UUID?
    public var disabledDisplays: Set<String> = []
    public var manuallyPaused = false
    public var language = AppLanguage.english
    public var quality = PlaybackQuality()
    public var syncSystemBackground = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case energy, fit, selectedID, disabledDisplays, manuallyPaused, language, quality, syncSystemBackground
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        energy = try values.decodeIfPresent(EnergySettings.self, forKey: .energy) ?? .init()
        fit = try values.decodeIfPresent(VideoFit.self, forKey: .fit) ?? .fill
        selectedID = try values.decodeIfPresent(UUID.self, forKey: .selectedID)
        disabledDisplays = try values.decodeIfPresent(Set<String>.self, forKey: .disabledDisplays) ?? []
        manuallyPaused = try values.decodeIfPresent(Bool.self, forKey: .manuallyPaused) ?? false
        language = (try? values.decode(AppLanguage.self, forKey: .language)) ?? .english
        quality = (try? values.decode(PlaybackQuality.self, forKey: .quality)) ?? .init()
        syncSystemBackground = try values.decodeIfPresent(Bool.self, forKey: .syncSystemBackground) ?? false
    }
}

public struct LibraryState: Codable, Equatable, Sendable {
    public var version = 1
    public var wallpapers: [Wallpaper] = []
    public var settings = AppSettings()
    public init() {}

    public mutating func remove(_ id: UUID) {
        wallpapers.removeAll { $0.id == id }
        if settings.selectedID == id { settings.selectedID = nil }
    }

    public func mediaURL(for wallpaper: Wallpaper, in directory: URL) -> URL? {
        // A damaged or edited manifest must never escape the library directory.
        guard !wallpaper.filename.isEmpty,
              wallpaper.filename == (wallpaper.filename as NSString).lastPathComponent,
              wallpaper.filename != ".", wallpaper.filename != ".." else { return nil }
        return directory.appendingPathComponent(wallpaper.filename)
    }
}

public enum LibraryStorage {
    public static func load(from url: URL) throws -> LibraryState {
        let state = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw StorageError.unsupportedVersion }
        return state
    }

    public static func save(_ state: LibraryState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    public enum StorageError: Error { case unsupportedVersion }
}
