import AVFoundation
import SwiftUI

@MainActor
final class Voice: ObservableObject {
    enum State: Equatable { case idle, requesting, running, failed(String) }
    @Published private(set) var state = State.idle
    @Published var preset = VoicePreset.deep { didSet { effects?.apply(preset) } }
    @Published var destination: UInt32 = 0
    @Published private(set) var outputs: [UInt32] = []
    private var engine: AVAudioEngine?
    private var feed: MicFeed?
    enum Setup { case idle, downloading, waiting, removing, failed(String) }
    @Published private(set) var setup = Setup.idle
    @Published private(set) var driverPresent = VirtualMicSetup.driverPresent()
    var virtualMic: UInt32? { outputs.first { FoniaOutputName($0) == "BlackHole 2ch" } }
    private var effects: VoiceEffects?
    private var observer: NSObjectProtocol?
    private var session = UUID()

    func refresh() {
        driverPresent = VirtualMicSetup.driverPresent()
        outputs = FoniaOutputs().map(\.uint32Value)
        if case .removing = setup, virtualMic == nil { setup = .idle }
        if !outputs.contains(destination) {
            if state == .running || state == .requesting { stop() }
            destination = 0
        }
        if let virtualMic, case .waiting = setup, state != .running, state != .requesting {
            destination = virtualMic
            setup = .idle
        } else if destination == 0, let virtualMic {
            destination = virtualMic
        }
    }

    func configureCalls(_ action: DriverAction = .install) async {
        if case .downloading = setup { return }
        setup = .downloading
        do {
            let package = try await VirtualMicSetup.download(action)
            guard NSWorkspace.shared.open(package) else { throw VoiceRouteError("Não foi possível abrir o Instalador do macOS.") }
            setup = action == .install ? .waiting : .removing
            refresh()
        } catch {
            setup = .failed(error.localizedDescription)
        }
    }

    func start() async {
        guard engine == nil, state != .requesting, destination != 0 else { return }
        let token = UUID()
        session = token
        state = .requesting
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard session == token else { return }
        guard allowed else {
            state = .failed("Permita o microfone em Ajustes do Sistema → Privacidade e Segurança → Microfone.")
            return
        }
        let inputID = FoniaInput()
        guard inputID != 0, FoniaOutputs().contains(NSNumber(value: destination)) else {
            state = .failed("Microfone ou destino indisponível. Confira os dispositivos.")
            return
        }
        let audio = AVAudioEngine()
        let chain = VoiceEffects()
        let microphone = MicFeed()
        do {
            // A headset may supply both endpoints, but a loopback device must not feed itself.
            if inputID == destination && isVirtualDevice(inputID) {
                state = .failed("Escolha um microfone físico como entrada padrão do Mac.")
                return
            }
            try selectVoiceOutput(destination, engine: audio)
            try microphone.configure()
            audio.attach(microphone.player)
            chain.connect(in: audio, source: microphone.player, format: microphone.format)
            chain.apply(preset)
            try audio.start()
            microphone.player.play()
            microphone.capture.startRunning()
            guard microphone.capture.isRunning else { throw VoiceRouteError("O microfone não iniciou. Confira a entrada nos Ajustes de Som.") }
            feed = microphone
            engine = audio
            effects = chain
            state = .running
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.session == token else { return }
                    self.stop()
                    self.state = .failed("A configuração de áudio mudou. Confira o destino e reative a voz.")
                }
            }
        } catch {
            microphone.stop()
            audio.stop()
            state = .failed("Não foi possível iniciar a voz: \(error.localizedDescription)")
        }
    }

    private func isVirtualDevice(_ id: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: transport))
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return status != 0 || transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate
    }

    func stop() {
        session = UUID()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        feed?.stop()
        feed = nil
        engine?.stop()
        engine = nil
        effects = nil
        state = .idle
    }
}

struct VoicePanel: View {
    @ObservedObject var voice: Voice
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Voz", selection: $voice.preset) {
                ForEach(VoicePreset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Enviar para", selection: $voice.destination) {
                Text("Escolha uma saída").tag(UInt32(0))
                ForEach(voice.outputs, id: \.self) { Text(FoniaOutputName($0)).tag($0) }
            }.disabled(voice.state == .running || voice.state == .requesting)
            switch voice.state {
            case .running: Button("Desativar microfone") { voice.stop() }
            case .requesting: Button("Cancelar ativação") { voice.stop() }
            default:
                if case let .failed(message) = voice.state { Text(message).font(.callout) }
                Button("Ativar microfone") { Task { await voice.start() } }.disabled(voice.destination == 0)
            }
        }.onAppear { voice.refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in voice.refresh() }
    }
}

struct DriverPanel: View {
    @ObservedObject var voice: Voice
    @State private var confirmingRemoval = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let virtualMic = voice.virtualMic {
                if voice.destination == virtualMic {
                    Text("Na chamada, selecione BlackHole 2ch como microfone.").font(.caption)
                } else {
                    Button("Usar microfone para chamadas") { voice.destination = virtualMic }
                        .disabled(voice.state == .running || voice.state == .requesting)
                }
                switch voice.setup {
                case .downloading: Text("Verificando pacote oficial…").font(.caption)
                default:
                    if case .removing = voice.setup {
                        Text("Conclua a remoção no Instalador do macOS.").font(.caption)
                    }
                    if case let .failed(message) = voice.setup { Text(message).font(.caption) }
                    Button("Remover BlackHole 2ch…") { confirmingRemoval = true }
                        .disabled(voice.state == .requesting)
                        .alert("Remover o BlackHole 2ch deste Mac?", isPresented: $confirmingRemoval) {
                            Button("Cancelar", role: .cancel) {}
                            Button("Abrir desinstalador", role: .destructive) {
                                voice.stop()
                                Task { await voice.configureCalls(.remove) }
                            }
                        } message: {
                            Text("A interface deixará de funcionar em todos os apps. O desinstalador reinicia o áudio do Mac e pode interromper chamadas e gravações.")
                        }
                }
            } else if voice.driverPresent {
                Text("BlackHole 2ch instalado. A saída ainda não apareceu no macOS. Se você acabou de instalar, reinicie o Mac; não é preciso reinstalar.").font(.caption).fixedSize(horizontal: false, vertical: true)
            } else {
                switch voice.setup {
                case .downloading: Text("Baixando BlackHole 2ch…").font(.caption)
                case .waiting:
                    Text("Conclua a instalação do BlackHole 2ch. Se a saída não aparecer, reinicie o Mac.").font(.caption)
                    Button("Reabrir instalador") { Task { await voice.configureCalls() } }
                default:
                    if case let .failed(message) = voice.setup { Text(message).font(.caption) }
                    Text("Para usar a voz em chamadas, instale a interface virtual BlackHole 2ch.").font(.caption)
                    Button("Instalar interface para chamadas…") { Task { await voice.configureCalls() } }
                }
            }
        }.onAppear { voice.refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in voice.refresh() }
    }
}
