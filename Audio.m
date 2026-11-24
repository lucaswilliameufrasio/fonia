#import "Audio.h"
#import <libproc.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <AudioToolbox/AudioHardwareService.h>
#import <stdatomic.h>

static OSStatus readValue(AudioObjectID object, UInt32 key, UInt32 scope, void *destination, UInt32 size) {
    AudioObjectPropertyAddress address = { key, scope, 0 };
    return AudioObjectGetPropertyData(object, &address, 0, NULL, &size, destination);
}
static UInt32 number(AudioObjectID object, UInt32 key) {
    UInt32 result = 0;
    readValue(object, key, kAudioObjectPropertyScopeGlobal, &result, sizeof(result));
    return result;
}
static NSString *string(AudioObjectID object, UInt32 key) {
    CFStringRef result = NULL;
    readValue(object, key, kAudioObjectPropertyScopeGlobal, &result, sizeof(result));
    return CFBridgingRelease(result);
}
NSArray<NSNumber *> *FoniaProcesses(void) {
    AudioObjectPropertyAddress address = { kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal, 0 };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(1, &address, 0, NULL, &size) || !size) {
        return @[];
    }
    NSMutableData *storage = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(1, &address, 0, NULL, &size, storage.mutableBytes)) {
        return @[];
    }
    NSMutableArray *result = [NSMutableArray array];
    const UInt32 *items = storage.bytes;
    for (unsigned i = 0; i < size / sizeof(UInt32); i++) {
        [result addObject:@(items[i])];
    }
    return result;
}
int FoniaPID(unsigned int process) { return (int)number(process, kAudioProcessPropertyPID); }
NSString *FoniaExecutablePath(int pid) {
    char path[PROC_PIDPATHINFO_MAXSIZE] = {};
    if (proc_pidpath(pid, path, sizeof(path)) <= 0) { return nil; }
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:strlen(path)];
}
NSString *FoniaBundleIdentifier(unsigned int process) {
    return string(process, kAudioProcessPropertyBundleID);
}
BOOL FoniaActive(unsigned int process) { return number(process, kAudioProcessPropertyIsRunningOutput) != 0; }
unsigned int FoniaOutput(void) { return number(1, kAudioHardwarePropertyDefaultOutputDevice); }
unsigned int FoniaInput(void) { return number(1, kAudioHardwarePropertyDefaultInputDevice); }
NSArray<NSNumber *> *FoniaOutputs(void) {
    AudioObjectPropertyAddress address = { kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, 0 };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(1, &address, 0, NULL, &size) || !size) { return @[]; }
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(1, &address, 0, NULL, &size, data.mutableBytes)) { return @[]; }
    NSMutableArray *outputs = [NSMutableArray array];
    const UInt32 *devices = data.bytes;
    AudioObjectPropertyAddress streams = {kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput, 0};
    for (UInt32 i = 0; i < size / sizeof(UInt32); i++) {
        UInt32 bytes = 0;
        if (!AudioObjectGetPropertyDataSize(devices[i], &streams, 0, NULL, &bytes) && bytes &&
            ![string(devices[i], kAudioObjectPropertyName) isEqualToString:@"Fonia • reprodução"]) {
            [outputs addObject:@(devices[i])];
        }
    }
    return outputs;
}
NSString *FoniaOutputName(unsigned int device) { return string(device, kAudioObjectPropertyName) ?: @"Sem saída"; }
static AudioObjectPropertyAddress volumeAddress(void) {
    return (AudioObjectPropertyAddress){kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput, 0};
}
float FoniaVolume(unsigned int device) {
    AudioObjectPropertyAddress address = volumeAddress();
    Boolean writable = false;
    float value;
    UInt32 size = sizeof(value);
    if (AudioObjectIsPropertySettable(device, &address, &writable) || !writable ||
        AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &value)) {
        return -1;
    }
    return value;
}
BOOL FoniaSetVolume(unsigned int device, float value) {
    AudioObjectPropertyAddress address = volumeAddress();
    return !AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(value), &value);
}

// The aggregate's physical input streams precede the appended stereo tap.
// Only the tap feeds playback; never forward a device's microphone.
static OSStatus render(AudioDeviceID device, const AudioTimeStamp *now, const AudioBufferList *input,
                       const AudioTimeStamp *inTime, AudioBufferList *output, const AudioTimeStamp *outTime, void *context) {
    if (!input || !input->mNumberBuffers || !output) { return noErr; }
    const AudioBuffer *source = &input->mBuffers[input->mNumberBuffers - 1];
    if (!source->mData || source->mNumberChannels != 2) { return noErr; }
    const float *samples = source->mData;
    const float gain = atomic_load_explicit((_Atomic(float) *)context, memory_order_relaxed);
    UInt32 channel = 0;
    for (UInt32 i = 0; i < output->mNumberBuffers && channel < 2; i++) {
        AudioBuffer *target = &output->mBuffers[i];
        UInt32 width = target->mNumberChannels;
        if (!width) { continue; }
        UInt32 frames = MIN(source->mDataByteSize / (2 * sizeof(float)), target->mDataByteSize / (width * sizeof(float)));
        if (target->mData) {
            float *destination = target->mData;
            for (UInt32 frame = 0; frame < frames; frame++) {
                for (UInt32 c = 0; c < width && channel + c < 2; c++) {
                    destination[frame * width + c] = samples[frame * 2 + channel + c] * gain;
                }
            }
        }
        channel += width;
    }
    return noErr;
}
@implementation FoniaChannel {
    AudioObjectID _tap, _aggregate;
    AudioDeviceIOProcID _callback;
    _Atomic(float) _gain;
}
+ (instancetype)channel:(NSArray<NSNumber *> *)processes output:(unsigned int)device gain:(float)gain error:(NSError **)error {
    FoniaChannel *channel = [self new];
    OSStatus status = [channel start:processes output:device gain:gain];
    if (status) {
        [channel stop];
        if (error) { *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]; }
        return nil;
    }
    return channel;
}
- (OSStatus)start:(NSArray<NSNumber *> *)processes output:(AudioDeviceID)device gain:(float)gain {
    NSString *uid = string(device, kAudioDevicePropertyDeviceUID);
    if (!uid || !processes.count) { return kAudioHardwareBadObjectError; }
    CATapDescription *description = [[CATapDescription alloc] initStereoMixdownOfProcesses:processes];
    description.privateTap = YES;
    description.muteBehavior = CATapMutedWhenTapped;
    description.name = @"Fonia";
    OSStatus status = AudioHardwareCreateProcessTap(description, &_tap);
    if (status) { return status; }
    AudioStreamBasicDescription format = {};
    status = readValue(_tap, kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal, &format, sizeof(format));
    if (status || format.mFormatID != kAudioFormatLinearPCM || !(format.mFormatFlags & kAudioFormatFlagIsFloat)
        || format.mChannelsPerFrame != 2 || format.mBytesPerFrame != 8 || format.mBitsPerChannel != 32) {
        return status ?: kAudioDeviceUnsupportedFormatError;
    }
    NSDictionary *configuration = @{
        @kAudioAggregateDeviceNameKey: @"Fonia • reprodução",
        @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceIsPrivateKey: @YES,
        @kAudioAggregateDeviceMainSubDeviceKey: uid,
        @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: uid}],
        @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: description.UUID.UUIDString,
                                               @kAudioSubTapDriftCompensationKey: @YES}]
    };
    status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)configuration, &_aggregate);
    if (status) { return status; }
    [self setLevel:gain];
    status = AudioDeviceCreateIOProcID(_aggregate, render, &_gain, &_callback);
    if (status) { return status; }
    return AudioDeviceStart(_aggregate, _callback);
}
- (void)setLevel:(float)value { atomic_store_explicit(&_gain, value, memory_order_relaxed); }
- (void)stop {
    if (_callback) {
        AudioDeviceStop(_aggregate, _callback);
        AudioDeviceDestroyIOProcID(_aggregate, _callback);
        _callback = NULL;
    }
    if (_aggregate) { AudioHardwareDestroyAggregateDevice(_aggregate); _aggregate = 0; }
    if (_tap) { AudioHardwareDestroyProcessTap(_tap); _tap = 0; }
}
- (void)dealloc { [self stop]; }
@end
