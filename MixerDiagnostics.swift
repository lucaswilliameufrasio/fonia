import AppKit
import CoreAudio
import AudioToolbox

// Read-only: run on the affected Mac while the mixer is visible.
for screen in NSScreen.screens {
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let bounds = number.map { CGDisplayBounds($0.uint32Value) }
    print("Tela: \(screen.localizedName); quadro Quartz \(bounds?.debugDescription ?? "indisponível"); escala \(screen.backingScaleFactor)x")
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "Fonia" {
    print("Janela Fonia: \(window[kCGWindowBounds as String] ?? "sem geometria")")
}

let output = FoniaOutput()
print("Saída padrão: \(FoniaOutputName(output)); volume geral Fonia: \(FoniaVolume(output))")
var stereo = [UInt32](repeating: 0, count: 2)
var pair = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
                                     mScope: kAudioDevicePropertyScopeOutput, mElement: 0)
var size = UInt32(2 * MemoryLayout<UInt32>.size)
let hasPair = AudioObjectGetPropertyData(output, &pair, 0, nil, &size, &stereo) == noErr
for element in Set([UInt32(0)] + (hasPair ? stereo : [1, 2])).sorted() {
    let selectors = element == 0 ? [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] : [kAudioDevicePropertyVolumeScalar]
    for selector in selectors {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        var writable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(output, &address, &writable)
        let name = selector == kAudioDevicePropertyVolumeScalar ? "volume escalar" : "volume geral virtual"
        print("\(name), elemento \(element): \(status == noErr ? (writable.boolValue ? "ajustável" : "somente leitura") : "indisponível (\(status))")")
    }
}
