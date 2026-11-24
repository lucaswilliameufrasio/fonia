import AVFAudio

enum VoicePreset: String, CaseIterable {
    case natural = "Natural", deep = "Grave", bright = "Aguda", radio = "Rádio"
}

final class VoiceEffects {
    let pitch = AVAudioUnitTimePitch()
    let filter = AVAudioUnitEQ(numberOfBands: 1)

    func connect(in engine: AVAudioEngine, source: AVAudioNode, format: AVAudioFormat) {
        engine.attach(pitch)
        engine.attach(filter)
        engine.connect(source, to: pitch, format: format)
        engine.connect(pitch, to: filter, format: format)
        engine.connect(filter, to: engine.mainMixerNode, format: format)
    }

    func apply(_ preset: VoicePreset) {
        pitch.pitch = preset == .deep ? -600 : preset == .bright ? 700 : 0
        pitch.bypass = preset == .natural || preset == .radio
        let band = filter.bands[0]
        band.filterType = .bandPass
        band.frequency = 1200
        band.bandwidth = 1.8
        band.bypass = preset != .radio
    }
}
