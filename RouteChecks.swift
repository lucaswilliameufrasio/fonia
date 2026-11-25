import AVFoundation

@main
struct RouteChecks {
    static func main() async throws {
        if CommandLine.arguments.contains("--check-package") {
            for action in DriverAction.allCases {
                let package = try await VirtualMicSetup.download(action)
                defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
                print("\(action.filename): hash, editor e Gatekeeper confirmados; pacote não executado.")
            }
            return
        }
        let signer = "Developer ID Installer: Existential Audio Inc. (Q5C99V536K)"
        let assessment = "driver.pkg: accepted\nsource=Notarized Developer ID\norigin=\(signer)"
        precondition(VirtualMicSetup.accepts(signed: "1. \(signer)", assessment: assessment))
        precondition(!VirtualMicSetup.accepts(signed: "2. \(signer)", assessment: assessment))
        precondition(!VirtualMicSetup.accepts(signed: "1. \(signer)", assessment: "assessments disabled"))
        precondition(!VirtualMicSetup.accepts(signed: "1. \(signer)", assessment: assessment.replacingOccurrences(of: "Notarized Developer ID", with: "Developer ID")))
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("unexpected package".utf8).write(to: invalid)
        defer { try? FileManager.default.removeItem(at: invalid) }
        precondition(!VirtualMicSetup.driverPresent(at: invalid))
        let driver = invalid.appendingPathExtension("driver")
        precondition(!VirtualMicSetup.driverPresent(at: driver))
        try FileManager.default.createDirectory(at: driver, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: driver) }
        precondition(VirtualMicSetup.driverPresent(at: driver))
        for action in DriverAction.allCases {
            do {
                try VirtualMicSetup.verify(invalid, for: action)
                fatalError("Pacote alterado foi aceito.")
            } catch is VoiceRouteError {}
        }
        if CommandLine.arguments.contains("--offline") { return }
        let original = FoniaOutput()
        guard original != 0 else { throw VoiceRouteError("Teste requer uma saída padrão.") }
        var devices = [original]
        if let alternate = FoniaOutputs().map(\.uint32Value).first(where: { $0 != original }) {
            devices.append(alternate)
        }
        for device in devices {
            let engine = AVAudioEngine()
            try selectVoiceOutput(device, engine: engine)
            let mic = MicFeed()
            let chain = VoiceEffects()
            engine.attach(mic.player)
            chain.connect(in: engine, source: mic.player, format: mic.format)
            try engine.start()
            engine.stop()
            precondition(FoniaOutput() == original)
            print("Grafo de saída iniciado em \(FoniaOutputName(device)), sem capturar o microfone.")
        }
    }
}
