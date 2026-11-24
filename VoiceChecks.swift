import AVFAudio
import Foundation

@main
struct VoiceChecks {
    // Render the production graph without opening a microphone or speaker.
    static func measure(_ preset: VoicePreset, tone: Double) throws -> (frequency: Double, rms: Double) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let chain = VoiceEffects()
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(player)
        chain.connect(in: engine, source: player, format: format)
        chain.apply(preset)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let samples = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        samples.frameLength = samples.frameCapacity
        for index in 0..<Int(samples.frameLength) {
            samples.floatChannelData![0][index] = Float(0.25 * sin(2 * .pi * tone * Double(index) / rate))
        }
        player.scheduleBuffer(samples)
        try engine.start()
        defer { engine.stop() }
        player.play()
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        var crossings = 0, count = 0
        var energy = 0.0, previous: Float = 0
        for block in 0..<42 {
            precondition(tryRender(engine, output))
            if block < 10 { continue }
            for index in 0..<Int(output.frameLength) {
                let value = output.floatChannelData![0][index]
                if previous <= 0 && value > 0 { crossings += 1 }
                energy += Double(value * value)
                count += 1
                previous = value
            }
        }
        return (Double(crossings) * rate / Double(count), sqrt(energy / Double(count)))
    }

    static func tryRender(_ engine: AVAudioEngine, _ buffer: AVAudioPCMBuffer) -> Bool {
        (try? engine.renderOffline(1024, to: buffer)) == .success
    }

    static func main() throws {
        for (preset, expected) in [(VoicePreset.natural, 440.0), (.deep, 311.1), (.bright, 659.3)] {
            let output = try measure(preset, tone: 440)
            precondition(abs(output.frequency - expected) < 12 && output.rms > 0.02)
        }
        let middle = try measure(.radio, tone: 1200)
        let bass = try measure(.radio, tone: 80)
        precondition(middle.rms > bass.rms * 3)
        print("Quatro presets verificados por renderização offline.")
    }
}
