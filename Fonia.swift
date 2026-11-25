import AppKit
import ServiceManagement
import SwiftUI

struct Source: Identifiable {
    let id: String
    let name: String
    var objects: [NSNumber]
}

@MainActor
final class Mixer: ObservableObject {
    @Published private(set) var sources = [Source]()
    @Published private(set) var levels = [String: Float]()
    @Published private(set) var outputName = ""
    @Published private(set) var master: Float = -1
    @Published var message = ""
    private var output: UInt32 = 0
    private var channels = [String: FoniaChannel]()
    private var timer: Timer?

    init() {
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
            message = "Não foi possível ajustar o volume desta saída."
            refresh()
            return
        }
        master = value
    }

    func setLevel(_ source: Source, _ value: Float) {
        if value >= 1 {
            channels.removeValue(forKey: source.id)?.stop()
            levels.removeValue(forKey: source.id)
        } else if let channel = channels[source.id] {
            channel.setLevel(value)
            levels[source.id] = value
        } else {
            connect(source, device: output, value: value)
        }
    }

    private func connect(_ source: Source, device: UInt32, value: Float) {
        do {
            channels[source.id] = try FoniaChannel(source.objects, output: device, gain: value)
            levels[source.id] = value
        } catch {
            levels.removeValue(forKey: source.id)
            message = "Não foi possível ajustar \(source.name) (Core Audio: \((error as NSError).code)). Confira a permissão de gravação de áudio do sistema em Privacidade e Segurança."
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
                    Text("\(mixer.outputName) · volume indisponível").foregroundStyle(.secondary)
                }
                Divider()
                Text("Aplicativos").font(.headline)
                if mixer.sources.isEmpty {
                    Text("Reproduza áudio em um aplicativo para vê-lo aqui.").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(mixer.sources) { source in
                                Fader(name: source.name, level: Binding(get: { mixer.levels[source.id] ?? 1 },
                                                                         set: { mixer.setLevel(source, $0) }))
                            }
                        }
                    }.frame(height: min(CGFloat(mixer.sources.count) * 54, 270))
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
                    Button("Encerrar Fonia") { NSApplication.shared.terminate(nil) }
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ajustes do Fonia").help("Ajustes do Fonia")
                        .keyboardShortcut(",", modifiers: .command)
                }
            }.padding(16).frame(width: 320)
        }.menuBarExtraStyle(.window)
        Settings {
            FoniaSettings(voice: voice)
        }.windowResizability(.contentSize)
    }
}

private struct FoniaSettings: View {
    @ObservedObject var voice: Voice
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section("Geral") {
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
