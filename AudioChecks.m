// Compile as a standalone test translation unit to exercise the real callback.
#import <CoreAudio/CoreAudio.h>
#include <assert.h>

static const AudioObjectID fixture = 0xfffffffe;
static AudioObjectPropertySelector supported;
static Boolean adjustable;
static float fixtureVolume;
static OSStatus canWrite(AudioObjectID device, const AudioObjectPropertyAddress *address, Boolean *result) {
    if (device != fixture) { return AudioObjectIsPropertySettable(device, address, result); }
    *result = adjustable;
    return address->mSelector == supported ? noErr : kAudioHardwareUnknownPropertyError;
}
static OSStatus getData(AudioObjectID device, const AudioObjectPropertyAddress *address, UInt32 qualifierSize,
                        const void *qualifier, UInt32 *size, void *data) {
    if (device != fixture) { return AudioObjectGetPropertyData(device, address, qualifierSize, qualifier, size, data); }
    assert(address->mSelector == supported && address->mElement == 0 && *size == sizeof(float));
    *(float *)data = fixtureVolume;
    return noErr;
}
static OSStatus setData(AudioObjectID device, const AudioObjectPropertyAddress *address, UInt32 qualifierSize,
                        const void *qualifier, UInt32 size, const void *data) {
    if (device != fixture) { return AudioObjectSetPropertyData(device, address, qualifierSize, qualifier, size, data); }
    assert(adjustable && address->mSelector == supported && address->mElement == 0 && size == sizeof(float));
    fixtureVolume = *(const float *)data;
    return noErr;
}
#define AudioObjectIsPropertySettable canWrite
#define AudioObjectGetPropertyData getData
#define AudioObjectSetPropertyData setData
#import "Audio.m"

int main(void) {
    @autoreleasepool {
        float microphone[] = {1, 1, 1, 1};
        float tap[] = {1, -1, .5, -.25};
        float left[2] = {}, right[2] = {};
        struct { UInt32 count; AudioBuffer buffers[2]; } inputs = {
            2, {{1, sizeof(microphone), microphone}, {2, sizeof(tap), tap}}
        }, outputs = {2, {{1, sizeof(left), left}, {1, sizeof(right), right}}};
        _Atomic(float) gain = .5;
        render(0, NULL, (AudioBufferList *)&inputs, NULL, (AudioBufferList *)&outputs, NULL, &gain);
        assert(left[0] == .5 && right[0] == -.5 && left[1] == .25 && right[1] == -.125);
        atomic_store(&gain, 0);
        render(0, NULL, (AudioBufferList *)&inputs, NULL, (AudioBufferList *)&outputs, NULL, &gain);
        assert(!left[0] && !right[0] && !left[1] && !right[1]);
        assert(FoniaProcesses() != nil);
        assert(FoniaVolume(kAudioObjectUnknown) < 0);
        AudioObjectPropertySelector selectors[] = { kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar };
        for (int i = 0; i < 2; i++) {
            supported = selectors[i];
            adjustable = true;
            fixtureVolume = .25f;
            assert(FoniaVolume(fixture) == .25f);
            assert(FoniaSetVolume(fixture, .75f) && FoniaVolume(fixture) == .75f);
            adjustable = false;
            assert(FoniaVolume(fixture) < 0 && !FoniaSetVolume(fixture, .5f));
        }
        supported = 0;
        assert(FoniaVolume(fixture) < 0 && !FoniaSetVolume(fixture, .5f));
    }
    return 0;
}
