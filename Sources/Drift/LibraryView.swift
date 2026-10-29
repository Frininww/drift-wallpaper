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
        .alert("Не удалось завершить действие", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Понятно") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Удалить «\(pendingRemoval?.name ?? "")»?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Отмена", role: .cancel) { pendingRemoval = nil }
            Button("Удалить", role: .destructive) {
                if let wallpaper = pendingRemoval { model.remove(wallpaper) }
                pendingRemoval = nil
            }
        } message: { Text("Копия в библиотеке Drift будет удалена. Исходное видео останется на месте.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 11) {
                Image(systemName: "wind").font(.system(size: 29, weight: .medium)).foregroundStyle(accent)
                Text("drift").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-1)
            }.padding(.top, 18).padding(.bottom, 18)
            VStack(spacing: 8) {
                navigation("Обои", icon: "square.grid.2x2", selection: 0)
                navigation("Настройки", icon: "slider.horizontal.3", selection: 1)
            }
            VStack(alignment: .leading, spacing: 15) {
                Text("ЭКРАНЫ").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                ForEach(model.screens, id: \.driftID) { screen in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(screen.localizedName, systemImage: "display").font(.system(size: 12))
                        Text(model.settings.disabledDisplays.contains(screen.driftID) ? "Отключён" : (model.displayStatus[screen.driftID] ?? "Готов к работе"))
                            .font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 22)
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text("Меньше суеты. Больше воздуха.").font(.system(size: 10))
                }
                Text("DRIFT  /  1.0.0").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
            }
        }.padding(22).frame(width: 190).background(panel.opacity(0.55))
    }

    private func navigation(_ title: String, icon: String, selection: Int) -> some View {
        Button { tab = selection } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
            }.padding(12)
                .foregroundStyle(tab == selection ? accent : .white.opacity(0.60))
                .background(tab == selection ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 9) {
                Text(tab == 0 ? "РАБОЧИЙ СТОЛ, КОТОРЫЙ ДЫШИТ" : "ПОД ТВОЙ РИТМ")
                    .font(.system(size: 9, weight: .semibold)).tracking(2.1).foregroundStyle(accent)
                Text(tab == 0 ? "Немного движения." : "Тихо. И экономно.")
                    .font(.system(size: 29, weight: .medium)).tracking(-0.9)
            }
            Spacer()
            Button(action: model.chooseVideos) {
                Label(model.importing ? "Добавление…" : "Добавить видео", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(canvas).background(accent, in: Capsule())
            }.buttonStyle(.plain).disabled(model.importing || !model.storageAvailable)
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 24) {
            hero
            HStack {
                Text("Твоя коллекция").font(.system(size: 17, weight: .medium))
                Text("\(model.state.wallpapers.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("Локальные видео · без звука").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if model.state.wallpapers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack").font(.system(size: 30)).foregroundStyle(accent)
                    Text("Добавь видео, которое хочется видеть каждый день.").foregroundStyle(.secondary)
                    Button("Выбрать видео", action: model.chooseVideos)
                }.frame(maxWidth: .infinity).padding(30).background(panel, in: RoundedRectangle(cornerRadius: 14))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                ForEach(model.state.wallpapers) { wallpaper in wallpaperCard(wallpaper) }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "leaf").foregroundStyle(accent)
                Text(model.settings.energy.pauseWhenCovered
                     ? "Когда рабочий стол полностью скрыт, Drift ставит видео на паузу. Красота может подождать."
                     : "Автопауза при скрытом рабочем столе выключена. Включи её в настройках, чтобы экономить энергию.")
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
                Label(model.statusSummary, systemImage: model.statusSummary == "Воспроизводится" ? "waveform" : "pause.fill")
                    .font(.system(size: 10, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                    .background(.black.opacity(0.35), in: Capsule())
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.selected?.name ?? "Место для твоего настроения").font(.system(size: 32, weight: .medium)).lineLimit(1)
                        Text(model.selected.map(metadata) ?? "MP4, MOV, M4V  ·  H.264 и HEVC")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button { model.update { $0.manuallyPaused.toggle() } } label: {
                        Image(systemName: model.settings.manuallyPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16)).frame(width: 44, height: 44)
                            .background(.white.opacity(0.14), in: Circle())
                    }.buttonStyle(.plain).disabled(model.selected == nil)
                        .help(model.settings.manuallyPaused ? "Продолжить" : "Пауза")
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
                        Label("Тяжёлое видео", systemImage: "leaf").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }.padding(13)
            }.background(panel).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? accent.opacity(0.7) : .white.opacity(0.06), lineWidth: 1))
        }.buttonStyle(.plain).contextMenu {
            Button("Установить обои") { model.select(wallpaper) }
            Button("Удалить из библиотеки", role: .destructive) { pendingRemoval = wallpaper }
        }.accessibilityLabel("\(wallpaper.name), \(active ? "выбрано" : "выбрать обои")")
            .onAppear { model.loadThumbnail(wallpaper) }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 23) {
            settingsGroup("Энергия", icon: "leaf") {
                setting("Пауза, когда рабочий стол скрыт", detail: "Отдельно для каждого монитора", keyPath: \.energy.pauseWhenCovered)
                Divider().opacity(0.3)
                setting("Пауза в энергосбережении", detail: "Учитывает системный режим macOS", keyPath: \.energy.pauseInLowPowerMode)
                Divider().opacity(0.3)
                setting("Пауза от аккумулятора", detail: "Продолжит при подключении питания", keyPath: \.energy.pauseOnBattery)
            }
            settingsGroup("Отображение", icon: "display") {
                Picker("Масштаб видео", selection: Binding(get: { model.settings.fit }, set: { value in model.update { $0.fit = value } })) {
                    Text("Заполнить экран").tag(VideoFit.fill)
                    Text("Вписать целиком").tag(VideoFit.fit)
                }.pickerStyle(.segmented)
                ForEach(model.screens, id: \.driftID) { screen in
                    Toggle(screen.localizedName, isOn: Binding(get: { !model.settings.disabledDisplays.contains(screen.driftID) }, set: { enabled in
                        model.update { if enabled { $0.disabledDisplays.remove(screen.driftID) } else { $0.disabledDisplays.insert(screen.driftID) } }
                    })).toggleStyle(.switch)
                }
            }
            settingsGroup("При запуске", icon: "power") {
                Toggle("Открывать Drift при входе", isOn: Binding(get: { model.loginEnabled }, set: setLogin)).toggleStyle(.switch)
                Text("После закрытия окна Drift остаётся в строке меню. Завершить работу можно там же.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Сон экрана и высокая температура всегда приостанавливают воспроизведение. Для меньшей нагрузки выбирай H.264 или HEVC, 1080p, 24–30 кадров/с.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {
                Button("Открыть библиотеку") { NSWorkspace.shared.open(model.directory) }
                Spacer()
                Button("Выключить обои") { model.update { $0.selectedID = nil } }
            }.font(.system(size: 11))
        }.onAppear { model.loginEnabled = SMAppService.mainApp.status == .enabled }
    }

    private func settingsGroup<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(accent)
            content()
        }.padding(22).background(panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func setting(_ title: String, detail: String, keyPath: WritableKeyPath<AppSettings, Bool>) -> some View {
        Toggle(isOn: Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.update { $0[keyPath: keyPath] = value } })) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.toggleStyle(.switch).accessibilityLabel(title).accessibilityHint(detail)
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { model.errorMessage = "Не удалось изменить автозапуск: \(error.localizedDescription)" }
    }

    private func metadata(_ wallpaper: Wallpaper) -> String {
        "\(wallpaper.width) × \(wallpaper.height)  ·  \(Int(wallpaper.framesPerSecond.rounded())) FPS  ·  \(Int(wallpaper.duration)) с"
    }
}
