import AVFoundation
import AudioToolbox

// Capture on the default microphone, independently of the playback HAL unit.
// The bounded queue drops late audio rather than replaying it after a stall.
final class MicFeed: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let capture = AVCaptureSession()
    let player = AVAudioPlayerNode()
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private let queue = DispatchQueue(label: "local.fonia.voice.capture")
    private let available = DispatchSemaphore(value: 4)

    func configure() throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else {
            throw VoiceRouteError("Nenhum microfone disponível.")
        }
        let input = try AVCaptureDeviceInput(device: mic)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true
        ]
        capture.beginConfiguration()
        defer { capture.commitConfiguration() }
        guard capture.canAddInput(input) else { throw VoiceRouteError("O microfone não está disponível.") }
        capture.addInput(input)
        guard capture.canAddOutput(output) else { throw VoiceRouteError("Falha ao configurar a captura.") }
        output.setSampleBufferDelegate(self, queue: queue)
        capture.addOutput(output)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        let frames = sample.numSamples
        guard frames > 0, frames <= 8192, available.wait(timeout: .now()) == .success else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(frames)) else {
            available.signal()
            return
        }
        buffer.frameLength = UInt32(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else {
            available.signal()
            return
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [available] _ in available.signal() }
    }

    func stop() {
        capture.stopRunning()
        queue.sync {}
        if player.engine != nil { player.stop() }
    }
}

struct VoiceRouteError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func selectVoiceOutput(_ destination: AudioDeviceID, engine: AVAudioEngine) throws {
    guard let unit = engine.outputNode.audioUnit else { throw VoiceRouteError("Saída de áudio indisponível.") }
    var current: AudioDeviceID = 0
    var size = UInt32(MemoryLayout.size(ofValue: current))
    func readCurrent() -> OSStatus {
        AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size)
    }
    if readCurrent() == noErr && current == destination { return }
    var selected = destination
    let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selected, size)
    guard status == noErr, readCurrent() == noErr, current == destination else {
        throw VoiceRouteError("Não foi possível abrir a saída selecionada (\(status)). Selecione outra saída ou reconecte o dispositivo.")
    }
}
