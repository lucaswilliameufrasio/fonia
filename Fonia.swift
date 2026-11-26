import AppKit
import CoreAudio
import ServiceManagement
import SwiftUI

struct Source: Identifiable {
    let id: String
    let name: String
    var objects: [NSNumber]
}

@MainActor
final class Mixer: ObservableObject {
    private struct SavedLevel: Codable {
        let level: Float
        let beforeMute: Float?
    }
    private let defaults = UserDefaults.standard
    private var saved = [String: SavedLevel]()
    private var beforeMute = [String: Float]()
    @Published var rememberLevels: Bool {
        didSet {
            defaults.set(rememberLevels, forKey: "rememberLevels")
            if rememberLevels {
                for key in levels.keys { remember(key) }
            } else {
                saved.removeAll()
                defaults.removeObject(forKey: "savedLevels")
            }
        }
    }
    @Published private(set) var sources = [Source]()
    @Published private(set) var levels = [String: Float]()
    @Published private(set) var outputName = ""
    @Published private(set) var master: Float = -1
    @Published var message = ""
    private var output: UInt32 = 0
    private var channels = [String: FoniaChannel]()
    private var timer: Timer?

    init() {
        rememberLevels = UserDefaults.standard.bool(forKey: "rememberLevels")
        if rememberLevels, let data = defaults.data(forKey: "savedLevels"),
           let decoded = try? JSONDecoder().decode([String: SavedLevel].self, from: data) {
            saved = decoded.filter { (0...1).contains($0.value.level) }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let device = FoniaOutput()
        var groups = [String: Source]()
        for object in FoniaProcesses() {
            let pid = FoniaPID(object.uint32Value)
            guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { continue }
            let identity = SourceIdentity.resolve(pid: pid, object: object.uint32Value)
            let key = identity.id
            guard FoniaActive(object.uint32Value) || channels[key] != nil else { continue }
            groups[key, default: Source(id: key, name: identity.name, objects: [])].objects.append(object)
        }
        for (key, channel) in channels {
            let previous = sources.first { $0.id == key }
            if device != output || Set(previous?.objects ?? []) != Set(groups[key]?.objects ?? []) {
                channel.stop()
                channels.removeValue(forKey: key)
                if let source = groups[key], device != 0 {
                    connect(source, device: device, value: levels[key] ?? 1)
                } else {
                    levels.removeValue(forKey: key)
                    beforeMute.removeValue(forKey: key)
                }
            }
        }
        if rememberLevels, device != 0 {
            let existing = Set(sources.map(\.id))
            for source in groups.values where channels[source.id] == nil && (!existing.contains(source.id) || output == 0) {
                if let setting = saved[source.id], setting.level < 1 {
                    beforeMute[source.id] = setting.beforeMute
                    connect(source, device: device, value: setting.level)
                }
            }
        }
        output = device
        outputName = FoniaOutputName(device)
        master = FoniaVolume(device)
        sources = groups.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func setMaster(_ value: Float) {
        guard output == FoniaOutput(), FoniaSetVolume(output, value) else {
            message = output != FoniaOutput() || output == 0
                ? "A saída mudou ou foi desconectada. Selecione uma saída em Ajustes do Sistema → Som."
                : "Esta saída não aceitou o ajuste. Use o controle do dispositivo ou o volume por aplicativo."
            refresh()
            return
        }
        master = value
    }

    func setLevel(_ source: Source, _ value: Float) {
        let previous = levels[source.id] ?? 1
        if value >= 1 {
            channels.removeValue(forKey: source.id)?.stop()
            levels.removeValue(forKey: source.id)
        } else if let channel = channels[source.id] {
            channel.setLevel(value)
            levels[source.id] = value
        } else {
            connect(source, device: output, value: value)
        }
        guard (levels[source.id] ?? 1) == value else { return }
        if value == 0 && previous > 0 { beforeMute[source.id] = previous }
        if value > 0 { beforeMute.removeValue(forKey: source.id) }
        remember(source.id)
    }

    private func remember(_ key: String) {
        guard rememberLevels, !key.hasPrefix("pid:") else { return }
        saved[key] = levels[key].map { SavedLevel(level: $0, beforeMute: beforeMute[key]) }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "savedLevels") }
    }

    func toggleMute(_ source: Source) {
        let muted = levels[source.id] == 0
        setLevel(source, muted ? (beforeMute[source.id] ?? 1) : 0)
    }

    private func connect(_ source: Source, device: UInt32, value: Float) {
        do {
            channels[source.id] = try FoniaChannel(source.objects, output: device, gain: value)
            levels[source.id] = value
        } catch {
            levels.removeValue(forKey: source.id)
            let failure = error as NSError
            if device == 0 || device != FoniaOutput() || !FoniaOutputs().contains(NSNumber(value: device)) {
                message = "A saída mudou ou foi desconectada. Selecione uma saída em Ajustes do Sistema → Som e tente novamente."
            } else if failure.domain == NSOSStatusErrorDomain &&
                        [Int(kAudioDevicePermissionsError), -54, 0x7065726d].contains(failure.code) {
                message = "O acesso ao áudio de \(source.name) foi negado. Autorize o Fonia em Privacidade e Segurança → Gravação de Tela e Áudio do Sistema."
            } else {
                message = "Não foi possível capturar \(source.name) (Core Audio: \(failure.code)). Inicie a reprodução no aplicativo e tente ajustar o volume novamente."
            }
        }
    }
}

struct Fader: View {
    let name: String
    @Binding var level: Float
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).lineLimit(1)
                Spacer()
                Text("\(Int((level * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $level, in: 0...1).accessibilityLabel(name)
        }
    }
}

@main
struct Fonia: App {
    @StateObject private var mixer = Mixer()
    @StateObject private var voice = Voice()
    @State private var showingVoice = false
    var body: some Scene {
        MenuBarExtra("Fonia", systemImage: "slider.vertical.3") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saída do Mac").font(.headline)
                if mixer.master >= 0 {
                    Fader(name: mixer.outputName, level: Binding(get: { mixer.master }, set: mixer.setMaster))
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mixer.outputName)
                        Text("Sem ajuste geral pelo macOS. Use os controles por aplicativo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Aplicativos").font(.headline)
                if mixer.sources.isEmpty {
                    Text("Nenhum aplicativo tocando agora.").foregroundStyle(.secondary)
                } else if mixer.sources.count <= 5 {
                    sourceRows
                } else {
                    ScrollView {
                        sourceRows
                    }.frame(height: 270)
                }
                if !mixer.message.isEmpty {
                    Text(mixer.message).font(.callout)
                    Button("Dispensar") { mixer.message = "" }
                }
                Divider()
                DisclosureGroup(voice.state == .running ? "Modificador de voz · microfone ativo" : "Modificador de voz", isExpanded: $showingVoice) {
                    VoicePanel(voice: voice)
                }
                HStack {
                    SoundboardButton()
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ajustes do Fonia").help("Ajustes do Fonia")
                        .keyboardShortcut(",", modifiers: .command)
                    Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                        .accessibilityLabel("Encerrar Fonia").help("Encerrar Fonia")
                }
            }
            .padding(16)
            .frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top)
        }.menuBarExtraStyle(.window)
        Window("Painel de sons", id: "sounds") {
            SoundboardPanel(voice: voice)
        }.defaultSize(width: 500, height: 320)
        Settings {
            FoniaSettings(voice: voice, mixer: mixer)
        }.windowResizability(.contentSize)
    }

    private var sourceRows: some View {
        VStack(spacing: 10) {
            ForEach(mixer.sources) { source in
                fader(for: source)
            }
        }
    }

    private func fader(for source: Source) -> some View {
        let muted = mixer.levels[source.id] == 0
        return HStack {
            Button { mixer.toggleMute(source) } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2")
            }.accessibilityLabel("\(muted ? "Restaurar volume de" : "Silenciar") \(source.name)")
            Fader(name: source.name, level: Binding(get: { mixer.levels[source.id] ?? 1 },
                                                   set: { mixer.setLevel(source, $0) }))
        }
    }
}

private struct FoniaSettings: View {
    @ObservedObject var voice: Voice
    @ObservedObject var mixer: Mixer
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section("Geral") {
                Toggle("Lembrar volume por aplicativo", isOn: $mixer.rememberLevels)
                Toggle("Iniciar com o Mac", isOn: Binding(
                    get: { status == .enabled || status == .requiresApproval },
                    set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            errorMessage = ""
                        } catch {
                            errorMessage = "Não foi possível alterar o início automático. Mova o Fonia para Aplicativos e confira os Itens de Início do macOS. \(error.localizedDescription)"
                        }
                        status = SMAppService.mainApp.status
                    }))
                Text("Abre o mixer na barra de menus quando você inicia a sessão. O microfone continua desligado.").font(.caption)
                if !errorMessage.isEmpty { Text(errorMessage) }
                if status == .requiresApproval || !errorMessage.isEmpty {
                    Button("Abrir Itens de Início do macOS") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section("Microfone para chamadas") { DriverPanel(voice: voice) }
        }.formStyle(.grouped).frame(width: 460).fixedSize(horizontal: false, vertical: true)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            status = SMAppService.mainApp.status
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }
}
