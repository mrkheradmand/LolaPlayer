#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Small bridge to libmpv's stable client/render ABI; no vendor player code is used.
@interface LPMpvView : NSOpenGLView
@property(nonatomic, readonly) BOOL engineReady;
@property(nonatomic, readonly) BOOL fileLoaded;
@property(nonatomic, readonly) BOOL playbackFailed;
@property(nonatomic, readonly, nullable) NSString *engineError;
- (BOOL)startEngine:(NSString *)libraryPath;
- (void)command:(NSArray<NSString *> *)arguments;
- (void)setProperty:(NSString *)name value:(NSString *)value;
- (nullable NSString *)stringProperty:(NSString *)name;
- (double)numberProperty:(NSString *)name;
- (BOOL)flagProperty:(NSString *)name;
- (NSArray<NSDictionary<NSString *, id> *> *)tracks;
- (NSArray<NSDictionary<NSString *, id> *> *)chapters;
- (NSArray<NSString *> *)drainErrors;
- (void)shutdown;
@end
NS_ASSUME_NONNULL_END
