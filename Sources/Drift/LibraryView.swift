import SwiftUI
import DriftCore
import ServiceManagement

private let accent = Color(red: 0.76, green: 0.92, blue: 0.60)
private let canvas = Color(red: 0.055, green: 0.065, blue: 0.085)
private let panel = Color(red: 0.085, green: 0.10, blue: 0.125)

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    @State private var pendingRemoval: Wallpaper?
    private func t(_ key: String) -> String { model.text(key) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if tab == 0 { library } else { preferences }
                }.padding(32)
            }
        }
        .frame(minWidth: 960, minHeight: 700)
        .background(canvas)
        .preferredColorScheme(.dark)
        .tint(accent)
        .environment(\.locale, Locale(identifier: model.settings.language.rawValue))
        .alert(t("alert.error"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(t("action.ok")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert(model.localizer.format("alert.delete.title", pendingRemoval?.name ?? ""), isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button(t("action.cancel"), role: .cancel) { pendingRemoval = nil }
            Button(t("action.delete"), role: .destructive) {
                if let wallpaper = pendingRemoval { model.remove(wallpaper) }
                pendingRemoval = nil
            }
        } message: { Text(t("alert.delete.message")) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 11) {
                Image(systemName: "wind").font(.system(size: 29, weight: .medium)).foregroundStyle(accent)
                Text("drift").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-1)
            }.padding(.top, 18).padding(.bottom, 18)
            VStack(spacing: 8) {
                navigation("nav.wallpapers", icon: "square.grid.2x2", selection: 0)
                navigation("nav.settings", icon: "slider.horizontal.3", selection: 1)
            }
            VStack(alignment: .leading, spacing: 15) {
                Text(t("sidebar.displays")).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                ForEach(model.screens, id: \.driftID) { screen in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(screen.localizedName, systemImage: "display").font(.system(size: 12))
                        Text(model.settings.disabledDisplays.contains(screen.driftID) ? t("display.disabled") : (model.displayStatus[screen.driftID]?.label(using: model.localizer) ?? t("display.ready")))
                            .font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 22)
                    }
                }
            }
            Spacer()
            Text("DRIFT  /  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")")
                .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
        }.padding(22).frame(width: 190).background(panel.opacity(0.55))
    }

    private func navigation(_ title: String, icon: String, selection: Int) -> some View {
        Button { tab = selection } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 18)
                Text(t(title)).font(.system(size: 13, weight: .medium))
                Spacer()
            }.padding(12)
                .foregroundStyle(tab == selection ? accent : .white.opacity(0.60))
                .background(tab == selection ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(.interaction, RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityIdentifier(title)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 9) {
                Text(t(tab == 0 ? "header.library.eyebrow" : "header.settings.eyebrow"))
                    .font(.system(size: 9, weight: .semibold)).tracking(2.1).foregroundStyle(accent)
                Text(t(tab == 0 ? "header.library.title" : "header.settings.title"))
                    .font(.system(size: 29, weight: .medium)).tracking(-0.9)
            }
            Spacer()
            Button(action: model.chooseVideos) {
                Label(t(model.importing ? "action.adding" : "action.addVideo"), systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(canvas).background(accent, in: Capsule())
                    .contentShape(.interaction, Capsule())
            }.buttonStyle(.plain).fixedSize().disabled(model.importing || !model.storageAvailable)
                .accessibilityIdentifier("add-video")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 24) {
            hero
            HStack {
                Text(t("library.collection")).font(.system(size: 17, weight: .medium))
                Text("\(model.state.wallpapers.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text(t("library.local")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if model.state.wallpapers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack").font(.system(size: 30)).foregroundStyle(accent)
                    Text(t("library.empty")).foregroundStyle(.secondary)
                    Button(t("action.chooseVideo"), action: model.chooseVideos)
                }.frame(maxWidth: .infinity).padding(30).background(panel, in: RoundedRectangle(cornerRadius: 14))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                ForEach(model.state.wallpapers) { wallpaper in wallpaperCard(wallpaper) }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "leaf").foregroundStyle(accent)
                Text(t(model.settings.energy.pauseWhenCovered ? "library.energy.on" : "library.energy.off"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let selected = model.selected, let image = model.thumbnail(for: selected.id) {
                GeometryReader { proxy in
                    Image(nsImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
            } else {
                LinearGradient(colors: [.indigo.opacity(0.75), .teal.opacity(0.45), canvas], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Label(model.statusSummary, systemImage: model.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 10, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                    .background(.black.opacity(0.35), in: Capsule())
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.selected?.name ?? t("hero.empty")).font(.system(size: 32, weight: .medium)).lineLimit(1)
                        Text(model.selected.map(metadata) ?? t("hero.formats"))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button { model.update { $0.manuallyPaused.toggle() } } label: {
                        Image(systemName: model.settings.manuallyPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16)).frame(width: 44, height: 44)
                            .background(.white.opacity(0.14), in: Circle())
                            .contentShape(.interaction, Circle())
                    }.buttonStyle(.plain).disabled(model.selected == nil)
                        .help(t(model.settings.manuallyPaused ? "action.resume" : "action.pause"))
                }
            }.padding(26)
        }.frame(height: 305).clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.08)))
            .accessibilityElement(children: .contain)
    }

    private func wallpaperCard(_ wallpaper: Wallpaper) -> some View {
        let active = model.settings.selectedID == wallpaper.id
        return Button { model.select(wallpaper) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    GeometryReader { proxy in
                        if let image = model.thumbnail(for: wallpaper.id) {
                            Image(nsImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                        } else { Rectangle().fill(.indigo.opacity(0.3)) }
                    }.frame(height: 116)
                    if active {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(canvas)
                            .padding(6).background(accent, in: Circle()).padding(10)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(wallpaper.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(metadata(wallpaper)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    if wallpaper.needsOptimization {
                        Label(t("wallpaper.highQuality"), systemImage: "sparkles").font(.system(size: 9)).foregroundStyle(accent)
                    }
                }.padding(13)
            }.background(panel).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? accent.opacity(0.7) : .white.opacity(0.06), lineWidth: 1))
                .contentShape(.interaction, RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).contextMenu {
            Button(t("action.apply")) { model.select(wallpaper) }
            Button(t("action.remove"), role: .destructive) { pendingRemoval = wallpaper }
        }.accessibilityLabel("\(wallpaper.name), \(t(active ? "wallpaper.selected" : "wallpaper.select"))")
            .onAppear { model.loadThumbnail(wallpaper) }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 23) {
            settingsGroup("settings.appearance", icon: "globe") {
                HStack {
                    Text(t("settings.language")).font(.system(size: 12))
                    Spacer()
                    Picker(t("settings.language"), selection: Binding(get: { model.settings.language }, set: { value in model.update { $0.language = value } })) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in Text(language.name).tag(language) }
                    }.labelsHidden().frame(width: 180).accessibilityIdentifier("language-picker")
                }
                Text(t("settings.language.hint")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            settingsGroup("settings.quality", icon: "sparkles") {
                HStack {
                    Text(t("settings.resolution")).font(.system(size: 12))
                    Spacer()
                    Picker(t("settings.resolution"), selection: Binding(get: { model.settings.quality.resolution }, set: { value in model.update { $0.quality.resolution = value } })) {
                        ForEach(ResolutionLimit.allCases, id: \.self) { value in
                            Text(value == .original ? t("quality.original") : value == .ultraHD ? t("quality.4K") : value.name).tag(value)
                        }
                    }.labelsHidden().frame(width: 180).accessibilityIdentifier("resolution-picker")
                }
                HStack {
                    Text(t("settings.frameRate")).font(.system(size: 12))
                    Spacer()
                    Picker(t("settings.frameRate"), selection: Binding(get: { model.settings.quality.frameRate }, set: { value in model.update { $0.quality.frameRate = value } })) {
                        ForEach(FrameRateLimit.allCases, id: \.self) { value in
                            Text(value == .original ? t("quality.original") : "\(value.rawValue) FPS").tag(value)
                        }
                    }.labelsHidden().frame(width: 180).accessibilityIdentifier("fps-picker")
                }
                if let output = model.outputDescription { Text(output).font(.system(size: 11, design: .monospaced)).foregroundStyle(accent) }
                Text(t("quality.explanation")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Divider().opacity(0.3)
                Button(t("action.demo4K"), action: model.addHighQualityDemo).disabled(model.importing || !model.storageAvailable)
                Text(t("quality.demo")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            settingsGroup("settings.energy", icon: "leaf") {
                setting("settings.covered", detail: "settings.covered.detail", keyPath: \.energy.pauseWhenCovered)
                Divider().opacity(0.3)
                setting("settings.lowPower", detail: "settings.lowPower.detail", keyPath: \.energy.pauseInLowPowerMode)
                Divider().opacity(0.3)
                setting("settings.battery", detail: "settings.battery.detail", keyPath: \.energy.pauseOnBattery)
            }
            settingsGroup("settings.display", icon: "display") {
                Picker(t("settings.scaling"), selection: Binding(get: { model.settings.fit }, set: { value in model.update { $0.fit = value } })) {
                    Text(t("settings.fill")).tag(VideoFit.fill)
                    Text(t("settings.fit")).tag(VideoFit.fit)
                }.pickerStyle(.segmented)
                ForEach(model.screens, id: \.driftID) { screen in
                    Toggle(screen.localizedName, isOn: Binding(get: { !model.settings.disabledDisplays.contains(screen.driftID) }, set: { enabled in
                        model.update { if enabled { $0.disabledDisplays.remove(screen.driftID) } else { $0.disabledDisplays.insert(screen.driftID) } }
                    })).toggleStyle(.switch)
                }
            }
            settingsGroup("settings.startup", icon: "power") {
                Toggle(t("settings.login"), isOn: Binding(get: { model.loginEnabled }, set: setLogin)).toggleStyle(.switch)
                Text(t("settings.background"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(t("settings.safety"))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            Text(t("quality.processing")).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                Button(t("action.openLibrary")) { NSWorkspace.shared.open(model.directory) }
                Spacer()
                Button(t("action.turnOff")) { model.update { $0.selectedID = nil } }
            }.font(.system(size: 11))
        }.onAppear { model.loginEnabled = SMAppService.mainApp.status == .enabled }
    }

    private func settingsGroup<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(t(title), systemImage: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(accent)
            content()
        }.padding(22).background(panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func setting(_ title: String, detail: String, keyPath: WritableKeyPath<AppSettings, Bool>) -> some View {
        Toggle(isOn: Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.update { $0[keyPath: keyPath] = value } })) {
            VStack(alignment: .leading, spacing: 5) {
                Text(t(title)).font(.system(size: 12))
                Text(t(detail)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.toggleStyle(.switch).accessibilityLabel(t(title)).accessibilityHint(t(detail))
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { model.errorMessage = model.localizer.format("error.login", error.localizedDescription) }
    }

    private func metadata(_ wallpaper: Wallpaper) -> String {
        "\(wallpaper.width) × \(wallpaper.height)  ·  \(model.fpsLabel(wallpaper.framesPerSecond)) FPS  ·  \(Int(wallpaper.duration)) \(t("metadata.seconds"))"
    }
}
