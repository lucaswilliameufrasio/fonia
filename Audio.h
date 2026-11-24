#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSArray<NSNumber *> *FoniaProcesses(void);
int FoniaPID(unsigned int process);
NSString * _Nullable FoniaExecutablePath(int pid);
NSString * _Nullable FoniaBundleIdentifier(unsigned int process);
BOOL FoniaActive(unsigned int process);
unsigned int FoniaOutput(void);
unsigned int FoniaInput(void);
NSArray<NSNumber *> *FoniaOutputs(void);
NSString *FoniaOutputName(unsigned int device);
float FoniaVolume(unsigned int device);
BOOL FoniaSetVolume(unsigned int device, float value);

@interface FoniaChannel : NSObject
+ (nullable instancetype)channel:(NSArray<NSNumber *> *)processes output:(unsigned int)device gain:(float)gain error:(NSError **)error;
- (void)setLevel:(float)value;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
