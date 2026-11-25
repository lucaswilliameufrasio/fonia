import AVFoundation

@main
struct SoundChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = SoundLibrary(folder: root.appendingPathComponent("library"))
        let empty = try library.list()
        precondition(empty.isEmpty)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("clip.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
            buffer.frameLength = 128
            try file.write(from: buffer)
        }
        try library.add(source)
        do {
            try library.add(source)
            fatalError("Duplicate replaced an imported clip")
        } catch is VoiceRouteError {}
        try FileManager.default.removeItem(at: source)
        let reopened = try SoundLibrary(folder: library.folder).list()
        precondition(reopened.count == 1)
        let copy = try AVAudioFile(forReading: reopened[0])
        precondition(copy.length == 128)
        let invalid = root.appendingPathComponent("broken.wav")
        try Data("not audio".utf8).write(to: invalid)
        do {
            try library.add(invalid)
            fatalError("Invalid clip accepted")
        } catch {}
        let remaining = try library.list()
        precondition(remaining == reopened)
        if CommandLine.arguments.contains("--playback") {
            // A silent fixture exercises the real output completion callback.
            let board = Soundboard()
            let device = FoniaOutput()
            for _ in 0..<2 {
                board.playOnce(reopened[0], to: device)
                precondition(board.playing == reopened[0], "Player did not start: \(board.message)")
            }
            for _ in 0..<50 where board.playing != nil {
                try await Task.sleep(for: .milliseconds(40))
            }
            precondition(board.playing == nil && board.message.isEmpty, "Clip did not finish automatically")
            print("Clipe redisparado e finalizado automaticamente na saída de teste.")
        }
    }
}
