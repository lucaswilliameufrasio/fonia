import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SoundLibrary {
    let folder: URL

    func list() throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func add(_ source: URL) throws {
        let file = try AVAudioFile(forReading: source)
        guard file.length > 0, (1...2).contains(file.processingFormat.channelCount) else {
            throw VoiceRouteError("Escolha um clipe mono ou estéreo com áudio.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VoiceRouteError("Já existe um som com o nome \(source.lastPathComponent).")
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

@MainActor
final class Soundboard: ObservableObject {
    private let library = SoundLibrary(folder: URL.applicationSupportDirectory.appending(path: "Fonia/Sons", directoryHint: .isDirectory))
    @Published private(set) var sounds: [URL] = []
    @Published private(set) var playing: URL?
    @Published var message = ""
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private var generation = UUID()

    func reload() {
        do { sounds = try library.list() } catch { message = error.localizedDescription }
    }

    func add(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            do { try library.add(url) } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        message = failures.joined(separator: "\n")
        reload()
    }

    func remove(_ url: URL) {
        if playing == url { stop() }
        do { try FileManager.default.removeItem(at: url) } catch { message = error.localizedDescription }
        reload()
    }

    func play(_ url: URL) {
        guard let device = FoniaOutputs().first(where: { FoniaOutputName($0.uint32Value) == "BlackHole 2ch" }) else {
            stop()
            message = "BlackHole 2ch indisponível. Confira Ajustes → Microfone para chamadas."
            return
        }
        playOnce(url, to: device.uint32Value)
    }

    func playOnce(_ url: URL, to device: AudioDeviceID) {
        stop()
        let audio = AVAudioEngine()
        let token = generation
        do {
            let file = try AVAudioFile(forReading: url)
            try selectVoiceOutput(device, engine: audio)
            let player = AVAudioPlayerNode()
            audio.attach(player)
            audio.connect(player, to: audio.mainMixerNode, format: file.processingFormat)
            try audio.start()
            engine = audio
            playing = url
            message = ""
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.stop()
                    self.message = "A saída de áudio mudou. Toque o som novamente."
                }
            }
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.stop()
                }
            }
            player.play()
        } catch {
            audio.stop()
            message = "Não foi possível tocar o som: \(error.localizedDescription)"
        }
    }

    func stop() {
        generation = UUID()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.stop()
        engine = nil
        playing = nil
    }
}

struct SoundboardButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Painel de sons", systemImage: "square.grid.2x2") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "sounds")
        }
    }
}

struct SoundboardPanel: View {
    @StateObject private var board = Soundboard()
    @ObservedObject var voice: Voice
    @State private var importing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Meus sons").font(.title2.bold())
                Spacer()
                if !board.sounds.isEmpty { importButton }
            }.padding()
            Divider()
            if !board.message.isEmpty { Text(board.message).font(.callout).padding(.horizontal) }
            if board.sounds.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Adicione seu primeiro som").font(.headline)
                    Text("Cada clipe vira um botão. Clique para tocar uma vez.").foregroundStyle(.secondary)
                    importButton.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 18) {
                        ForEach(board.sounds, id: \.self) { url in
                            Button { board.play(url) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: board.playing == url ? "waveform" : "play.fill")
                                        .font(.title2).foregroundStyle(.white)
                                        .frame(width: 58, height: 58)
                                        .background(Circle().fill(padColor(url)))
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
                                }.frame(maxWidth: .infinity).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(voice.virtualMic == nil)
                            .accessibilityLabel("Tocar \(url.deletingPathExtension().lastPathComponent)")
                            .contextMenu { Button("Remover da biblioteca") { board.remove(url) } }
                        }
                    }.padding()
                }
            }
            Divider()
            HStack {
                Label(voice.virtualMic == nil ? "BlackHole 2ch indisponível" : "Saída: BlackHole 2ch", systemImage: "cable.connector")
                    .foregroundStyle(.secondary)
                Spacer()
                if voice.virtualMic == nil { SettingsLink { Text("Configurar…") } }
            }.font(.callout).padding(12)
        }.frame(minWidth: 420, minHeight: 290)
        .onAppear { board.reload(); voice.refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in voice.refresh() }
        .onDisappear { board.stop() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): board.add(urls)
            case .failure(let error): board.message = error.localizedDescription
            }
        }
    }

    private var importButton: some View {
        Button("Importar sons…", systemImage: "plus") { importing = true }
    }

    private func padColor(_ url: URL) -> Color {
        let palette: [Color] = [.indigo, .teal, .purple, .blue, .pink]
        let slot = url.lastPathComponent.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
        return palette[slot]
    }
}
