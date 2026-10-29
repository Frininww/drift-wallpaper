import Foundation
import DriftCore

struct Localizer {
    let language: AppLanguage

    func text(_ key: String) -> String {
        let resource = DriftResources.bundle
        let bundle = resource.url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? resource
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

enum DisplayPlaybackStatus: Equatable {
    case preparing, playing, paused(PauseReason), failed

    func label(using localizer: Localizer) -> String {
        switch self {
        case .preparing: return localizer.text("status.preparing")
        case .playing: return localizer.text("status.playing")
        case .failed: return localizer.text("error.playback")
        case .paused(let reason): return localizer.text("pause.\(reason.rawValue)")
        }
    }
}
