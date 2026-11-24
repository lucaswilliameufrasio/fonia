// Compile as a standalone test translation unit to exercise the real callback.
#import "Audio.m"
#include <assert.h>

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
    }
    return 0;
}
